extends Node3D
## Match controller: island (World), loot, Battle Bus, storm, HUD + map, and online sync.
## Offline: everything runs locally. Online: the host (listen or dedicated server) simulates bots, storm, bus,
## loot, chests, building and health; each client simulates only its own player and sends its state / hits.
const ISLAND := World.ISLAND
const WAIT := [75.0, 50.0, 45.0, 40.0, 35.0, 30.0, 25.0, 20.0, 20.0]
const SHRINK := [35.0, 32.0, 30.0, 26.0, 24.0, 20.0, 18.0, 16.0, 15.0]
var world: World
var combatants: Array = []
var player: Player
var storm_center := Vector3.ZERO
var storm_radius := ISLAND * 1.2
var storm_target := ISLAND * 1.2
var phase := 0
var phase_timer := WAIT[0]
var shrinking := false
var storm_mesh: MeshInstance3D
var storm_audio: AudioStreamPlayer
var hud := {}
var minimap: Control
var over := false
var bus: Node3D
var bus_dir := Vector3.ZERO
var bus_t := 0.0
const BUS_TIME := 42.0
const BUS_HEIGHT := 115.0
var loot: Array = []
var chests: Array = []
var match_time := 0.0
var bus_start := Vector3.ZERO
var bus_end := Vector3.ZERO
var trees: Array = []
var house_spots: Array = []
var nav_ready := false
var nav_region: NavigationRegion3D
# --- bus interior
var seats: Array = []           # local Transform3D per seat (on the bus node)
var bus_cam: Camera3D
var bus_view_inside := true
var bus_shell: Node3D
# --- online
var online := false
var is_host := true
var my_key := "p1"
var ent := {}                   # key -> Combatant (host: everything; client: own player + puppets)
var loot_by_id := {}
var chest_by_id := {}
var pieces := {}
var next_loot := 0
var next_piece := 0
var loaded_peers := {}
var roster: Array = []
var snap_t := 0.0
var state_t := 0.0
var map_tex: ImageTexture
var current_poi := ""
var big_map: Control
var crosshair: Crosshair

func _ready() -> void:
	online = Net.active() and Net.in_match
	is_host = Net.is_server()
	var sd: int = Net.match_seed if online else randi()
	seed(sd)
	world = World.new(sd); world.low = Util.low_end(); world.build_heights()
	_env(); world.build_terrain(self); world.build_roads(self); world.build_pois(self); world.build_nature(self)
	trees = world.trees; house_spots = world.house_spots
	map_tex = world.build_map_image(256)
	_loot(); _bus_route()
	if is_host: _bake_nav()
	_storm(); _spawn(); _build_bus()
	if player: _hud()
	if not Net.dedicated: Util.music("res://assets/music13/match.ogg")
	if online:
		if is_host:
			for c in ent.values(): _push_roster_entry(c)
		else:
			_handshake()
	_shot_setup()
	if "--nettest" in OS.get_cmdline_user_args(): _nettest()

func _handshake() -> void:
	while roster.is_empty() and is_inside_tree() and Net.active():
		_c_loaded.rpc_id(1)
		await get_tree().create_timer(1.0).timeout

## Automated online check (used by tools/nettest.sh): logs what each peer sees and exercises hits / building / loot.
func _nettest() -> void:
	var tag := "[nettest %s]" % (my_key if not Net.dedicated else "server")
	await get_tree().create_timer(4.0).timeout
	print(tag, " entities=", ent.size(), " puppets=", ent.values().filter(func(c): return c is Puppet).size(), " loot=", loot_by_id.size(), " chests=", chests.size(), " bus_t=%.1f" % bus_t)
	if is_instance_valid(player) and not is_host:
		# shoot the first bot we know about (host validates and applies damage)
		var target := ""
		for k in ent: if k.begins_with("b"): target = k; break
		var hp0: float = ent[target].health + ent[target].shield
		request_hit(target, 30.0)
		request_build(Transform3D(Basis(), player.global_position + Vector3(3, 0, 0)), Vector3(4, 3, 0.2))
		var lid: int = loot_by_id.keys()[0]
		await get_tree().create_timer(1.5).timeout
		print(tag, " hit %s: %.0f -> %.0f  pieces=%d" % [target, hp0, ent[target].health + ent[target].shield, pieces.size()])
		_c_take.rpc_id(1, lid, false) # too far away: host must refuse
		await get_tree().create_timer(1.0).timeout
		print(tag, " far loot %d still there: %s" % [lid, loot_by_id.has(lid)])
	await get_tree().create_timer(3.0).timeout
	var pos := []
	for k in ent: if k.begins_with("p"): pos.append("%s@%s st=%d hp=%.0f" % [k, str(ent[k].global_position.round()), _st_code(ent[k]), ent[k].health])
	print(tag, " humans: ", ", ".join(pos), " storm r=%.0f phase=%d alive=%d" % [storm_radius, phase, _alive_count()])
	if is_instance_valid(player) and player.state == Player.State.BUS: player.jump_from_bus()
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(player): print(tag, " after jump: state=%d y=%.0f" % [player.state, player.global_position.y])
	if not is_host:
		var other := []
		for k in ent: if k.begins_with("p") and k != my_key: other.append("%s st=%d y=%.0f" % [k, ent[k].net_state, ent[k].global_position.y])
		print(tag, " sees other humans: ", ", ".join(other))

# ---------------------------------------------------------------- helpers for older code
func height(x: float, z: float) -> float: return world.height(x, z)
func _ground(x: float, z: float) -> Vector3: return world.ground(x, z)
func _rand_point(r := ISLAND * 0.85) -> Vector3: return world.rand_point(r)

func nearest_human_dist(p: Vector3) -> float:
	var best := 1e9
	for c in ent.values():
		if is_instance_valid(c) and (c is Player or (c is Puppet and c.peer_id > 0)) and c.alive:
			best = minf(best, c.global_position.distance_to(p))
	return best

func _env() -> void:
	var low := Util.low_end()
	var we := WorldEnvironment.new(); var e := Environment.new()
	var sky_mat := PanoramaSkyMaterial.new(); sky_mat.panorama = load("res://assets/sky/sky_1k.hdr"); sky_mat.energy_multiplier = 0.75
	e.background_mode = Environment.BG_SKY; e.sky = Sky.new(); e.sky.sky_material = sky_mat
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; e.ambient_light_energy = 0.6
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; e.tonemap_exposure = 0.85; e.tonemap_white = 6.0
	e.adjustment_enabled = true; e.adjustment_saturation = 1.2; e.adjustment_contrast = 1.05
	e.glow_enabled = true; e.glow_intensity = 0.4 if low else 0.7; e.glow_bloom = 0.05; e.glow_hdr_threshold = 1.1
	e.fog_enabled = true; e.fog_light_color = Color(0.75, 0.85, 1.0); e.fog_density = 0.0012 if low else 0.0007; e.fog_sky_affect = 0.1
	if not low:
		e.ssao_enabled = true; e.ssao_radius = 1.5; e.ssao_intensity = 1.6
	we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85); sun.light_energy = 1.25
	sun.shadow_enabled = true; sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 70.0 if low else 150.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if low else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	var plane := PlaneMesh.new(); plane.size = Vector2(2000, 2000); plane.subdivide_width = 0 if low else 120; plane.subdivide_depth = plane.subdivide_width
	var water := MeshInstance3D.new(); water.mesh = plane; water.position.y = -1.2
	var wm := ShaderMaterial.new(); wm.shader = preload("res://shaders/water.gdshader")
	wm.set_shader_parameter("island_radius", ISLAND); water.material_override = wm
	add_child(water)

## Navmesh baked at runtime on a thread (host only; clients never run bots).
func _bake_nav() -> void:
	nav_region = NavigationRegion3D.new(); var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"nav"
	nm.cell_size = 1.0; nm.cell_height = 0.25; nm.agent_radius = 1.0; nm.agent_height = 2.0
	nm.agent_max_climb = 0.75; nm.agent_max_slope = 40.0
	nm.filter_baking_aabb = AABB(Vector3(-ISLAND * 1.02, -5, -ISLAND * 1.02), Vector3(ISLAND * 2.04, 90, ISLAND * 2.04))
	nav_region.navigation_mesh = nm; add_child(nav_region)
	var t0 := Time.get_ticks_msec()
	nav_region.bake_finished.connect(func(): nav_ready = true; print("[game] navmesh baked in %d ms" % (Time.get_ticks_msec() - t0)))
	nav_region.bake_navigation_mesh(true)

