extends SceneTree
var failures := 0
var messages := {}
var peer: Node
var guest_id := 0
var server := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func receive(id: int,op: Dictionary) -> void:
	if str(op.get("op","")).begins_with("test_"):
		messages[op.op] = op
		if id!=1: guest_id = id
func wait_message(id: String) -> void:
	for i in 400:
		if messages.has(id): return
		await create_timer(.1).timeout
	check(false,"Message timeout "+id)
func main_ready() -> Node:
	var start := Time.get_ticks_msec()
	while current_scene==null or current_scene.get("world_ready")!=true:
		await process_frame
		if Time.get_ticks_msec()-start>90000: quit(1); return null
	return current_scene
func run() -> void:
	server = "--server" in OS.get_cmdline_user_args()
	peer = root.get_node("Net")
	peer.op_received.connect(receive)
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("world_features",false)
	if server:
		root.get_node("Worlds").new_world({"seed_text":"Krieger-Freunde","size":0,"villages":1,"difficulty":0})
		change_scene_to_file("res://scenes/main.tscn")
		var main := await main_ready()
		main.player.set_physics_process(false)
		var ep := ENetMultiplayerPeer.new()
		ep.set_bind_ip("127.0.0.1")
		check(ep.create_server(17980,7)==OK,"Combat host starts seed world")
		peer._peer = ep
		peer.multiplayer.multiplayer_peer = ep
		peer.players = {1:{"name":"CombatHost","color":0}}
		peer.roster_changed.emit()
		await wait_message("test_loaded")
		for animal in main.wildlife.animals: animal.set_physics_process(false)
		var wolf: Node = main.wildlife.by_id[19]
		wolf.hp = 65
		wolf.position = main.player.position+Vector3(0,0,-2)
		main.combat.server_peers[guest_id] = {"mana":20.0,"potions":3,"ranks":{},"rage":0.0,"next":0.0,"cd":{},"combo":0,"until":0.0}
		peer.send_op({"op":"test_prepare","point":main.player.position})
		await wait_message("test_attack1")
		await create_timer(.35).timeout
		check(wolf.hp==42,"Host applies guest sword hit at animation impact")
		check(main.remotes[guest_id].model.combat_kind=="attack","Host receives guest swing animation")
		peer.send_op({"op":"test_first_ok"})
		await wait_message("test_killed")
		check(wolf.hp==0 and not wolf.visible,"Host owns the guest combo kill")
		check(main.combat.server_peers[guest_id].mana>26,"Host awards kill and combo mana")
		# Repeated forged ability requests cannot bypass cooldown or spend negative mana.
		var before: int = main.combat.jobs.size()
		check(main.combat._accept(guest_id,{"kind":"spin","yaw":0,"level":1,"ranks":{},"sword":true}),"Host accepts one affordable ability")
		check(not main.combat._accept(guest_id,{"kind":"spin","yaw":0,"level":1,"ranks":{},"sword":true}),"Host rejects duplicate skill request during cooldown")
		check(main.combat.jobs.size()==before+3,"Rejected skill does not duplicate hits")
		main.combat.server_peers[guest_id].next = 0
		main.combat.server_peers[guest_id].mana = 0
		check(not main.combat._accept(guest_id,{"kind":"slam","yaw":0,"level":1,"ranks":{},"sword":true}),"Host rejects unaffordable mana skill")
		peer.send_op({"op":"test_done"})
		await create_timer(1).timeout
		print("COMBAT_NETWORK_SERVER_FAILURES ",failures)
		quit(failures)
	else:
		change_scene_to_file("res://scenes/menu.tscn")
		await create_timer(2).timeout
		check(peer.join("127.0.0.1:17980","CombatGuest"),"Guest joins generated combat world")
		var main := await main_ready()
		main.player.set_physics_process(false)
		peer.send_op_to(1,{"op":"test_loaded"})
		await wait_message("test_prepare")
		main.player.position = messages.test_prepare.point
		main.cam_rig.yaw = 0
		main.player.mana = 20
		for i in 30: await physics_frame
		var wolf: Node = main.wildlife.by_id[19]
		check(main.combat.request("attack"),"Guest starts first swing locally")
		peer.send_op_to(1,{"op":"test_attack1"})
		await wait_message("test_first_ok")
		check(wolf.hp==42 and wolf._hurt>0,"Guest receives damage and hit blink immediately")
		for i in 10: await physics_frame
		check(main.combat.request("attack"),"Guest starts right swing")
		for i in 30: await physics_frame
		check(main.combat.request("attack") and main.combat.combo==3,"Guest chains spin finisher")
		for i in 45: await physics_frame
		check(wolf.hp==0 and not wolf.visible,"Guest sees synchronized enemy death")
		check(main.combat.fx.pieces.size()>0,"Guest sees falling death voxels")
		check(main.player.mana>26,"Guest receives kill and finisher mana")
		peer.send_op_to(1,{"op":"test_killed"})
		await wait_message("test_done")
		print("COMBAT_NETWORK_CLIENT_FAILURES ",failures)
		quit(failures)
