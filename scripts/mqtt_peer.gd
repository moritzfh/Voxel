extends MultiplayerPeerExtension
## Online play by code, no port forwarding: a MultiplayerPeer that tunnels Godot's multiplayer packets through
## a public MQTT broker (MQTT 3.1.1 over secure WebSocket). Star topology like ENet: clients talk to the host,
## SceneMultiplayer's server relay forwards between clients. High-rate hero states bypass the relay
## (send_raw_all -> one publish that every peer receives).
##
## Topics:  gw1/<code>/p/<peer id>  (direct)   gw1/<code>/all  (broadcast)
## Payload: [kind u8][from u32 LE][...]
##   kind 0 data: [mode u8][channel u8][bytes]   1 hello (+ name)   2 welcome   3 bye   4 ping   5 full   6 raw broadcast

signal raw_received(from_id: int, data: PackedByteArray)
signal broker_status(text: String)

const KIND_DATA := 0
const KIND_HELLO := 1
const KIND_WELCOME := 2
const KIND_BYE := 3
const KIND_PING := 4
const KIND_FULL := 5
const KIND_RAW := 6
const TIMEOUT := 12.0

var code := ""
var max_clients := 7
var _url := ""
var _ws := WebSocketPeer.new()
var _ws_open := false
var _mqtt_ready := false
var _rx := PackedByteArray()
var _uid := 1
var _server := false
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _refuse := false
var _queue: Array = []          # [{from, mode, channel, data}]
var _cur: Dictionary = {}
var _peers := {}                # peer id -> seconds since last packet
var _ping_t := 0.0
var _mqtt_ping_t := 0.0
var _last_poll := 0.0
var _connect_t := 0.0
var _pid := 1
var _base := ""

func _init(broker_url: String, game_code: String, as_server: bool) -> void:
	_url = broker_url
	code = game_code
	_server = as_server
	_base = "gw1/" + code
	_uid = 1 if as_server else (randi() % 2000000000) + 2
	_ws.supported_protocols = PackedStringArray(["mqtt"])
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var tls := TLSOptions.client() if broker_url.begins_with("wss") else null
	var err := _ws.connect_to_url(broker_url, tls)
	_status = MultiplayerPeer.CONNECTION_CONNECTING if err == OK else MultiplayerPeer.CONNECTION_DISCONNECTED

# ------------------------------------------------------------------ MultiplayerPeer interface
func _get_available_packet_count() -> int:
	return _queue.size()

func _get_max_packet_size() -> int:
	return 200000

func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty():
		return PackedByteArray()
	_cur = _queue.pop_front()
	return _cur["data"]

func _get_packet_peer() -> int:
	return int(_cur.get("from", 0))