# ---------------------------------------------------------------- loot (ids are identical on every peer)
func _loot() -> void:
	var rng := world.rng
	for i in 140:
		var p := world.rand_point()
		if p.y < 0.3: continue
		_add_loot(next_loot, p + Vector3(0, 0.8, 0), Weapons.random_drop(rng)); next_loot += 1
	var spots: Array = house_spots.duplicate()
	for i in 60:
		var p: Vector3 = world.rand_point()
		if i < spots.size(): p = spots[i] + Vector3(rng.randf_range(-6, 6), 0, 7.5)
		p = world.ground(p.x, p.z)
		if p.y < 0.3: continue
		var c := Util.static_box(Vector3(1.3, 1.0, 1.1), Color(0.85, 0.6, 0.1), p + Vector3(0, 0.5, 0))
		for mi in c.find_children("*", "MeshInstance3D", true, false): mi.visible = false
		var cm: Node3D = load("res://assets/props13/chest.glb").instantiate(); cm.name = "ChestModel"
		cm.scale = Vector3.ONE * 0.62; cm.position = Vector3(0, -0.5, 0); cm.rotation.y = PI; c.add_child(cm)
		Util.stylize(cm, 0.0, 0.45); World.vis(c, 120.0)
		var l := OmniLight3D.new(); l.light_color = Color(1, 0.8, 0.3); l.omni_range = 4; l.position.y = 0.6
		l.distance_fade_enabled = true; l.distance_fade_begin = 40; l.distance_fade_length = 10; c.add_child(l)
		c.add_to_group("nav"); add_child(c); chests.append(c)
		c.set_meta("id", chests.size() - 1); chest_by_id[chests.size() - 1] = c

func _add_loot(id: int, pos: Vector3, w: Dictionary) -> Node3D:
	var n := Node3D.new(); n.position = pos; add_child(n)
	var g: Node3D = Gear.make_gun(w.type); g.scale = Vector3.ONE * 1.3; g.rotation.z = 0.25; n.add_child(g)
	var ring := TorusMesh.new(); ring.inner_radius = 0.5; ring.outer_radius = 0.65
	var rm := Util.mesh(ring, Weapons.color(w), Vector3(0, -0.6, 0))
	rm.material_override.emission_enabled = true; rm.material_override.emission = Weapons.color(w)
	n.add_child(rm); World.vis(n, 90.0)
	n.set_meta("weapon", w); n.set_meta("id", id); loot.append(n); loot_by_id[id] = n
	return n

## Host: create loot and tell everyone.
func _spawn_floor_loot(pos: Vector3, w: Dictionary) -> void:
	if not is_host: return
	var id := next_loot; next_loot += 1
	_add_loot(id, pos, w)
	if online: _rpc_all("_s_loot", [id, pos, w])

func _remove_loot(id: int) -> void:
	var n = loot_by_id.get(id)
	loot_by_id.erase(id)
	if n and is_instance_valid(n): loot.erase(n); n.queue_free()
	if online and is_host: _rpc_all("_s_loot_gone", [id])

func _pickup_check() -> void:
	if not is_instance_valid(player) or player.state != Player.State.GROUND: return
	var now := Time.get_ticks_msec()
	for n in loot.duplicate():
		if not is_instance_valid(n): loot.erase(n); continue
		n.rotate_y(0.03)
		if n.global_position.distance_to(player.global_position + Vector3(0, 0.8, 0)) < 1.6:
			var free := false
			for i in range(1, 4): if player.slots[i] == null: free = true
			if not free: continue
			if online and not is_host:
				if now - int(n.get_meta("asked", 0)) > 800: n.set_meta("asked", now); _c_take.rpc_id(1, n.get_meta("id"), false)
			else:
				player.give_weapon(n.get_meta("weapon")); _feed("Picked up " + Weapons.label(n.get_meta("weapon")))
				Util.sfx("reload", n.global_position); _remove_loot(n.get_meta("id"))

func nearest_loot(pos: Vector3, max_d: float):
	var best = null; var bd := max_d
	for n in loot:
		if is_instance_valid(n):
			var d: float = n.global_position.distance_to(pos)
			if d < bd: bd = d; best = n
	return best

func bot_try_pickup(b: Bot) -> void:
	var n = nearest_loot(b.global_position, 2.0)
	if n == null: return
	var w: Dictionary = n.get_meta("weapon").duplicate(); w.damage *= 0.5
	var free := false
	for i in range(1, 4): if b.slots[i] == null: free = true
	if not free and w.rarity <= b.weapon().get("rarity", 0): return
	b.give_weapon(w); _remove_loot(n.get_meta("id"))

func nearest_interactable():
	var best = null; var bd := 2.6
	for n in loot + chests:
		if is_instance_valid(n):
			var d: float = n.global_position.distance_to(player.global_position)
			if d < bd: bd = d; best = n
	return best

func nearest_chest(pos: Vector3, max_d: float):
	var best = null; var bd := max_d
	for n in chests:
		if is_instance_valid(n):
			var d: float = n.global_position.distance_to(pos)
			if d < bd: bd = d; best = n
	return best

## Host only. Rewards go to the opener (a remote player's ammo/mats/heals are sent to their client).
func open_chest(p: Combatant, n: Node3D) -> void:
	if not n in chests or not is_host: return
	var id: int = n.get_meta("id")
	_chest_fx(id)
	if online: _rpc_all("_s_chest", [id])
	for k in 2: _spawn_floor_loot(n.global_position + Vector3(randf_range(-1.5, 1.5), 0.8, randf_range(1, 2)), Weapons.random_drop())
	p.shield = min(50.0, p.shield + 25)
	if p is Puppet and p.peer_id > 0: _s_chest_reward.rpc_id(p.peer_id)
	else: _chest_reward(p)

func _chest_reward(p: Combatant) -> void:
	for k in p.reserve: p.reserve[k] += {"light": 60, "heavy": 6, "shells": 10, "rockets": 1}[k]
	p.mats = mini(p.mats + 30, 999); p.heals += 1
	if p == player: _feed("Chest opened: +ammo, +30 mats, +25 shield")

func _chest_fx(id: int) -> void:
	var n = chest_by_id.get(id)
	if n == null or not is_instance_valid(n) or not n in chests: return
	chests.erase(n); Util.sfx("victory", n.global_position, -10)
	var cap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	if cap:
		for a in cap.get_animation_list(): if a.ends_with("Chest_Open"): cap.play(a)
	n.remove_from_group("nav")
	get_tree().create_timer(1.2).timeout.connect(n.queue_free)

func interact(p: Player) -> void:
	var n = nearest_interactable()
	if n == null: return
	if online and not is_host:
		if n in chests: _c_chest.rpc_id(1, n.get_meta("id"))
		else: _c_take.rpc_id(1, n.get_meta("id"), true)
		return
	if n in chests: open_chest(p, n); return
	var old = p.give_weapon(n.get_meta("weapon"))
	_feed("Picked up " + Weapons.label(n.get_meta("weapon")))
	_remove_loot(n.get_meta("id"))
	if old != null: _spawn_floor_loot(p.global_position + Vector3(0, 0.8, 0) - p.global_transform.basis.z, old)

# ---------------------------------------------------------------- building (host-authoritative)
func spawn_piece(xf: Transform3D, size: Vector3, id := -1) -> Node3D:
	if id < 0:
		if not is_host: return null
		id = next_piece; next_piece += 1
		if online: _rpc_all("_s_piece", [id, xf, size])
	var piece := Util.static_box(size, Color(0.7, 0.5, 0.3), Vector3.ZERO)
	piece.set_script(load("res://scripts/build_piece.gd"))
	piece.set_meta("id", id); add_child(piece); piece.global_transform = xf
	pieces[id] = piece
	return piece

func request_build(xf: Transform3D, size: Vector3) -> void:
	if online and not is_host: _c_build.rpc_id(1, xf, size)
	else: spawn_piece(xf, size)

