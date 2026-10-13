extends Node3D
## Match controller: island generation, spawning, storm, HUD, end screen.
const ISLAND := 120.0
var combatants: Array = []
var player: Player
var storm_center := Vector3.ZERO
var storm_radius := 130.0
var storm_target := 130.0
var phase := 0
var phase_timer := 30.0
var shrinking := false
var storm_mesh: MeshInstance3D
var hud := {}
var minimap: Control
var over := false
var noise := FastNoiseLite.new()

func _ready() -> void:
	randomize(); noise.seed = randi(); noise.frequency = 0.01
	_env(); _terrain(); _props(); _storm(); _spawn(); _hud()

func height(x: float, z: float) -> float:
	var d := Vector2(x, z).length() / ISLAND
	return noise.get_noise_2d(x, z) * 6.0 * (1.0 - clamp(d, 0, 1)) - max(0.0, d - 0.9) * 30.0

func _env() -> void:
	var we := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_SKY; e.sky = Sky.new(); e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, 40, 0); sun.shadow_enabled = true
	add_child(sun)
	var water := Util.mesh(Util.box(Vector3(1000, 1, 1000)), Color(0.1, 0.4, 0.8), Vector3(0, -3, 0)); add_child(water)

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
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true; mi.material_override = mat
	var body := StaticBody3D.new(); body.add_child(mi)
	var cs := CollisionShape3D.new(); cs.shape = m.create_trimesh_shape(); body.add_child(cs)
	add_child(body)

func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)

func _rand_point(r := ISLAND * 0.85) -> Vector3:
	var a := randf() * TAU; var d := sqrt(randf()) * r
	return _ground(cos(a) * d, sin(a) * d)

func _props() -> void:
	for i in 120: # trees
		var p := _rand_point(); var t := Util.static_box(Vector3(0.6, 4, 0.6), Color(0.45, 0.3, 0.15), p + Vector3(0, 2, 0))
		var cone := CylinderMesh.new(); cone.top_radius = 0; cone.bottom_radius = 2; cone.height = 4
		t.add_child(Util.mesh(cone, Color(0.1, 0.5, 0.2), Vector3(0, 3.5, 0))); add_child(t)
	for i in 50: # rocks
		var p := _rand_point(); var r := StaticBody3D.new(); r.position = p
		var s := SphereMesh.new(); var rad := randf_range(0.8, 2.2); s.radius = rad; s.height = rad * 1.4
		r.add_child(Util.mesh(s, Color(0.5, 0.5, 0.55)))
		var cs := CollisionShape3D.new(); var sh := SphereShape3D.new(); sh.radius = rad * 0.7; cs.shape = sh; r.add_child(cs)
		add_child(r)
	for i in 12: # houses: 4 walls with a door gap + roof
		var p := _rand_point(ISLAND * 0.7); var h := Node3D.new(); h.position = p; h.rotation.y = randf() * TAU
		var c := Color.from_hsv(randf(), 0.4, 0.9)
		h.add_child(Util.static_box(Vector3(8, 4, 0.3), c, Vector3(0, 2, -4)))
		h.add_child(Util.static_box(Vector3(0.3, 4, 8), c, Vector3(-4, 2, 0)))
		h.add_child(Util.static_box(Vector3(0.3, 4, 8), c, Vector3(4, 2, 0)))
		h.add_child(Util.static_box(Vector3(3, 4, 0.3), c, Vector3(-2.5, 2, 4)))
		h.add_child(Util.static_box(Vector3(3, 4, 0.3), c, Vector3(2.5, 2, 4)))
		h.add_child(Util.static_box(Vector3(8.6, 0.3, 8.6), Color(0.6, 0.2, 0.2), Vector3(0, 4.1, 0)))
		h.add_child(Util.static_box(Vector3(8, 0.2, 8), Color(0.5, 0.4, 0.3), Vector3(0, 0.1, 0)))
		add_child(h)

func _storm() -> void:
	var cyl := CylinderMesh.new(); cyl.top_radius = 1; cyl.bottom_radius = 1; cyl.height = 200
	cyl.cap_top = false; cyl.cap_bottom = false
	storm_mesh = Util.mesh(cyl, Color(0.6, 0.2, 1, 0.35))
	storm_mesh.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(storm_mesh)

func _spawn() -> void:
	player = Player.new(); add_child(player); player.global_position = _rand_point() + Vector3(0, 2, 0)
	_register(player)
	var names := ["Ace", "Blaze", "Cinder", "Dash", "Echo", "Flux", "Grit", "Hex", "Ion", "Jinx"]
	for i in Util.bot_count:
		var b := Bot.new(); b.game = self; b.display_name = names[i % names.size()] + str(i)
		add_child(b); b.global_position = _rand_point() + Vector3(0, 2, 0); _register(b)

func _register(c: Combatant) -> void:
	combatants.append(c); c.died.connect(_on_died)

func _on_died(who: Combatant, killer) -> void:
	var kn: String = killer.display_name if killer else "The Storm"
	_feed("%s eliminated %s" % [kn, who.display_name])
	if who == player: _end(false, kn)
	else:
		who.queue_free()
		await get_tree().process_frame
		if _alive_count() == 1 and player.alive: _end(true, "")

