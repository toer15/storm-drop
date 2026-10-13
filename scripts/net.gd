extends Node
## Autoload "Net": online play with Godot's high-level multiplayer API.
## - ENet (UDP) for desktop / Android, WebSocket for the web build (browsers cannot open UDP sockets).
## - Host Game (listen server), Join by IP, LAN server browser (UDP broadcast on port 7778),
##   and a dedicated headless server: `StormDrop --headless -- --server [--port=7777] [--ws] [--max=16] [--bots=30]`.
## The host is authoritative for health/damage, loot, chests, building, the storm, the bus and all bots.
const DEFAULT_PORT := 7777
const LAN_PORT := 7778
const SAVE := "user://online.cfg"
const REGIONS := ["Auto", "LAN", "EU", "NA-East", "NA-West", "Asia", "Oceania", "South America"]
var settings := {"name": "Player", "address": "127.0.0.1", "port": DEFAULT_PORT, "region": "Auto", "max_players": 16, "protocol": "enet", "bots": 30}
var dedicated := false
var in_match := false
var peers := {}            # peer_id -> {name, ready, skin, bb, pick}
var match_seed := 0
var match_bots := 0
var status_text := ""
var lan_servers := {}      # "ip:port" -> {info..., seen}
var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_t := 0.0
var _auto_t := -1.0
signal lobby_changed
signal status(msg: String)

func _ready() -> void:
	_load()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _status("Could not connect to %s:%d" % [settings.address, settings.port]); leave())
	multiplayer.server_disconnected.connect(_on_server_gone)
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		dedicated = true
		for a in args:
			if a.begins_with("--port="): settings.port = int(a.substr(7))
			elif a.begins_with("--max="): settings.max_players = int(a.substr(6))
			elif a.begins_with("--bots="): settings.bots = int(a.substr(7))
			elif a.begins_with("--name="): settings.name = a.substr(7)
	for a in args: # test / scripted clients:  --join=host:port --player-name=Bob --autoready
		if a.begins_with("--player-name="): settings.name = a.substr(14)
		elif a.begins_with("--join="):
			var hp := a.substr(7).split(":"); settings.address = hp[0]
			if hp.size() > 1: settings.port = int(hp[1])
			get_tree().create_timer(1.5).timeout.connect(func(): join())
		elif a == "--host": get_tree().create_timer(1.5).timeout.connect(func(): host())
	if "--ws" in args: settings.protocol = "ws"
	elif "--enet" in args: settings.protocol = "enet"
	if "--autoready" in args:
		lobby_changed.connect(func():
			if active() and peers.has(my_id()) and not peers[my_id()].ready and not in_match: set_ready.call_deferred(true))

func _load() -> void:
	var f := ConfigFile.new()
	if f.load(SAVE) == OK:
		for k in settings: settings[k] = f.get_value("online", k, settings[k])
	if OS.has_feature("web"): settings.protocol = "ws"

func save() -> void:
	var f := ConfigFile.new()
	for k in settings: f.set_value("online", k, settings[k])
	f.save(SAVE)

func _status(m: String) -> void:
	status_text = m; print("[net] ", m); status.emit(m)

func active() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_client() -> bool:
	return active() and not multiplayer.is_server()

func is_server() -> bool:
	return not active() or multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id() if active() else 1

func my_info() -> Dictionary:
	return {"name": settings.name, "ready": false, "skin": Profile.equipped.skin, "bb": Profile.equipped.backbling, "pick": Profile.equipped.pickaxe}

# ---------------------------------------------------------------- host / join / leave
func host() -> Error:
	leave()
	var port: int = settings.port; var err: Error
	var peer: MultiplayerPeer
	if settings.protocol == "ws":
		var ws := WebSocketMultiplayerPeer.new(); err = ws.create_server(port); peer = ws
	else:
		if not ClassDB.class_exists("ENetMultiplayerPeer"): _status("ENet isn't available on this platform - use WebSocket"); return ERR_UNAVAILABLE
		var en = ClassDB.instantiate("ENetMultiplayerPeer"); err = en.create_server(port, maxi(1, settings.max_players - 1)); peer = en
	if err != OK:
		_status("Could not host on port %d (%s). Is it already in use?" % [port, error_string(err)]); return err
	multiplayer.multiplayer_peer = peer
	peers.clear(); in_match = false
	if not dedicated: peers[1] = my_info(); peers[1].ready = true
	_start_broadcast()
	_status("%s server on port %d (%s)" % ["Dedicated" if dedicated else "Hosting", port, "WebSocket" if settings.protocol == "ws" else "ENet/UDP"])
	lobby_changed.emit()
	return OK

func join(address := "", port := -1) -> Error:
	leave()
	if address != "": settings.address = address
	if port > 0: settings.port = port
	var err: Error; var peer: MultiplayerPeer
	if settings.protocol == "ws" or OS.has_feature("web"):
		var url: String = settings.address
		if not "://" in url: url = "%s://%s:%d" % ["wss" if OS.has_feature("web") and JavaScriptBridge.eval("location.protocol") == "https:" else "ws", url, settings.port]
		var ws := WebSocketMultiplayerPeer.new(); err = ws.create_client(url); peer = ws
	else:
		var en = ClassDB.instantiate("ENetMultiplayerPeer"); err = en.create_client(settings.address, settings.port); peer = en # (ClassDB: the web build has no ENet)
	if err != OK:
		_status("Could not start connection (%s)" % error_string(err)); return err
	multiplayer.multiplayer_peer = peer
	_status("Connecting to %s:%d ..." % [settings.address, settings.port])
	return OK

