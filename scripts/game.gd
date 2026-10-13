extends Node3D
## Match controller: island generation, spawning, storm, HUD, end screen.
const ISLAND := 120.0
var combatants: Array = []
var player: Player
var storm_center := Vector3.ZERO
var storm_radius := 130.0
var storm_target := 130.0
var phase := 0
var phase_timer := 50.0
var shrinking := false
var storm_mesh: MeshInstance3D
var storm_audio: AudioStreamPlayer
var hud := {}
var minimap: Control
var over := false
var noise := FastNoiseLite.new()
var bus: Node3D
var bus_dir := Vector3.ZERO
var bus_t := 0.0
const BUS_TIME := 22.0
var loot: Array = []     # floor loot Area-less nodes: {node, weapon or kind}
var chests: Array = []
var match_time := 0.0
var bus_start := Vector3.ZERO

func _ready() -> void:
	randomize(); noise.seed = randi(); noise.frequency = 0.01
	_env(); _terrain(); _props(); _loot(); _bake_nav(); _storm(); _spawn(); _bus(); _hud()
	if Util.shot_tab in ["ground", "victory", "touch", "wide", "combat", "ai"]:
		for c in combatants:
			if c is Bot: c.drop(); c.gliding = false; c.glider.visible = false; c.global_position = _rand_point() + Vector3(0, 1, 0)
	match Util.shot_tab: # screenshot helpers (see Util)
		"ground", "victory", "touch":
			player.jump_from_bus(); player.state = Player.State.GROUND; player.glider.visible = false
			var ch: Node3D = chests[0]; player.global_position = ch.global_position + Vector3(0, 1, 3.5)
			player.yaw = 0.0; player.pitch = -0.25
			player.give_weapon(Weapons.make("ar", 4)); player.give_weapon(Weapons.make("shotgun", 3))
			if Util.shot_tab == "victory":
				await get_tree().create_timer(1.0).timeout; _end(true, "")
		"wide", "combat":
			player.jump_from_bus(); player.state = Player.State.GROUND; player.glider.visible = false
			player.give_weapon(Weapons.make("ar", 3))
			if Util.shot_tab == "wide":
				player.model.visible = false
				player.global_position = _ground(0, 60) + Vector3(0, 45, 0); player.pitch = -0.55; player.yaw = 0.0
				player.set_physics_process(false)
			else:
				var b: Combatant = combatants[1]; player.global_position = chests[1].global_position + Vector3(0, 1, 4)
				b.global_position = player.global_position + Vector3(1.5, 0, -8); player.yaw = 0.0; player.pitch = -0.12
				for c in combatants.slice(2): c.visible = false; c.process_mode = Node.PROCESS_MODE_DISABLED; c.get_node("CollisionShape3D").disabled = true
				Util.touch_fire = true
		"ai": # debug overlay screenshot: watch a cluster of bots from above
			player.jump_from_bus(); player.state = Player.State.GROUND; player.glider.visible = false
			var center: Vector3 = chests[2].global_position
			player.global_position = center + Vector3(60, 5, 60); player.process_mode = Node.PROCESS_MODE_DISABLED
			var cam := Camera3D.new(); add_child(cam); cam.current = true
			cam.global_position = center + Vector3(0, 13, 17); cam.look_at(center)
			var i := 0
			for c in combatants:
				if c is Bot:
					c.global_position = _ground(center.x + cos(i * 2.4) * (8 + i), center.z + sin(i * 2.4) * (8 + i)) + Vector3(0, 1, 0); i += 1
					if i % 2 == 0: c.give_weapon(Weapons.make("ar", 2))
		"glide":
			await get_tree().create_timer(1.0).timeout; player.jump_from_bus()

func height(x: float, z: float) -> float:
	var d := Vector2(x, z).length() / ISLAND
	# Rolling hills that stay above water inside the island, sloping to a beach at the edge.
	var hills := (noise.get_noise_2d(x, z) * 0.5 + 0.5) * 7.0 * (1.0 - clampf(d, 0, 1))
	return 0.4 + hills - smoothstep(0.82, 1.0, d) * 1.5 - maxf(0.0, d - 0.95) * 30.0

