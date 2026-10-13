extends Control
## Lobby: 3D stage with your equipped character, tabs (Lobby, Battle Pass, Locker, Item Shop, Career),
## PLAY with mode select and a fake matchmaking countdown. Touch-friendly: big buttons, scroll containers.
const TABS := ["LOBBY", "BATTLE PASS", "LOCKER", "ITEM SHOP", "CAREER"]
const RARITY := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
var stage_root: Node3D
var hero: Node3D
var cam_pivot: Node3D
var pages := {}
var tab_buttons := {}
var coins_label: Label
var tier_label: Label
var settings: PanelContainer
var mm_overlay: ColorRect
var mm_label: Label
var mm_time := -1.0
var locker_cat := "skin"
var mode_note: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Util.music("res://assets/music13/lobby.ogg")
	_stage()
	var top := ColorRect.new(); top.color = Color(0.05, 0.03, 0.15, 0.85)
	top.anchor_right = 1; top.offset_bottom = 84; add_child(top)
	var hb := HBoxContainer.new(); hb.anchor_right = 1; hb.offset_bottom = 84; hb.offset_left = 16; hb.offset_right = -16
	hb.add_theme_constant_override("separation", 8); add_child(hb)
	var logo := Label.new(); logo.text = "STORM DROP"; logo.add_theme_font_size_override("font_size", 34)
	logo.add_theme_color_override("font_color", Color(1, 0.82, 0.2)); logo.add_theme_constant_override("outline_size", 8)
	logo.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.4)); logo.size_flags_vertical = SIZE_SHRINK_CENTER
	hb.add_child(logo)
	var bg := ButtonGroup.new()
	for t in TABS:
		var b := Button.new(); b.text = t; b.toggle_mode = true; b.button_group = bg; b.flat = true
		b.custom_minimum_size = Vector2(150, 70); b.add_theme_font_size_override("font_size", 22)
		b.size_flags_vertical = SIZE_SHRINK_CENTER
		b.pressed.connect(_show_tab.bind(t)); b.pressed.connect(func(): Util.sfx("click"))
		hb.add_child(b); tab_buttons[t] = b
	var sp := Control.new(); sp.size_flags_horizontal = SIZE_EXPAND_FILL; hb.add_child(sp)
	var cv := VBoxContainer.new(); cv.size_flags_vertical = SIZE_SHRINK_CENTER; hb.add_child(cv)
	coins_label = Label.new(); coins_label.add_theme_font_size_override("font_size", 24)
	coins_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3)); cv.add_child(coins_label)
	tier_label = Label.new(); tier_label.add_theme_font_size_override("font_size", 16); cv.add_child(tier_label)
	for t in TABS:
		var pg := Control.new(); pg.set_anchors_and_offsets_preset(PRESET_FULL_RECT); pg.offset_top = 90
		pg.mouse_filter = MOUSE_FILTER_IGNORE; add_child(pg); pages[t] = pg
	_build_lobby(); _build_settings(); _build_matchmaking()
	_refresh_all()
	var start := Util.shot_tab.to_upper().replace("_", " ") if Util.shot_tab != "" else "LOBBY"
	if Util.shot_tab == "matchmaking": start = "LOBBY"
	_show_tab(start if pages.has(start) else "LOBBY")
	if Util.shot_tab == "matchmaking": _play()

# ---------- 3D stage ----------
func _stage() -> void:
	stage_root = Node3D.new(); add_child(stage_root)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.22, 0.1, 0.42)
	env.environment.ambient_light_color = Color(0.7, 0.7, 1); env.environment.ambient_light_energy = 0.6
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	stage_root.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 25, 0); stage_root.add_child(sun)
	var spot := SpotLight3D.new(); spot.position = Vector3(0, 7, 2); spot.rotation_degrees.x = -80
	spot.light_color = Color(1, 0.85, 0.5); spot.light_energy = 4; spot.spot_range = 12; stage_root.add_child(spot)
	var cyl := CylinderMesh.new(); cyl.top_radius = 2.4; cyl.bottom_radius = 2.6; cyl.height = 0.5
	var pad := Util.mesh(cyl, Color(0.15, 0.6, 1)); pad.material_override.emission_enabled = true
	pad.material_override.emission = Color(0.1, 0.3, 0.8); stage_root.add_child(pad)
	var ring := TorusMesh.new(); ring.inner_radius = 6; ring.outer_radius = 6.3
	var rm := Util.mesh(ring, Color(0.8, 0.4, 1), Vector3(0, 0.3, 0)); rm.material_override.emission_enabled = true
	rm.material_override.emission = Color(0.6, 0.2, 1); rm.name = "Ring"; stage_root.add_child(rm)
	for i in 14: # floating crystals in the background
		var p := PrismMesh.new(); p.size = Vector3(0.6, 1.2, 0.6)
		var a := i / 14.0 * TAU
		var c := Util.mesh(p, Color.from_hsv(0.75 + randf() * 0.15, 0.6, 1), Vector3(cos(a) * 9, 1 + randf() * 4, sin(a) * 9 - 3))
		stage_root.add_child(c)
	cam_pivot = Node3D.new(); stage_root.add_child(cam_pivot)
	var cam := Camera3D.new(); cam.position = Vector3(-0.9, 1.5, 3.4); cam.rotation_degrees = Vector3(-8, -14, 0)
	cam.current = true; cam_pivot.add_child(cam)
	_rebuild_hero()

