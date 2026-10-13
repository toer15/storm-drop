class_name Bot
extends Combatant
## Human-like AI opponent.
## Decision making: a utility system. Every ~0.3 s (staggered per bot, slower when far from the player)
## each action is scored from health, shield, ammo, materials, weapon quality, storm distance,
## nearby enemies and loot. The best one runs until the next think.
## Movement: NavigationAgent3D on a navmesh baked at runtime, with acceleration, smooth turning,
## strafing, jump spam, crouch-peeking, reaction time and aim error scaled by skill.
enum Persona { AGGRESSIVE, CAUTIOUS, LOOTER, BUILDER }
const PERSONA_NAMES := ["Aggressive", "Cautious", "Looter", "Builder"]
enum Act { ROAM, LOOT_WEAPON, OPEN_CHEST, ROTATE, ENGAGE, THIRD_PARTY, RETREAT, HEAL, BUILD_COVER, CAMP }
const ACT_NAMES := ["Roam", "Loot weapon", "Open chest", "Rotate to zone", "Engage", "Third-party", "Retreat", "Heal", "Build cover", "Camp house"]

var game
var persona: int = Persona.AGGRESSIVE
var skill := 0.5               # 0 = clumsy, 1 = sharp. Set from difficulty + randomness.
var reaction := 0.4            # seconds before first shot at a newly seen enemy
var aim_error := 0.06
var act: int = Act.ROAM
var act_score := 0.0
var scores := {}
var target_pos := Vector3.ZERO
var target_node: Node3D
var enemy: Combatant
var enemy_seen_at := 0.0
var think_t := 0.0
var agent: NavigationAgent3D
var in_bus := true
var gliding := false
var drop_at := 0.0
var land_target := Vector3.ZERO
var build_cd := 0.0
var heal_t := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var burst_t := 0.0
var pause_t := 0.0
var crouch_t := 0.0
var crouching := false
var action_anim := ""
var action_anim_t := 0.0
var glider: Node3D
var debug_label: Label3D

func _ready() -> void:
	persona = randi() % 4
	skill = clampf(Util.difficulty * 0.33 + randf_range(-0.1, 0.35), 0.0, 1.0)
	reaction = lerpf(0.75, 0.15, skill)
	aim_error = lerpf(0.13, 0.025, skill)
	heals = 1 if persona == Persona.CAUTIOUS else 0
	# Varied outfits: random character, back bling and pickaxe.
	var bbs := ["bb_none", "bb_cube", "bb_orb", "bb_tank", "bb_candy", "bb_crystal"]
	var picks := ["pick_default", "pick_neon", "pick_gold", "pick_candy", "pick_void"]
	setup_body("", bbs[randi() % bbs.size()], picks[randi() % picks.size()])
	give_weapon(_nerf(Weapons.make("pistol", 0)))
	select_slot(0) # land with the pickaxe, like a player
	glider = Node3D.new(); glider.visible = false; add_child(glider)
	var wing := PrismMesh.new(); wing.size = Vector3(3.2, 0.6, 1.4)
	glider.add_child(Util.mesh(wing, Color.from_hsv(randf(), 0.7, 1), Vector3(0, 3.0, 0)))
	agent = NavigationAgent3D.new(); agent.path_desired_distance = 1.5; agent.target_desired_distance = 1.5
	agent.radius = 0.5; agent.path_max_distance = 6.0; add_child(agent)
	debug_label = Label3D.new(); debug_label.position.y = 3.3; debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label.font_size = 22; debug_label.outline_size = 10; debug_label.no_depth_test = true; debug_label.pixel_size = 0.0011; debug_label.fixed_size = true
	debug_label.visible = false; add_child(debug_label)
	think_t = randf() * 0.3 # stagger

func _nerf(w: Dictionary) -> Dictionary:
	w = w.duplicate(); w.damage *= lerpf(0.4, 0.75, skill); return w

func start_in_bus(t: float, target: Vector3) -> void:
	in_bus = true; drop_at = t; land_target = target; visible = false
	$CollisionShape3D.disabled = true; target_pos = target