func _env() -> void:
	var low := Util.low_end()
	var we := WorldEnvironment.new(); var e := Environment.new()
	# Poly Haven HDRI sky (CC0) for both background and ambient light.
	var sky_mat := PanoramaSkyMaterial.new(); sky_mat.panorama = load("res://assets/sky/sky_1k.hdr"); sky_mat.energy_multiplier = 0.75
	e.background_mode = Environment.BG_SKY; e.sky = Sky.new(); e.sky.sky_material = sky_mat
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; e.ambient_light_energy = 0.6
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; e.tonemap_exposure = 0.85; e.tonemap_white = 6.0
	e.adjustment_enabled = true; e.adjustment_saturation = 1.2; e.adjustment_contrast = 1.05
	e.glow_enabled = true; e.glow_intensity = 0.4 if low else 0.7; e.glow_bloom = 0.05; e.glow_hdr_threshold = 1.1
	if not low:
		e.ssao_enabled = true; e.ssao_radius = 1.5; e.ssao_intensity = 1.6
		e.fog_enabled = true; e.fog_light_color = Color(0.75, 0.85, 1.0); e.fog_density = 0.0006; e.fog_sky_affect = 0.15
	we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85); sun.light_energy = 1.25
	sun.shadow_enabled = true; sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 80.0 if low else 160.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if low else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	var plane := PlaneMesh.new(); plane.size = Vector2(900, 900); plane.subdivide_width = 0 if low else 80; plane.subdivide_depth = plane.subdivide_width
	var water := MeshInstance3D.new(); water.mesh = plane; water.position.y = -1.2
	var wm := ShaderMaterial.new(); wm.shader = preload("res://shaders/water.gdshader")
	wm.set_shader_parameter("island_radius", ISLAND); water.material_override = wm
	add_child(water)

func _terrain() -> void:
	var size := ISLAND * 2.4; var res := 80
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / res
	for i in res:
		for j in res:
			var x0 := -size / 2 + i * step; var z0 := -size / 2 + j * step
			var p := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0, 0, z0 + step), Vector3(x0 + step, 0, z0 + step)]
			for k in 4: p[k].y = height(p[k].x, p[k].z)
			for v in [p[0], p[1], p[2], p[1], p[3], p[2]]:
				st.set_color(Color(0.85, 0.8, 0.5) if v.y < 0.3 else Color(0.3, 0.65, 0.25))
				st.add_vertex(v)
	st.generate_normals()
	var m := st.commit()
	var mi := MeshInstance3D.new(); mi.mesh = m
	var mat := ShaderMaterial.new(); mat.shader = preload("res://shaders/terrain.gdshader")
	for k in ["grass", "sand", "rock"]: mat.set_shader_parameter(k + "_tex", load("res://assets/textures/%s_diff.jpg" % k))
	mat.set_shader_parameter("grass_nrm", load("res://assets/textures/grass_nor_gl.jpg"))
	mat.set_shader_parameter("rock_nrm", load("res://assets/textures/rock_nor_gl.jpg"))
	mi.material_override = mat
	var body := StaticBody3D.new(); body.add_child(mi)
	var cs := CollisionShape3D.new(); cs.shape = m.create_trimesh_shape(); body.add_child(cs)
	body.add_to_group("nav"); add_child(body)

## Navmesh baked at runtime (on a thread) from the terrain, rocks, houses and chests.
func _bake_nav() -> void:
	nav_region = NavigationRegion3D.new(); var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"nav"
	nm.cell_size = 0.5; nm.cell_height = 0.25; nm.agent_radius = 0.5; nm.agent_height = 2.0
	nm.agent_max_climb = 0.5; nm.agent_max_slope = 40.0
	nm.filter_baking_aabb = AABB(Vector3(-ISLAND * 1.05, -5, -ISLAND * 1.05), Vector3(ISLAND * 2.1, 40, ISLAND * 2.1))
	nav_region.navigation_mesh = nm; add_child(nav_region)
	nav_region.bake_finished.connect(func(): nav_ready = true)
	nav_region.bake_navigation_mesh(true)

func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)

func _rand_point(r := ISLAND * 0.85) -> Vector3:
	var a := randf() * TAU; var d := sqrt(randf()) * r
	return _ground(cos(a) * d, sin(a) * d)

const TREES := ["res://assets/nature/tree_default.glb", "res://assets/nature/tree_cone.glb",
	"res://assets/nature/tree_detailed.glb", "res://assets/nature/tree_oak.glb"]
const ROCKS := ["res://assets/nature/rock_largeA.glb", "res://assets/nature/rock_largeC.glb",
	"res://assets/nature/rock_tallA.glb", "res://assets/nature/rock_smallA.glb"]
var HOUSES: Array = Array("acdefghkl".split("")).map(func(x): return "res://assets/buildings/building-type-%s.glb" % x)
var trees: Array = []

