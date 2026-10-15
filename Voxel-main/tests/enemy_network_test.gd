extends SceneTree
var failures := 0
var messages := {}
var peer: Node
var guest_id := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func receive(id: int,op: Dictionary) -> void:
	if str(op.get("op","")).begins_with("test_"):
		messages[op.op] = op
		if id!=1: guest_id = id
func wait_message(id: String) -> void:
	for i in 500:
		if messages.has(id): return
		await create_timer(.1).timeout
	check(false,"Network message timeout "+id)
func main_ready() -> Node:
	var start := Time.get_ticks_msec()
	while current_scene==null or current_scene.get("world_ready")!=true:
		await process_frame
		if Time.get_ticks_msec()-start>90000: quit(1); return null
	return current_scene
func prepare(game: Node, point: Vector3) -> void:
	game.player.position = point+Vector3(0,0,-7)
	var key: Vector2i = game.generator.chunk_of(point)
	for dx in range(-1,2):
		for dz in range(-1,2): game.generator.ensure_sync(key+Vector2i(dx,dz))
	for actor in game.wildlife.all_actors(): actor.set_physics_process(false)
func run() -> void:
	peer = root.get_node("Net")
	peer.op_received.connect(receive)
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("world_features",false)
	if "--server" in OS.get_cmdline_user_args():
		root.get_node("Worlds").new_world({"seed_text":"Gegner-Freunde","size":1,"villages":1,"difficulty":0})
		change_scene_to_file("res://scenes/main.tscn")
		var game := await main_ready()
		game.player.set_physics_process(false)
		var ep := ENetMultiplayerPeer.new()
		ep.set_bind_ip("127.0.0.1")
		check(ep.create_server(17982,7)==OK,"Enemy world starts local host")
		peer._peer = ep; peer.multiplayer.multiplayer_peer = ep
		peer.players = {1:{"name":"EnemyHost","color":0}}
		peer.roster_changed.emit()
		await wait_message("test_loaded")
		var plan := {}
		for x in range(100,130):
			for z in range(100,130):
				var candidate: Dictionary = game.enemies.standard_plan(Vector2i(x,z))
				if candidate.get("species","")=="goblin": plan = candidate; break
			if not plan.is_empty(): break
		check(not plan.is_empty() and plan.count==5,"Host finds a real five-goblin encounter")
		prepare(game,plan.point)
		var enemy: Node = game.wildlife.by_id[int(plan.id)]
		enemy.hp = 1
		peer.send_op({"op":"test_standard","point":enemy.position,"id":enemy.animal_id,"group":enemy.encounter_id})
		await wait_message("test_kill")
		check(enemy.hp==0 and enemy.collision_layer==0,"Host owns guest enemy kill and collision removal")
		peer.send_op({"op":"test_kill_ok"})
		await wait_message("test_next")
		var dungeon := {}
		for x in range(-2,3):
			for z in range(-2,3):
				for site in game.generator.land.region(Vector2i(x,z)).dungeons:
					if site.species=="dragon": dungeon = site; break
				if not dungeon.is_empty(): break
			if not dungeon.is_empty(): break
		var point := Vector3(dungeon.p.x,float(dungeon.h)+.2,dungeon.p.y)
		prepare(game,point)
		var boss: Node
		for actor in game.wildlife.foes:
			if actor.dungeon_id==str(dungeon.id): boss = actor
		check(boss!=null,"Host streams one actual dungeon dragon")
		peer.send_op({"op":"test_boss","point":point,"id":boss.animal_id,"dungeon":dungeon.id})
		await wait_message("test_boss_loaded")
		game.enemies.cue(boss,"breath",point,.9)
		game.enemies.shoot(boss,point+Vector3.UP*6,Vector3.UP,1,true)
		peer.send_op({"op":"test_spell_sent"})
		await wait_message("test_spell_seen")
		boss.receive_hit(1000000,point)
		await create_timer(.4).timeout
		peer.send_op({"op":"test_boss_dead"})
		await wait_message("test_done")
		var record: Dictionary = boss.snapshot()
		check(record.enemy and record.hp==0,"Boss defeat is saved with enemy identity")
		print("ENEMY_NETWORK_SERVER_FAILURES ",failures)
		quit(failures)
	else:
		change_scene_to_file("res://scenes/menu.tscn")
		await create_timer(2).timeout
		check(peer.join("127.0.0.1:17982","EnemyGuest"),"Guest joins host seed with enemy generation")
		var game := await main_ready()
		game.player.set_physics_process(false)
		peer.send_op_to(1,{"op":"test_loaded"})
		await wait_message("test_standard")
		var data: Dictionary = messages.test_standard
		prepare(game,data.point)
		game.player.position = data.point+Vector3(0,0,-1.8)
		game.cam_rig.yaw = PI
		for i in 30: await physics_frame
		var enemy: Node = game.wildlife.by_id.get(int(data.id))
		check(enemy!=null and enemy.species=="goblin","Guest generates the same enemy class and stable ID")
		var group: Array = game.wildlife.foes.filter(func(actor: Node): return actor.encounter_id==int(data.group))
		check(group.size()==5,"Guest generates the same group size")
		check(enemy.collision_layer==16 and game.player.test_move(game.player.global_transform,Vector3(0,0,3)),"Guest cannot walk through synchronized enemy body")
		check(game.combat.request("attack"),"Guest sword can attack new enemy")
		for i in 40: await physics_frame
		peer.send_op_to(1,{"op":"test_kill"})
		await wait_message("test_kill_ok")
		check(enemy.hp==0 and enemy.collision_layer==0,"Guest sees death and can cross the released hitbox")
		check(game.combat.fx.pieces.size()>0,"Guest sees enemy voxel disintegration")
		peer.send_op_to(1,{"op":"test_next"})
		await wait_message("test_boss")
		data = messages.test_boss
		prepare(game,data.point)
		var boss: Node = game.wildlife.by_id.get(int(data.id))
		check(boss!=null and boss.species=="dragon" and boss.is_boss,"Guest loads the same dungeon dragon")
		var same: Array = game.wildlife.foes.filter(func(actor: Node): return actor.dungeon_id==str(data.dungeon))
		check(same.size()==1,"Guest has one boss in this dungeon")
		peer.send_op_to(1,{"op":"test_boss_loaded"})
		await wait_message("test_spell_sent")
		check(boss._visual_kind=="breath" and game.enemies.projectiles.size()>0,"Boss telegraph and fire projectile reach guest")
		peer.send_op_to(1,{"op":"test_spell_seen"})
		await wait_message("test_boss_dead")
		check(boss.hp==0 and not boss.visible and boss.collision_layer==0,"Guest receives dungeon boss death")
		peer.send_op_to(1,{"op":"test_done"})
		print("ENEMY_NETWORK_CLIENT_FAILURES ",failures)
		quit(failures)
