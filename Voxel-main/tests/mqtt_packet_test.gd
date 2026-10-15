extends SceneTree
var failures := 0
func check(ok: bool, title: String) -> void:
	print(("PASS " if ok else "FAIL ")+title)
	if not ok: failures += 1
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var peer = load("res://scripts/mqtt_peer.gd").new("ws://127.0.0.1:18081","ABCDEF",false)
	peer._queue = [{"from":17,"mode":MultiplayerPeer.TRANSFER_MODE_RELIABLE,"channel":2,"data":PackedByteArray([10])},
		{"from":42,"mode":MultiplayerPeer.TRANSFER_MODE_UNRELIABLE,"channel":3,"data":PackedByteArray([20])}]
	check(peer.get_packet_peer()==17,"First RPC packet exposes its sender before consumption")
	check(peer.get_packet_channel()==2 and peer.get_packet_mode()==MultiplayerPeer.TRANSFER_MODE_RELIABLE,"First packet metadata is read from the same queued packet")
	check(peer.get_packet()==PackedByteArray([10]),"First packet payload is unchanged")
	check(peer.get_packet_peer()==42 and peer.get_packet_channel()==3 and peer.get_packet_mode()==MultiplayerPeer.TRANSFER_MODE_UNRELIABLE,"Next sender, mode and channel advance together")
	check(peer.get_packet()==PackedByteArray([20]) and peer.get_available_packet_count()==0,"Packets are delivered in order")
	check(peer.get_packet_peer()==0,"An empty queue does not report a stale sender")
	peer.close()
	print("MQTT_PACKET_FAILURES ",failures)
	quit(failures)
