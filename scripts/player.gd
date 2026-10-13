class_name Player
extends Combatant
## Third-person controller: battle bus drop + glider, building, pickaxe, inventory, emotes.
enum State { BUS, GLIDE, GROUND }
var state := State.GROUND
var game
var yaw := 0.0
var pitch := -0.2
var cam: Camera3D
var spring: SpringArm3D
var build_mode := 0 # 0 none, 1 wall, 2 floor, 3 ramp
var ghost: MeshInstance3D
var glider: Node3D
var emote_t := 0.0
const GRID := 4.0
## First-person mode (V): camera at the eyes, body hidden, a view-model gun with recoil / reload / muzzle flash.
var fp := false
var view: Node3D
var _view_kick := 0.0
var _view_type := ""

func _ready() -> void:
	display_name = "You"
	mats = 300
	setup_body(Profile.equipped.skin, Profile.equipped.backbling, Profile.equipped.pickaxe)
	select_slot(0)
	var pivot := Node3D.new(); pivot.name = "Pivot"; pivot.position.y = 1.6; add_child(pivot)
	spring = SpringArm3D.new(); spring.spring_length = 4.0; spring.position.x = 0.7
	spring.add_excluded_object(get_rid()); pivot.add_child(spring)
	cam = Camera3D.new(); cam.current = true; cam.far = 600; spring.add_child(cam)
	view = Node3D.new(); view.name = "ViewModel"; cam.add_child(view); view.visible = false
	fired.connect(func(w): _view_kick = 1.0; if fp and view.get_child_count() > 0: Util.muzzle_flash(view.get_child(0), w.type in ["shotgun", "rocket", "sniper"]))
	if "--fp" in OS.get_cmdline_user_args(): set_first_person(true)
	ghost = MeshInstance3D.new(); ghost.material_override = Util.mat(Color(0.3, 0.7, 1, 0.4))
	ghost.visible = false; ghost.top_level = true; add_child(ghost)
	glider = Node3D.new(); glider.visible = false; add_child(glider)
	var wing := PrismMesh.new(); wing.size = Vector3(3.2, 0.6, 1.4)
	glider.add_child(Util.mesh(wing, Color(1, 0.55, 0.1), Vector3(0, 3.0, 0)))
	glider.add_child(Util.mesh(Util.box(Vector3(0.05, 1.2, 0.05)), Color(0.2, 0.2, 0.2), Vector3(0, 2.3, 0)))
	if not Util.touch_enabled: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e: InputEvent) -> void:
	if not alive: return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * Util.sensitivity * 0.01
		pitch = clamp(pitch - e.relative.y * Util.sensitivity * 0.01, -1.3, 0.9)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if Util.touch_enabled: return # touches are emulated as clicks; use the FIRE button
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if build_mode > 0: _place()
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_R: reload()
			KEY_Z: _toggle(1)
			KEY_X: _toggle(2)
			KEY_C, KEY_Q: _toggle(3)
			KEY_1, KEY_2, KEY_3, KEY_4: _toggle(0); select_slot(e.physical_keycode - KEY_1)
			KEY_E: interact()
			KEY_B: emote()
			KEY_F3: Util.debug_ai = not Util.debug_ai
			KEY_V: set_first_person(not fp)
			KEY_SPACE: if state == State.BUS: jump_from_bus()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_first_person(on: bool) -> void:
	fp = on; _view_type = ""

func _update_view(delta: float) -> void:
	var on := fp and state == State.GROUND and alive
	if model: model.visible = not on
	view.visible = on
	spring.position.x = 0.0 if on else 0.7
	if not on: return
	spring.spring_length = 0.0
	var want := "pick" if current == 0 else String(weapon().get("type", "ar"))
	if want != _view_type:
		for c in view.get_children(): c.free()
		var g: Node3D = Gear.make_pickaxe(Profile.equipped.pickaxe) if current == 0 else Gear.make_gun(want)
		view.add_child(g); _view_type = want
		for mi: MeshInstance3D in g.find_children("*", "MeshInstance3D", true, false): mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_view_kick = move_toward(_view_kick, 0.0, delta * 6.0)
	var bob := sin(Time.get_ticks_msec() * 0.012) * 0.012 * clampf(Vector2(velocity.x, velocity.z).length() / 6.0, 0, 1)
	var g: Node3D = view.get_child(0)
	if current == 0:
		var sw := clampf(_shot_anim / 0.3, 0, 1)
		g.position = Vector3(0.32, -0.42 + bob, -0.55); g.rotation = Vector3(-0.5 - sw * 1.2, 0.3, -0.3)
	else:
		var rl := clampf(_reload_anim / 1.4, 0, 1); var dip := sin(rl * PI)
		g.position = Vector3(0.17, -0.17 + bob - dip * 0.15, -0.42 + _view_kick * 0.06)
		g.rotation = Vector3(_view_kick * 0.1 - dip * 0.5, 0.04, dip * 0.6)
		g.scale = Vector3.ONE * {"pistol": 1.5, "smg": 1.0}.get(_view_type, 0.75)
		if _view_type == "pistol": g.position += Vector3(-0.03, 0.05, 0.08)