func _rebuild_hero() -> void:
	if is_instance_valid(hero): hero.queue_free()
	hero = Util.make_character(Profile.equipped.skin, Profile.equipped.backbling, Profile.equipped.pickaxe)
	hero.position = Vector3(0, 0.25, 0); hero.rotation.y = PI + 0.4  # face the camera
	hero.scale = Vector3.ONE * 1.55
	Util.hold(hero, true); hero.get_meta("pickaxe").visible = locker_cat == "pickaxe" and pages.has("LOCKER") and pages["LOCKER"].visible
	Util.play_anim(hero, "idle")
	stage_root.add_child(hero)

func _process(delta: float) -> void:
	if is_instance_valid(hero) and Util.anim_player(hero) and not Util.anim_player(hero).is_playing():
		Util.play_anim(hero, "idle")
	if is_instance_valid(hero): Util.align_gear(hero)
	var ring := stage_root.get_node_or_null("Ring")
	if ring: ring.rotate_y(delta * 0.3)
	if mm_time >= 0:
		mm_time -= delta
		mm_label.text = "FINDING MATCH...\n%s  -  %d players\n\nStarting in %d" % [Profile.mode, Util.bot_count + 1, ceili(maxf(mm_time, 0))]
		if mm_time <= 0:
			mm_time = -1; get_tree().change_scene_to_file("res://scenes/game.tscn")

# ---------- helpers ----------
func _btn(text: String, size := Vector2(220, 70), fs := 24) -> Button:
	var b := Button.new(); b.text = text; b.custom_minimum_size = size; b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(func(): Util.sfx("click")); return b

func _lbl(text: String, fs := 20, col := Color.WHITE) -> Label:
	var l := Label.new(); l.text = text; l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col); l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color.BLACK); return l

func _card(rarity: int, owned := true) -> PanelContainer:
	var pc := PanelContainer.new(); var sb := StyleBoxFlat.new()
	var c: Color = Weapons.RARITY_COLORS[rarity]
	sb.bg_color = c.darkened(0.55) if owned else c.darkened(0.75); sb.border_color = c
	sb.set_border_width_all(3); sb.set_corner_radius_all(10); sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb); return pc

func _right_panel(pg: Control, title: String) -> VBoxContainer:
	var bgp := ColorRect.new(); bgp.color = Color(0.03, 0.02, 0.1, 0.8)
	bgp.anchor_left = 0.42; bgp.anchor_right = 1; bgp.anchor_bottom = 1; bgp.offset_right = -12; bgp.offset_bottom = -12
	pg.add_child(bgp)
	var vb := VBoxContainer.new(); vb.set_anchors_and_offsets_preset(PRESET_FULL_RECT); vb.offset_left = 16; vb.offset_top = 10
	vb.offset_right = -16; vb.offset_bottom = -10; bgp.add_child(vb)
	vb.add_child(_lbl(title, 34, Color(1, 0.85, 0.3)))
	return vb

func _clear(n: Node) -> void:
	for c in n.get_children(): c.queue_free()

func _show_tab(t: String) -> void:
	for k in pages: pages[k].visible = k == t
	var tw := create_tween(); tw.tween_property(cam_pivot, "position:x", 0.0 if t in ["LOBBY", "BATTLE PASS"] else 1.6, 0.35)
	tab_buttons[t].button_pressed = true
	match t:
		"BATTLE PASS": _build_bp()
		"LOCKER": _build_locker()
		"ITEM SHOP": _build_shop()
		"CAREER": _build_career()
	_refresh_all()

func _refresh_all() -> void:
	coins_label.text = "%d DROP COINS" % Profile.coins
	tier_label.text = "Battle Pass Tier %d / %d" % [Profile.tier(), Profile.TIERS]

