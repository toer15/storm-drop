class_name Puppet
extends Combatant
## Network stand-in for a combatant simulated elsewhere: other human players (on every peer) and the host's bots
## (on clients). Position/animation are interpolated from snapshots. On the host, a remote human's Puppet also
## holds that player's authoritative health, shield and kills.
var net_key := ""
var peer_id := 0
var net_state := 2          # 0 bus, 1 falling, 2 gliding, 3 ground
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var net_anim := "idle"
var net_gun := "pick"
var glider: Node3D
var game
var seat := -1
var has_snap := false

func setup(key: String, nm: String, model_path: String, bb := "bb_none", pick := "pick_default") -> void:
	net_key = key; display_name = nm
	setup_body(model_path, bb, pick)
	glider = Node3D.new(); glider.visible = false; add_child(glider)
	var wing := PrismMesh.new(); wing.size = Vector3(3.2, 0.6, 1.4)
	glider.add_child(Util.mesh(wing, Color.from_hsv(randf(), 0.7, 1), Vector3(0, 3.0, 0)))
	var tag := Label3D.new(); tag.text = nm; tag.position.y = 2.3; tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40; tag.outline_size = 10; tag.pixel_size = 0.01; tag.visibility_range_end = 40.0
	tag.visible = key.begins_with("p"); add_child(tag)

func targetable() -> bool:
	return alive and net_state == 3

func apply_snap(pos: Vector3, yaw: float, anim: String, st: int, gun: String) -> void:
	target_pos = pos; target_yaw = yaw; net_anim = anim; net_state = st
	if not has_snap: global_position = pos; rotation.y = yaw; has_snap = true
	if gun != net_gun:
		net_gun = gun
		if gun == "pick": select_slot(0)
		else: slots[1] = Weapons.make(gun, 0); select_slot(1)

func take_damage(amount: float, killer = null) -> void:
	if Net.is_client():
		if game and killer == game.player: game.request_hit(net_key, amount)
		return
	super(amount, killer)

func _physics_process(delta: float) -> void:
	fire_cd -= delta; _shot_anim -= delta; _reload_anim -= delta
	var in_bus := net_state == 0
	$CollisionShape3D.disabled = in_bus or not alive
	if in_bus and game and game.bus_seat_transform(seat) != null:
		global_transform = game.bus_seat_transform(seat); visible = game.bus_visible_for_seats()
	else:
		visible = true
		global_position = global_position.lerp(target_pos, minf(1.0, delta * 12.0))
		if global_position.distance_to(target_pos) > 8.0: global_position = target_pos
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * 12.0))
	glider.visible = net_state == 2 and alive
	if model and alive: Util.play_anim(model, "sit" if in_bus else net_anim)