func piece_hit(piece: Node3D, amount: float) -> void:
	if online and not is_host: _c_piece_hit.rpc_id(1, piece.get_meta("id"), amount); return
	piece.hp -= amount
	if piece.hp <= 0: _remove_piece(piece.get_meta("id"))

func _remove_piece(id: int) -> void:
	var p = pieces.get(id); pieces.erase(id)
	if p and is_instance_valid(p): p.queue_free()
	if online and is_host: _rpc_all("_s_piece_gone", [id])

# ---------------------------------------------------------------- Battle Bus
## Route crosses the island through a random chord; seeded so every peer agrees.
func _bus_route() -> void:
	var a := world.rng.randf() * TAU; var off := world.rng.randf_range(-0.35, 0.35) * ISLAND
	var dir := -Vector3(cos(a), 0, sin(a)); var side := Vector3(-dir.z, 0, dir.x)
	bus_start = -dir * ISLAND * 1.25 + side * off + Vector3(0, BUS_HEIGHT, 0)
	bus_end = dir * ISLAND * 1.25 + side * off + Vector3(0, BUS_HEIGHT, 0)
	bus_dir = dir

## Bus model: "Bus" by Poly by Google (CC-BY 3.0) + "Hot air balloon" by Poly by Google (CC-BY 3.0), see CREDITS.md.
## The exterior shell is on render layer 2 so the interior camera (which hides layer 2) sees the cabin we build
## here: floor, ceiling, walls with window gaps and 52 seats (13 rows of 2+2).
func _build_bus() -> void:
	bus = Node3D.new(); bus.name = "BattleBus"; add_child(bus)
	bus_shell = Node3D.new(); bus.add_child(bus_shell)
	var bm: Node3D = load("res://assets/bus14/bus.glb").instantiate(); bm.scale = Vector3.ONE * 0.1; bm.rotation.y = PI
	bus_shell.add_child(bm)
	for gi: GeometryInstance3D in bm.find_children("*", "GeometryInstance3D", true, false): gi.layers = 2
	Util.stylize(bm, 0.0, 0.25)
	var bal: Node3D = load("res://assets/bus14/balloon.glb").instantiate(); bal.scale = Vector3.ONE * 0.036
	bal.rotation.x = -PI / 2; bal.position = Vector3(0, 9.0, 0); bus.add_child(bal); bal.name = "Balloon"
	for gi: GeometryInstance3D in bal.find_children("*", "GeometryInstance3D", true, false): gi.layers = 2
	bal.position.y = 6.2
	for rp: Vector3 in [Vector3(-2.0, 4.85, -6.5), Vector3(2.0, 4.85, -6.5), Vector3(-2.0, 4.85, 6.5), Vector3(2.0, 4.85, 6.5), Vector3(-2.0, 4.85, 0), Vector3(2.0, 4.85, 0)]:
		var top := Vector3(signf(rp.x) * 0.6, 6.4, signf(rp.z) * 0.6 if rp.z != 0 else 0.0)
		var axis: Vector3 = top - rp
		var rope := MeshInstance3D.new(); rope.mesh = Util.box(Vector3(0.07, 1, 0.07)); rope.material_override = Util.mat(Color(0.3, 0.22, 0.12))
		var yb: Vector3 = axis.normalized(); var xb: Vector3 = yb.cross(Vector3.FORWARD if absf(yb.z) < 0.9 else Vector3.RIGHT).normalized(); var zb: Vector3 = xb.cross(yb)
		rope.transform = Transform3D(Basis(xb, yb * axis.length(), zb), (rp + top) / 2); rope.layers = 2; bus.add_child(rope)
	# cabin interior (layer 1, seen from inside; mostly hidden by the shell from outside)
	var cabin := Node3D.new(); cabin.name = "Cabin"; bus.add_child(cabin)
	var L := 14.0; var W := 4.3; var H := 3.0; var floor_y := 0.75
	var wall_c := Color(0.92, 0.9, 0.85); var seat_c := Color(0.15, 0.35, 0.8)
	cabin.add_child(Util.mesh(Util.box(Vector3(W, 0.1, L)), Color(0.3, 0.3, 0.33), Vector3(0, floor_y, 0)))
	cabin.add_child(Util.mesh(Util.box(Vector3(W, 0.1, L)), wall_c, Vector3(0, floor_y + H, 0)))
	cabin.add_child(Util.mesh(Util.box(Vector3(0.6, 0.02, L - 1)), Color(1, 0.95, 0.8), Vector3(0, floor_y + H - 0.06, 0))) # light strip
	for sx in [-1, 1]:
		cabin.add_child(Util.mesh(Util.box(Vector3(0.1, 1.05, L)), wall_c, Vector3(sx * W / 2, floor_y + 0.5, 0)))
		cabin.add_child(Util.mesh(Util.box(Vector3(0.1, 0.5, L)), wall_c, Vector3(sx * W / 2, floor_y + H - 0.25, 0)))
		for k in 8: # window pillars
			cabin.add_child(Util.mesh(Util.box(Vector3(0.12, H - 1.5, 0.25)), Color(0.85, 0.75, 0.2), Vector3(sx * W / 2, floor_y + 1.05 + (H - 1.55) / 2, -L / 2 + k * L / 7.0)))
	cabin.add_child(Util.mesh(Util.box(Vector3(W, 1.0, 0.1)), wall_c, Vector3(0, floor_y + 0.5, -L / 2)))  # front dash (windscreen above)
	var back := Util.mesh(Util.box(Vector3(W, H, 0.1)), Color(0.85, 0.2, 0.2), Vector3(0, floor_y + H / 2, L / 2)); cabin.add_child(back)
	var sign := Label3D.new(); sign.text = "JUMP DOOR"; sign.font_size = 48; sign.pixel_size = 0.01; sign.position = Vector3(0, floor_y + 2.3, L / 2 - 0.08)
	sign.rotation.y = PI; sign.modulate = Color(1, 0.9, 0.3); cabin.add_child(sign)
	var steer := TorusMesh.new(); steer.inner_radius = 0.18; steer.outer_radius = 0.24
	var sw := Util.mesh(steer, Color(0.1, 0.1, 0.1), Vector3(-1.2, floor_y + 1.3, -L / 2 + 0.6)); sw.rotation.x = PI / 3; cabin.add_child(sw)
	var lamp := OmniLight3D.new(); lamp.position = Vector3(0, floor_y + H - 0.4, 0); lamp.omni_range = 12; lamp.light_energy = 1.4
	lamp.light_color = Color(1, 0.95, 0.85); lamp.shadow_enabled = false; cabin.add_child(lamp)
	seats.clear()
	for row in range(12, -1, -1): # seat 0 is in the back row, so players look forward over everyone
		for col in [-1.55, -0.75, 0.75, 1.55]:
			var z := -L / 2 + 1.8 + row * 0.92
			if row != 12 or absf(col) > 1.0: # back row aisle seats are the "players' seats" - add them below
				pass
			cabin.add_child(Util.mesh(Util.box(Vector3(0.7, 0.45, 0.6)), seat_c, Vector3(col, floor_y + 0.22, z + 0.05)))
			cabin.add_child(Util.mesh(Util.box(Vector3(0.7, 0.8, 0.12)), seat_c.darkened(0.2), Vector3(col, floor_y + 0.75, z + 0.38)))
			seats.append(Transform3D(Basis(), Vector3(col, floor_y + 0.02, z + 0.12)))
	# humans get the aisle seats of the back row first (best view)
	var order := [1, 2, 0, 3]
	var first := []
	for k in order: first.append(seats[k])
	for k in 4: seats[k] = first[k]
	for mi: GeometryInstance3D in cabin.find_children("*", "GeometryInstance3D", true, false): mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bus_cam = Camera3D.new(); bus_cam.cull_mask = 0xFFFFF & ~2; bus_cam.fov = 80; bus_cam.near = 0.05; bus_cam.far = 900; bus.add_child(bus_cam)
	bus.look_at_from_position(bus_start, bus_start + bus_dir)
	_update_bus(0.0)
	# seat everyone and plan the bots' drops
	var i := 0
	for c in ent.values():
		c.set_meta("seat", i); i += 1
		if c is Puppet: c.seat = c.get_meta("seat")
	if player:
		player.seat = player.get_meta("seat", 0); player.state = Player.State.BUS
		player.get_node("CollisionShape3D").disabled = true
		player.yaw = 0.0; player.pitch = -0.1
	if is_host:
		for c in ent.values():
			if c is Bot:
				var target := _bot_drop_target()
				c.start_in_bus(_drop_time_for(target), target, c.get_meta("seat"))
	_feed("Welcome aboard the Storm Bus!  [V] inside / outside view")

