class_name Player
extends Combatant
## Third-person controller + building.
var yaw := 0.0
var pitch := -0.2
var cam: Camera3D
var spring: SpringArm3D
var build_mode := 0 # 0 none, 1 wall, 2 floor, 3 ramp
var ghost: MeshInstance3D
var mats := 500
const GRID := 4.0

func _ready() -> void:
	display_name = "You"
	setup_body(Color(1, 0.5, 0.1))
	var pivot := Node3D.new(); pivot.name = "Pivot"; pivot.position.y = 1.6; add_child(pivot)
	spring = SpringArm3D.new(); spring.spring_length = 4.0; spring.position.x = 0.7
	spring.add_excluded_object(get_rid()); pivot.add_child(spring)
	cam = Camera3D.new(); cam.current = true; spring.add_child(cam)
	ghost = MeshInstance3D.new(); ghost.material_override = Util.mat(Color(0.3, 0.7, 1, 0.4))
	ghost.visible = false; ghost.top_level = true; add_child(ghost)
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
			KEY_C: _toggle(3)
			KEY_Q: _toggle(3)
			KEY_1: _toggle(0)
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	# snap rotation to 90 degrees
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

func _physics_process(delta: float) -> void:
	super(delta)
	if not alive: return
	if Util.touch_look != Vector2.ZERO:
		yaw -= Util.touch_look.x * Util.sensitivity * 0.02
		pitch = clamp(pitch - Util.touch_look.y * Util.sensitivity * 0.02, -1.3, 0.9)
		Util.touch_look = Vector2.ZERO
	if Util.touch_fire and build_mode > 0:
		Util.touch_fire = false; _place()
	rotation.y = yaw
	$Pivot.rotation.x = pitch
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input.y -= 1
	if Input.is_physical_key_pressed(KEY_S): input.y += 1
	if Input.is_physical_key_pressed(KEY_A): input.x -= 1
	if Input.is_physical_key_pressed(KEY_D): input.x += 1
	if Util.touch_move != Vector2.ZERO: input = Util.touch_move
	var speed := 9.0 if (Input.is_physical_key_pressed(KEY_SHIFT) or Util.touch_sprint) else 6.0
	var dir := transform.basis * Vector3(input.x, 0, input.y).limit_length(1.0)
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
		# aim from the camera, fire from the gun
		var q := PhysicsRayQueryParameters3D.create(o, o + d * 200); q.exclude = [get_rid()]
		var h := get_world_3d().direct_space_state.intersect_ray(q)
		var target: Vector3 = h.position if h else o + d * 200
		var gun := global_position + Vector3(0, 1.4, 0)
		fire(gun, (target - gun).normalized(), 0.01)