# ---------- LOBBY ----------
func _build_lobby() -> void:
	var pg: Control = pages["LOBBY"]
	var play := _btn("PLAY", Vector2(360, 120), 54)
	var ps := StyleBoxFlat.new(); ps.bg_color = Color(1, 0.8, 0.15); ps.set_corner_radius_all(14)
	var ph := ps.duplicate(); ph.bg_color = Color(1, 0.9, 0.4)
	play.add_theme_stylebox_override("normal", ps); play.add_theme_stylebox_override("hover", ph); play.add_theme_stylebox_override("pressed", ph)
	play.add_theme_color_override("font_color", Color(0.15, 0.05, 0.3)); play.add_theme_color_override("font_hover_color", Color(0.15, 0.05, 0.3))
	play.anchor_left = 1; play.anchor_right = 1; play.anchor_top = 1; play.anchor_bottom = 1
	play.offset_left = -400; play.offset_right = -40; play.offset_top = -160; play.offset_bottom = -40
	play.pressed.connect(_play); pg.add_child(play)
	var modes := HBoxContainer.new(); modes.anchor_left = 1; modes.anchor_right = 1; modes.anchor_top = 1; modes.anchor_bottom = 1
	modes.offset_left = -400; modes.offset_right = -40; modes.offset_top = -250; modes.offset_bottom = -175; pg.add_child(modes)
	var mg := ButtonGroup.new()
	for m in ["Solo", "Duos"]:
		var b := _btn(m.to_upper(), Vector2(176, 70), 26); b.toggle_mode = true; b.button_group = mg
		b.button_pressed = Profile.mode == m
		b.pressed.connect(func(): Profile.mode = m; mode_note.visible = m == "Duos")
		modes.add_child(b)
	mode_note = _lbl("Duos is visual only for now - you'll drop solo.", 16, Color(1, 0.8, 0.6))
	mode_note.anchor_left = 1; mode_note.anchor_right = 1; mode_note.anchor_top = 1; mode_note.anchor_bottom = 1
	mode_note.offset_left = -400; mode_note.offset_top = -280; mode_note.visible = Profile.mode == "Duos"; pg.add_child(mode_note)
	var left := VBoxContainer.new(); left.anchor_top = 1; left.anchor_bottom = 1; left.offset_left = 30
	left.offset_top = -250; left.offset_bottom = -40; left.add_theme_constant_override("separation", 10); pg.add_child(left)
	var em := _btn("EMOTE", Vector2(220, 64)); em.pressed.connect(func(): Util.play_anim(hero, Profile.item("emote").data.anim)); left.add_child(em)
	var st := _btn("SETTINGS", Vector2(220, 64)); st.pressed.connect(func(): settings.visible = not settings.visible); left.add_child(st)
	var q := _btn("QUIT", Vector2(220, 64)); q.pressed.connect(func(): get_tree().quit()); left.add_child(q)
	var news := PanelContainer.new(); news.anchor_left = 1; news.anchor_right = 1; news.offset_left = -400; news.offset_right = -40
	news.offset_top = 20; pg.add_child(news)
	var nv := VBoxContainer.new(); news.add_child(nv)
	nv.add_child(_lbl("NEWS", 24, Color(1, 0.85, 0.3)))
	var nl := _lbl("Season 1: Storm Rising\n- Battle Bus drops are live\n- Loot chests + 5 weapon types\n- New: Item Shop rotates daily", 18)
	nv.add_child(nl)

func _play() -> void:
	mm_time = 5.0; mm_overlay.visible = true

func _build_matchmaking() -> void:
	mm_overlay = ColorRect.new(); mm_overlay.color = Color(0, 0, 0, 0.7); mm_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mm_overlay.visible = false; add_child(mm_overlay)
	var vb := VBoxContainer.new(); vb.set_anchors_preset(PRESET_CENTER); vb.grow_horizontal = GROW_DIRECTION_BOTH
	vb.grow_vertical = GROW_DIRECTION_BOTH; vb.alignment = BoxContainer.ALIGNMENT_CENTER; mm_overlay.add_child(vb)
	mm_label = _lbl("", 40, Color(1, 0.85, 0.3)); mm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vb.add_child(mm_label)
	var c := _btn("CANCEL", Vector2(260, 70)); c.pressed.connect(func(): mm_time = -1; mm_overlay.visible = false); vb.add_child(c)