func drop() -> void:
	in_bus = false; gliding = true; visible = true; glider.visible = true
	$CollisionShape3D.disabled = false

func base_anim(hs: float) -> String:
	if gliding: return "glide"
	if action_anim_t > 0: return action_anim
	if crouching and is_on_floor(): return "crouch" if hs < 1.0 else "crouch-walk"
	return super(hs)

func _play_action(a: String, t: float) -> void:
	action_anim = a; action_anim_t = t

func take_damage(amount: float, killer = null) -> void:
	super(amount, killer)
	if alive and killer is Combatant and killer != self:
		if not is_instance_valid(enemy): enemy = killer; enemy_seen_at = now()
		think_t = minf(think_t, 0.05) # react quickly to being shot

# ---------------------------------------------------------------- perception
func _visible_enemy(range_m: float) -> Combatant:
	var best: Combatant = null; var bd := range_m
	for c in game.combatants:
		if not is_instance_valid(c) or c == self or not c.alive: continue
		if (c is Player and c.state != Player.State.GROUND) or (c is Bot and (c.in_bus or c.gliding)): continue
		var d := global_position.distance_to(c.global_position)
		if d < bd and _line_of_sight(c): bd = d; best = c
	return best

func _line_of_sight(c: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), c.global_position + Vector3(0, 1.2, 0))
	q.exclude = [get_rid(), c.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func weapon_quality() -> float:
	var best := 0.0
	for i in range(1, 4):
		if slots[i] != null: best = maxf(best, 1.0 + slots[i].rarity)
	return best # 0 = no gun, 1..5 rarity

func _storm_dist() -> float:
	# >0 = metres inside the (next) safe zone edge, <0 = outside
	var r: float = game.storm_target if game.shrinking else game.storm_radius
	return r - Vector2(global_position.x - game.storm_center.x, global_position.z - game.storm_center.z).length()

# ---------------------------------------------------------------- utility scoring
func _think() -> void:
	var hp := (health + shield) / 150.0
	var wq := weapon_quality()
	var ammo: int = weapon().get("ammo", 0) + reserve.get(ammo_kind(weapon()), 0) if current > 0 else 0
	var aggressive := persona == Persona.AGGRESSIVE
	var cautious := persona == Persona.CAUTIOUS
	var sight := lerpf(45.0, 85.0, skill) * (1.2 if aggressive else 1.0)
	var seen := _visible_enemy(sight)
	if seen != null and seen != enemy: enemy = seen; enemy_seen_at = now()
	if is_instance_valid(enemy) and (not enemy.alive or global_position.distance_to(enemy.global_position) > sight * 1.4): enemy = null
	var ed := global_position.distance_to(enemy.global_position) if is_instance_valid(enemy) else 999.0
	var storm := _storm_dist()
	var loot_n = game.nearest_loot(global_position, 45.0)
	var chest_n = game.nearest_chest(global_position, 50.0)
	var hit_recent := now() - last_hit_time < 2.0
	scores.clear()
	scores[Act.ROAM] = 0.15
	# Looting: strong when unarmed or weakly armed; looters care more.
	var loot_drive := 1.6 if persona == Persona.LOOTER else 1.0
	if loot_n != null:
		var better: bool = loot_n.get_meta("weapon").rarity + 1 > wq or slots[2] == null
		scores[Act.LOOT_WEAPON] = (0.9 if wq < 1.0 else (0.55 if better else 0.05)) * loot_drive * (1.0 - global_position.distance_to(loot_n.global_position) / 60.0)
	if chest_n != null:
		scores[Act.OPEN_CHEST] = (0.5 + (0.3 if shield < 25 else 0.0)) * loot_drive * (1.0 - global_position.distance_to(chest_n.global_position) / 70.0)
	# Rotation: aggressive bots rotate late, cautious ones early.
	var early := 25.0 if cautious else (5.0 if aggressive else 12.0)
	if storm < early: scores[Act.ROTATE] = clampf(0.45 + (early - storm) / 30.0, 0.0, 1.6)
	if storm < 0: scores[Act.ROTATE] = 1.8 # get out of the storm!
	if is_instance_valid(enemy) and wq > 0:
		var fight_busy := now() - enemy.last_hit_time < 1.5 and enemy.last_attacker != self
		var base := 0.55 + (0.35 if aggressive else 0.0) - (0.2 if cautious else 0.0)
		var e := base * (0.4 + hp) * (0.6 + wq * 0.1) * clampf(1.0 - ed / (sight * 1.2), 0.2, 1.0)
		if ammo <= 0: e *= 0.2
		scores[Act.ENGAGE] = e
		if fight_busy: scores[Act.THIRD_PARTY] = e + 0.25 # someone else is already fighting them
		# Retreat when hurt (cautious bots bail earlier).
		var bail := 0.5 if cautious else (0.25 if aggressive else 0.35)
		if hp < bail: scores[Act.RETREAT] = 0.9 + (bail - hp)
	elif is_instance_valid(enemy) and wq == 0:
		scores[Act.RETREAT] = 0.8 # only a pickaxe: run and find a gun
	if heals > 0 and shield < 30 and (not is_instance_valid(enemy) or ed > 35 or not _line_of_sight(enemy)):
		scores[Act.HEAL] = 0.85
	if hit_recent and mats >= 10 and build_cd <= 0:
		scores[Act.BUILD_COVER] = 1.3 if persona == Persona.BUILDER else (0.7 if cautious else 0.45)
	if cautious and storm > 25 and not is_instance_valid(enemy) and wq >= 2 and game.house_spots.size() > 0:
		scores[Act.CAMP] = 0.5
	# Pick best with a little hysteresis so bots don't flip-flop.
	var best := act; var bs: float = scores.get(act, 0.0) + 0.1
	for k in scores:
		if scores[k] > bs: bs = scores[k]; best = k
	if best != act: _enter(best, loot_n, chest_n)
	act = best; act_score = bs
	if Util.debug_ai: _update_debug()

func _enter(a: int, loot_n, chest_n) -> void:
	crouching = false
	match a:
		Act.LOOT_WEAPON: target_node = loot_n
		Act.OPEN_CHEST: target_node = chest_n
		Act.ROTATE:
			var ang := randf() * TAU; var r: float = (game.storm_target if game.shrinking else game.storm_radius) * randf_range(0.2, 0.6)
			target_pos = game.storm_center + Vector3(cos(ang) * r, 0, sin(ang) * r)
		Act.CAMP:
			var best: Vector3 = game.house_spots[0]
			for h in game.house_spots: if h.distance_to(global_position) < best.distance_to(global_position): best = h
			target_pos = best + Vector3(0, 0, 1.0)
		Act.ROAM:
			var ang := randf() * TAU; var r: float = randf() * game.storm_radius * 0.6
			target_pos = game.storm_center + Vector3(cos(ang) * r, 0, sin(ang) * r)
		Act.HEAL: heal_t = 2.0
		Act.BUILD_COVER: _build_cover()

func _update_debug() -> void:
	var top := []
	for k in scores: top.append([scores[k], k])
	top.sort_custom(func(x, y): return x[0] > y[0])
	var alt := ""
	for i in range(1, mini(3, top.size())): alt += "  %s %.2f" % [ACT_NAMES[top[i][1]], top[i][0]]
	debug_label.text = "%s  [%s, skill %.1f]\n> %s (%.2f)\n%s\nHP %d  SH %d  W%d  mats %d" % [display_name, PERSONA_NAMES[persona], skill,
		ACT_NAMES[act], act_score, alt, int(health), int(shield), int(weapon_quality()), mats]
	debug_label.modulate = Color(1, 0.4, 0.4) if act in [Act.ENGAGE, Act.THIRD_PARTY] else (Color(1, 0.9, 0.3) if act == Act.RETREAT else Color(0.6, 1, 0.7))

# ---------------------------------------------------------------- actions
func _build_cover() -> void:
	build_cd = 3.5 if persona == Persona.BUILDER else 6.0
	if mats < 10: return
	var threat := last_attacker if is_instance_valid(last_attacker) else enemy
	if not is_instance_valid(threat): return
	var dir := Vector3(threat.global_position.x - global_position.x, 0, threat.global_position.z - global_position.z).normalized()
	var ramp := persona == Persona.BUILDER and randf() < 0.5
	mats -= 10
	var piece := Util.static_box(Vector3(4, 0.2, 5) if ramp else Vector3(4, 3, 0.2), Color(0.7, 0.5, 0.3), Vector3.ZERO)
	piece.set_script(load("res://scripts/build_piece.gd"))
	get_tree().current_scene.add_child(piece)
	piece.global_position = global_position + dir * 2.2 + Vector3(0, 1.5, 0)
	piece.look_at(piece.global_position + dir)
	if ramp: piece.rotate_object_local(Vector3.RIGHT, deg_to_rad(36.87))
	_play_action("build", 0.4)
	Util.sfx("build", global_position, -6)

func _move_to(p: Vector3, speed: float, delta: float, face := true) -> void:
	var next := p
	if game.nav_ready:
		if agent.target_position.distance_to(p) > 1.0: agent.target_position = p
		if not agent.is_navigation_finished(): next = agent.get_next_path_position()
	var flat := Vector3(next.x - global_position.x, 0, next.z - global_position.z)
	var want := flat.normalized() * speed if flat.length() > 0.6 else Vector3.ZERO
	_steer(want, delta)
	if face and want.length() > 0.1: _turn_to(global_position + want, delta)

func _steer(want: Vector3, delta: float) -> void:
	var accel := 14.0 if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, want.x, accel * delta)
	velocity.z = move_toward(velocity.z, want.z, accel * delta)

