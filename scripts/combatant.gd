class_name Combatant
extends CharacterBody3D
## Shared health/shield/inventory/weapon logic for player and bots.
signal died(who, killer)
var health := 100.0
var shield := 50.0
## slots[0] is always the pickaxe (null); slots 1-3 hold weapon dictionaries (see Weapons).
var slots: Array = [null, null, null, null]
var current := 0
var reserve := {"light": 120, "heavy": 30, "shells": 15, "rockets": 2}
var reloading := false
var fire_cd := 0.0
var alive := true
var display_name := "Player"
var kills := 0
var mats := 200
const GRAVITY := 20.0
var _shot_anim := 0.0
var _reload_anim := 0.0
var aim_pitch := 0.0
signal fired(w)
var model: Node3D
var step_t := 0.0

func weapon() -> Dictionary:
	return slots[current] if slots[current] != null else {}

static func ammo_kind(w: Dictionary) -> String:
	match w.get("type", ""):
		"sniper": return "heavy"
		"shotgun": return "shells"
		"rocket": return "rockets"
	return "light"

var heals := 0            # shield potions (used by bots; chests give one)
var last_hit_time := -99.0
var last_attacker: Combatant
var last_shot_time := -99.0

func now() -> float:
	return Time.get_ticks_msec() / 1000.0

func take_damage(amount: float, killer = null) -> void:
	if not alive: return
	last_hit_time = now()
	if killer is Combatant and killer != self: last_attacker = killer
	var s: float = min(shield, amount); shield -= s; health -= amount - s
	if health <= 0:
		health = 0; alive = false
		if model: Util.play_anim(model, "die")
		if killer is Combatant and killer != self: killer.kills += 1
		died.emit(self, killer)

func select_slot(i: int) -> void:
	if i < 0 or i >= slots.size() or (i > 0 and slots[i] == null): return
	current = i; reloading = false
	if model: Util.hold(model, i == 0, Weapons.color(weapon()) if i > 0 else Color.WHITE, weapon().get("type", "ar"))

## Puts a weapon in a free slot (or replaces the current one). Returns the dropped weapon or null.
func give_weapon(w: Dictionary):
	for i in range(1, slots.size()):
		if slots[i] == null:
			slots[i] = w; if current == 0 or current == i: select_slot(i)
			return null
	var idx := current if current > 0 else 1
	var old = slots[idx]; slots[idx] = w; select_slot(idx)
	return old

func reload() -> void:
	var w := weapon()
	if w.is_empty() or reloading or w.ammo == w.mag or reserve[ammo_kind(w)] <= 0: return
	reloading = true; _reload_anim = 1.4
	Util.sfx(w.get("reload", "reload"), global_position, -4.0 if self is Bot else 0.0)
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree() or not reloading or weapon() != w: return
	var k := ammo_kind(w)
	var need: int = min(w.mag - w.ammo, reserve[k]); w.ammo += need; reserve[k] -= need; reloading = false

## Fire the held item from origin along dir. Pickaxe = melee + harvest.
func fire(origin: Vector3, dir: Vector3, extra_spread := 0.0):
	if fire_cd > 0 or reloading or not alive: return null
	if current == 0: return _swing(origin, dir)
	var w := weapon()
	if w.ammo <= 0: reload(); return null
	w.ammo -= 1; fire_cd = w.rate; _shot_anim = 0.25; last_shot_time = now()
	Util.sfx(w.get("sound", "shoot"), origin, -8.0 if self is Bot else -2.0)
	if model and model.has_meta("mount"): Util.muzzle_flash(model.get_meta("mount").get_node_or_null("Gun"), w.type in ["shotgun", "rocket", "sniper"])
	fired.emit(w)
	var end := origin
	for p in w.pellets:
		var sp: float = w.spread + extra_spread
		var d := (dir + Vector3(randf_range(-sp, sp), randf_range(-sp, sp), randf_range(-sp, sp))).normalized()
		end = _ray(origin, d, w.range, w.damage, Weapons.color(w))
	if w.has("splash"): _explode(end, w.splash, w.damage)
	return end

