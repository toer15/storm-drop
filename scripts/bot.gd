class_name Bot
extends Combatant
## Simple AI: roam toward safe zone, engage nearest visible enemy.
var game
var target_pos := Vector3.ZERO
var think := 0.0
var enemy: Combatant

func _ready() -> void:
	setup_body("")
	var w := Weapons.random_drop(); w.damage *= 0.5 # bots are a bit weaker than players
	give_weapon(w)

func _physics_process(delta: float) -> void:
	super(delta)
	if not alive: return
	think -= delta
	if think <= 0:
		think = 0.5
		enemy = null
		var best := 40.0
		for c in game.combatants:
			if not is_instance_valid(c) or c == self or not c.alive: continue
			if c is Player and c.state == Player.State.BUS: continue
			var d := global_position.distance_to(c.global_position)
			if d < best: best = d; enemy = c
		if global_position.distance_to(target_pos) < 3 or randf() < 0.05:
			var a := randf() * TAU; var r: float = randf() * game.storm_radius * 0.8
			target_pos = game.storm_center + Vector3(cos(a) * r, 0, sin(a) * r)
	var dest := target_pos
	if is_instance_valid(enemy) and enemy.alive:
		var to := enemy.global_position - global_position
		look_at(Vector3(enemy.global_position.x, global_position.y, enemy.global_position.z))
		if to.length() > 15: dest = enemy.global_position
		else: dest = global_position + to.cross(Vector3.UP).normalized() * 3.0 # strafe
		if randf() < 0.3:
			var gun := global_position + Vector3(0, 1.4, 0)
			if weapon().get("ammo", 0) <= 0: reserve[ammo_kind(weapon())] = 99; reload()
			fire(gun, (enemy.global_position + Vector3(0, 1, 0) - gun).normalized(), 0.06)
	var flat := Vector3(dest.x - global_position.x, 0, dest.z - global_position.z)
	if flat.length() > 0.5:
		var v := flat.normalized() * 5.0; velocity.x = v.x; velocity.z = v.z
		if not is_instance_valid(enemy): look_at(global_position + flat)
	else:
		velocity.x = 0; velocity.z = 0
	if is_on_floor():
		if is_on_wall(): velocity.y = 7.0
	else: velocity.y -= GRAVITY * delta
	move_and_slide()
