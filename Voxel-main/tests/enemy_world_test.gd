extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Worlds").new_world({"seed_text":"Monster-und-Dungeons","size":1,"villages":1,"difficulty":2})
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene==null or current_scene.get("world_ready")!=true: await process_frame
	var game := current_scene
	game.player.set_physics_process(false)
	game.set_process(false)
	game.generator.set_process(false)
	for actor in game.wildlife.all_actors(): actor.set_physics_process(false)
	var bosses := {}
	var layouts := []
	for x in range(-3,4):
		for z in range(-3,4):
			var layout: Dictionary = game.generator.land.region(Vector2i(x,z))
			for dungeon in layout.dungeons:
				bosses[dungeon.species] = dungeon
				layouts.append(dungeon)
	check(bosses.size()==3,"Generated regions contain cyclops, dragon and sandworm dungeons")
	var unique := {}
	for dungeon in layouts:
		var key: Vector2i = game.generator.chunk_of(Vector3(dungeon.p.x,dungeon.h,dungeon.p.y))
		var plans: Array = game.enemies.dungeon_plans(key)
		for plan in plans:
			check(plan.count==1 and not unique.has(plan.id),"Dungeon contains one unique boss")
			unique[plan.id] = true
	for species in bosses:
		var dungeon: Dictionary = bosses[species]
		var point := Vector3(dungeon.p.x,dungeon.h+.3,dungeon.p.y)
		var key: Vector2i = game.generator.chunk_of(point)
		game.generator.ensure_sync(key)
		var matching := []
		for enemy in game.wildlife.foes:
			if enemy.dungeon_id==str(dungeon.id): matching.append(enemy)
		check(matching.size()==1 and matching[0].species==species,"Actual streamed singleton spawns: "+species)
		if matching.is_empty(): continue
		var boss: Node = matching[0]
		check(game.wildlife.village_clear(boss.home,18),"Boss arena lies outside village protection")
		boss.receive_hit(1000000,point)
		game.enemies.unload_chunk(key)
		game.enemies.load_chunk(key)
		var restored: Node = game.wildlife.by_id[boss.animal_id]
		check(restored.hp==0 and not restored.visible,"Defeated boss stays dead when its chunk is revisited")
	var standard := {}
	var owner := Vector2i.ZERO
	for x in range(100,110):
		for z in range(100,110):
			var plan: Dictionary = game.enemies.standard_plan(Vector2i(x,z))
			if not plan.is_empty(): standard = plan; owner = Vector2i(x,z); break
		if not standard.is_empty(): break
	check(not standard.is_empty() and standard.count==5,"Distant high-level encounters spawn five standard enemies")
	if not standard.is_empty():
		game.generator.ensure_sync(owner)
		var group := []
		for enemy in game.wildlife.foes:
			if enemy.encounter_id==int(standard.id): group.append(enemy)
		check(group.size()==5,"Actual streamed group contains exactly five actors")
		if group.size()>0:
			game.wildlife.provoke(group[0],root.get_node("Net").my_id())
			check(group.all(func(enemy: Node): return enemy.anger_time>0),"Encounter companions react together to attacks")
	# Exercise melee and a moving spell against an actual player body in a clear dungeon floor.
	var arena: Dictionary = bosses.get("sandworm",{})
	if not arena.is_empty():
		var point := Vector3(arena.p.x,arena.h+.4,arena.p.y)
		var key: Vector2i = game.generator.chunk_of(point)
		for dx in range(-1,2):
			for dz in range(-1,2): game.generator.ensure_sync(key+Vector2i(dx,dz))
		for enemy in game.wildlife.foes: enemy.set_physics_process(false)
		var goblin: Node = game.wildlife.spawn_external(90000000000001,{"species":"goblin","encounter":90000000000001},point)
		goblin.set_physics_process(false)
		game.player.position = point+Vector3(0,0,1)
		game.player.hurt_cooldown = 0
		var before: float = game.player.hp
		goblin.start_attack(root.get_node("Net").my_id(),game.player.position)
		check(game.player.hp==before,"Goblin wind-up gives time to react")
		goblin._simulate(.4)
		check(game.player.hp<before,"Goblin melee attack damages player after wind-up")
		var witch: Node = game.wildlife.spawn_external(90000000000002,{"species":"witch","encounter":90000000000002},point+Vector3(0,0,5))
		witch.set_physics_process(false)
		game.player.position = point
		game.player.hurt_cooldown = 0
		before = game.player.hp
		witch.start_attack(root.get_node("Net").my_id(),game.player.position)
		witch._simulate(.4)
		check(game.enemies.projectiles.size()==1,"Witch casts a moving magic projectile")
		for i in 50: await physics_frame
		check(game.player.hp<before and game.enemies.projectiles.is_empty(),"Magic projectile hits the player and disappears")
	print("ENEMY_WORLD_FAILURES ",failures)
	game.queue_free()
	await process_frame
	await process_frame
	quit(failures)
