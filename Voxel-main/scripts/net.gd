extends Node
## Multiplayer (autoload "Net"): online play by code (MQTT relay, no port forwarding), direct ENet host/join by IP,
## LAN discovery, UPnP port mapping, player roster, chat.
## Every peer simulates its own hero and sends its state ~20x per second; the host relays it to the others.

signal status_changed(text: String)
signal roster_changed
signal chat_received(from_name: String, text: String, color: Color)
signal player_state(id: int, state: Dictionary)
signal player_left(id: int)
signal lan_list_changed
signal player_joined(id: int)   # host only: a new player registered (send them the world)

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 8
const GAME_ID := "gruenweiten-1"
const MQTT_PEER := preload("res://scripts/mqtt_peer.gd")
# public MQTT brokers used only as a mailbox between the players (secure WebSocket); the last letter of a code says which
const BROKERS := ["wss://broker.emqx.io:8084/mqtt", "wss://broker.hivemq.com:8884/mqtt", "wss://test.mosquitto.org:8081/mqtt"]
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const COLORS := [Color(0.93, 0.45, 0.13), Color(0.20, 0.55, 0.95), Color(0.30, 0.78, 0.30), Color(0.85, 0.22, 0.30),
	Color(0.62, 0.36, 0.86), Color(0.95, 0.80, 0.20), Color(0.15, 0.80, 0.78), Color(0.95, 0.50, 0.70)]

var player_name := "Abenteurer"
var players := {}          # peer id -> {"name": String, "color": int}
var lan_hosts := {}        # ip -> {"name": String, "players": int, "t": float}
var status := ""
var public_ip := ""
var _peer: MultiplayerPeer
var online_code := ""      # set while hosting / joined by code
var broker_override := ""  # --broker=ws://... (tests)
var _broker_idx := 0
var _broker_msg := ""
var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_t := 0.0
var _upnp: UPNP
var _upnp_thread: Thread
var _join_timeout := 0.0
var world_loading := false
var _pending_world_ops: Array = []

func finish_world_loading() -> void:
	world_loading = false
	var pending := _pending_world_ops.duplicate()
	_pending_world_ops.clear()
	for entry in pending: op_received.emit(entry[0],entry[1])

func _receive_world_offer(op: Dictionary) -> void:
	var descriptor: Variant = op.get("descriptor",{})
	if not descriptor is Dictionary or int(descriptor.get("version",0)) not in [0,1,2]: return
	Worlds.config = descriptor.duplicate(true)
	Worlds.remote = true
	Worlds.continuing = false
	Worlds.join_spawn = op.get("spawn",[0,2,0])
	Settings.session_mode = "guest"
	var current := get_tree().current_scene
	if current and current.get("world_ready")==true and current.world_data.get("descriptor",{}).get("id","")==descriptor.get("id",""):
		current.accept_world_rule(bool(op.get("rule",false)))
		send_op_to(1,{"op":"world_ready"})
		return
	world_loading = true
	Game.reset()
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file","res://scenes/main.tscn")

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
func host(name: String, local_test := false) -> bool:
	if Worlds.remote:
		_set_status("Zum Hosten im Hauptmenü eine eigene Welt wählen.")
		return false
	leave(true)
	player_name = _clean_name(name)
	var ep := ENetMultiplayerPeer.new()
	if local_test: ep.set_bind_ip("127.0.0.1")
	_peer = ep
	var port := 17979 if local_test else PORT
	var err := ep.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		_set_status("Hosten fehlgeschlagen (Port %d belegt?)" % PORT)
		return false
	multiplayer.multiplayer_peer = _peer
	players = {1: {"name": player_name, "color": 0}}
	roster_changed.emit()
	if not local_test:
		_start_broadcast()
		_start_upnp()
	_set_status("Lokaler Testserver: 127.0.0.1:17979" if local_test else "Server läuft – LAN: %s  Port %d" % [", ".join(local_ips()),PORT])
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
	var ep := ENetMultiplayerPeer.new()
	_peer = ep
	var err := ep.create_client(address, port)
	if err != OK:
		_peer = null
		_set_status("Verbindung fehlgeschlagen.")
		return false
	multiplayer.multiplayer_peer = _peer
	# generous timeouts: a hitch while loading or compiling shaders must not drop the connection
	(_peer as ENetMultiplayerPeer).get_peer(1).set_timeout(32, 20000, 45000)
	_join_timeout = 25.0
	_set_status("Verbinde mit %s …" % address)
	return true

