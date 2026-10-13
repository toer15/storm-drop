extends Node
## Dedicated server lobby (headless). Started with:  StormDrop --headless -- --server [--port=7777] [--ws] [--max=16] [--bots=30]
## Players connect, press READY in their party screen, and the match starts 10 s after everyone is ready.
func _ready() -> void:
	if not Net.active():
		if Net.host() != OK:
			push_error("Server failed to start"); get_tree().quit(1); return
	print("[server] Storm Drop dedicated server ready on port %d (%s), max %d players, %d bots. Waiting for players..." % [
		Net.settings.port, "WebSocket" if Net.settings.protocol == "ws" else "ENet/UDP", Net.settings.max_players, Net.settings.bots])
	Net.lobby_changed.connect(_log)

func _log() -> void:
	var names := []
	for k in Net.peers: names.append("%s%s" % [Net.peers[k].name, " (ready)" if Net.peers[k].ready else ""])
	print("[server] lobby: ", ", ".join(names) if names.size() > 0 else "(empty)")