func interact() -> void:
	if game and state == State.GROUND: game.interact(self)

func cycle_slot() -> void:
	_toggle(0)
	for k in range(1, 5):
		var i := (current + k) % 4
		if i == 0 or slots[i] != null: select_slot(i); return

func emote() -> void:
	if state != State.GROUND or not is_on_floor(): return
	emote_t = 3.0
	Util.play_anim(model, Profile.item("emote").data.anim)

func jump_from_bus() -> void:
	if state != State.BUS: return
	state = State.GLIDE; glider.visible = true; Util.touch_jump = false
	velocity = Vector3.ZERO
	$CollisionShape3D.disabled = false

func _toggle(m: int) -> void:
	build_mode = 0 if build_mode == m else m
	ghost.visible = build_mode > 0
	match build_mode:
		1: ghost.mesh = Util.box(Vector3(GRID, 3, 0.2))
		2: ghost.mesh = Util.box(Vector3(GRID, 0.2, GRID))
		3: ghost.mesh = Util.box(Vector3(GRID, 0.2, GRID * 1.25))

func _piece_transform() -> Transform3D:
	var fwd := Vector3(sin(yaw), 0, cos(yaw)) * -1
	var p := global_position + fwd * GRID
	var gp := Vector3(round(p.x / GRID) * GRID, floor(global_position.y / 3.0 + 0.1) * 3.0, round(p.z / GRID) * GRID)
	var r: float = round(yaw / (PI / 2)) * (PI / 2)
	var t := Transform3D(Basis(Vector3.UP, r), gp)
	match build_mode:
		1: t.origin += t.basis * Vector3(0, 1.5, -GRID * 0.5)
		2: t.origin += Vector3(0, 3, 0)
		3:
			t.basis = t.basis * Basis(Vector3.RIGHT, deg_to_rad(36.87))
			t.origin += Vector3(0, 1.5, 0)
	return t

func _place() -> void:
	if mats < 10: return
	mats -= 10
	Util.sfx("build", global_position)
	var size: Vector3 = (ghost.mesh as BoxMesh).size
	var piece := Util.static_box(size, Color(0.7, 0.5, 0.3), Vector3.ZERO)
	piece.set_script(load("res://scripts/build_piece.gd"))
	get_tree().current_scene.add_child(piece)
	piece.global_transform = _piece_transform()

func base_anim(hs: float) -> String:
	if state == State.BUS: return "sit"
	if state == State.GLIDE: return "glide"
	if emote_t > 0 and hs < 0.5 and is_on_floor(): return Profile.item("emote").data.anim
	return super(hs)

func _physics_process(delta: float) -> void:
	super(delta)
	if not alive: return
	emote_t -= delta
	if Util.touch_look != Vector2.ZERO:
		yaw -= Util.touch_look.x * Util.sensitivity * 0.02
		pitch = clamp(pitch - Util.touch_look.y * Util.sensitivity * 0.02, -1.3, 0.9)
		Util.touch_look = Vector2.ZERO
	rotation.y = yaw
	$Pivot.rotation.x = pitch
	aim_pitch = pitch
	spring.spring_length = 4.0 if state == State.GROUND else 9.0
	_update_view(delta)
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input.y -= 1
	if Input.is_physical_key_pressed(KEY_S): input.y += 1
	if Input.is_physical_key_pressed(KEY_A): input.x -= 1
	if Input.is_physical_key_pressed(KEY_D): input.x += 1
	if Util.touch_move != Vector2.ZERO: input = Util.touch_move
	if input != Vector2.ZERO: emote_t = 0
	var dir := transform.basis * Vector3(input.x, 0, input.y).limit_length(1.0)
	match state:
		State.BUS:
			if Util.touch_jump: jump_from_bus()
			return # position is driven by the game (bus)
		State.GLIDE:
			velocity.x = dir.x * 14.0; velocity.z = dir.z * 14.0; velocity.y = -9.0
			move_and_slide()
			if is_on_floor():
				state = State.GROUND; glider.visible = false
			return
	if Util.touch_fire and build_mode > 0:
		Util.touch_fire = false; _place()
	var speed := 9.0 if (Input.is_physical_key_pressed(KEY_SHIFT) or Util.touch_sprint) else 6.0
	velocity.x = dir.x * speed; velocity.z = dir.z * speed
	if is_on_floor():
		if (Input.is_physical_key_pressed(KEY_SPACE) or Util.touch_jump): velocity.y = 8.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if build_mode > 0: ghost.global_transform = _piece_transform()
	elif Util.touch_fire or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		var vp := get_viewport().get_visible_rect().size / 2
		var o := cam.project_ray_origin(vp); var d := cam.project_ray_normal(vp)
		var q := PhysicsRayQueryParameters3D.create(o, o + d * 400); q.exclude = [get_rid()]
		var h := get_world_3d().direct_space_state.intersect_ray(q)
		var target: Vector3 = h.position if h else o + d * 400
		var gun := global_position + Vector3(0, 1.4, 0)
		if current == 0: fire(gun, (-global_transform.basis.z + Vector3(0, -0.2, 0)).normalized())
		else: fire(gun, (target - gun).normalized(), 0.0)