func _alive_count() -> int:
	var n := 0
	for c in combatants: if is_instance_valid(c) and c.alive: n += 1
	return n

func _process(delta: float) -> void:
	combatants = combatants.filter(func(c): return is_instance_valid(c))
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
		var flat := Vector2(c.global_position.x - storm_center.x, c.global_position.z - storm_center.z)
		if c.alive and flat.length() > storm_radius:
			c.take_damage(delta * (2.0 + phase), null)
		if c.alive and c.global_position.y < -20: c.take_damage(9999, null)
	_update_hud()

# ---------------- HUD ----------------
func _label(parent: Node, pos: Vector2, size := 20) -> Label:
	var l := Label.new(); l.position = pos; l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK); l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l); return l

func _hud() -> void:
	var cl := CanvasLayer.new(); add_child(cl); hud.layer = cl
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE; cl.add_child(root)
	var cross := _label(root, Vector2.ZERO, 24); cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER); cross.position -= Vector2(8, 16)
	hud.shield = ProgressBar.new(); _anchor(hud.shield, 0, 1, Vector2(20, -80)); hud.shield.size = Vector2(300, 20)
	hud.shield.max_value = 50; hud.shield.modulate = Color(0.3, 0.6, 1); root.add_child(hud.shield)
	hud.health = ProgressBar.new(); _anchor(hud.health, 0, 1, Vector2(20, -55)); hud.health.size = Vector2(300, 24)
	hud.health.modulate = Color(0.3, 1, 0.3); root.add_child(hud.health)
	hud.ammo = _label(root, Vector2.ZERO, 28); _anchor(hud.ammo, 0.5, 1, Vector2(-60, -50))
	hud.alive = _label(root, Vector2.ZERO, 22); _anchor(hud.alive, 1, 0, Vector2(-210, 220))
	hud.storm = _label(root, Vector2.ZERO, 18); _anchor(hud.storm, 1, 0, Vector2(-210, 250))
	hud.build = _label(root, Vector2.ZERO, 18); _anchor(hud.build, 0, 1, Vector2(20, -110))
	hud.feed = _label(root, Vector2(20, 20), 16)
	minimap = Control.new(); minimap.size = Vector2(200, 200); _anchor(minimap, 1, 0, Vector2(-210, 10))
	minimap.draw.connect(_draw_minimap); root.add_child(minimap)
	var tc := preload("res://scripts/touch_controls.gd").new(); tc.player = player
	tc.visible = Util.touch_enabled; root.add_child(tc); hud.touch = tc
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
	hud.ammo.text = "RELOADING..." if player.reloading else "%d / %d" % [player.ammo, player.reserve]
	hud.alive.text = "Players left: %d" % _alive_count()
	hud.storm.text = ("Storm closing: %ds" if shrinking else "Storm shrinks in: %ds") % int(phase_timer)
	hud.build.text = "Mats: %d  %s" % [player.mats, ["[1] Weapon", "[Z] Wall", "[X] Floor", "[C/Q] Ramp"][player.build_mode]]
	minimap.queue_redraw()

func _draw_minimap() -> void:
	var s := 200.0 / (ISLAND * 2.4)
	var c := Vector2(100, 100)
	minimap.draw_rect(Rect2(0, 0, 200, 200), Color(0.1, 0.3, 0.6, 0.8))
	minimap.draw_circle(c, ISLAND * s, Color(0.3, 0.6, 0.3))
	minimap.draw_arc(c + Vector2(storm_center.x, storm_center.z) * s, storm_radius * s, 0, TAU, 48, Color(0.8, 0.3, 1), 2)
	if is_instance_valid(player):
		minimap.draw_circle(c + Vector2(player.global_position.x, player.global_position.z) * s, 4, Color.YELLOW)

func _end(won: bool, killer: String) -> void:
	if over: return
	over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var panel := ColorRect.new(); panel.color = Color(0, 0, 0, 0.6); panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.layer.add_child(panel)
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH; vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.alignment = BoxContainer.ALIGNMENT_CENTER; panel.add_child(vb)
	if hud.has("touch"): hud.touch.visible = false
	var t := _label(vb, Vector2.ZERO, 64)
	t.text = "ELIMINATED" if not won else "#1 STORM CHAMPION!"
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.2) if won else Color(1, 0.3, 0.3))
	var sub := _label(vb, Vector2.ZERO, 24)
	sub.text = "You outlasted everyone!" if won else ("You left the match" if killer == "Quit" else "Eliminated by %s - placed #%d" % [killer, _alive_count() + 1])
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := Button.new(); b.text = "Back to Menu"; b.custom_minimum_size = Vector2(260, 70)
	b.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")); vb.add_child(b)
	var r := Button.new(); r.text = "Play Again"; r.custom_minimum_size = Vector2(260, 70)
	r.pressed.connect(func(): get_tree().reload_current_scene()); vb.add_child(r)
