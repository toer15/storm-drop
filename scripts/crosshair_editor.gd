extends PanelContainer
## Settings > Crosshair: style, colour, size, thickness, gap, outline, opacity, centre dot, presets, live preview.
## Big touch-sized controls; saved to user://crosshair.cfg (Crosshair.save_cfg).
const SWATCHES := [Color(1, 1, 1), Color(0.2, 1, 0.3), Color(1, 0.95, 0.2), Color(0.3, 0.9, 1), Color(1, 0.2, 0.9), Color(1, 0.25, 0.2), Color(1, 0.6, 0.1), Color(0, 0, 0)]
var preview: Crosshair
var preview_bg: ColorRect
var controls := {}
var syncing := false
signal closed

func _ready() -> void:
	Crosshair.load_cfg()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.04, 0.03, 0.12, 0.96); sb.set_corner_radius_all(14)
	sb.border_color = Color(1, 0.8, 0.2); sb.set_border_width_all(2); sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	var root := HBoxContainer.new(); root.add_theme_constant_override("separation", 18); add_child(root)
	# left: controls (scrollable for phones)
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(560, 520); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var vb := VBoxContainer.new(); vb.size_flags_horizontal = SIZE_EXPAND_FILL; vb.add_theme_constant_override("separation", 8); sc.add_child(vb)
	vb.add_child(_lbl("CROSSHAIR EDITOR", 30, Color(1, 0.85, 0.3)))
	vb.add_child(_lbl("Presets", 20))
	var pg := GridContainer.new(); pg.columns = 3; vb.add_child(pg)
	for n in Crosshair.PRESETS:
		var b := _btn(n, Vector2(170, 56)); b.pressed.connect(_apply_preset.bind(n)); pg.add_child(b)
	vb.add_child(_lbl("Style", 20))
	var sg := GridContainer.new(); sg.columns = 4; vb.add_child(sg)
	var bgp := ButtonGroup.new()
	for i in Crosshair.STYLES.size():
		var b := _btn(Crosshair.STYLE_NAMES[i], Vector2(128, 56), 16); b.toggle_mode = true; b.button_group = bgp
		b.pressed.connect(_setv.bind("style", Crosshair.STYLES[i])); sg.add_child(b); controls["style_" + Crosshair.STYLES[i]] = b
	vb.add_child(_lbl("Colour", 20))
	var cg := HBoxContainer.new(); vb.add_child(cg)
	for c in SWATCHES:
		var b := Button.new(); b.custom_minimum_size = Vector2(54, 54); b.focus_mode = FOCUS_NONE
		var s := StyleBoxFlat.new(); s.bg_color = c; s.set_corner_radius_all(8); s.border_color = Color(0.5, 0.5, 0.5); s.set_border_width_all(2)
		for st in ["normal", "hover", "pressed"]: b.add_theme_stylebox_override(st, s)
		b.pressed.connect(_setv.bind("color", c)); cg.add_child(b)
	var cp := ColorPickerButton.new(); cp.custom_minimum_size = Vector2(80, 54); cp.text = "Custom"; cp.edit_alpha = false
	cp.color_changed.connect(func(c): _setv("color", c)); cg.add_child(cp); controls.color = cp
	for d in [["size", "Size", 2.0, 40.0, 1.0], ["thickness", "Thickness", 1.0, 8.0, 0.5], ["gap", "Gap", 0.0, 30.0, 1.0], ["opacity", "Opacity", 0.1, 1.0, 0.05], ["outline_thickness", "Outline thickness", 0.5, 4.0, 0.5]]:
		var row := HBoxContainer.new(); vb.add_child(row)
		var l := _lbl(d[1], 20); l.custom_minimum_size = Vector2(190, 0); row.add_child(l)
		var s := HSlider.new(); s.min_value = d[2]; s.max_value = d[3]; s.step = d[4]; s.custom_minimum_size = Vector2(260, 48)
		s.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(s)
		var v := _lbl("", 20); v.custom_minimum_size = Vector2(56, 0); row.add_child(v)
		s.value_changed.connect(func(x): v.text = ("%.2f" % x) if d[4] < 1.0 else str(int(x)); _setv(d[0], x))
		controls[d[0]] = s
	for d in [["outline", "Black outline"], ["center_dot", "Centre dot"], ["dynamic", "Dynamic spread (moving / shooting)"], ["per_weapon", "Shape changes per weapon in game"]]:
		var cb := CheckButton.new(); cb.text = d[1]; cb.add_theme_font_size_override("font_size", 20); cb.custom_minimum_size = Vector2(0, 50)
		cb.toggled.connect(func(on): _setv(d[0], on)); vb.add_child(cb); controls[d[0]] = cb
	var bh := HBoxContainer.new(); bh.add_theme_constant_override("separation", 10); vb.add_child(bh)
	var sv := _btn("SAVE", Vector2(170, 64)); sv.pressed.connect(func(): Crosshair.save_cfg(); Util.sfx("click")); bh.add_child(sv)
	var rs := _btn("RESET", Vector2(170, 64)); rs.pressed.connect(func(): Crosshair.cfg = Crosshair.DEFAULT.duplicate(); _sync()); bh.add_child(rs)
	var cl := _btn("CLOSE", Vector2(170, 64)); cl.pressed.connect(func(): Crosshair.save_cfg(); visible = false; closed.emit()); bh.add_child(cl)
	# right: live preview over a sky / grass / dark background (tap to cycle), animated spread + hit markers
	var pv := VBoxContainer.new(); root.add_child(pv)
	pv.add_child(_lbl("LIVE PREVIEW", 22, Color(1, 0.85, 0.3)))
	preview_bg = ColorRect.new(); preview_bg.custom_minimum_size = Vector2(320, 320); preview_bg.color = Color(0.45, 0.7, 0.95)
	preview_bg.clip_contents = true; pv.add_child(preview_bg)
	preview = Crosshair.new(); preview.preview = true; preview.set_anchors_and_offsets_preset(PRESET_FULL_RECT); preview_bg.add_child(preview)
	var bgb := _btn("Background", Vector2(320, 56)); pv.add_child(bgb)
	bgb.pressed.connect(func():
		var cols := [Color(0.45, 0.7, 0.95), Color(0.3, 0.55, 0.25), Color(0.08, 0.08, 0.1), Color(0.85, 0.8, 0.6)]
		preview_bg.color = cols[(cols.find(preview_bg.color) + 1) % cols.size()])
	var hm := _btn("Test hit marker", Vector2(320, 56)); hm.pressed.connect(func(): preview.hit_marker(randf() < 0.3)); pv.add_child(hm)
	pv.add_child(_lbl("Preview breathes to show\ndynamic spread.", 16, Color(0.8, 0.8, 0.9)))
	_sync()

