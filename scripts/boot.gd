extends Control
## Boot / loading screen: loads the main menu asynchronously with rotating tips.
const TARGET := "res://scenes/main_menu.tscn"
const TIPS := ["Build a ramp to gain the high ground! (Q)",
	"The storm shrinks over time - stay inside the circle.",
	"Shields absorb damage before your health does.",
	"Press R to reload. Sprint with Shift.",
	"Walls (Z), Floors (X), Ramps (C) - left click to place in build mode."]
var bar: ProgressBar
var tip: Label
var t := 0.0
var shown := 0.0
var tip_i := 0

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color(0.08, 0.05, 0.2)
	bg.set_anchors_preset(PRESET_FULL_RECT); add_child(bg)
	var box := VBoxContainer.new(); box.set_anchors_preset(PRESET_CENTER)
	box.custom_minimum_size = Vector2(600, 0); box.position = Vector2(-300, -100)
	add_child(box)
	var title := Label.new(); title.text = "STORM DROP"
	title.add_theme_font_size_override("font_size", 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.2)); box.add_child(title)
	bar = ProgressBar.new(); bar.custom_minimum_size = Vector2(600, 30); box.add_child(bar)
	tip = Label.new(); tip.text = TIPS[0]; tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD; box.add_child(tip)
	ResourceLoader.load_threaded_request(TARGET)

func _process(delta: float) -> void:
	t += delta
	if t > 2.5:
		t = 0; tip_i = (tip_i + 1) % TIPS.size(); tip.text = TIPS[tip_i]
	var p := []
	var st := ResourceLoader.load_threaded_get_status(TARGET, p)
	var real: float = 1.0 if st == ResourceLoader.THREAD_LOAD_LOADED else (p[0] if p.size() > 0 else 0.0)
	# animate toward real progress, min ~2s so the screen is visible
	shown = min(shown + delta * 0.5, real)
	bar.value = shown * 100.0
	if st == ResourceLoader.THREAD_LOAD_FAILED:
		tip.text = "Failed to load!"
	elif st == ResourceLoader.THREAD_LOAD_LOADED and shown >= 1.0:
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(TARGET))
