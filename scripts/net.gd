extends Node
## Multiplayer (autoload "Net"): ENet host/join, LAN discovery, UPnP port mapping, player roster, chat.
## Every peer simulates its own hero and sends its state ~20x per second; the host relays it to the others.

signal status_changed(text: String)
signal roster_changed
signal chat_received(from_name: String, text: String, color: Color)
signal player_state(id: int, state: Dictionary)
signal player_left(id: int)
signal lan_list_changed

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 8
const GAME_ID := "gruenweiten-1"
const COLORS := [Color(0.93, 0.45, 0.13), Color(0.20, 0.55, 0.95), Color(0.30, 0.78, 0.30), Color(0.85, 0.22, 0.30),
	Color(0.62, 0.36, 0.86), Color(0.95, 0.80, 0.20), Color(0.15, 0.80, 0.78), Color(0.95, 0.50, 0.70)]

var player_name := "Abenteurer"
var players := {}          # peer id -> {"name": String, "color": int}
var lan_hosts := {}        # ip -> {"name": String, "players": int, "t": float}
var status := ""
var public_ip := ""
var _peer: ENetMultiplayerPeer
var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_t := 0.0
var _upnp: UPNP
var _upnp_thread: Thread
var _join_timeout := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	var n := OS.get_environment("USERNAME")
	if n == "":
		n = OS.get_environment("USER")
	if n != "":
		player_name = n.substr(0, 16)

func active() -> bool:
	return _peer != null and multiplayer.multiplayer_peer == _peer and \
		_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_host() -> bool:
	return active() and multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id() if active() else 1

func color_of(id: int) -> Color:
	if players.has(id):
		return COLORS[int(players[id]["color"]) % COLORS.size()]
	return COLORS[0]

func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)
	print("[net] ", t)

# ------------------------------------------------------------------ host / join / leave
func host(name: String) -> bool:
	leave(true)
	player_name = _clean_name(name)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		_set_status("Hosten fehlgeschlagen (Port %d belegt?)" % PORT)
		return false
	multiplayer.multiplayer_peer = _peer
	players = {1: {"name": player_name, "color": 0}}
	roster_changed.emit()
	_start_broadcast()
	_set_status("Server läuft – LAN: %s  Port %d" % [", ".join(local_ips()), PORT])
	_start_upnp()
	return true

func join(address: String, name: String) -> bool:
	leave(true)
	player_name = _clean_name(name)
	address = address.strip_edges()
	var port := PORT
	if address.count(":") == 1:
		port = int(address.get_slice(":", 1))
		address = address.get_slice(":", 0)
	if address == "":
		_set_status("Bitte eine IP-Adresse eingeben.")
		return false
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		_set_status("Verbindung fehlgeschlagen.")
		return false
	multiplayer.multiplayer_peer = _peer
	# generous timeouts: a hitch while loading or compiling shaders must not drop the connection
	_peer.get_peer(1).set_timeout(32, 20000, 45000)
	_join_timeout = 25.0
	_set_status("Verbinde mit %s …" % address)
	return true

func leave(silent := false) -> void:
	_stop_broadcast()
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp:
		_upnp.delete_port_mapping(PORT, "UDP")
		_upnp = null
	var ids := players.keys()
	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {}
	_join_timeout = 0.0
	for id in ids:
		if id != 1 or true:
			player_left.emit(id)
	roster_changed.emit()
	if not silent:
		_set_status("Getrennt.")

func _clean_name(n: String) -> String:
	n = n.strip_edges().replace("\n", " ")
	if n == "":
		n = "Abenteurer"
	return n.substr(0, 16)

func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out

# ------------------------------------------------------------------ UPnP (internet play without manual port forwarding)
func _start_upnp() -> void:
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker)

func _upnp_worker() -> void:
	var u := UPNP.new()
	var r := u.discover(2000, 2, "InternetGatewayDevice")
	if r != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
		call_deferred("_upnp_done", null, "")
		return
	var m := u.add_port_mapping(PORT, PORT, "Gruenweiten", "UDP", 0)
	if m != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred("_upnp_done", null, "")
		return
	call_deferred("_upnp_done", u, u.query_external_address())

func _upnp_done(u: UPNP, ext: String) -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if not is_host():
		if u:
			u.delete_port_mapping(PORT, "UDP")
		return
	_upnp = u
	public_ip = ext
	if u and ext != "":
		_set_status("Server läuft – LAN: %s  ·  Internet: %s (Port %d offen)" % [", ".join(local_ips()), ext, PORT])
	else:
		_set_status("Server läuft – LAN: %s  ·  Internet: Port %d UDP im Router freigeben" % [", ".join(local_ips()), PORT])

