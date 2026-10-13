extends Control
## Main menu with a slowly rotating "lobby" 3D background.
var cam_pivot: Node3D
var settings: PanelContainer

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var svc := SubViewportContainer.new(); svc.stretch = true
	svc.set_anchors_preset(PRESET_FULL_RECT); add_child(svc)
	var sv := SubViewport.new(); svc.add_child(sv)
	var world := Node3D.new(); sv.add_child(world)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.4, 0.3, 0.8)
	env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = 0.5
	world.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); world.add_child(sun)
	var stage := MeshInstance3D.new(); var cyl := CylinderMesh.new()
	cyl.top_radius = 3; cyl.bottom_radius = 3; cyl.height = 0.5; stage.mesh = cyl
	stage.material_override = Util.mat(Color(0.2, 0.8, 1)); world.add_child(stage)
	var hero := Util.make_character(Color(1, 0.5, 0.1)); hero.position.y = 0.25; world.add_child(hero)
	cam_pivot = Node3D.new(); world.add_child(cam_pivot)
	var cam := Camera3D.new(); cam.position = Vector3(0, 2, 6); cam.rotation_degrees.x = -10
	cam_pivot.add_child(cam)
	var box := VBoxContainer.new(); box.anchor_top = 0.5; box.anchor_bottom = 0.5
	box.offset_left = 60; box.offset_top = -180; box.add_theme_constant_override("separation", 14); add_child(box)
	var title := Label.new(); title.text = "STORM DROP"
	title.add_theme_font_size_override("font_size", 64); box.add_child(title)
	for b in [["PLAY", _play], ["SETTINGS", _settings], ["QUIT", func(): get_tree().quit()]]:
		var btn := Button.new(); btn.text = b[0]; btn.custom_minimum_size = Vector2(300, 80)
		btn.add_theme_font_size_override("font_size", 30)
		btn.pressed.connect(b[1]); btn.pressed.connect(func(): Util.sfx("click")); box.add_child(btn)
	settings = PanelContainer.new(); settings.anchor_top = 0.5; settings.anchor_bottom = 0.5
	settings.offset_left = 420; settings.offset_top = -180; settings.visible = false
	add_child(settings)
	var sb := VBoxContainer.new(); settings.add_child(sb)
	var l := Label.new(); l.text = "Mouse sensitivity"; sb.add_child(l)
	var s := HSlider.new(); s.min_value = 0.05; s.max_value = 1.0; s.step = 0.01
	s.value = Util.sensitivity; s.custom_minimum_size = Vector2(320, 50)
	s.value_changed.connect(func(v): Util.sensitivity = v); sb.add_child(s)
	var l2 := Label.new(); l2.text = "Bots"; sb.add_child(l2)
	var s2 := SpinBox.new(); s2.min_value = 1; s2.max_value = 40; s2.value = Util.bot_count
	s2.value_changed.connect(func(v): Util.bot_count = int(v)); sb.add_child(s2)
	var fs := CheckButton.new(); fs.text = "Fullscreen"
	fs.toggled.connect(func(on): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	sb.add_child(fs)
	var tc := CheckButton.new(); tc.text = "Touch controls"; tc.button_pressed = Util.touch_enabled
	tc.toggled.connect(func(on): Util.touch_enabled = on); sb.add_child(tc)
	for c in sb.get_children():
		c.add_theme_font_size_override("font_size", 26)

func _process(delta: float) -> void:
	cam_pivot.rotate_y(delta * 0.3)

func _play() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _settings() -> void:
	settings.visible = not settings.visible