var house_spots: Array = []
var nav_ready := false
var nav_region: NavigationRegion3D

func _props() -> void:
	# Kenney Nature Kit trees: cheap cylinder collider for the trunk instead of trimesh.
	var tree_scenes := TREES.map(func(p): return load(p))
	for i in 100:
		var p := _rand_point(); var t := StaticBody3D.new(); t.position = p
		var m: Node3D = tree_scenes[randi() % tree_scenes.size()].instantiate()
		var sc := randf_range(4.5, 6.5); m.scale = Vector3.ONE * sc; m.rotation.y = randf() * TAU; t.add_child(m)
		var cs := CollisionShape3D.new(); var cyl := CylinderShape3D.new(); cyl.radius = 0.5; cyl.height = 6
		cs.shape = cyl; cs.position.y = 3; t.add_child(cs); t.set_meta("harvest", 15); add_child(t)
		if not Util.low_end(): Util.stylize(m, 0.01, 0.2)
		trees.append([m, randf() * TAU, randf_range(0.6, 1.2)])
	for i in 40:
		var r := Util.static_model(ROCKS[randi() % ROCKS.size()], randf_range(3, 5), _rand_point() - Vector3(0, 0.3, 0))
		r.rotation.y = randf() * TAU; r.set_meta("harvest", 20); r.add_to_group("nav"); add_child(r)
	for i in 14: # Kenney City Kit (Suburban) houses
		var h := Util.static_model(HOUSES[i % HOUSES.size()], 8.0, _rand_point(ISLAND * 0.7) - Vector3(0, 0.2, 0))
		h.rotation.y = randi() % 4 * PI / 2; h.set_meta("harvest", 10); h.add_to_group("nav"); add_child(h)
		Util.stylize(h, 0.004 if not Util.low_end() else 0.0, 0.15)
		house_spots.append(h.position)

# ---------------- Loot ----------------
func _loot() -> void:
	for i in 45: _spawn_floor_loot(_rand_point() + Vector3(0, 0.8, 0), Weapons.random_drop())
	for i in 22:
		var p: Vector3 = _rand_point()
		if i < house_spots.size(): p = house_spots[i] + Vector3(randf_range(-6, 6), 0, 6.5)
		p = _ground(p.x, p.z)
		var c := Util.static_box(Vector3(1.4, 0.9, 0.9), Color(0.85, 0.6, 0.1), p + Vector3(0, 0.45, 0))
		var lid := Util.mesh(Util.box(Vector3(1.5, 0.2, 1.0)), Color(1, 0.85, 0.3), Vector3(0, 0.5, 0))
		lid.material_override.emission_enabled = true; lid.material_override.emission = Color(1, 0.7, 0.1) * 0.6
		c.add_child(lid); var l := OmniLight3D.new(); l.light_color = Color(1, 0.8, 0.3); l.omni_range = 4; c.add_child(l)
		c.add_to_group("nav"); add_child(c); chests.append(c)

func _spawn_floor_loot(pos: Vector3, w: Dictionary) -> void:
	var n := Node3D.new(); n.position = pos; add_child(n)
	var g: Node3D = load(w.model).instantiate(); g.scale = Vector3.ONE * 1.4; n.add_child(g)
	var ring := TorusMesh.new(); ring.inner_radius = 0.5; ring.outer_radius = 0.65
	var rm := Util.mesh(ring, Weapons.color(w), Vector3(0, -0.6, 0))
	rm.material_override.emission_enabled = true; rm.material_override.emission = Weapons.color(w)
	n.add_child(rm)
	n.set_meta("weapon", w); loot.append(n)

func _pickup_check() -> void:
	if not is_instance_valid(player) or player.state != Player.State.GROUND: return
	for n in loot.duplicate():
		if not is_instance_valid(n): loot.erase(n); continue
		n.rotate_y(0.03)
		if n.global_position.distance_to(player.global_position + Vector3(0, 0.8, 0)) < 1.6:
			var free := false
			for i in range(1, 4): if player.slots[i] == null: free = true
			if free:
				player.give_weapon(n.get_meta("weapon")); _feed("Picked up " + Weapons.label(n.get_meta("weapon")))
				Util.sfx("reload", n.global_position); loot.erase(n); n.queue_free()

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
	b.give_weapon(w); loot.erase(n); n.queue_free()

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