# ------------------------------------------------------------------ LAN discovery
func _start_broadcast() -> void:
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	_bcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_bcast_t = 0.0

func _stop_broadcast() -> void:
	if _bcast:
		_bcast.close()
		_bcast = null

func start_lan_search() -> void:
	if _listen:
		return
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null

func stop_lan_search() -> void:
	if _listen:
		_listen.close()
		_listen = null
	lan_hosts.clear()

func _process(delta: float) -> void:
	if _bcast and is_host():
		_bcast_t -= delta
		if _bcast_t <= 0.0:
			_bcast_t = 1.0
			var msg := JSON.stringify({"game": GAME_ID, "name": player_name, "players": players.size(), "port": PORT})
			_bcast.put_packet(msg.to_utf8_buffer())
	if _listen:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet()
			var ip := _listen.get_packet_ip()
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if d is Dictionary and d.get("game", "") == GAME_ID:
				if not lan_hosts.has(ip):
					changed = true
				lan_hosts[ip] = {"name": str(d.get("name", "?")), "players": int(d.get("players", 1)), "t": 0.0}
		for ip in lan_hosts.keys():
			lan_hosts[ip]["t"] += delta
			if lan_hosts[ip]["t"] > 4.0:
				lan_hosts.erase(ip)
				changed = true
		if changed:
			lan_list_changed.emit()
	if _join_timeout > 0.0:
		_join_timeout -= delta
		if _join_timeout <= 0.0 and not active():
			leave(true)
			_set_status("Keine Antwort vom Server (IP, Port %d, Firewall?)" % PORT)

# ------------------------------------------------------------------ connection events
func _on_peer_connected(id: int) -> void:
	if is_host() and _peer.get_peer(id):
		_peer.get_peer(id).set_timeout(32, 20000, 45000)
	if is_host():
		_set_status("Spieler verbunden (%d/%d)" % [players.size() + 1, MAX_PLAYERS])

func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		var nm: String = players[id]["name"]
		players.erase(id)
		chat_received.emit("", "%s hat das Spiel verlassen." % nm, Color(0.8, 0.8, 0.8))
	player_left.emit(id)
	if is_host():
		_roster.rpc(players)
	roster_changed.emit()

func _on_connected() -> void:
	_join_timeout = 0.0
	_set_status("Verbunden.")
	_register.rpc_id(1, player_name)

func _on_failed() -> void:
	leave(true)
	_set_status("Verbindung fehlgeschlagen.")

func _on_server_gone() -> void:
	leave(true)
	_set_status("Der Server hat das Spiel beendet.")
	chat_received.emit("", "Verbindung zum Server getrennt.", Color(1, 0.6, 0.5))

# ------------------------------------------------------------------ RPCs
@rpc("any_peer", "reliable")
func _register(name: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var used := {}
	for p in players.values():
		used[int(p["color"])] = true
	var c := 0
	while used.has(c) and c < COLORS.size() - 1:
		c += 1
	players[id] = {"name": _clean_name(name), "color": c}
	_roster.rpc(players)
	roster_changed.emit()
	var msg := "%s ist beigetreten." % players[id]["name"]
	_chat_msg.rpc("", msg)
	chat_received.emit("", msg, Color(0.8, 0.8, 0.8))

@rpc("authority", "reliable")
func _roster(p: Dictionary) -> void:
	var old := players.keys()
	players = {}
	for k in p:
		players[int(k)] = p[k]
	for id in old:
		if not players.has(id):
			player_left.emit(id)
	roster_changed.emit()

## own hero state -> everybody (the host relays client packets)
func send_state(pos: Vector3, yaw: float, vel: Vector3, flags: int, attack_n: int) -> void:
	if not active():
		return
	_state.rpc(pos, yaw, vel, flags, attack_n)

@rpc("any_peer", "unreliable_ordered")
func _state(pos: Vector3, yaw: float, vel: Vector3, flags: int, attack_n: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == my_id() or not players.has(id):
		return
	player_state.emit(id, {"pos": pos, "yaw": yaw, "vel": vel, "flags": flags, "attack": attack_n})

func send_chat(text: String) -> void:
	text = text.strip_edges().substr(0, 160)
	if text == "":
		return
	if active():
		_chat_msg.rpc(player_name, text)
	chat_received.emit(player_name, text, color_of(my_id()))

@rpc("any_peer", "reliable")
func _chat_msg(from_name: String, text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var col := color_of(id) if from_name != "" else Color(0.8, 0.8, 0.8)
	chat_received.emit(from_name, text.substr(0, 160), col)

func _exit_tree() -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
	if _upnp:
		_upnp.delete_port_mapping(PORT, "UDP")