func _bot_drop_target() -> Vector3:
	# 65% of bots aim for a named location, the rest for a random spot near the route
	if randf() < 0.65:
		var p: Array = World.POIS[randi() % World.POIS.size()]
		var c: Vector2 = p[2] + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * p[3] * 0.6
		return world.ground(c.x, c.y)
	for k in 20:
		var q := world.rand_point()
		if q.y > 0.5: return q
	return world.ground(0, 0)

## Bots jump when the bus is closest to their target, plus a little human randomness.
func _drop_time_for(target: Vector3) -> float:
	var a := Vector2(bus_start.x, bus_start.z); var b := Vector2(bus_end.x, bus_end.z)
	var t := clampf((Vector2(target.x, target.z) - a).dot(b - a) / (b - a).length_squared(), 0.08, 0.88)
	return clampf(t * BUS_TIME + randf_range(-2.5, 1.0), BUS_TIME * 0.06, BUS_TIME * 0.9)

func bus_seat_transform(seat: int):
	if not is_instance_valid(bus) or seat < 0 or seat >= seats.size(): return null
	return bus.global_transform * seats[seat]

func bus_visible_for_seats() -> bool:
	return is_instance_valid(bus)

func bus_exit_point() -> Vector3:
	return bus.global_transform * Vector3(0, -0.5, 8.5) if is_instance_valid(bus) else Vector3(0, BUS_HEIGHT, 0)

func toggle_bus_view() -> void:
	bus_view_inside = not bus_view_inside

func _update_bus(delta: float) -> void:
	if not is_instance_valid(bus): return
	bus_t += delta
	var k := bus_t / BUS_TIME
	bus.global_position = bus_start.lerp(bus_end, k) + Vector3(0, sin(bus_t * 0.8) * 0.6, 0)
	if bus.has_node("Balloon"): bus.get_node("Balloon").rotation.y = bus_t * 0.1
	if is_instance_valid(player) and player.state == Player.State.BUS:
		player.global_transform = bus_seat_transform(player.seat)
		bus_cam.current = bus_view_inside
		if bus_view_inside:
			var seat_t: Transform3D = seats[player.seat]
			bus_cam.position = seat_t.origin + Vector3(0, 1.25, -0.05)
			bus_cam.rotation = Vector3(player.pitch, player.yaw, 0)
		else: player.cam.current = true
		if (is_host or not online) and bus_t > BUS_TIME * 0.92: player.jump_from_bus()
	if is_host:
		for c in ent.values():
			if is_instance_valid(c) and c is Bot and c.in_bus:
				c.global_transform = bus_seat_transform(c.seat)
				if bus_t >= c.drop_at: c.drop(bus_exit_point())
	if bus_t > BUS_TIME + 2.0:
		if player and player.state == Player.State.BUS: player.jump_from_bus()
		bus.queue_free()

# ---------------------------------------------------------------- storm
func _storm() -> void:
	var cyl := CylinderMesh.new(); cyl.top_radius = 1; cyl.bottom_radius = 1; cyl.height = 300
	cyl.cap_top = false; cyl.cap_bottom = false; cyl.radial_segments = 96
	storm_mesh = MeshInstance3D.new(); storm_mesh.mesh = cyl
	var sm := ShaderMaterial.new(); sm.shader = preload("res://shaders/storm.gdshader"); storm_mesh.material_override = sm
	storm_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if "--nostorm" in OS.get_cmdline_user_args(): storm_mesh.visible = false
	add_child(storm_mesh)
	storm_audio = AudioStreamPlayer.new(); var st: AudioStreamOggVorbis = load("res://assets/audio/storm.ogg").duplicate()
	st.loop = true; storm_audio.stream = st; storm_audio.volume_db = -80; add_child(storm_audio); storm_audio.play()

func _update_storm(delta: float) -> void:
	phase_timer -= delta
	if is_host and phase_timer <= 0:
		if shrinking or phase >= WAIT.size() - 1:
			shrinking = false; phase_timer = WAIT[mini(phase + 1, WAIT.size() - 1)]
		else:
			shrinking = true; phase += 1; phase_timer = SHRINK[mini(phase, SHRINK.size() - 1)]
			storm_target = max(6.0, storm_radius * (0.62 if phase < 3 else 0.55))
			var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).limit_length(1.0) * (storm_radius - storm_target) * 0.6
			var nc := storm_center + off
			if Vector2(nc.x, nc.z).length() > ISLAND * 0.7: nc = nc.normalized() * ISLAND * 0.7 # keep it over land
			storm_center = Vector3(nc.x, 0, nc.z)
	if shrinking:
		storm_radius = move_toward(storm_radius, storm_target, delta * (storm_radius - storm_target + 1) / max(phase_timer, 0.1))
	storm_mesh.position = storm_center; storm_mesh.scale = Vector3(storm_radius, 1, storm_radius)
	if is_host:
		for c in combatants:
			if not is_instance_valid(c) or not c.alive: continue
			if (c is Bot and c.in_bus) or (c is Player and c.state == Player.State.BUS) or (c is Puppet and c.net_state == 0): continue
			var flat := Vector2(c.global_position.x - storm_center.x, c.global_position.z - storm_center.z)
			if flat.length() > storm_radius: c.take_damage(delta * (1.0 + phase * 1.5), null)
			if c.global_position.y < -20 and not (c is Puppet): c.take_damage(9999, null)
	if is_instance_valid(player):
		var pf := Vector2(player.global_position.x - storm_center.x, player.global_position.z - storm_center.z)
		storm_audio.volume_db = -4.0 if (pf.length() > storm_radius and player.alive) else -80.0

# ---------------------------------------------------------------- spawning / roster
func _make_entry(c: Combatant, key: String, peer := 0) -> void:
	c.set_meta("key", key); c.set_meta("peer", peer); ent[key] = c; _register(c)

func _spawn() -> void:
	var names := ["Ace", "Blaze", "Cinder", "Dash", "Echo", "Flux", "Grit", "Hex", "Ion", "Jinx", "Kilo", "Lux", "Moss", "Nyx"]
	if not online:
		player = Player.new(); player.game = self; add_child(player); player.global_position = Vector3(0, BUS_HEIGHT, 0)
		_make_entry(player, "p1", 1)
		for i in Util.bot_count: _new_bot("b%d" % i, names[i % names.size()] + str(i))
		return
	my_key = "p%d" % Net.my_id()
	if not is_host:
		player = Player.new(); player.game = self; add_child(player); player.global_position = Vector3(0, BUS_HEIGHT, 0)
		player.display_name = Net.settings.name; _make_entry(player, my_key, Net.my_id())
		return # everyone else arrives in the roster from the host
	var ids: Array = Net.peers.keys(); ids.sort()
	for id in ids:
		var info: Dictionary = Net.peers[id]
		if id == 1 and not Net.dedicated:
			player = Player.new(); player.game = self; add_child(player); player.global_position = Vector3(0, BUS_HEIGHT, 0)
			player.display_name = info.name; _make_entry(player, "p1", 1)
		else:
			var pp := Puppet.new(); pp.game = self; pp.peer_id = id; add_child(pp)
			pp.setup("p%d" % id, info.name, _skin_path(info.get("skin", "")), info.get("bb", "bb_none"), info.get("pick", "pick_default"))
			pp.global_position = Vector3(0, BUS_HEIGHT, 0); _make_entry(pp, "p%d" % id, id)
			loaded_peers[id] = false
	for i in Net.match_bots: _new_bot("b%d" % i, names[i % names.size()] + str(i))

func _skin_path(skin: String) -> String:
	return Profile.CATALOG[skin].data.model if Profile.CATALOG.has(skin) else Util.CHARACTERS[0]

func _new_bot(key: String, nm: String) -> void:
	var b := Bot.new(); b.game = self; b.display_name = nm
	add_child(b); b.global_position = Vector3(0, BUS_HEIGHT, 0); _make_entry(b, key)