## Rocket impact: splash damage with falloff, flash + smoke puff.
func _explode(at: Vector3, radius: float, dmg: float) -> void:
	for c in get_tree().get_nodes_in_group("combatants"):
		if c is Combatant and c.alive:
			var d: float = c.global_position.distance_to(at)
			if d < radius: c.take_damage(dmg * (1.0 - d / radius) * 0.8, self)
	for b in get_tree().get_nodes_in_group("built"):
		if is_instance_valid(b) and b.global_position.distance_to(at) < radius and b.has_method("take_damage"): b.take_damage(200.0, self)
	Util.sfx("shotgun", at, 4.0)
	var fx := Node3D.new(); get_tree().current_scene.add_child(fx); fx.global_position = at
	var ball := Util.mesh(SphereMesh.new(), Color(1, 0.6, 0.2)); ball.material_override.emission_enabled = true
	ball.material_override.emission = Color(1, 0.5, 0.1) * 3.0; fx.add_child(ball)
	var smoke := Sprite3D.new(); smoke.texture = load("res://assets/fx13/smoke.png"); smoke.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	smoke.pixel_size = 0.012; smoke.modulate = Color(0.35, 0.33, 0.3, 0.9); fx.add_child(smoke)
	var tw := fx.create_tween(); tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 1.2, 0.25); tw.tween_property(smoke, "pixel_size", 0.03, 1.2)
	tw.tween_property(smoke, "modulate:a", 0.0, 1.2); tw.chain().tween_callback(fx.queue_free)
	get_tree().create_timer(0.25).timeout.connect(func(): if is_instance_valid(ball): ball.visible = false)

func _ray(origin: Vector3, d: Vector3, rng: float, dmg: float, col: Color) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + d * rng); q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := origin + d * rng
	if hit:
		end = hit.position
		var c = hit.collider
		if c.has_method("take_damage"):
			c.take_damage(dmg, self)
			if c is Combatant: Util.sfx("hit", end, -4.0)
	_tracer(origin, end, col)
	return end

func _swing(origin: Vector3, dir: Vector3):
	fire_cd = 0.45; _shot_anim = 0.3
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 3.5); q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		var c = hit.collider
		if c.has_meta("harvest"):
			mats = mini(mats + int(c.get_meta("harvest")), 999); Util.sfx("build", hit.position, -4.0)
		elif c.has_method("take_damage"):
			c.take_damage(20.0, self); Util.sfx("hit", hit.position)
		return hit.position
	return null

func _tracer(a: Vector3, b: Vector3, col := Color(1, 1, 0.3)) -> void:
	var im := ImmediateMesh.new(); var mi := MeshInstance3D.new(); mi.mesh = im
	mi.material_override = Util.mat(col.lightened(0.3))
	mi.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	im.surface_begin(Mesh.PRIMITIVE_LINES); im.surface_add_vertex(a); im.surface_add_vertex(b); im.surface_end()
	get_tree().current_scene.add_child(mi)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)

func setup_body(skin := "", backbling := "bb_none", pickaxe := "pick_default") -> void:
	model = Util.make_character(skin, backbling, pickaxe); add_child(model)
	add_to_group("combatants")
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.4; cap.height = 1.8
	cs.shape = cap; cs.position.y = 0.9; cs.name = "CollisionShape3D"; add_child(cs)

func base_anim(hs: float) -> String:
	if not is_on_floor(): return "jump" if velocity.y > 2.0 else "fall"
	if _shot_anim > 0: return "pickaxe" if current == 0 else "holding-right-shoot"
	if _reload_anim > 0 and current > 0: return "reload"
	if hs > 7.0: return "sprint"
	if hs > 0.5: return "walk"
	return "idle" if current == 0 else "holding-right"

func _physics_process(delta: float) -> void:
	fire_cd -= delta
	_shot_anim -= delta; _reload_anim -= delta
	if not alive or model == null: return
	var hs := Vector2(velocity.x, velocity.z).length()
	Util.play_anim(model, base_anim(hs))
	if is_on_floor() and hs > 0.5:
		step_t -= delta * hs / 6.0
		if step_t <= 0:
			step_t = 0.4
			Util.sfx("step%d" % (randi() % 3), global_position, -8.0 if self is Bot else -2.0)

func _process(_d: float) -> void:
	if model: Util.align_gear(model, aim_pitch)