## Online by code: no router setup needed. The host gets a short code, friends type it in.
func host_online(name: String, broker_idx := 0) -> bool:
	if Worlds.remote:
		_set_status("Zum Hosten im Hauptmenü eine eigene Welt wählen.")
		return false
	leave(true)
	player_name = _clean_name(name)
	_broker_idx = clampi(broker_idx, 0, BROKERS.size() - 1)
	var c := ""
	for i in 5:
		c += CODE_CHARS[randi() % CODE_CHARS.length()]
	c += CODE_CHARS[_broker_idx]
	_start_mqtt(c, true)
	players = {1: {"name": player_name, "color": 0}}
	roster_changed.emit()
	_set_status("Verbinde mit dem Vermittlungsdienst …")
	return true

func join_code(c: String, name: String) -> bool:
	leave(true)
	player_name = _clean_name(name)
	c = c.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if c.length() != 6:
		_set_status("Der Code hat 6 Zeichen.")
		return false
	_broker_idx = maxi(0, CODE_CHARS.find(c[5])) % BROKERS.size()
	_start_mqtt(c, false)
	_set_status("Suche Spiel %s …" % c)
	return true

func _start_mqtt(c: String, as_host: bool) -> void:
	online_code = c
	_broker_msg = ""
	var url: String = broker_override if broker_override != "" else BROKERS[_broker_idx]
	var mp = MQTT_PEER.new(url, c, as_host)
	mp.max_clients = MAX_PLAYERS - 1
	mp.raw_received.connect(_on_raw)
	mp.broker_status.connect(_on_broker_status.bind(as_host))
	_peer = mp
	multiplayer.multiplayer_peer = mp

func _on_broker_status(text: String, as_host: bool) -> void:
	if text == "online":
		DisplayServer.clipboard_set(online_code)
		_set_status("Online! Code: %s  (in die Zwischenablage kopiert – an Freunde schicken)" % online_code)
		chat_received.emit("", "Online-Spiel offen. Code: %s" % online_code, Color(1.0, 0.85, 0.45))
		return
	_broker_msg = text
	if as_host and not active() and broker_override == "" and _broker_idx + 1 < BROKERS.size():
		# this mailbox is down: try the next one (gives a new code)
		var nxt := _broker_idx + 1
		call_deferred("host_online", player_name, nxt)
		return
	_set_status(text)

func is_online_mode() -> bool:
	return _peer != null and _peer.get_script() == MQTT_PEER

func _on_raw(from: int, data: PackedByteArray) -> void:
	if not players.has(from) or from == my_id():
		return
	var v = bytes_to_var(data)
	if v is Array and v.size() == 5:
		player_state.emit(from, {"pos": v[0], "yaw": v[1], "vel": v[2], "flags": v[3], "attack": v[4]})

func leave(silent := false) -> void:
	world_loading = false
	_pending_world_ops.clear()
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
	online_code = ""
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
	if is_host() and _peer is ENetMultiplayerPeer and (_peer as ENetMultiplayerPeer).get_peer(id):
		(_peer as ENetMultiplayerPeer).get_peer(id).set_timeout(32, 20000, 45000)
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
	var why := _broker_msg
	leave(true)
	_set_status(why if why != "" else "Verbindung fehlgeschlagen.")

func _on_server_gone() -> void:
	leave(true)
	_set_status("Der Host hat das Spiel beendet.")
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
	player_joined.emit(id)
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
	if is_online_mode():
		_peer.send_raw_all(var_to_bytes([pos, yaw, vel, flags, attack_n]))
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

# ------------------------------------------------------------------ world edits
signal op_received(from_id: int, op: Dictionary)

func send_op(op: Dictionary) -> void:
	if not active():
		return
	_op.rpc(op)

func send_op_to(id: int, op: Dictionary) -> void:
	if active():
		_op.rpc_id(id, op)

@rpc("any_peer", "reliable")
func _op(op: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == my_id():
		return
	if op.get("op","")=="world_offer":
		if id==1 and not is_host(): _receive_world_offer(op)
		return
	if world_loading:
		if op.get("op","") not in ["wild_state","village_state"] and _pending_world_ops.size()<4096: _pending_world_ops.append([id,op])
		return
	op_received.emit(id, op)