func leave() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peers.clear(); in_match = false; _auto_t = -1.0
	if _bcast: _bcast.close(); _bcast = null
	lobby_changed.emit()

func _on_connected() -> void:
	_status("Connected! Waiting in the lobby.")
	_c_hello.rpc_id(1, my_info())

func _on_server_gone() -> void:
	_status("Disconnected from the server.")
	leave()
	if get_tree().current_scene and get_tree().current_scene.name == "game":
		get_tree().current_scene.call_deferred("net_server_lost")

func _on_peer_connected(_id: int) -> void:
	pass # wait for _c_hello

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server(): return
	var nm: String = peers.get(id, {}).get("name", "?")
	peers.erase(id); _push_lobby()
	var g := get_tree().current_scene
	if in_match and g and g.has_method("net_peer_left"): g.net_peer_left(id, nm)

@rpc("any_peer", "reliable")
func _c_hello(info: Dictionary) -> void:
	if not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	if in_match:
		_s_kick.rpc_id(id, "A match is in progress on this server. Try again in a few minutes.")
		return
	info.ready = false; info.name = String(info.get("name", "Player")).left(16)
	peers[id] = info; _push_lobby()

@rpc("authority", "reliable")
func _s_kick(msg: String) -> void:
	_status(msg); leave()

@rpc("any_peer", "reliable")
func _c_ready(r: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if peers.has(id): peers[id].ready = r; _push_lobby()

func set_ready(r: bool) -> void:
	if not active(): return
	if multiplayer.is_server(): peers[1].ready = r; _push_lobby()
	else: _c_ready.rpc_id(1, r)

func _push_lobby() -> void:
	if multiplayer.is_server() and active():
		_s_lobby.rpc(peers)
	lobby_changed.emit()

@rpc("authority", "reliable")
func _s_lobby(p: Dictionary) -> void:
	peers = p; lobby_changed.emit()

func all_ready() -> bool:
	if peers.is_empty(): return false
	for k in peers: if not peers[k].ready: return false
	return true

## Host / dedicated server: start the match for everyone in the lobby.
func start_match() -> void:
	if not multiplayer.is_server() or in_match: return
	in_match = true
	_s_start.rpc(randi(), clampi(settings.bots if dedicated else Util.bot_count, 0, 52 - peers.size()), peers)
	get_tree().change_scene_to_file("res://scenes/game.tscn")

@rpc("authority", "call_local", "reliable")
func _s_start(seed_v: int, bots: int, p: Dictionary) -> void:
	match_seed = seed_v; match_bots = bots; peers = p; in_match = true
	if not multiplayer.is_server(): get_tree().change_scene_to_file("res://scenes/game.tscn")

## Host: back to the lobby after a match (players keep their connection).
func end_match() -> void:
	in_match = false
	for k in peers: peers[k].ready = (k == 1 and not dedicated)
	_push_lobby()

# ---------------------------------------------------------------- LAN discovery
func _start_broadcast() -> void:
	_bcast = PacketPeerUDP.new(); _bcast.set_broadcast_enabled(true)
	_bcast.set_dest_address("255.255.255.255", LAN_PORT)

func browse(on: bool) -> void:
	if on and _listen == null and not OS.has_feature("web"):
		_listen = PacketPeerUDP.new()
		if _listen.bind(LAN_PORT) != OK: _status("LAN browser: port %d busy" % LAN_PORT); _listen = null
	elif not on and _listen: _listen.close(); _listen = null

func _process(delta: float) -> void:
	if _bcast and active() and multiplayer.is_server():
		_bcast_t -= delta
		if _bcast_t <= 0:
			_bcast_t = 1.0
			var host_name: String = settings.name if not dedicated else "Dedicated server"
			var info := {"game": "stormdrop", "v": 14, "name": host_name, "port": settings.port, "players": peers.size(),
				"max": settings.max_players, "in_match": in_match, "region": settings.region, "proto": settings.protocol}
			_bcast.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listen:
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet().get_string_from_utf8(); var ip := _listen.get_packet_ip()
			var d = JSON.parse_string(pkt)
			if d is Dictionary and d.get("game") == "stormdrop":
				d.ip = ip; d.seen = Time.get_ticks_msec(); lan_servers["%s:%d" % [ip, d.port]] = d
		for k in lan_servers.keys():
			if Time.get_ticks_msec() - lan_servers[k].seen > 4000: lan_servers.erase(k)
	# dedicated server: auto-start 10 s after everyone in the lobby is ready
	if dedicated and active() and not in_match:
		if all_ready():
			if _auto_t < 0: _auto_t = 10.0; _status("All %d players ready - starting in 10 s" % peers.size())
			_auto_t -= delta
			if _auto_t <= 0: _auto_t = -1.0; start_match()
		else: _auto_t = -1.0
