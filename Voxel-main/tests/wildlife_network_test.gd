extends SceneTree
var game: Node
var network: Node
var server := false
var failures := 0
var received_state := false
var remote_hit := false

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ")+message)
	if not condition:
		failures += 1

func _run() -> void:
	server = "--server" in OS.get_cmdline_user_args()
	root.get_node("Settings").update("fullscreen",false)
	change_scene_to_file("res://scenes/main.tscn")
	for i in 300:
		await process_frame
		game = current_scene
		if game != null and game.get("soundscape") != null:
			break
	game.player.set_physics_process(false)
	game.tools.set_process(false)
	network = root.get_node("Net")
	network.op_received.connect(func(_from: int, op: Dictionary):
		if op.get("op","") == "wild_state":
			received_state = true
		if op.get("op","") == "wild_hit":
			remote_hit = true)
	var wolf: Node = game.wildlife.by_id[19]
	var ground: Dictionary = game.wildlife.ground_at(Vector3(-4,0,9),70)
	var point: Vector3 = ground["position"]+Vector3.UP*0.1
	if server:
		var peer := ENetMultiplayerPeer.new()
		peer.set_bind_ip("127.0.0.1")
		var error := peer.create_server(17977,7)
		check(error == OK,"Local multiplayer host starts")
		network._peer = peer
		network.multiplayer.multiplayer_peer = peer
		network.players = {1:{"name":"WildlifeHost","color":0}}
		network.roster_changed.emit()
		wolf.set_physics_process(false)
		wolf.home = point
		wolf.global_position = point
		wolf.hp = 65.0
		game.player.global_position = point+Vector3(-2,0,0)
		for i in 150:
			if network.players.size() == 2:
				break
			await create_timer(.1).timeout
		check(network.players.size() == 2,"Client registers with host")
		root.get_node("Settings").update("world_features",true)
		for i in 100:
			if wolf.hp < 65.0:
				break
			await create_timer(.1).timeout
		check(remote_hit and wolf.hp == 42.0,"Host validates and applies client melee hit")
		root.get_node("Settings").update("world_features",false)
		var other := 0
		for id in network.players:
			if id != 1:
				other = id
		if other != 0:
			game.wildlife.damage_player(other,11.0,19)
		await create_timer(2.0).timeout
	else:
		await create_timer(1.0).timeout
		check(network.join("127.0.0.1:17977","WildlifeGuest"),"Client connects over loopback")
		for i in 150:
			if received_state and network.players.size() == 2:
				break
			await create_timer(.1).timeout
		check(received_state and not game.wildlife.authority(),"Client receives host-authoritative wildlife snapshots")
		await create_timer(.4).timeout
		check(game.world_features_enabled(),"Client applies host world-feature rule")
		check(wolf.global_position.distance_to(point) < .3,"Client interpolates wolf to host position")
		game.player.global_position = point+Vector3(1.3,0,0)
		await create_timer(.5).timeout
		game.wildlife.hit(19)
		for i in 100:
			if wolf.hp == 42.0:
				break
			await create_timer(.1).timeout
		check(wolf.hp == 42.0,"Host sword damage replicates back to client")
		for i in 50:
			if game.player.hp < 100.0:
				break
			await create_timer(.1).timeout
		check(game.player.hp == 89.0,"Host predator damage reaches attacked client only")
		await create_timer(.4).timeout
		check(not game.world_features_enabled(),"Host can disable world features for connected clients")
	print("WILDLIFE NETWORK %s RESULT: %d failures" % ["HOST" if server else "CLIENT",failures])
	network.leave(true)
	await create_timer(.2).timeout
	quit(0 if failures == 0 else 1)