func _register(c: Combatant) -> void:
	combatants.append(c); c.died.connect(_on_died)

func _push_roster_entry(c: Combatant) -> void:
	roster.append([c.get_meta("key"), c.display_name, c.model.get_meta("path", Util.CHARACTERS[0]) if c.model else "",
		c.get_meta("bb", "bb_none"), c.get_meta("pick", "pick_default"), c.get_meta("seat", -1), c.get_meta("peer", 0)])

func _on_died(who: Combatant, killer) -> void:
	var kn: String = killer.display_name if killer else "The Storm"
	_feed("%s eliminated %s" % [kn, who.display_name])
	if online and is_host:
		_rpc_all("_s_died", [who.get_meta("key", ""), kn, killer.get_meta("key", "") if killer else ""])
		if killer is Puppet and killer.peer_id > 0: _s_kill.rpc_id(killer.peer_id, who.display_name)
	if who == player: _end(false, kn); return
	await get_tree().create_timer(1.2).timeout # let the death animation play
	if is_instance_valid(who) and not (who is Puppet): who.queue_free()
	elif is_instance_valid(who): who.visible = false; who.get_node("CollisionShape3D").disabled = true
	await get_tree().process_frame
	if is_host: _check_winner()

func _check_winner() -> void:
	if over and not Net.dedicated: return
	var alive := []
	for c in combatants: if is_instance_valid(c) and c.alive: alive.append(c)
	if alive.size() != 1: return
	var w: Combatant = alive[0]
	if online: _rpc_all("_s_winner", [w.get_meta("key", ""), w.display_name])
	if w == player: _end(true, "")
	elif Net.dedicated: _server_match_over(w.display_name)
	else: _feed("%s won the match!" % w.display_name)

func _alive_count() -> int:
	var n := 0
	for c in combatants: if is_instance_valid(c) and c.alive: n += 1
	return n

## Called from Combatant.take_damage (host): hit markers for whoever dealt it.
func on_damage(target: Combatant, killer, killed: bool) -> void:
	if killer == null or killer == target: return
	if killer == player and hud.has("cross"): hud.cross.hit_marker(killed)
	elif online and is_host and killer is Puppet and killer.peer_id > 0: _s_hitmark.rpc_id(killer.peer_id, killed)

# ---------------------------------------------------------------- main loop
func _process(delta: float) -> void:
	combatants = combatants.filter(func(c): return is_instance_valid(c))
	match_time += delta
	if is_instance_valid(player) or not Net.dedicated:
		var cam := get_viewport().get_camera_3d()
		var cp := cam.global_position if cam else Vector3.ZERO
		for tr in trees: # wind sway, only near the camera
			var m: Node3D = tr[0]
			if m.global_position.distance_squared_to(cp) < 6400.0:
				m.rotation.z = sin(match_time * tr[2] + tr[1]) * 0.035; m.rotation.x = cos(match_time * tr[2] * 0.8 + tr[1]) * 0.02
	_update_bus(delta); _pickup_check(); _update_storm(delta)
	if online: _net_tick(delta)
	_update_hud()

# ---------------------------------------------------------------- networking
func _rpc_all(method: String, args: Array) -> void:
	for id in loaded_peers:
		if loaded_peers[id]: callv("rpc_id", [id, method] + args)

static func _st_code(c: Combatant) -> int:
	if c is Player: return [0, 1, 2, 3][c.state]
	if c is Bot: return 0 if c.in_bus else (1 if c.falling else (2 if c.gliding else 3))
	if c is Puppet: return c.net_state
	return 3

func _net_tick(delta: float) -> void:
	if is_host:
		snap_t -= delta
		if snap_t <= 0:
			snap_t = 0.1
			var e := {}
			for k in ent:
				var c: Combatant = ent[k]
				if not is_instance_valid(c): continue
				var gun: String = "pick" if c.current == 0 else String(c.weapon().get("type", "pick"))
				e[k] = [c.global_position, c.rotation.y, c.cur_anim, _st_code(c), gun, c.health, c.shield, c.alive]
			var s := [storm_center, storm_radius, storm_target, phase, phase_timer, shrinking, bus_t, _alive_count()]
			for id in loaded_peers:
				if loaded_peers[id]: _s_snap.rpc_id(id, e, s)
	elif is_instance_valid(player) and player.alive:
		state_t -= delta
		if state_t <= 0:
			state_t = 0.05
			var gun: String = "pick" if player.current == 0 else String(player.weapon().get("type", "pick"))
			_c_state.rpc_id(1, player.global_position, player.rotation.y, player.cur_anim, _st_code(player), gun)

@rpc("any_peer", "reliable")
func _c_loaded() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host: return
	loaded_peers[id] = true
	_s_roster.rpc_id(id, roster, next_loot, loot_by_id.keys(), [storm_center, storm_radius, phase, phase_timer, shrinking, bus_t])
	# late loaders: replay current structures
	for pid in pieces: if is_instance_valid(pieces[pid]): _s_piece.rpc_id(id, pid, pieces[pid].global_transform, pieces[pid].get_child(1).shape.size)

@rpc("authority", "reliable")
func _s_roster(r: Array, _nl: int, loot_alive: Array, s: Array) -> void:
	roster = r
	var alive_set := {}
	for id in loot_alive: alive_set[id] = true
	for id in loot_by_id.keys(): if not alive_set.has(id): _remove_loot(id)
	for e in r:
		var key: String = e[0]
		if key == my_key:
			player.seat = e[5]; player.set_meta("seat", e[5]); continue
		if ent.has(key): continue
		var pp := Puppet.new(); pp.game = self; pp.peer_id = e[6]; add_child(pp)
		pp.setup(key, e[1], e[2] if e[2] != "" else Util.CHARACTERS[0], e[3], e[4])
		pp.seat = e[5]; pp.net_state = 0; pp.global_position = Vector3(0, BUS_HEIGHT, 0)
		_make_entry(pp, key, e[6])
	storm_center = s[0]; storm_radius = s[1]; phase = s[2]; phase_timer = s[3]; shrinking = s[4]; bus_t = s[5]

@rpc("authority", "unreliable_ordered")
func _s_snap(e: Dictionary, s: Array) -> void:
	storm_center = s[0]; storm_radius = s[1]; storm_target = s[2]; phase = s[3]; phase_timer = s[4]; shrinking = s[5]
	if absf(bus_t - s[6]) > 0.4: bus_t = s[6]
	hud["net_alive"] = s[7]
	for k in e:
		var d: Array = e[k]
		if k == my_key:
			if is_instance_valid(player): player.health = d[5]; player.shield = d[6]
			continue
		var c = ent.get(k)
		if c == null or not is_instance_valid(c): continue
		c.apply_snap(d[0], d[1], d[2], d[3], d[4]); c.health = d[5]; c.shield = d[6]
		if c.alive and not d[7]: c.alive = false; Util.play_anim(c.model, "die")

@rpc("any_peer", "unreliable_ordered")
func _c_state(pos: Vector3, yaw: float, anim: String, st: int, gun: String) -> void:
	var c = ent.get("p%d" % multiplayer.get_remote_sender_id())
	if c is Puppet and c.alive: c.apply_snap(pos, yaw, anim, st, gun)

func request_hit(key: String, amount: float) -> void:
	_c_hit.rpc_id(1, key, amount)

@rpc("any_peer", "reliable")
func _c_hit(key: String, amount: float) -> void:
	var shooter = ent.get("p%d" % multiplayer.get_remote_sender_id())
	var target = ent.get(key)
	if shooter == null or target == null or not shooter.alive or not target.alive: return
	if amount > 120.0 or shooter.global_position.distance_to(target.global_position) > 420.0: return # sanity checks
	target.take_damage(amount, shooter)

@rpc("authority", "reliable")
func _s_hitmark(kill: bool) -> void:
	if hud.has("cross"): hud.cross.hit_marker(kill)

@rpc("authority", "reliable")
func _s_kill(victim: String) -> void:
	if is_instance_valid(player): player.kills += 1
	_feed("You eliminated %s!" % victim)

