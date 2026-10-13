extends Control
## Boot / loading screen: key art (code-drawn storm + skyline), logo, progress bar, rotating tips.
## Loads the lobby asynchronously with ResourceLoader.load_threaded_request.
const TARGET := "res://scenes/main_menu.tscn"
const TIPS := ["Build a ramp to gain the high ground! (C / RAMP)",
	"The storm shrinks over time - stay inside the circle.",
	"Shields absorb damage before your health does. Chests give shield!",
	"Golden glow = Legendary weapon. Rarity: grey, green, blue, purple, gold.",
	"Swing your pickaxe at trees, rocks and houses to collect materials.",
	"Earn Drop Coins every match and spend them in the Item Shop.",
	"The Item Shop rotates every day - check back tomorrow!",
	"Level up the Battle Pass by earning XP from eliminations and placement."]
var bar: ProgressBar
var tip: Label
var pct: Label
var art: Control
var t := 0.0
var time := 0.0
var shown := 0.0
var tip_i := 0

func _ready() -> void:
	if Net.dedicated: # headless dedicated server: skip the loading screen and lobby UI
		get_tree().change_scene_to_file.call_deferred("res://scenes/server.tscn"); set_process(false); return
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := TextureRect.new(); bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT); bg.stretch_mode = TextureRect.STRETCH_SCALE
	var gt := GradientTexture2D.new(); var g := Gradient.new()
	g.set_color(0, Color(0.32, 0.12, 0.6)); g.set_color(1, Color(0.05, 0.02, 0.15)); gt.gradient = g
	gt.fill_from = Vector2(0.5, 0); gt.fill_to = Vector2(0.5, 1); bg.texture = gt; add_child(bg)
	art = Control.new(); art.set_anchors_and_offsets_preset(PRESET_FULL_RECT); art.draw.connect(_draw_art); add_child(art)
	var box := VBoxContainer.new(); box.set_anchors_preset(PRESET_CENTER_BOTTOM)
	box.grow_horizontal = GROW_DIRECTION_BOTH; box.grow_vertical = GROW_DIRECTION_BEGIN
	box.offset_top = -330; box.offset_bottom = -40; box.offset_left = -360; box.offset_right = 360
	box.add_theme_constant_override("separation", 12); add_child(box)
	var title := Label.new(); title.text = "STORM DROP"
	title.add_theme_font_size_override("font_size", 110)
	title.add_theme_color_override("font_color", Color(1, 0.82, 0.2))
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.4)); title.add_theme_constant_override("outline_size", 24)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6)); title.add_theme_constant_override("shadow_offset_y", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(title)
	var sub := Label.new(); sub.text = "B A T T L E   R O Y A L E"; sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26); sub.add_theme_color_override("font_color", Color(0.75, 0.9, 1)); box.add_child(sub)
	bar = ProgressBar.new(); bar.custom_minimum_size = Vector2(720, 34); bar.show_percentage = false
	var fill := StyleBoxFlat.new(); fill.bg_color = Color(1, 0.8, 0.2); fill.set_corner_radius_all(17)
	var bgs := StyleBoxFlat.new(); bgs.bg_color = Color(0, 0, 0, 0.5); bgs.set_corner_radius_all(17)
	bar.add_theme_stylebox_override("fill", fill); bar.add_theme_stylebox_override("background", bgs); box.add_child(bar)
	pct = Label.new(); pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(pct)
	tip = Label.new(); tip.text = "TIP: " + TIPS[0]; tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 22); tip.autowrap_mode = TextServer.AUTOWRAP_WORD; box.add_child(tip)
	ResourceLoader.load_threaded_request(TARGET)

func _draw_art() -> void:
	var sz := art.size
	var c := Vector2(sz.x * 0.5, sz.y * 0.32)
	# swirling storm eye
	for i in 7:
		var r := 60.0 + i * 55.0
		art.draw_arc(c, r, time * (0.4 + i * 0.1) + i, time * (0.4 + i * 0.1) + i + PI * 1.3, 48, Color(0.7, 0.4, 1, 0.5 - i * 0.06), 10.0 - i)
	# lightning bolt
	var b := PackedVector2Array([c + Vector2(-10, -90), c + Vector2(30, -90), c + Vector2(5, -15), c + Vector2(30, -15), c + Vector2(-20, 90), c + Vector2(-5, 10), c + Vector2(-30, 10)])
	art.draw_colored_polygon(b, Color(1, 0.9, 0.3, 0.8 + 0.2 * sin(time * 8)))
	# island + skyline silhouette
	var base := sz.y * 0.62
	art.draw_rect(Rect2(0, base, sz.x, sz.y - base), Color(0.06, 0.03, 0.12))
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var x := 0.0
	while x < sz.x:
		var w := rng.randf_range(30, 90); var h := rng.randf_range(20, 110)
		if rng.randf() < 0.4: art.draw_colored_polygon(PackedVector2Array([Vector2(x, base), Vector2(x + w / 2, base - h * 1.4), Vector2(x + w, base)]), Color(0.08, 0.04, 0.16))
		else: art.draw_rect(Rect2(x, base - h, w, h), Color(0.08, 0.04, 0.16))
		x += w
	# falling gliders
	for i in 5:
		var gp := Vector2(fmod(i * 260.0 + time * 40.0, sz.x), fmod(i * 90.0 + time * 30.0, base - 40))
		art.draw_colored_polygon(PackedVector2Array([gp + Vector2(-22, 0), gp + Vector2(22, 0), gp + Vector2(0, -12)]), Color(1, 0.55, 0.1))
		art.draw_circle(gp + Vector2(0, 14), 5, Color(1, 0.85, 0.7))

func _process(delta: float) -> void:
	t += delta; time += delta; art.queue_redraw()
	if t > 2.5:
		t = 0; tip_i = (tip_i + 1) % TIPS.size(); tip.text = "TIP: " + TIPS[tip_i]
	var p := []
	var st := ResourceLoader.load_threaded_get_status(TARGET, p)
	var real: float = 1.0 if st == ResourceLoader.THREAD_LOAD_LOADED else (p[0] if p.size() > 0 else 0.0)
	shown = min(shown + delta * 0.4, real)
	bar.value = shown * 100.0; pct.text = "Loading... %d%%" % int(shown * 100)
	if st == ResourceLoader.THREAD_LOAD_FAILED:
		tip.text = "Failed to load!"
	elif st == ResourceLoader.THREAD_LOAD_LOADED and shown >= 1.0 and not Util.hold_boot:
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(TARGET))
