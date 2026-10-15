extends SceneTree
## Minimal local MQTT-over-WebSocket mailbox for end-to-end tests; never contacts public brokers.
var server := TCPServer.new()
var clients: Array = []
const PEER := preload("res://scripts/mqtt_peer.gd")
func _initialize() -> void:
	if server.listen(18081,"127.0.0.1")!=OK: quit(1); return
	print("LOCAL_MQTT_READY")
func _process(_delta: float) -> bool:
	while server.is_connection_available():
		var socket := WebSocketPeer.new()
		socket.supported_protocols = PackedStringArray(["mqtt"])
		socket.inbound_buffer_size = 1<<22
		socket.outbound_buffer_size = 1<<22
		if socket.accept_stream(server.take_connection())==OK: clients.append({"ws":socket,"rx":PackedByteArray(),"topics":{}})
	for client in clients.duplicate():
		client.ws.poll()
		if client.ws.get_ready_state()==WebSocketPeer.STATE_CLOSED:
			clients.erase(client); continue
		while client.ws.get_available_packet_count()>0:
			client.rx.append_array(client.ws.get_packet())
		parse(client)
	return false
func packet(header: int, body: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray([header])
	result.append_array(PEER._remaining_length(body.size()))
	result.append_array(body)
	return result
func parse(client: Dictionary) -> void:
	while client.rx.size()>=2:
		var length := 0
		var mult := 1
		var offset := 1
		var complete := false
		while offset<client.rx.size() and offset<=4:
			var value: int = client.rx[offset]
			length += (value&127)*mult
			mult *= 128
			offset += 1
			if value&128==0: complete = true; break
		if not complete or client.rx.size()<offset+length: return
		var header: int = client.rx[0]
		var body: PackedByteArray = client.rx.slice(offset,offset+length)
		client.rx = client.rx.slice(offset+length)
		match header>>4:
			1: client.ws.send(PackedByteArray([0x20,2,0,0]))
			8:
				var position := 2
				var grants := PackedByteArray([body[0],body[1]])
				while position+2<=body.size():
					var size := (body[position]<<8)|body[position+1]
					position += 2
					client.topics[body.slice(position,position+size).get_string_from_utf8()] = true
					position += size+1
					grants.append(0)
				client.ws.send(packet(0x90,grants))
			3:
				var size := (body[0]<<8)|body[1]
				var topic := body.slice(2,2+size).get_string_from_utf8()
				for target in clients:
					if target.topics.has(topic) and target.ws.get_ready_state()==WebSocketPeer.STATE_OPEN: target.ws.send(packet(0x30,body))
			12: client.ws.send(PackedByteArray([0xd0,0]))
			14: client.ws.close()
