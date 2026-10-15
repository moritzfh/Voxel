extends SceneTree
var failures := 0
var server := false
var peer: Node
var loaded := {}
var far_request := {}
var door_confirm := false
var client_done := false
var far_confirm := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures += 1
func main_ready() -> Node:
	var start := Time.get_ticks_msec()
	while current_scene==null or current_scene.get("world_ready")!=true:
		await process_frame
		if Time.get_ticks_msec()-start>120000: print("FAIL network world startup timeout"); quit(1); return null
	return current_scene
func receive(_from: int,op: Dictionary) -> void:
	match str(op.get("op","")):
		"test_loaded": loaded = op
		"test_far": far_request = op
		"test_door_ok": door_confirm = true
		"test_done": client_done = true
		"test_far_ok": far_confirm = true
func run() -> void:
	server = "--server" in OS.get_cmdline_user_args()
	peer = root.get_node("Net")
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("world_features",false)
	peer.op_received.connect(receive)
	if server:
		root.get_node("Worlds").new_world({"seed_text":"Gemeinsam-Unendlich","size":0,"villages":1,"difficulty":0})
		change_scene_to_file("res://scenes/main.tscn")
		var main := await main_ready()
		main.player.set_physics_process(false)
		var ep := ENetMultiplayerPeer.new()
		ep.set_bind_ip("127.0.0.1")
		check(ep.create_server(17978,7)==OK,"Local host starts generated world")
		peer._peer = ep
		peer.multiplayer.multiplayer_peer = ep
		peer.players = {1:{"name":"StreamHost","color":0}}
		peer.roster_changed.emit()
		for i in 600:
			if not loaded.is_empty(): break
			await create_timer(.1).timeout
		check(not loaded.is_empty(),"Guest completes seed handshake and generation")
		if loaded.is_empty(): quit(1); return
		var key: Vector2i = main.generator.chunk_of(main.player.spawn_point)
		check(str(loaded.world)==root.get_node("Worlds").config.id,"Guest uses host's world identity")
		check(int(loaded.fingerprint)==hash(main.vworld.vol.get_chunk_data(key.x,key.y)),"Host and guest generate byte-identical fine voxels")
		var door_id := str(loaded.door)
		for i in 100:
			if main.generator.life.door_states.get(door_id,false): break
			await create_timer(.1).timeout
		check(main.generator.life.door_states.get(door_id,false),"Host validates and applies guest door interaction")
		peer.send_op({"op":"test_door_ok"})
		for i in 400:
			if not far_request.is_empty(): break
			await create_timer(.1).timeout
		var far_key: Vector2i = far_request.get("key",Vector2i.ZERO)
		for i in 300:
			if main.vworld.vol.has_chunk(far_key.x,far_key.y): break
			await create_timer(.1).timeout
		check(main.vworld.vol.has_chunk(far_key.x,far_key.y),"Host streams terrain around distant guest, not only its own player")
		if main.vworld.vol.has_chunk(far_key.x,far_key.y): check(hash(main.vworld.vol.get_chunk_data(far_key.x,far_key.y))==int(far_request.get("fingerprint",0)),"Distant newly generated chunks also match across peers")
		peer.send_op({"op":"test_far_ok"})
		for i in 100:
			if client_done: break
			await create_timer(.1).timeout
		main._save()
		check(main.guest_progress.has("StreamGuest"),"Host saves guest progress with shared world")
		check(float(main.guest_progress.get("StreamGuest",{}).get("hp",0))==61,"Guest health survives rejoining the host")
		print("STREAM_NETWORK_SERVER_FAILURES ",failures)
		quit(failures)
	else:
		change_scene_to_file("res://scenes/menu.tscn")
		await create_timer(1).timeout
		check(peer.join("127.0.0.1:17978","StreamGuest"),"Guest joins from main menu without preparing its own seed")
		var main := await main_ready()
		main.player.set_physics_process(false)
		main._autosave = 1000
		check(root.get_node("Worlds").remote and root.get_node("Worlds").config.seed_text=="Gemeinsam-Unendlich","Host seed and settings arrive before world load")
		check(main.world_data.streamed and main.vworld.vs==.125,"Guest loads same unlimited fine-voxel generator")
		check(main.remotes.has(1),"Guest sees the host avatar after loading the shared world")
		var door: Node = main.generator.life.doors.values()[0]
		var client_door_id: String = door.door_id
		var key: Vector2i = main.generator.chunk_of(main.player.spawn_point)
		main.player.position = door.position+Vector3(0,0,1)
		for i in 25: await physics_frame
		peer.send_op_to(1,{"op":"test_loaded","world":root.get_node("Worlds").config.id,"fingerprint":hash(main.vworld.vol.get_chunk_data(key.x,key.y)),"door":door.door_id})
		door.request_toggle()
		for i in 150:
			if door_confirm: break
			await create_timer(.1).timeout
		check(door.opened,"Guest sees host's synchronized door state")
		var village: Dictionary = main.generator.land.region(Vector2i(3,-2)).villages[0]
		var point := Vector3(village.p.x,float(village.h)+.5,village.p.y)
		var far_key: Vector2i = main.generator.chunk_of(point)
		main.generator.ensure_sync(far_key)
		main.player.position = point
		for i in 20: await physics_frame
		peer.send_op_to(1,{"op":"test_far","key":far_key,"fingerprint":hash(main.vworld.vol.get_chunk_data(far_key.x,far_key.y))})
		main.player.hp = 61
		main._save()
		for i in 300:
			if far_confirm: break
			await create_timer(.1).timeout
		check(far_confirm,"Host confirms the distant guest terrain before reconnecting")
		await create_timer(2).timeout
		peer.leave(true)
		await create_timer(.5).timeout
		main.player.hp = 20
		main.generator.life.door_states[client_door_id] = false
		check(peer.join("127.0.0.1:17978","StreamGuest"),"Guest can reconnect to the existing generated world")
		for i in 150:
			if main.player.hp==61: break
			await create_timer(.1).timeout
		check(main.player.hp==61,"Rejoining restores guest's saved player progress")
		check(main.generator.life.door_states.get(client_door_id,false),"Rejoining receives authoritative saved door states")
		peer.send_op_to(1,{"op":"test_done"})
		await create_timer(1.5).timeout
		print("STREAM_NETWORK_CLIENT_FAILURES ",failures)
		quit(failures)
