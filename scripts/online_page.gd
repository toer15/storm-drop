extends Control
## Lobby > ONLINE: Host Game, Join by IP, LAN server browser, Online settings and the party / ready-up screen.
var status_l: Label
var party_box: VBoxContainer
var party_list: VBoxContainer
var connect_box: VBoxContainer
var lan_list: VBoxContainer
var ready_btn: Button
var start_btn: Button
var fields := {}
var lan_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT); mouse_filter = MOUSE_FILTER_IGNORE
	var bg := ColorRect.new(); bg.color = Color(0.03, 0.02, 0.1, 0.85); bg.anchor_left = 0.3; bg.anchor_right = 1; bg.anchor_bottom = 1
	bg.offset_right = -12; bg.offset_bottom = -12; add_child(bg)
	var sc := ScrollContainer.new(); sc.set_anchors_and_offsets_preset(PRESET_FULL_RECT); sc.offset_left = 16; sc.offset_top = 10; sc.offset_right = -16; sc.offset_bottom = -10
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; bg.add_child(sc)
	var cols := HBoxContainer.new(); cols.add_theme_constant_override("separation", 24); cols.size_flags_horizontal = SIZE_EXPAND_FILL; sc.add_child(cols)
	# --- left column: connect / party
	var left := VBoxContainer.new(); left.custom_minimum_size = Vector2(430, 0); left.add_theme_constant_override("separation", 10); cols.add_child(left)
	left.add_child(_lbl("PLAY ONLINE", 34, Color(1, 0.85, 0.3)))
	status_l = _lbl("Offline", 18, Color(0.8, 0.9, 1)); status_l.autowrap_mode = TextServer.AUTOWRAP_WORD; status_l.custom_minimum_size = Vector2(420, 0); left.add_child(status_l)
	connect_box = VBoxContainer.new(); connect_box.add_theme_constant_override("separation", 10); left.add_child(connect_box)
	var hb := _btn("HOST GAME", Vector2(420, 72), 28); hb.pressed.connect(func(): _apply_fields(); Net.host()); connect_box.add_child(hb)
	if OS.has_feature("web"): hb.disabled = true; hb.tooltip_text = "Browsers can't host - join a server instead"
	var jb := _btn("JOIN BY IP", Vector2(420, 72), 28); jb.pressed.connect(func(): _apply_fields(); Net.join()); connect_box.add_child(jb)
	connect_box.add_child(_lbl("LAN games (same Wi-Fi)", 22, Color(1, 0.85, 0.3)))
	lan_list = VBoxContainer.new(); connect_box.add_child(lan_list)
	if OS.has_feature("web"): connect_box.add_child(_lbl("LAN browsing isn't possible in a browser.\nType the server's address instead.", 16, Color(1, 0.8, 0.6)))
	party_box = VBoxContainer.new(); party_box.add_theme_constant_override("separation", 10); left.add_child(party_box)
	party_box.add_child(_lbl("PARTY LOBBY", 28, Color(1, 0.85, 0.3)))
	party_list = VBoxContainer.new(); party_box.add_child(party_list)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); party_box.add_child(row)
	ready_btn = _btn("READY", Vector2(200, 72), 28); ready_btn.toggle_mode = true; row.add_child(ready_btn)
	ready_btn.toggled.connect(func(on): Net.set_ready(on); ready_btn.text = "READY ✓" if on else "READY")
	start_btn = _btn("START MATCH", Vector2(210, 72), 24); start_btn.pressed.connect(func(): Net.start_match()); row.add_child(start_btn)
	var lv := _btn("LEAVE", Vector2(420, 60), 22); lv.pressed.connect(func(): Net.leave(); Net._status("Left the lobby.")); party_box.add_child(lv)
	# --- right column: Online settings
	var right := VBoxContainer.new(); right.custom_minimum_size = Vector2(380, 0); right.add_theme_constant_override("separation", 6); cols.add_child(right)
	right.add_child(_lbl("ONLINE SETTINGS", 26, Color(1, 0.85, 0.3)))
	_field(right, "name", "Player name", Net.settings.name)
	_field(right, "address", "Server address (IP, host or ws:// URL)", Net.settings.address)
	_field(right, "port", "Port", str(Net.settings.port))
	right.add_child(_lbl("Region", 18))
	var reg := OptionButton.new(); reg.custom_minimum_size = Vector2(360, 52); reg.add_theme_font_size_override("font_size", 20)
	for r in Net.REGIONS: reg.add_item(r)
	reg.selected = maxi(0, Net.REGIONS.find(Net.settings.region)); reg.item_selected.connect(func(i): Net.settings.region = Net.REGIONS[i]; Net.save())
	right.add_child(reg)
	right.add_child(_lbl("Max players (when hosting)", 18))
	var mp := SpinBox.new(); mp.min_value = 2; mp.max_value = 32; mp.value = Net.settings.max_players; mp.custom_minimum_size = Vector2(360, 52)
	mp.value_changed.connect(func(v): Net.settings.max_players = int(v); Net.save()); right.add_child(mp)
	right.add_child(_lbl("Protocol", 18))
	var pr := OptionButton.new(); pr.custom_minimum_size = Vector2(360, 52); pr.add_theme_font_size_override("font_size", 20)
	pr.add_item("ENet / UDP (PC + Android)"); pr.add_item("WebSocket (lets browser players join)")
	pr.selected = 1 if Net.settings.protocol == "ws" else 0; pr.disabled = OS.has_feature("web")
	pr.item_selected.connect(func(i): Net.settings.protocol = "ws" if i == 1 else "enet"; Net.save()); right.add_child(pr)
	right.add_child(_lbl("Bots in online matches use the Bots setting (max 51 total).\nNo public matchmaking server: host on your network\nor self-host the dedicated server (see README).", 15, Color(0.8, 0.8, 0.9)))
	Net.lobby_changed.connect(_refresh); Net.status.connect(func(m): status_l.text = m)
	Net.browse(true)
	_refresh()