func _build_settings() -> void:
	settings = PanelContainer.new(); settings.anchor_top = 0.5; settings.anchor_bottom = 0.5
	settings.offset_left = 270; settings.offset_top = -200; settings.visible = false
	pages["LOBBY"].add_child(settings)
	var sb := VBoxContainer.new(); settings.add_child(sb)
	sb.add_child(_lbl("Mouse / touch sensitivity", 22))
	var s := HSlider.new(); s.min_value = 0.05; s.max_value = 1.0; s.step = 0.01
	s.value = Util.sensitivity; s.custom_minimum_size = Vector2(320, 50)
	s.value_changed.connect(func(v): Util.sensitivity = v); sb.add_child(s)
	sb.add_child(_lbl("Bot difficulty", 22))
	var dif := OptionButton.new(); dif.custom_minimum_size = Vector2(320, 50); dif.add_theme_font_size_override("font_size", 22)
	for d in ["Easy", "Normal", "Hard"]: dif.add_item(d)
	dif.selected = Util.difficulty; dif.item_selected.connect(func(i): Util.difficulty = i); sb.add_child(dif)
	var dbg := CheckButton.new(); dbg.text = "AI debug overlay (F3)"; dbg.button_pressed = Util.debug_ai
	dbg.add_theme_font_size_override("font_size", 22); dbg.toggled.connect(func(on): Util.debug_ai = on); sb.add_child(dbg)
	sb.add_child(_lbl("Bots", 22))
	var s2 := SpinBox.new(); s2.min_value = 1; s2.max_value = 40; s2.value = Util.bot_count
	s2.value_changed.connect(func(v): Util.bot_count = int(v)); sb.add_child(s2)
	var fs := CheckButton.new(); fs.text = "Fullscreen"; fs.add_theme_font_size_override("font_size", 22)
	fs.toggled.connect(func(on): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	sb.add_child(fs)
	var tc := CheckButton.new(); tc.text = "Touch controls"; tc.button_pressed = Util.touch_enabled
	tc.add_theme_font_size_override("font_size", 22)
	tc.toggled.connect(func(on): Util.touch_enabled = on); sb.add_child(tc)

# ---------- BATTLE PASS ----------
func _build_bp() -> void:
	var pg: Control = pages["BATTLE PASS"]; _clear(pg)
	var bgp := ColorRect.new(); bgp.color = Color(0.03, 0.02, 0.1, 0.8); bgp.anchor_right = 1; bgp.anchor_top = 0.35
	bgp.anchor_bottom = 1; bgp.offset_left = 12; bgp.offset_right = -12; bgp.offset_bottom = -12; pg.add_child(bgp)
	var vb := VBoxContainer.new(); vb.set_anchors_and_offsets_preset(PRESET_FULL_RECT); vb.offset_left = 16; vb.offset_top = 10; vb.offset_right = -16
	bgp.add_child(vb)
	var into := Profile.xp % Profile.XP_PER_TIER
	vb.add_child(_lbl("SEASON 1 BATTLE PASS  -  Tier %d / %d   (%d XP total)" % [Profile.tier(), Profile.TIERS, Profile.xp], 28, Color(1, 0.85, 0.3)))
	var pb := ProgressBar.new(); pb.max_value = Profile.XP_PER_TIER; pb.value = into if Profile.tier() < Profile.TIERS else Profile.XP_PER_TIER
	pb.custom_minimum_size = Vector2(0, 26); vb.add_child(pb)
	vb.add_child(_lbl("Earn XP every match: eliminations, placement and wins. Rewards unlock automatically.", 18))
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(0, 230); sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = SIZE_EXPAND_FILL; vb.add_child(sc)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); sc.add_child(row)
	for t in range(1, Profile.TIERS + 1):
		var r := Profile.bp_reward(t); var unlocked := Profile.tier() >= t
		var rar := 1
		var txt := "%d Drop Coins" % r.get("coins", 0)
		if r.has("item"): var it: Dictionary = Profile.CATALOG[r.item]; rar = it.rarity; txt = "%s\n(%s)" % [it.name, it.type.capitalize()]
		var c := _card(rar, unlocked); c.custom_minimum_size = Vector2(150, 200)
		var cv := VBoxContainer.new(); c.add_child(cv)
		cv.add_child(_lbl("TIER %d" % t, 24, Color(1, 0.85, 0.3)))
		var l := _lbl(txt, 18); l.autowrap_mode = TextServer.AUTOWRAP_WORD; l.custom_minimum_size = Vector2(130, 80); cv.add_child(l)
		cv.add_child(_lbl("UNLOCKED" if unlocked else "LOCKED", 18, Color(0.4, 1, 0.4) if unlocked else Color(0.7, 0.7, 0.7)))
		row.add_child(c)

