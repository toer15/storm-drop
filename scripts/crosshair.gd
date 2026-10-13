class_name Crosshair
extends Control
## Dynamic crosshair + hit markers. Settings live in `cfg` (static, saved to user://crosshair.cfg).
## Styles: cross, dot, circle, t (T-shape), cross_circle, t_dot, circle_dot, chevron.
## With "per_weapon" on, each weapon picks its own shape (shotgun = circle, sniper = fine cross ...), keeping
## the player's colour / thickness / outline / opacity. Spread grows while moving, airborne and shooting.
const SAVE := "user://crosshair.cfg"
const STYLES := ["cross", "dot", "circle", "t", "cross_circle", "t_dot", "circle_dot", "chevron"]
const STYLE_NAMES := ["Cross", "Dot", "Circle", "T-shape", "Cross + circle", "T + dot", "Circle + dot", "Chevron"]
const DEFAULT := {"style": "cross", "color": Color(1, 1, 1), "size": 10.0, "thickness": 2.0, "gap": 5.0,
	"outline": true, "outline_thickness": 1.0, "opacity": 0.95, "center_dot": false, "dynamic": true, "per_weapon": true}
const PRESETS := {
	"Classic": {"style": "cross", "color": Color(1, 1, 1), "size": 10.0, "thickness": 2.0, "gap": 5.0, "outline": true, "opacity": 0.95, "center_dot": false},
	"Pro Green": {"style": "cross", "color": Color(0.2, 1, 0.3), "size": 6.0, "thickness": 2.0, "gap": 3.0, "outline": true, "opacity": 1.0, "center_dot": true},
	"Tiny Dot": {"style": "dot", "color": Color(1, 0.2, 0.9), "size": 4.0, "thickness": 2.0, "gap": 0.0, "outline": true, "opacity": 1.0, "center_dot": true},
	"Circle": {"style": "circle_dot", "color": Color(0.3, 0.9, 1), "size": 14.0, "thickness": 2.0, "gap": 0.0, "outline": true, "opacity": 0.9, "center_dot": true},
	"T Sniper": {"style": "t_dot", "color": Color(1, 0.9, 0.2), "size": 12.0, "thickness": 1.5, "gap": 4.0, "outline": true, "opacity": 1.0, "center_dot": true},
	"Big Red": {"style": "cross_circle", "color": Color(1, 0.25, 0.2), "size": 16.0, "thickness": 3.0, "gap": 8.0, "outline": false, "opacity": 0.85, "center_dot": false},
}
## Shape used per weapon when per_weapon is on (size multiplier, base spread px).
const WEAPON_STYLE := {
	"pick": ["dot", 0.8, 0.0], "pistol": ["cross", 0.9, 4.0], "ar": ["cross", 1.0, 6.0], "smg": ["cross_circle", 0.9, 10.0],
	"shotgun": ["circle_dot", 1.6, 22.0], "sniper": ["t_dot", 1.2, 0.0], "rocket": ["chevron", 1.3, 4.0],
}
static var cfg := {}

static func load_cfg() -> Dictionary:
	if not cfg.is_empty(): return cfg
	cfg = DEFAULT.duplicate()
	var f := ConfigFile.new()
	if f.load(SAVE) == OK:
		for k in DEFAULT: cfg[k] = f.get_value("crosshair", k, DEFAULT[k])
	return cfg

static func save_cfg() -> void:
	var f := ConfigFile.new()
	for k in cfg: f.set_value("crosshair", k, cfg[k])
	f.save(SAVE)

var weapon_type := "ar"   # set by the HUD every frame
var spread := 0.0         # 0..1 bloom (movement / air / recoil)
var preview := false      # editor preview: ignore per-weapon override
var hit_t := 0.0
var hit_kill := false
var hit_head := false

func _ready() -> void:
	load_cfg(); mouse_filter = MOUSE_FILTER_IGNORE

func hit_marker(kill := false) -> void:
	hit_t = 0.25 if not kill else 0.45; hit_kill = kill

func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta); queue_redraw()

func _draw() -> void:
	var c: Dictionary = cfg if not cfg.is_empty() else load_cfg()
	var style: String = c.style; var sz: float = c.size; var base := 0.0
	if not preview and c.per_weapon:
		var ws: Array = WEAPON_STYLE.get(weapon_type, WEAPON_STYLE.ar)
		style = ws[0]; sz *= ws[1]; base = ws[2]
	var gap: float = c.gap + (base + spread * 26.0 if c.dynamic else base)
	draw_shape(self, _center(), style, sz, float(c.thickness), gap, c.color, float(c.opacity), c.outline, c.center_dot, float(c.outline_thickness))
	if hit_t > 0.0: # hit marker: four diagonal ticks, red + bigger on eliminations
		var col := Color(1, 0.2, 0.2) if hit_kill else Color(1, 1, 1)
		col.a = clampf(hit_t / 0.15, 0, 1)
		var r0 := 8.0 + gap * 0.3; var r1 := r0 + (14.0 if hit_kill else 9.0)
		for k in 4:
			var d := Vector2.from_angle(PI / 4 + k * PI / 2)
			draw_line(_center() + d * r0, _center() + d * r1, Color(0, 0, 0, col.a * 0.7), 5.0)
			draw_line(_center() + d * r0, _center() + d * r1, col, 2.5)

func _center() -> Vector2:
	return size / 2.0

## Draws a crosshair (used by the HUD and by the editor preview).
static func draw_shape(ci: CanvasItem, p: Vector2, style: String, size: float, th: float, gap: float, col: Color, opacity: float, outline: bool, dot: bool, ot := 1.0) -> void:
	col.a = opacity
	var oc := Color(0, 0, 0, opacity * 0.8); var ow := th + ot * 2.0
	var lines := []   # [from, to]
	var circles := [] # radius
	var dots := []    # radius
	match style:
		"cross", "cross_circle":
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]: lines.append([p + d * gap, p + d * (gap + size)])
			if style == "cross_circle": circles.append(gap + size + 4.0)
		"t", "t_dot":
			for d in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]: lines.append([p + d * gap, p + d * (gap + size)])
			if style == "t_dot": dots.append(maxf(1.5, th))
		"dot": dots.append(maxf(2.0, size * 0.35))
		"circle", "circle_dot":
			circles.append(gap + size)
			if style == "circle_dot": dots.append(maxf(1.5, th))
		"chevron":
			lines.append([p + Vector2(-size, size * 0.7 + gap), p + Vector2(0, gap)]); lines.append([p + Vector2(size, size * 0.7 + gap), p + Vector2(0, gap)])
	if dot and dots.is_empty(): dots.append(maxf(1.5, th * 0.9))
	if outline:
		for l in lines: ci.draw_line(l[0], l[1], oc, ow)
		for r in circles: ci.draw_arc(p, r, 0, TAU, 48, oc, ow, true)
		for r in dots: ci.draw_circle(p, r + 1.0, oc)
	for l in lines: ci.draw_line(l[0], l[1], col, th)
	for r in circles: ci.draw_arc(p, r, 0, TAU, 48, col, th, true)
	for r in dots: ci.draw_circle(p, r, col)