func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return int(_cur.get("mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE)) as MultiplayerPeer.TransferMode

func _get_packet_channel() -> int:
	return int(_cur.get("channel", 0))

func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var msg := _header(KIND_DATA)
	msg.append(int(_mode))
	msg.append(_channel)
	msg.append_array(buffer)
	if _target == 0:
		if _server:
			_publish(_base + "/all", msg)
		else:
			_publish(_base + "/p/1", msg)
	elif _target > 0:
		_publish(_base + "/p/%d" % _target, msg)
	else:
		# everybody except -target
		var skip := -_target
		if _server:
			for id in _peers:
				if id != skip:
					_publish(_base + "/p/%d" % id, msg)
		elif skip != 1:
			_publish(_base + "/p/1", msg)
	return OK

func _set_target_peer(peer: int) -> void:
	_target = peer

func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode

func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode

func _set_transfer_channel(channel: int) -> void:
	_channel = channel

func _get_transfer_channel() -> int:
	return _channel

func _get_unique_id() -> int:
	return _uid

func _is_server() -> bool:
	return _server

func _is_server_relay_supported() -> bool:
	return true

func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable

func _is_refusing_new_connections() -> bool:
	return _refuse

func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status

func _disconnect_peer(peer: int, _force: bool) -> void:
	if _peers.has(peer):
		_publish(_base + "/p/%d" % peer, _header(KIND_BYE))
		_peers.erase(peer)
		peer_disconnected.emit(peer)

func _close() -> void:
	if _mqtt_ready:
		if _server:
			_publish(_base + "/all", _header(KIND_BYE))
		else:
			_publish(_base + "/p/1", _header(KIND_BYE))
		_ws.send(PackedByteArray([0xE0, 0x00]))
	_ws.close()
	_queue.clear()
	var ids := _peers.keys()
	_peers.clear()
	_mqtt_ready = false
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	for id in ids:
		peer_disconnected.emit(id)

## one publish that reaches every peer (used for the 20 Hz hero states)
func send_raw_all(data: PackedByteArray) -> void:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var msg := _header(KIND_RAW)
	msg.append_array(data)
	_publish(_base + "/all", msg)

# ------------------------------------------------------------------ polling
func _poll() -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	var dt := 1.0 / 60.0
	if st == WebSocketPeer.STATE_OPEN:
		if not _ws_open:
			_ws_open = true
			_send_connect()
		while _ws.get_available_packet_count() > 0:
			_rx.append_array(_ws.get_packet())
		_parse_rx()
	elif st == WebSocketPeer.STATE_CLOSED or st == WebSocketPeer.STATE_CLOSING:
		if st == WebSocketPeer.STATE_CLOSING:
			return
		if _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
			var was := _status
			_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			_mqtt_ready = false
			broker_status.emit("Vermittlungsdienst nicht erreichbar (%d)." % _ws.get_close_code() if was == MultiplayerPeer.CONNECTION_CONNECTING else "Verbindung zum Vermittlungsdienst verloren.")
			var ids := _peers.keys()
			_peers.clear()
			for id in ids:
				peer_disconnected.emit(id)
		return
	# timers (poll runs every frame; use real time)
	# real time, but clamped per frame: a long hitch (loading, shader compile) must not count as a timeout
	var now := Time.get_ticks_msec() / 1000.0
	dt = clampf(now - _last_poll, 0.0, 0.25) if _last_poll > 0.0 else 0.0
	_last_poll = now
	_connect_t += dt
	if not _mqtt_ready:
		if _connect_t > 10.0 and _status == MultiplayerPeer.CONNECTION_CONNECTING:
			broker_status.emit("Vermittlungsdienst antwortet nicht.")
			_close()
		return
	_mqtt_ping_t += dt
	if _mqtt_ping_t > 20.0:
		_mqtt_ping_t = 0.0
		_ws.send(PackedByteArray([0xC0, 0x00]))
	_ping_t += dt
	if _ping_t > 2.0:
		_ping_t = 0.0
		if _server:
			if not _peers.is_empty():
				_publish(_base + "/all", _header(KIND_PING))
		elif _status == MultiplayerPeer.CONNECTION_CONNECTED:
			_publish(_base + "/p/1", _header(KIND_PING))
		elif _status == MultiplayerPeer.CONNECTION_CONNECTING:
			_send_hello()
	for id in _peers.keys():
		_peers[id] += dt
		if _peers[id] > TIMEOUT:
			_peers.erase(id)
			_purge(id)
			if not _server:
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			peer_disconnected.emit(id)
	if not _server and _status == MultiplayerPeer.CONNECTION_CONNECTING and _connect_t > 22.0:
		broker_status.emit("Kein Spiel mit dem Code %s gefunden." % code)
		_close()

func _on_message(topic: String, payload: PackedByteArray) -> void:
	if payload.size() < 5:
		return
	var kind := payload[0]
	var from := payload.decode_u32(1)
	if from == _uid:
		return
	if _peers.has(from):
		_peers[from] = 0.0
	match kind:
		KIND_DATA:
			if payload.size() < 7 or not _peers.has(from):
				return
			_queue.append({"from": from, "mode": payload[5], "channel": payload[6], "data": payload.slice(7)})
		KIND_RAW:
			if _peers.has(from) or (not _server and _status == MultiplayerPeer.CONNECTION_CONNECTED):
				raw_received.emit(from, payload.slice(5))
		KIND_HELLO:
			if not _server:
				return
			if _peers.has(from):
				_publish(_base + "/p/%d" % from, _header(KIND_WELCOME))
				return
			if _refuse or _peers.size() >= max_clients:
				_publish(_base + "/p/%d" % from, _header(KIND_FULL))
				return
			_peers[from] = 0.0
			_publish(_base + "/p/%d" % from, _header(KIND_WELCOME))
			peer_connected.emit(from)
		KIND_WELCOME:
			if _server or from != 1:
				return
			if _status == MultiplayerPeer.CONNECTION_CONNECTING:
				_peers[1] = 0.0
				_status = MultiplayerPeer.CONNECTION_CONNECTED
				peer_connected.emit(1)
		KIND_FULL:
			if not _server:
				broker_status.emit("Das Spiel ist voll.")
				_close()
		KIND_BYE:
			if _peers.has(from):
				_peers.erase(from)
				_purge(from)
				if not _server:
					_status = MultiplayerPeer.CONNECTION_DISCONNECTED
				peer_disconnected.emit(from)
		KIND_PING:
			pass

func _purge(id: int) -> void:
	var keep: Array = []
	for q in _queue:
		if int(q["from"]) != id:
			keep.append(q)
	_queue = keep

func _header(kind: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(5)
	b[0] = kind
	b.encode_u32(1, _uid)
	return b

func _send_hello() -> void:
	_publish(_base + "/p/1", _header(KIND_HELLO))

# ------------------------------------------------------------------ minimal MQTT 3.1.1 client
static func _remaining_length(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	while true:
		var d := n % 128
		n = n / 128
		if n > 0:
			d |= 0x80
		out.append(d)
		if n == 0:
			break
	return out

static func _str(s: String) -> PackedByteArray:
	var u := s.to_utf8_buffer()
	var out := PackedByteArray([u.size() >> 8, u.size() & 0xFF])
	out.append_array(u)
	return out

func _packet(header: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([header])
	out.append_array(_remaining_length(body.size()))
	out.append_array(body)
	return out

func _send_connect() -> void:
	var body := _str("MQTT")
	body.append(4)        # protocol level 3.1.1
	body.append(0x02)     # clean session
	body.append(0)
	body.append(30)       # keep alive 30 s
	var cid := "gw%08x%04x" % [randi(), randi() & 0xFFFF]
	body.append_array(_str(cid))
	_ws.send(_packet(0x10, body))

func _subscribe(topic: String) -> void:
	_pid = (_pid % 65000) + 1
	var body := PackedByteArray([_pid >> 8, _pid & 0xFF])
	body.append_array(_str(topic))
	body.append(0)
	_ws.send(_packet(0x82, body))

func _publish(topic: String, payload: PackedByteArray) -> void:
	if not _mqtt_ready:
		return
	var body := _str(topic)
	body.append_array(payload)
	_ws.send(_packet(0x30, body))

func _parse_rx() -> void:
	while _rx.size() >= 2:
		var mult := 1
		var length := 0
		var i := 1
		var complete := false
		while i < _rx.size() and i <= 4:
			var d := _rx[i]
			length += (d & 0x7F) * mult
			mult *= 128
			i += 1
			if (d & 0x80) == 0:
				complete = true
				break
		if not complete or _rx.size() < i + length:
			return
		var typ := _rx[0] >> 4
		var body := _rx.slice(i, i + length)
		_rx = _rx.slice(i + length)
		match typ:
			2:  # CONNACK
				if body.size() >= 2 and body[1] == 0:
					_mqtt_ready = true
					_subscribe(_base + "/p/%d" % _uid)
					_subscribe(_base + "/all")
					if _server:
						_status = MultiplayerPeer.CONNECTION_CONNECTED
						broker_status.emit("online")
					else:
						_send_hello()
				else:
					broker_status.emit("Vermittlungsdienst hat die Verbindung abgelehnt.")
					_close()
			3:  # PUBLISH (QoS 0 only)
				if body.size() < 2:
					continue
				var tl := (body[0] << 8) | body[1]
				var topic := body.slice(2, 2 + tl).get_string_from_utf8()
				_on_message(topic, body.slice(2 + tl))
			9, 13:  # SUBACK, PINGRESP
				pass
