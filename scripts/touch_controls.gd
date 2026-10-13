extends Control
## On-screen phone controls: left joystick, right-side drag to look, action buttons.
var player
var stick_id := -1
var look_id := -1
var stick_origin := Vector2.ZERO
var base: Panel
var knob: Panel
const R := 90.0

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	base = _circle(R * 2, Color(1, 1, 1, 0.15)); knob = _circle(70, Color(1, 1, 1, 0.4))
	base.visible = false; knob.visible = false
	# right-bottom cluster: [label, callable, size, offset from bottom-right]
	var defs := [
		["FIRE", "fire", 130, Vector2(-170, -330)],
		["JUMP", "jump", 110, Vector2(-150, -170)],
		["RELOAD", func(): player.reload(), 90, Vector2(-290, -150)],
		["SPRINT", "sprint", 90, Vector2(-330, -280)],
		["USE", func(): player.interact(), 90, Vector2(-290, -420)],
		["EMOTE", func(): player.emote(), 80, Vector2(-120, -440)],
		["WALL", func(): player._toggle(1), 80, Vector2(-450, -110)],
		["FLOOR", func(): player._toggle(2), 80, Vector2(-540, -110)],
		["RAMP", func(): player._toggle(3), 80, Vector2(-630, -110)],
		["SWAP", func(): player.cycle_slot(), 80, Vector2(-720, -110)],
		["VIEW", func(): player.set_first_person(not player.fp), 70, Vector2(-110, -560)],
		["GLIDE", func(): if player.state == Player.State.FALL: player._open_glider(), 80, Vector2(-260, -560)],
	]
	for d in defs: _button(d[0], d[1], d[2], d[3])

func _circle(sz: float, c: Color) -> Panel:
	var p := Panel.new(); var sb := StyleBoxFlat.new(); sb.bg_color = c
	sb.set_corner_radius_all(int(sz / 2)); p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(sz, sz); p.mouse_filter = MOUSE_FILTER_IGNORE; add_child(p); return p

func _button(text: String, action, sz: float, off: Vector2) -> void:
	var b := Button.new(); b.text = text; b.focus_mode = FOCUS_NONE
	b.anchor_left = 1; b.anchor_right = 1; b.anchor_top = 1; b.anchor_bottom = 1
	b.offset_left = off.x; b.offset_top = off.y; b.offset_right = off.x + sz; b.offset_bottom = off.y + sz
	b.add_theme_font_size_override("font_size", 20)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0, 0, 0, 0.35); sb.set_corner_radius_all(int(sz / 2))
	b.add_theme_stylebox_override("normal", sb); b.add_theme_stylebox_override("hover", sb)
	var sp := sb.duplicate(); sp.bg_color = Color(1, 1, 1, 0.4); b.add_theme_stylebox_override("pressed", sp)
	if action is String: # held buttons
		b.button_down.connect(func(): Util.set("touch_" + action, true))
		b.button_up.connect(func(): Util.set("touch_" + action, false))
	else:
		b.pressed.connect(func(): if is_instance_valid(player) and player.alive: action.call())
	add_child(b)

func _input(e: InputEvent) -> void:
	if not visible: return
	var half := get_viewport_rect().size.x * 0.5
	if e is InputEventScreenTouch:
		if e.pressed:
			if e.position.x < half * 0.8 and stick_id == -1:
				stick_id = e.index; stick_origin = e.position
				base.position = e.position - base.size / 2; knob.position = e.position - knob.size / 2
				base.visible = true; knob.visible = true
			elif e.position.x >= half and look_id == -1 and not _over_button(e.position):
				look_id = e.index
		else:
			if e.index == stick_id:
				stick_id = -1; Util.touch_move = Vector2.ZERO; base.visible = false; knob.visible = false
			if e.index == look_id: look_id = -1
	elif e is InputEventScreenDrag:
		if e.index == stick_id:
			var v: Vector2 = (e.position - stick_origin).limit_length(R)
			knob.position = stick_origin + v - knob.size / 2
			Util.touch_move = v / R
		elif e.index == look_id:
			Util.touch_look += e.relative

func _over_button(p: Vector2) -> bool:
	for c in get_children():
		if c is Button and c.get_global_rect().has_point(p): return true
	return false