func _turn_to(p: Vector3, delta: float) -> void:
	var d := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
	if d.length() < 0.01: return
	var want := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * lerpf(5.0, 12.0, skill)))

func _combat(delta: float) -> void:
	if current == 0 or weapon().is_empty():
		for i in range(1, 4): if slots[i] != null: select_slot(i)
	if not is_instance_valid(enemy) or current == 0: return
	var to := enemy.global_position - global_position
	var dist := to.length()
	_turn_to(enemy.global_position, delta)
	# Positioning by weapon / persona: shotguns close in, snipers back off.
	var w := weapon()
	var ideal: float = {"shotgun": 6.0, "smg": 12.0, "pistol": 18.0, "ar": 25.0, "sniper": 55.0}.get(w.get("type", "ar"), 20.0)
	if persona == Persona.AGGRESSIVE: ideal *= 0.6
	if persona == Persona.CAUTIOUS: ideal *= 1.3
	strafe_t -= delta
	if strafe_t <= 0: strafe_t = randf_range(0.4, 1.4); strafe_dir = -strafe_dir if randf() < 0.6 else strafe_dir
	var side := to.cross(Vector3.UP).normalized() * strafe_dir
	var radial := to.normalized() * clampf((dist - ideal) / 8.0, -1.0, 1.0)
	var want := (side * 0.8 + radial).normalized() * (6.0 if persona == Persona.AGGRESSIVE else 4.5)
	if game.nav_ready and dist > ideal + 10: _move_to(enemy.global_position, 6.0, delta, false)
	else: _steer(want, delta)
	# Jump spam (aggressive) and crouch peeking (cautious) while fighting.
	if is_on_floor() and persona == Persona.AGGRESSIVE and randf() < 0.025 * (0.5 + skill): velocity.y = 7.5
	if persona == Persona.CAUTIOUS:
		crouch_t -= delta
		if crouch_t <= 0: crouching = not crouching; crouch_t = randf_range(0.5, 1.2)
	# Reaction time, then spray (AR/SMG) or tap (pistol/shotgun/sniper).
	if now() - enemy_seen_at < reaction: return
	if w.ammo <= 0:
		if reserve[ammo_kind(w)] <= 0: reserve[ammo_kind(w)] = 30 # bots never fully run dry
		reload(); return
	var spray: bool = w.type in ["ar", "smg"]
	if pause_t > 0: pause_t -= delta; return
	if spray:
		burst_t -= delta
		if burst_t <= 0: burst_t = randf_range(0.5, 1.2); pause_t = randf_range(0.2, 0.6) * (1.3 - skill); return
	else:
		pause_t = randf_range(0.15, 0.5) * (1.4 - skill)
	var moving := Vector2(velocity.x, velocity.z).length() > 1.0
	var err := aim_error * (1.4 if moving else 1.0) * (1.0 + dist / 120.0)
	if crouching: err *= 0.7
	var gun := global_position + Vector3(0, 1.4, 0)
	var aim := enemy.global_position + Vector3(0, 1.1, 0) + enemy.velocity * dist / 200.0 * skill # lead targets
	aim_pitch = asin(clampf((aim - gun).normalized().y, -1, 1))
	fire(gun, (aim - gun).normalized(), err)