func _exit_tree() -> void:
	Net.browse(false)

func _field(parent: Node, key: String, label: String, val: String) -> void:
	parent.add_child(_lbl(label, 18))
	var le := LineEdit.new(); le.text = val; le.custom_minimum_size = Vector2(360, 52); le.add_theme_font_size_override("font_size", 20)
	le.text_submitted.connect(func(_t): _apply_fields()); le.focus_exited.connect(_apply_fields)
	parent.add_child(le); fields[key] = le

func _apply_fields() -> void:
	Net.settings.name = fields.name.text.strip_edges().left(16) if fields.name.text.strip_edges() != "" else "Player"
	Net.settings.address = fields.address.text.strip_edges()
	Net.settings.port = clampi(int(fields.port.text), 1024, 65535) if fields.port.text.is_valid_int() else Net.DEFAULT_PORT
	Net.save()

func _refresh() -> void:
	if not is_inside_tree(): return
	var on := Net.active()
	connect_box.visible = not on; party_box.visible = on
	if Net.status_text != "": status_l.text = Net.status_text
	for c in party_list.get_children(): c.queue_free()
	var ids: Array = Net.peers.keys(); ids.sort()
	for id in ids:
		var p: Dictionary = Net.peers[id]
		var host_tag := " (host)" if id == 1 else ""
		var you := "  <- you" if on and id == Net.my_id() else ""
		var l := _lbl("%s  %s%s%s" % ["✓" if p.ready else "…", p.name, host_tag, you], 24, Color(0.5, 1, 0.5) if p.ready else Color(1, 1, 1))
		party_list.add_child(l)
	if on and ids.is_empty(): party_list.add_child(_lbl("Waiting for the host...", 20))
	start_btn.visible = on and multiplayer.is_server()
	start_btn.disabled = not Net.all_ready()
	start_btn.text = "START MATCH" if Net.all_ready() else "WAITING..."
	if on and Net.peers.has(Net.my_id()): ready_btn.set_pressed_no_signal(Net.peers[Net.my_id()].ready); ready_btn.text = "READY ✓" if ready_btn.button_pressed else "READY"

func _process(delta: float) -> void:
	lan_t -= delta
	if lan_t > 0 or not visible: return
	lan_t = 1.0
	for c in lan_list.get_children(): c.queue_free()
	if Net.lan_servers.is_empty(): lan_list.add_child(_lbl("Searching... (nobody hosting yet)", 18, Color(0.7, 0.7, 0.8)))
	for k in Net.lan_servers:
		var s: Dictionary = Net.lan_servers[k]
		var b := _btn("%s  -  %d/%d  %s%s" % [s.name, s.players, s.max, s.ip, "  (in match)" if s.in_match else ""], Vector2(420, 60), 18)
		b.disabled = s.in_match
		b.pressed.connect(func(): Net.settings.protocol = s.get("proto", "enet"); fields.address.text = s.ip; fields.port.text = str(s.port); _apply_fields(); Net.join(s.ip, int(s.port)))
		lan_list.add_child(b)

func _btn(t: String, sz: Vector2, fs := 22) -> Button:
	var b := Button.new(); b.text = t; b.custom_minimum_size = sz; b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(func(): Util.sfx("click")); return b

func _lbl(t: String, fs := 20, col := Color.WHITE) -> Label:
	var l := Label.new(); l.text = t; l.add_theme_font_size_override("font_size", fs); l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4); l.add_theme_color_override("font_outline_color", Color.BLACK); return l