func open_chest(p: Combatant, n: Node3D) -> void:
	if not n in chests: return
	chests.erase(n); Util.sfx("victory", n.global_position, -10)
	for k in 2: _spawn_floor_loot(n.global_position + Vector3(randf_range(-1.5, 1.5), 0.8, randf_range(1, 2)), Weapons.random_drop())
	for k in p.reserve: p.reserve[k] += {"light": 60, "heavy": 6, "shells": 10}[k]
	p.mats = mini(p.mats + 30, 999); p.shield = min(50.0, p.shield + 25); p.heals += 1
	if p == player: _feed("Chest opened: +ammo, +30 mats, +25 shield")
	n.queue_free()

func interact(p: Player) -> void:
	var n = nearest_interactable()
	if n == null: return
	if n in chests: open_chest(p, n); return
	else:
		var old = p.give_weapon(n.get_meta("weapon"))
		_feed("Picked up " + Weapons.label(n.get_meta("weapon")))
		loot.erase(n); n.queue_free()
		if old != null: _spawn_floor_loot(p.global_position + Vector3(0, 0.8, 0) - p.global_transform.basis.z, old)

# ---------------- Battle bus ----------------
func _bus() -> void:
	var a := randf() * TAU
	bus_start = Vector3(cos(a), 0, sin(a)) * ISLAND * 1.2 + Vector3(0, 70, 0)
	bus_dir = -Vector3(cos(a), 0, sin(a))
	bus = Node3D.new(); add_child(bus)
	bus.add_child(Util.mesh(Util.box(Vector3(3, 2.5, 7)), Color(0.2, 0.5, 1)))
	bus.add_child(Util.mesh(Util.box(Vector3(3.1, 0.8, 5)), Color(0.9, 0.95, 1), Vector3(0, 0.4, 0)))
	var bal := SphereMesh.new(); bal.radius = 3; bal.height = 6
	bus.add_child(Util.mesh(bal, Color(1, 0.4, 0.2), Vector3(0, 6, 0)))
	bus.look_at_from_position(bus_start, bus_start + bus_dir)
	player.state = Player.State.BUS; player.game = self
	player.get_node("CollisionShape3D").disabled = true
	player.yaw = atan2(-bus_dir.x, -bus_dir.z)
	for c in combatants:
		if c is Bot:
			c.start_in_bus(randf_range(BUS_TIME * 0.15, BUS_TIME * 0.85), _rand_point(ISLAND * 0.8))
	_feed("Press SPACE / JUMP to drop from the Storm Bus!")

func _update_bus(delta: float) -> void:
	if not is_instance_valid(bus): return
	bus_t += delta
	bus.global_position = bus_start + bus_dir * (bus_t / BUS_TIME) * ISLAND * 2.4
	if player.state == Player.State.BUS:
		player.global_position = bus.global_position - Vector3(0, 6, 0)
		if bus_t > BUS_TIME * 0.92: player.jump_from_bus()
	for c in combatants:
		if c is Bot and c.in_bus:
			c.global_position = bus.global_position - Vector3(0, 6, 0)
			if bus_t >= c.drop_at: c.drop()
	if bus_t > BUS_TIME: bus.queue_free()

func _storm() -> void:
	var cyl := CylinderMesh.new(); cyl.top_radius = 1; cyl.bottom_radius = 1; cyl.height = 200
	cyl.cap_top = false; cyl.cap_bottom = false
	storm_mesh = Util.mesh(cyl, Color(0.6, 0.2, 1, 0.35))
	storm_mesh.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(storm_mesh)
	storm_audio = AudioStreamPlayer.new(); var st: AudioStreamOggVorbis = load("res://assets/audio/storm.ogg").duplicate()
	st.loop = true; storm_audio.stream = st; storm_audio.volume_db = -80; add_child(storm_audio); storm_audio.play()

func _spawn() -> void:
	player = Player.new(); player.game = self; add_child(player); player.global_position = Vector3(0, 70, 0)
	_register(player)
	var names := ["Ace", "Blaze", "Cinder", "Dash", "Echo", "Flux", "Grit", "Hex", "Ion", "Jinx"]
	for i in Util.bot_count:
		var b := Bot.new(); b.game = self; b.display_name = names[i % names.size()] + str(i)
		add_child(b); b.global_position = Vector3(0, 70, 0); _register(b)

func _register(c: Combatant) -> void:
	combatants.append(c); c.died.connect(_on_died)