func _process(_d: float) -> void:
	if visible and preview: preview.spread = (sin(Time.get_ticks_msec() * 0.003) * 0.5 + 0.5) * 0.6 if Crosshair.cfg.dynamic else 0.0

func _setv(k: String, v) -> void:
	if syncing: return
	Crosshair.cfg[k] = v; if k == "color": controls.color.color = v

func _apply_preset(n: String) -> void:
	for k in Crosshair.PRESETS[n]: Crosshair.cfg[k] = Crosshair.PRESETS[n][k]
	_sync()

func _sync() -> void:
	syncing = true
	var c := Crosshair.cfg
	for s in Crosshair.STYLES: controls["style_" + s].button_pressed = c.style == s
	controls.color.color = c.color
	for k in ["size", "thickness", "gap", "opacity", "outline_thickness"]: controls[k].value = c[k]
	for k in ["outline", "center_dot", "dynamic", "per_weapon"]: controls[k].button_pressed = c[k]
	syncing = false
	for k in ["size", "thickness", "gap", "opacity", "outline_thickness"]: controls[k].value_changed.emit(c[k])

func _btn(t: String, sz: Vector2, fs := 20) -> Button:
	var b := Button.new(); b.text = t; b.custom_minimum_size = sz; b.add_theme_font_size_override("font_size", fs)
	b.focus_mode = FOCUS_NONE; return b

func _lbl(t: String, fs := 20, col := Color.WHITE) -> Label:
	var l := Label.new(); l.text = t; l.add_theme_font_size_override("font_size", fs); l.add_theme_color_override("font_color", col); return l