@rpc("authority", "reliable")
func _s_died(key: String, killer_name: String, _killer_key: String) -> void:
	var c = ent.get(key)
	if c == null or not is_instance_valid(c): return
	if c == player:
		player.alive = false; player.health = 0; Util.play_anim(player.model, "die"); _end(false, killer_name)
	else:
		_feed("%s eliminated %s" % [killer_name, c.display_name])
		c.alive = false; Util.play_anim(c.model, "die")
		get_tree().create_timer(1.2).timeout.connect(func(): if is_instance_valid(c): c.visible = false)

@rpc("authority", "reliable")
func _s_winner(key: String, nm: String) -> void:
	if key == my_key: _end(true, "")
	else: _feed("%s won the match!" % nm)

@rpc("authority", "reliable")
func _s_to_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func net_shot(shooter: Combatant, origin: Vector3, end: Vector3, sound: String, big: bool) -> void:
	if is_host: _rpc_all_except(shooter.get_meta("peer", 0), "_s_shot", [shooter.get_meta("key", ""), origin, end, sound, big])
	elif shooter == player: _c_shot.rpc_id(1, origin, end, sound, big)

func _rpc_all_except(peer: int, method: String, args: Array) -> void:
	for id in loaded_peers:
		if loaded_peers[id] and id != peer: callv("rpc_id", [id, method] + args)

@rpc("any_peer", "unreliable")
func _c_shot(origin: Vector3, end: Vector3, sound: String, big: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	var c = ent.get("p%d" % id)
	if c: _shot_fx(c, origin, end, sound, big)
	_rpc_all_except(id, "_s_shot", ["p%d" % id, origin, end, sound, big])

@rpc("authority", "unreliable")
func _s_shot(key: String, origin: Vector3, end: Vector3, sound: String, big: bool) -> void:
	var c = ent.get(key)
	if c and is_instance_valid(c): _shot_fx(c, origin, end, sound, big)

func _shot_fx(c: Combatant, origin: Vector3, end: Vector3, sound: String, big: bool) -> void:
	c._shot_anim = 0.25
	if Net.dedicated: return
	if c.model and c.model.has_meta("mount"): Util.muzzle_flash(c.model.get_meta("mount").get_node_or_null("Gun"), big)
	c._tracer(origin, end, Color(1, 0.9, 0.4))
	if SoundCheck.ok(sound): Util.sfx(sound, origin, -6.0)

@rpc("any_peer", "reliable")
func _c_take(id: int, swap: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var n = loot_by_id.get(id); var c = ent.get("p%d" % sender)
	if n == null or c == null or not is_instance_valid(n) or n.global_position.distance_to(c.global_position) > 4.0: return
	var w: Dictionary = n.get_meta("weapon")
	_remove_loot(id)
	_s_give.rpc_id(sender, w, swap)

@rpc("authority", "reliable")
func _s_give(w: Dictionary, swap: bool) -> void:
	if not is_instance_valid(player): return
	var old = player.give_weapon(w); _feed("Picked up " + Weapons.label(w)); Util.sfx("reload")
	if swap and old != null: _c_drop.rpc_id(1, player.global_position + Vector3(0, 0.8, 0) - player.global_transform.basis.z, old)

@rpc("any_peer", "reliable")
func _c_drop(pos: Vector3, w: Dictionary) -> void:
	if w.has("type") and Weapons.TYPES.has(w.type): _spawn_floor_loot(pos, w)

@rpc("authority", "reliable")
func _s_loot(id: int, pos: Vector3, w: Dictionary) -> void:
	if not loot_by_id.has(id): _add_loot(id, pos, w)

@rpc("authority", "reliable")
func _s_loot_gone(id: int) -> void:
	_remove_loot(id)

@rpc("any_peer", "reliable")
func _c_chest(id: int) -> void:
	var c = ent.get("p%d" % multiplayer.get_remote_sender_id()); var n = chest_by_id.get(id)
	if c and n and is_instance_valid(n) and n.global_position.distance_to(c.global_position) < 4.0: open_chest(c, n)

@rpc("authority", "reliable")
func _s_chest(id: int) -> void:
	_chest_fx(id)

@rpc("authority", "reliable")
func _s_chest_reward() -> void:
	if is_instance_valid(player): _chest_reward(player)

@rpc("any_peer", "reliable")
func _c_build(xf: Transform3D, size: Vector3) -> void:
	if size.length() < 8.0: spawn_piece(xf, size)

@rpc("authority", "reliable")
func _s_piece(id: int, xf: Transform3D, size: Vector3) -> void:
	if not pieces.has(id): spawn_piece(xf, size, id)

@rpc("any_peer", "reliable")
func _c_piece_hit(id: int, amount: float) -> void:
	var p = pieces.get(id)
	if p and is_instance_valid(p): piece_hit(p, minf(amount, 200.0))

@rpc("authority", "reliable")
func _s_piece_gone(id: int) -> void:
	_remove_piece(id)

func net_peer_left(id: int, nm: String) -> void:
	loaded_peers.erase(id)
	var c = ent.get("p%d" % id)
	_feed("%s left the match" % nm)
	if c and is_instance_valid(c) and c.alive: c.take_damage(9999, null)

func net_server_lost() -> void:
	if not over: _end(false, "Disconnected")

## Dedicated server: send everyone back to the lobby a few seconds after the match ends.
func _server_match_over(winner: String) -> void:
	if over: return
	over = true
	print("[server] match over, winner: ", winner)
	await get_tree().create_timer(12.0).timeout
	_rpc_all("_s_to_lobby", [])
	Net.end_match()
	get_tree().change_scene_to_file("res://scenes/server.tscn")

# ---------------------------------------------------------------- HUD
func _label(parent: Node, pos: Vector2, size := 20) -> Label:
	var l := Label.new(); l.position = pos; l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK); l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l); return l

func _hud() -> void:
	var cl := CanvasLayer.new(); add_child(cl); hud.layer = cl
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE; cl.add_child(root); hud.root = root
	crosshair = Crosshair.new(); crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(crosshair); hud.cross = crosshair
	hud.shield = ProgressBar.new(); _anchor(hud.shield, 0, 1, Vector2(20, -80)); hud.shield.size = Vector2(300, 20)
	hud.shield.max_value = 50; hud.shield.modulate = Color(0.3, 0.6, 1); root.add_child(hud.shield)
	hud.health = ProgressBar.new(); _anchor(hud.health, 0, 1, Vector2(20, -55)); hud.health.size = Vector2(300, 24)
	hud.health.modulate = Color(0.3, 1, 0.3); root.add_child(hud.health)
	hud.ammo = _label(root, Vector2.ZERO, 28); _anchor(hud.ammo, 0, 1, Vector2(20, -230))
	hud.alive = _label(root, Vector2.ZERO, 22); _anchor(hud.alive, 1, 0, Vector2(-230, 240))
	hud.storm = _label(root, Vector2.ZERO, 18); _anchor(hud.storm, 1, 0, Vector2(-230, 270))
	hud.place = _label(root, Vector2.ZERO, 18); _anchor(hud.place, 1, 0, Vector2(-230, 296))
	hud.build = _label(root, Vector2.ZERO, 18); _anchor(hud.build, 0, 1, Vector2(20, -110))
	hud.feed = _label(root, Vector2(20, 20), 16)
	minimap = Control.new(); minimap.size = Vector2(220, 220); _anchor(minimap, 1, 0, Vector2(-230, 10))
	minimap.clip_contents = true; minimap.draw.connect(_draw_minimap); root.add_child(minimap)
	var tc := preload("res://scripts/touch_controls.gd").new(); tc.player = player
	tc.visible = Util.touch_enabled; root.add_child(tc); hud.touch = tc
	hud.prompt = _label(root, Vector2.ZERO, 26); hud.prompt.set_anchors_preset(Control.PRESET_CENTER)
	hud.prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hud.prompt.offset_left = -400; hud.prompt.offset_right = 400; hud.prompt.offset_top = 70
	hud.banner = _label(root, Vector2.ZERO, 40); hud.banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud.banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hud.banner.offset_left = -400; hud.banner.offset_right = 400; hud.banner.offset_top = 110
	hud.banner.add_theme_color_override("font_color", Color(1, 0.88, 0.35)); hud.banner.modulate.a = 0
	hud.slots = []
	for i in 4:
		var pnl := Panel.new(); pnl.size = Vector2(110, 60); _anchor(pnl, 0, 1, Vector2(20 + i * 118, -185))
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0, 0.5); sb.set_border_width_all(3); sb.set_corner_radius_all(8)
		pnl.add_theme_stylebox_override("panel", sb); root.add_child(pnl)
		var l := _label(pnl, Vector2(6, 4), 14); l.size = Vector2(100, 52); l.autowrap_mode = TextServer.AUTOWRAP_WORD
		hud.slots.append([pnl, sb, l])
	var pause := Button.new(); pause.text = "II"; pause.custom_minimum_size = Vector2(64, 64)
	_anchor(pause, 0.5, 0, Vector2(-70, 10)); pause.pressed.connect(_menu); root.add_child(pause)
	var mb := Button.new(); mb.text = "MAP"; mb.custom_minimum_size = Vector2(80, 64); mb.focus_mode = Control.FOCUS_NONE
	_anchor(mb, 0.5, 0, Vector2(4, 10)); mb.pressed.connect(toggle_map); root.add_child(mb)
	big_map = Control.new(); big_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); big_map.visible = false
	big_map.draw.connect(_draw_big_map); big_map.mouse_filter = Control.MOUSE_FILTER_STOP; root.add_child(big_map)
	big_map.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: toggle_map())