func _on_died(who: Combatant, killer) -> void:
	var kn: String = killer.display_name if killer else "The Storm"
	_feed("%s eliminated %s" % [kn, who.display_name])
	if who == player: _end(false, kn)
	else:
		await get_tree().create_timer(1.2).timeout # let the death animation play
		if is_instance_valid(who): who.queue_free()
		await get_tree().process_frame
		if _alive_count() == 1 and player.alive: _end(true, "")

func _alive_count() -> int:
	var n := 0
	for c in combatants: if is_instance_valid(c) and c.alive: n += 1
	return n

func _process(delta: float) -> void:
	combatants = combatants.filter(func(c): return is_instance_valid(c))
	match_time += delta
	for tr in trees: # wind sway on foliage
		tr[0].rotation.z = sin(match_time * tr[2] + tr[1]) * 0.035
		tr[0].rotation.x = cos(match_time * tr[2] * 0.8 + tr[1]) * 0.02
	_update_bus(delta); _pickup_check()
	# storm phases: wait, then shrink
	phase_timer -= delta
	if phase_timer <= 0:
		if shrinking or phase >= 6:
			shrinking = false; phase_timer = 25.0
		else:
			shrinking = true; phase += 1; phase_timer = 20.0
			storm_target = max(5.0, storm_radius * 0.55)
			var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * (storm_radius - storm_target) * 0.5
			storm_center += off
	if shrinking:
		storm_radius = move_toward(storm_radius, storm_target, delta * (storm_radius - storm_target + 1) / max(phase_timer, 0.1))
	storm_mesh.position = storm_center; storm_mesh.scale = Vector3(storm_radius, 1, storm_radius)
	for c in combatants:
		if (c is Bot and c.in_bus) or (c is Player and c.state == Player.State.BUS): continue
		var flat := Vector2(c.global_position.x - storm_center.x, c.global_position.z - storm_center.z)
		if c.alive and flat.length() > storm_radius:
			c.take_damage(delta * (2.0 + phase), null)
		if c.alive and c.global_position.y < -20: c.take_damage(9999, null)
	if is_instance_valid(player):
		var pf := Vector2(player.global_position.x - storm_center.x, player.global_position.z - storm_center.z)
		storm_audio.volume_db = -4.0 if (pf.length() > storm_radius and player.alive) else -80.0
	_update_hud()

# ---------------- HUD ----------------
func _label(parent: Node, pos: Vector2, size := 20) -> Label:
	var l := Label.new(); l.position = pos; l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK); l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l); return l

func _hud() -> void:
	var cl := CanvasLayer.new(); add_child(cl); hud.layer = cl
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE; cl.add_child(root)
	var cross := _label(root, Vector2.ZERO, 24); cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER); cross.position -= Vector2(8, 16)
	hud.shield = ProgressBar.new(); _anchor(hud.shield, 0, 1, Vector2(20, -80)); hud.shield.size = Vector2(300, 20)
	hud.shield.max_value = 50; hud.shield.modulate = Color(0.3, 0.6, 1); root.add_child(hud.shield)
	hud.health = ProgressBar.new(); _anchor(hud.health, 0, 1, Vector2(20, -55)); hud.health.size = Vector2(300, 24)
	hud.health.modulate = Color(0.3, 1, 0.3); root.add_child(hud.health)
	hud.ammo = _label(root, Vector2.ZERO, 28); _anchor(hud.ammo, 0, 1, Vector2(20, -230))
	hud.alive = _label(root, Vector2.ZERO, 22); _anchor(hud.alive, 1, 0, Vector2(-210, 220))
	hud.storm = _label(root, Vector2.ZERO, 18); _anchor(hud.storm, 1, 0, Vector2(-210, 250))
	hud.build = _label(root, Vector2.ZERO, 18); _anchor(hud.build, 0, 1, Vector2(20, -110))
	hud.feed = _label(root, Vector2(20, 20), 16)
	minimap = Control.new(); minimap.size = Vector2(200, 200); _anchor(minimap, 1, 0, Vector2(-210, 10))
	minimap.draw.connect(_draw_minimap); root.add_child(minimap)
	var tc := preload("res://scripts/touch_controls.gd").new(); tc.player = player
	tc.visible = Util.touch_enabled; root.add_child(tc); hud.touch = tc
	hud.prompt = _label(root, Vector2.ZERO, 22); _anchor(hud.prompt, 0.5, 0.5, Vector2(-120, 60))
	hud.slots = []
	for i in 4:
		var pnl := Panel.new(); pnl.size = Vector2(110, 60); _anchor(pnl, 0, 1, Vector2(20 + i * 118, -185))
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0, 0.5); sb.set_border_width_all(3); sb.set_corner_radius_all(8)
		pnl.add_theme_stylebox_override("panel", sb); root.add_child(pnl)
		var l := _label(pnl, Vector2(6, 4), 14); l.size = Vector2(100, 52); l.autowrap_mode = TextServer.AUTOWRAP_WORD
		hud.slots.append([pnl, sb, l])
	var pause := Button.new(); pause.text = "II"; pause.custom_minimum_size = Vector2(64, 64)
	_anchor(pause, 0.5, 0, Vector2(-32, 10)); pause.pressed.connect(_menu); root.add_child(pause)

