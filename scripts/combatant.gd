class_name Combatant
extends CharacterBody3D
## Shared health/shield/weapon logic for player and bots.
signal died(who, killer)
var health := 100.0
var shield := 50.0
var ammo := 30
var mag_size := 30
var reserve := 120
var reloading := false
var fire_cd := 0.0
var damage := 12.0
var alive := true
var display_name := "Player"
const GRAVITY := 20.0

func take_damage(amount: float, killer = null) -> void:
	if not alive: return
	var s: float = min(shield, amount); shield -= s; health -= amount - s
	if health <= 0:
		health = 0; alive = false
		if model: Util.play_anim(model, "die")
		died.emit(self, killer)

func reload() -> void:
	if reloading or ammo == mag_size or reserve <= 0: return
	reloading = true
	Util.sfx("reload", global_position)
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree(): return
	var need: int = min(mag_size - ammo, reserve); ammo += need; reserve -= need; reloading = false

## Hitscan from origin along dir. Returns hit point or null.
func fire(origin: Vector3, dir: Vector3, spread := 0.0):
	if fire_cd > 0 or reloading or not alive: return null
	if ammo <= 0: reload(); return null
	ammo -= 1; fire_cd = 0.12
	Util.sfx("shoot", origin, -6.0 if self is Bot else 0.0)
	_shot_anim = 0.2
	dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 200.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := origin + dir * 200.0
	if hit:
		end = hit.position
		var c = hit.collider
		if c.has_method("take_damage"):
			c.take_damage(damage, self)
			if c is Combatant: Util.sfx("hit", end, -4.0)
	_tracer(origin, end)
	return end

func _tracer(a: Vector3, b: Vector3) -> void:
	var im := ImmediateMesh.new(); var mi := MeshInstance3D.new(); mi.mesh = im
	mi.material_override = Util.mat(Color(1, 1, 0.3))
	mi.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	im.surface_begin(Mesh.PRIMITIVE_LINES); im.surface_add_vertex(a); im.surface_add_vertex(b); im.surface_end()
	get_tree().current_scene.add_child(mi)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)

var _shot_anim := 0.0
var model: Node3D
var step_t := 0.0

func setup_body(c: Color) -> void:
	model = Util.make_character(c); add_child(model)
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.4; cap.height = 1.8
	cs.shape = cap; cs.position.y = 0.9; add_child(cs)

func _physics_process(delta: float) -> void:
	fire_cd -= delta
	_shot_anim -= delta
	if not alive or model == null: return
	var hs := Vector2(velocity.x, velocity.z).length()
	var anim := "holding-right"
	if not is_on_floor(): anim = "jump" if velocity.y > 0 else "fall"
	elif _shot_anim > 0: anim = "holding-right-shoot"
	elif hs > 7.0: anim = "sprint"
	elif hs > 0.5: anim = "walk"
	Util.play_anim(model, anim)
	if is_on_floor() and hs > 0.5:
		step_t -= delta * hs / 6.0
		if step_t <= 0:
			step_t = 0.4
			Util.sfx("step%d" % (randi() % 3), global_position, -8.0 if self is Bot else -2.0)