func _physics_process(delta: float) -> void:
	super(delta)
	if not alive or in_bus: return
	build_cd -= delta; action_anim_t -= delta
	if gliding:
		var flat := Vector3(land_target.x - global_position.x, 0, land_target.z - global_position.z)
		var v := flat.limit_length(1.0) * 12.0
		velocity = Vector3(v.x, -9.0, v.z)
		if flat.length() > 1: _turn_to(land_target, delta)
		move_and_slide()
		if is_on_floor(): gliding = false; glider.visible = false; think_t = 0
		return
	# LOD: think less often when far from the player (mobile friendly).
	think_t -= delta
	if think_t <= 0:
		var far := is_instance_valid(game.player) and global_position.distance_to(game.player.global_position) > 90.0
		think_t = randf_range(0.25, 0.35) * (3.0 if far else 1.0)
		_think()
	debug_label.visible = Util.debug_ai
	match act:
		Act.ENGAGE, Act.THIRD_PARTY:
			_combat(delta)
		Act.LOOT_WEAPON, Act.OPEN_CHEST:
			if not is_instance_valid(target_node): think_t = 0; _steer(Vector3.ZERO, delta)
			else:
				_move_to(target_node.global_position, 6.5, delta)
				if global_position.distance_to(target_node.global_position) < 2.2:
					if act == Act.OPEN_CHEST:
						select_slot(0); _play_action("open-chest", 1.0); game.open_chest(self, target_node)
					else: game.bot_try_pickup(self)
					think_t = 0
			if is_instance_valid(enemy) and current > 0 and now() - enemy_seen_at > reaction and randf() < 0.1:
				_combat(delta) # shoot while moving if threatened
		Act.ROTATE, Act.ROAM:
			_move_to(target_pos, 7.5 if act == Act.ROTATE and _storm_dist() < 0 else 5.5, delta)
			if global_position.distance_to(target_pos) < 3: think_t = 0
		Act.RETREAT:
			var away := global_position - (enemy.global_position if is_instance_valid(enemy) else global_position + Vector3.FORWARD)
			away.y = 0
			_move_to(global_position + away.normalized() * 15.0, 7.0, delta)
			if mats >= 10 and build_cd <= 0 and now() - last_hit_time < 1.0: _build_cover()
		Act.HEAL:
			_steer(Vector3.ZERO, delta); heal_t -= delta; _play_action("pick-up", 0.2)
			if heal_t <= 0 and heals > 0: heals -= 1; shield = minf(50.0, shield + 35.0); think_t = 0
		Act.CAMP:
			if global_position.distance_to(target_pos) > 2.5: _move_to(target_pos, 5.0, delta)
			else:
				_steer(Vector3.ZERO, delta); crouch_t -= delta
				if crouch_t <= 0: crouching = not crouching; crouch_t = randf_range(1.0, 3.0)
				rotation.y += delta * 0.4 # look around
		Act.BUILD_COVER:
			_steer(Vector3.ZERO, delta); think_t = minf(think_t, 0.3)
			if is_instance_valid(enemy): _combat(delta)
	if is_on_floor():
		if is_on_wall() and Vector2(velocity.x, velocity.z).length() > 1.0: velocity.y = 7.5
	else: velocity.y -= GRAVITY * delta
	move_and_slide()