func toggle_map() -> void:
	big_map.visible = not big_map.visible
	if not big_map.visible and not Util.touch_enabled and player and player.alive: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif big_map.visible: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_M and big_map: toggle_map()

func _anchor(c: Control, ax: float, ay: float, off: Vector2) -> void:
	var sz := c.size
	c.anchor_left = ax; c.anchor_right = ax; c.anchor_top = ay; c.anchor_bottom = ay
	c.offset_left = off.x; c.offset_top = off.y; c.offset_right = off.x + sz.x; c.offset_bottom = off.y + sz.y

func _menu() -> void:
	if not over: _end(false, "Quit")

var feed_lines: Array = []
func _feed(t: String) -> void:
	if Net.dedicated: print("[feed] ", t); return
	feed_lines.append(t); if feed_lines.size() > 5: feed_lines.pop_front()
	if hud.has("feed"): hud.feed.text = "\n".join(feed_lines)

func _update_hud() -> void:
	if not hud.has("health") or not is_instance_valid(player): return
	hud.health.value = player.health; hud.shield.value = player.shield
	var w := player.weapon()
	if player.current == 0: hud.ammo.text = "Pickaxe"
	else: hud.ammo.text = "RELOADING..." if player.reloading else "%d / %d" % [w.ammo, player.reserve[Combatant.ammo_kind(w)]]
	for i in 4:
		var sl: Array = hud.slots[i]; var sw = player.slots[i]
		sl[2].text = "%d  %s" % [i + 1, "Pickaxe" if i == 0 else ("-" if sw == null else Weapons.label(sw))]
		sl[1].border_color = Color.WHITE if i == player.current else (Weapons.color(sw) if sw != null else Color(0.3, 0.3, 0.3))
	# crosshair: per weapon + bloom from movement, air time and recoil
	crosshair.visible = player.state == Player.State.GROUND and player.alive and player.build_mode == 0
	crosshair.weapon_type = "pick" if player.current == 0 else String(w.get("type", "ar"))
	var hs := Vector2(player.velocity.x, player.velocity.z).length()
	var want := clampf(hs / 9.0, 0, 1) * 0.6 + (0.5 if not player.is_on_floor() else 0.0) + clampf(player._shot_anim * 3.0, 0, 0.6)
	crosshair.spread = lerpf(crosshair.spread, minf(want, 1.2), 0.25)
	var n = nearest_interactable() if player.state == Player.State.GROUND else null
	match player.state:
		Player.State.BUS:
			hud.prompt.text = "[SPACE / JUMP] Jump out of the Storm Bus\n[V / VIEW] %s view" % ("outside" if bus_view_inside else "inside")
			if bus_t < BUS_TIME * 0.05: hud.prompt.text = "Doors open soon...\n[V / VIEW] %s view" % ("outside" if bus_view_inside else "inside")
		Player.State.FALL: hud.prompt.text = "Skydiving!  Glider opens automatically  [SPACE] open now"
		_:
			if n == null: hud.prompt.text = ""
			elif n in chests: hud.prompt.text = "[E / USE] Open chest"
			else: hud.prompt.text = "[E / USE] Swap for " + Weapons.label(n.get_meta("weapon"))
	var alive_n: int = hud.get("net_alive", _alive_count()) if online and not is_host else _alive_count()
	hud.alive.text = "Players left: %d" % alive_n
	hud.storm.text = ("Storm closing: %ds" if shrinking else "Storm shrinks in: %ds") % int(phase_timer)
	var poi := world.poi_at(player.global_position) if player.state == Player.State.GROUND else ""
	hud.place.text = poi if poi != "" else "Wilds"
	if poi != current_poi:
		current_poi = poi
		if poi != "":
			hud.banner.text = "— " + poi.to_upper() + " —"; hud.banner.modulate.a = 1.0
			var tw := create_tween(); tw.tween_interval(2.0); tw.tween_property(hud.banner, "modulate:a", 0.0, 1.0)
	hud.build.text = "Mats: %d  %s" % [player.mats, ["[1-4] Items", "[Z] Wall", "[X] Floor", "[C/Q] Ramp"][player.build_mode]]
	minimap.queue_redraw()
	if big_map.visible: big_map.queue_redraw()

const MINI_RANGE := 90.0   # metres from the centre to the edge of the minimap
func _draw_minimap() -> void:
	var sz := minimap.size; var c := sz / 2
	var center := Vector2(player.global_position.x, player.global_position.z)
	if player.state != Player.State.GROUND: center = Vector2.ZERO
	var rng_m := MINI_RANGE if player.state == Player.State.GROUND else World.SIZE / 2
	var s := c.x / rng_m
	var w2m := func(p: Vector2) -> Vector2: return c + (p - center) * s
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.1, 0.3, 0.6))
	var px := map_tex.get_width() / World.SIZE
	var src := Rect2((center - Vector2(rng_m, rng_m) + Vector2(World.SIZE / 2, World.SIZE / 2)) * px, Vector2(rng_m, rng_m) * 2 * px)
	minimap.draw_texture_rect_region(map_tex, Rect2(Vector2.ZERO, sz), src)
	_draw_overlays(minimap, w2m, s, rng_m > 200)
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.8), false, 3)