func _anchor(c: Control, ax: float, ay: float, off: Vector2) -> void:
	var sz := c.size
	c.anchor_left = ax; c.anchor_right = ax; c.anchor_top = ay; c.anchor_bottom = ay
	c.offset_left = off.x; c.offset_top = off.y; c.offset_right = off.x + sz.x; c.offset_bottom = off.y + sz.y

func _menu() -> void:
	if not over: _end(false, "Quit")

var feed_lines: Array = []
func _feed(t: String) -> void:
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
	var n = nearest_interactable() if player.state == Player.State.GROUND else null
	if player.state == Player.State.BUS: hud.prompt.text = "[SPACE / JUMP] Drop from the bus"
	elif n == null: hud.prompt.text = ""
	elif n in chests: hud.prompt.text = "[E / USE] Open chest"
	else: hud.prompt.text = "[E / USE] Swap for " + Weapons.label(n.get_meta("weapon"))
	hud.alive.text = "Players left: %d" % _alive_count()
	hud.storm.text = ("Storm closing: %ds" if shrinking else "Storm shrinks in: %ds") % int(phase_timer)
	hud.build.text = "Mats: %d  %s" % [player.mats, ["[1-4] Items", "[Z] Wall", "[X] Floor", "[C/Q] Ramp"][player.build_mode]]
	minimap.queue_redraw()

func _draw_minimap() -> void:
	var s := 200.0 / (ISLAND * 2.4)
	var c := Vector2(100, 100)
	minimap.draw_rect(Rect2(0, 0, 200, 200), Color(0.1, 0.3, 0.6, 0.8))
	minimap.draw_circle(c, ISLAND * s, Color(0.3, 0.6, 0.3))
	minimap.draw_arc(c + Vector2(storm_center.x, storm_center.z) * s, storm_radius * s, 0, TAU, 48, Color(0.8, 0.3, 1), 2)
	if is_instance_valid(bus):
		minimap.draw_circle(c + Vector2(bus.global_position.x, bus.global_position.z) * s, 5, Color(0.2, 0.5, 1))
	if is_instance_valid(player):
		minimap.draw_circle(c + Vector2(player.global_position.x, player.global_position.z) * s, 4, Color.YELLOW)

func _end(won: bool, killer: String) -> void:
	if over: return
	over = true
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
	t.text = "#1 STORM CHAMPION!" if won else "ELIMINATED"
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.2) if won else Color(1, 0.3, 0.3))
	t.add_theme_constant_override("outline_size", 12)
	var sub := _label(vb, Vector2.ZERO, 26)
	sub.text = "Victory! You outlasted %d opponents." % Util.bot_count if won else ("You left the match - placed #%d" % place if killer == "Quit" else "Eliminated by %s - placed #%d" % [killer, place])
	var st := _label(vb, Vector2.ZERO, 24)
	st.text = "Eliminations: %d    Time: %d:%02d" % [player.kills, int(match_time) / 60, int(match_time) % 60]
	var rew := _label(vb, Vector2.ZERO, 26); rew.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	rew.text = "+%d XP    +%d Drop Coins    Battle Pass tier %d" % [rw.xp, rw.coins, rw.tier]
	if rw.unlocked.size() > 0:
		var un := _label(vb, Vector2.ZERO, 22); un.text = "Unlocked: " + ", ".join(rw.unlocked)
	for l in [t, sub, st, rew]: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 20); vb.add_child(hb)
	var b := Button.new(); b.text = "Back to Lobby"; b.custom_minimum_size = Vector2(280, 80); b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")); hb.add_child(b)
	var r := Button.new(); r.text = "Play Again"; r.custom_minimum_size = Vector2(280, 80); r.add_theme_font_size_override("font_size", 26)
	r.pressed.connect(func(): get_tree().reload_current_scene()); hb.add_child(r)