# ---------- LOCKER ----------
func _build_locker() -> void:
	var pg: Control = pages["LOCKER"]; _clear(pg)
	var vb := _right_panel(pg, "LOCKER")
	var cats := HBoxContainer.new(); vb.add_child(cats)
	for c in [["skin", "OUTFIT"], ["backbling", "BACK BLING"], ["pickaxe", "PICKAXE"], ["emote", "EMOTE"]]:
		var b := _btn(c[1], Vector2(150, 60), 18); b.toggle_mode = true; b.button_pressed = locker_cat == c[0]
		b.pressed.connect(func(): locker_cat = c[0]; _build_locker()); cats.add_child(b)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = SIZE_EXPAND_FILL; vb.add_child(sc)
	var grid := GridContainer.new(); grid.columns = 3; grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10); sc.add_child(grid)
	for it in Profile.CATALOG.values():
		if it.type != locker_cat or not Profile.owned.has(it.id): continue
		var eq: bool = Profile.equipped[it.type] == it.id
		var c := _card(it.rarity); c.custom_minimum_size = Vector2(210, 130); grid.add_child(c)
		var cv := VBoxContainer.new(); c.add_child(cv)
		cv.add_child(_lbl(it.name, 22)); cv.add_child(_lbl(RARITY[it.rarity], 16, Weapons.RARITY_COLORS[it.rarity]))
		var b := _btn("EQUIPPED" if eq else "EQUIP", Vector2(180, 50), 18); b.disabled = eq
		b.pressed.connect(_equip.bind(it))
		cv.add_child(b)
	vb.add_child(_lbl("Locked items: buy them in the Item Shop or unlock them in the Battle Pass.", 16, Color(0.8, 0.8, 0.9)))

func _equip(it: Dictionary) -> void:
	Profile.equip(it.id); _rebuild_hero()
	if it.type == "emote": Util.play_anim(hero, it.data.anim)
	_build_locker()

# ---------- ITEM SHOP ----------
func _build_shop() -> void:
	var pg: Control = pages["ITEM SHOP"]; _clear(pg)
	var vb := _right_panel(pg, "ITEM SHOP")
	var s := Profile.seconds_to_reset()
	vb.add_child(_lbl("Daily items - new rotation in %dh %02dm.  Drop Coins are earned by playing (no real money)." % [s / 3600, (s % 3600) / 60], 16))
	var sc := ScrollContainer.new(); sc.size_flags_vertical = SIZE_EXPAND_FILL; vb.add_child(sc)
	var grid := GridContainer.new(); grid.columns = 3; grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10); sc.add_child(grid)
	for it in Profile.daily_shop():
		var own := Profile.owned.has(it.id)
		var c := _card(it.rarity); c.custom_minimum_size = Vector2(210, 170); grid.add_child(c)
		var cv := VBoxContainer.new(); c.add_child(cv)
		cv.add_child(_lbl(it.name, 22)); cv.add_child(_lbl("%s %s" % [RARITY[it.rarity], it.type.capitalize()], 16, Weapons.RARITY_COLORS[it.rarity]))
		if it.data.has("color"):
			var sw := ColorRect.new(); sw.color = it.data.color; sw.custom_minimum_size = Vector2(60, 16); cv.add_child(sw)
		var b := _btn("OWNED" if own else "%d DC" % it.price, Vector2(180, 54), 22)
		b.disabled = own or Profile.coins < it.price
		b.pressed.connect(_buy.bind(it))
		cv.add_child(b)

func _buy(it: Dictionary) -> void:
	if Profile.buy(it.id):
		Profile.equip(it.id); _rebuild_hero(); Util.sfx("victory", null, -8)
	_build_shop(); _refresh_all()

# ---------- CAREER ----------
func _build_career() -> void:
	var pg: Control = pages["CAREER"]; _clear(pg)
	var vb := _right_panel(pg, "CAREER")
	var st: Dictionary = Profile.stats
	var m: int = max(1, st.matches)
	var rows := [["Matches played", str(st.matches)], ["Victories", str(st.wins)], ["Win rate", "%.1f%%" % (100.0 * st.wins / m)],
		["Eliminations", str(st.kills)], ["K/D", "%.2f" % (float(st.kills) / max(1, st.deaths))], ["Top 10 finishes", str(st.top10)],
		["Best placement", "-" if st.best_place >= 99 else "#%d" % st.best_place], ["Time played", "%d min" % int(st.play_time / 60.0)],
		["Battle Pass tier", "%d / %d" % [Profile.tier(), Profile.TIERS]], ["Items owned", "%d / %d" % [Profile.owned.size(), Profile.CATALOG.size()]]]
	var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 40); vb.add_child(grid)
	for r in rows:
		grid.add_child(_lbl(r[0], 24, Color(0.8, 0.85, 1))); grid.add_child(_lbl(r[1], 26, Color(1, 0.85, 0.3)))