func _draw_big_map() -> void:
	var vs := big_map.size; var side := minf(vs.x, vs.y) - 60
	big_map.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.75))
	var o := (vs - Vector2(side, side)) / 2
	var s := side / World.SIZE
	var w2m := func(p: Vector2) -> Vector2: return o + (p + Vector2(World.SIZE / 2, World.SIZE / 2)) * s
	big_map.draw_texture_rect(map_tex, Rect2(o, Vector2(side, side)), false)
	_draw_overlays(big_map, w2m, s, true)
	var f := ThemeDB.fallback_font
	big_map.draw_string(f, o + Vector2(0, -12), "STORM DROP ISLAND  -  [M] / tap to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.85, 0.3))
	big_map.draw_rect(Rect2(o, Vector2(side, side)), Color(1, 1, 1, 0.9), false, 3)

func _draw_overlays(ci: Control, w2m: Callable, s: float, labels: bool) -> void:
	var f := ThemeDB.fallback_font
	# storm: current (purple) and next safe zone (white)
	ci.draw_arc(w2m.call(Vector2(storm_center.x, storm_center.z)), storm_radius * s, 0, TAU, 64, Color(0.8, 0.3, 1), 3)
	if shrinking or phase > 0: ci.draw_arc(w2m.call(Vector2(storm_center.x, storm_center.z)), storm_target * s, 0, TAU, 64, Color(1, 1, 1, 0.8), 2)
	if labels:
		for p in World.POIS:
			var q: Vector2 = w2m.call(p[2])
			ci.draw_circle(q, 4, Color(1, 0.88, 0.35))
			ci.draw_string_outline(f, q + Vector2(-80, -10), p[0].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 160, 15, 5, Color.BLACK)
			ci.draw_string(f, q + Vector2(-80, -10), p[0].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 160, 15, Color(1, 0.92, 0.6))
	# Battle Bus route line + bus position
	if is_instance_valid(bus) or (player and player.state == Player.State.BUS):
		var a: Vector2 = w2m.call(Vector2(bus_start.x, bus_start.z)); var b: Vector2 = w2m.call(Vector2(bus_end.x, bus_end.z))
		ci.draw_dashed_line(a, b, Color(1, 1, 1, 0.95), 3, 10)
		var dir := (b - a).normalized()
		ci.draw_colored_polygon(PackedVector2Array([b, b - dir * 16 + dir.orthogonal() * 8, b - dir * 16 - dir.orthogonal() * 8]), Color.WHITE)
		if is_instance_valid(bus):
			var bp: Vector2 = w2m.call(Vector2(bus.global_position.x, bus.global_position.z))
			ci.draw_circle(bp, 7, Color(0.2, 0.5, 1)); ci.draw_circle(bp, 4, Color(1, 0.6, 0.2))
	if is_instance_valid(player):
		var pp: Vector2 = w2m.call(Vector2(player.global_position.x, player.global_position.z))
		var fwd := Vector2(-sin(player.yaw), -cos(player.yaw)) if player.state != Player.State.BUS else Vector2(bus_dir.x, bus_dir.z)
		ci.draw_colored_polygon(PackedVector2Array([pp + fwd * 10, pp - fwd * 6 + fwd.orthogonal() * 6, pp - fwd * 6 - fwd.orthogonal() * 6]), Color.YELLOW)

func _end(won: bool, killer: String) -> void:
	if over: return
	over = true
	if not is_instance_valid(player): return
	var place := 1 if won else _alive_count() + 1
	var rw := Profile.award_match(player.kills, place, won, match_time)
	Util.sfx("victory" if won else "eliminated")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var panel := ColorRect.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.color = Color(0.25, 0.1, 0.45, 0.75) if won else Color(0, 0, 0, 0.65)
	hud.layer.add_child(panel)
	if hud.has("touch"): hud.touch.visible = false
	if won and is_instance_valid(player):
		Util.play_anim(player.model, Profile.item("emote").data.anim); player.emote_t = 99
		for i in 60: # confetti
			var cr := ColorRect.new(); cr.size = Vector2(10, 16); cr.color = Color.from_hsv(randf(), 0.8, 1)
			cr.position = Vector2(randf() * 1600, -40 - randf() * 600); panel.add_child(cr)
			var tw := create_tween(); tw.tween_property(cr, "position:y", 900.0, randf_range(2.5, 5)); tw.parallel().tween_property(cr, "rotation", randf() * 12, 4)
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH; vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.alignment = BoxContainer.ALIGNMENT_CENTER; vb.add_theme_constant_override("separation", 10); panel.add_child(vb)
	var t := _label(vb, Vector2.ZERO, 80)
	t.text = "#1 STORM CHAMPION!" if won else ("DISCONNECTED" if killer == "Disconnected" else "ELIMINATED")
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.2) if won else Color(1, 0.3, 0.3))
	t.add_theme_constant_override("outline_size", 12)
	var sub := _label(vb, Vector2.ZERO, 26)
	sub.text = "Victory! You outlasted %d opponents." % (combatants.size() - 1) if won else ("You left the match - placed #%d" % place if killer == "Quit" else ("Lost connection to the host." if killer == "Disconnected" else "Eliminated by %s - placed #%d" % [killer, place]))
	var st := _label(vb, Vector2.ZERO, 24)
	st.text = "Eliminations: %d    Time: %d:%02d" % [player.kills, int(match_time) / 60, int(match_time) % 60]
	var rew := _label(vb, Vector2.ZERO, 26); rew.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	rew.text = "+%d XP    +%d Drop Coins    Battle Pass tier %d" % [rw.xp, rw.coins, rw.tier]
	if rw.unlocked.size() > 0:
		var un := _label(vb, Vector2.ZERO, 22); un.text = "Unlocked: " + ", ".join(rw.unlocked)
	for l in [t, sub, st, rew]: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 20); vb.add_child(hb)
	var b := Button.new(); b.text = "Back to Lobby"; b.custom_minimum_size = Vector2(280, 80); b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(_back_to_lobby); hb.add_child(b)
	if not online:
		var r := Button.new(); r.text = "Play Again"; r.custom_minimum_size = Vector2(280, 80); r.add_theme_font_size_override("font_size", 26)
		r.pressed.connect(func(): get_tree().reload_current_scene()); hb.add_child(r)

func _back_to_lobby() -> void:
	if online and is_host and Net.active():
		_rpc_all("_s_to_lobby", []); Net.end_match()
	elif online and Net.active():
		pass # stay connected; the party screen shows the host's lobby
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ---------------------------------------------------------------- screenshot helpers (see Util)
func _shot_setup() -> void:
	if not player: return
	var tab := Util.shot_tab
	if tab in ["ground", "victory", "touch", "wide", "combat", "ai", "showcase", "xhair"]:
		bus_t = BUS_TIME + 1.0
		for c in combatants:
			if c is Bot: c.drop(_rand_point()); c.falling = false; c.gliding = false; c.glider.visible = false; c.global_position = _rand_point() + Vector3(0, 1, 0)
		player.jump_from_bus(); player.state = Player.State.GROUND; player.glider.visible = false
	match tab:
		"ground", "victory", "touch":
			var ch: Node3D = chests[0]; player.global_position = ch.global_position + Vector3(0, 1, 3.5)
			player.yaw = 0.0; player.pitch = -0.25
			player.give_weapon(Weapons.make("ar", 4)); player.give_weapon(Weapons.make("shotgun", 3))
			if tab == "victory":
				await get_tree().create_timer(1.0).timeout; _end(true, "")
		"wide":
			player.give_weapon(Weapons.make("ar", 3)); player.model.visible = false
			player.global_position = _ground(0, 90) + Vector3(0, 60, 0); player.pitch = -0.5; player.yaw = 0.0
			player.set_physics_process(false)
		"combat", "xhair":
			player.give_weapon(Weapons.make("ar", 3))
			var b: Combatant = combatants[1]
			var spot: Vector3 = _ground(World.POIS[1][2].x + 3, World.POIS[1][2].y + 16)
			player.global_position = spot + Vector3(0, 1, 0)
			b.global_position = _ground(spot.x + 1.5, spot.z - 9) + Vector3(0, 1, 0); player.yaw = 0.0; player.pitch = -0.1
			for c in combatants.slice(2): c.visible = false; c.process_mode = Node.PROCESS_MODE_DISABLED; c.get_node("CollisionShape3D").disabled = true
			Util.touch_fire = true
			if tab == "xhair":
				while is_inside_tree():
					await get_tree().create_timer(0.2).timeout; crosshair.hit_marker(false)
		"overview": # whole island from high above
			player.process_mode = Node.PROCESS_MODE_DISABLED
			var cam := Camera3D.new(); add_child(cam); cam.far = 2000; cam.current = true
			cam.global_position = Vector3(-60, 230, 300); cam.look_at(Vector3(10, 0, 0)); cam.fov = 70
			set_process(false); storm_mesh.visible = false
			for we in find_children("*", "WorldEnvironment", false, false): we.environment.fog_enabled = false
		"map":
			await get_tree().create_timer(0.5).timeout; toggle_map()
		"bus_inside":
			bus_view_inside = true; player.yaw = 0.25; player.pitch = -0.12
			set("bus_t", 6.0)
		"bus_outside":
			bus_view_inside = false; player.yaw = 2.6; player.pitch = -0.25; bus_t = 8.0
		"bots_jumping":
			bus_view_inside = false; player.yaw = 2.3; player.pitch = -0.32; bus_t = BUS_TIME * 0.3
			player.yaw = 0.45; player.pitch = -0.3
			var i := 0
			for c in combatants:
				if c is Bot: c.drop_at = bus_t + 3.0 + i * 0.15; i += 1
		"showcase":
			var spot: Vector3 = _ground(World.POIS[1][2].x + 10, World.POIS[1][2].y + 10)
			player.global_position = spot + Vector3(0, 0.5, 0); player.pitch = -0.08
			for c in combatants: if c != player: c.visible = false; c.process_mode = Node.PROCESS_MODE_DISABLED; c.get_node("CollisionShape3D").disabled = true

func _place_overview_labels() -> void:
	pass
