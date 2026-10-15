extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures += 1
func run() -> void:
	for path in ["worlds/infinite_land.gd","worlds/chunk_baker.gd","worlds/stream_world.gd","worlds/door.gd","worlds/resident.gd","worlds/village_life.gd","ui/multiplayer_setup.gd","main.gd"]:
		var script = load("res://scripts/"+path)
		check(script!=null and script.can_instantiate(),"Compile "+path)
	if failures>0 or "--compile-only" in OS.get_cmdline_user_args(): quit(failures); return
	var worlds := root.get_node("Worlds")
	worlds.new_world({"seed_text":"Unendliche-Wiesen","size":0,"villages":1,"difficulty":0})
	root.get_node("Settings").session_mode = "single"
	change_scene_to_file("res://scenes/main.tscn")
	var started := Time.get_ticks_msec()
	while current_scene==null or not current_scene.world_ready:
		await process_frame
		if Time.get_ticks_msec()-started>180000: print("FAIL stream startup timeout"); quit(1); return
	var main := current_scene
	print("STREAM_STARTUP_MS ",Time.get_ticks_msec()-started)
	check(main.world_data.get("streamed",false),"New worlds use streaming generator")
	check(main.vworld.vs==.125,"Terrain has same 12.5 cm resolution as test map")
	check(main.player.infinite_world,"Player has no finite map clamp")
	check(main.generator.life.doors.size()>0,"Interactive house doors and gates exist")
	check(main.generator.life.residents.size()>=4,"Village has working and walking residents")
	check(main.wildlife.animals.size()>=110,"Adult hens and chicks populate the farm")
	var safe_homes := true
	for animal in main.wildlife.animals:
		if not animal.pen_rect.has_area() and not main.wildlife.village_clear(animal.home): safe_homes = false; print("Unsafe spawn ",animal.name," ",animal.home)
	check(safe_homes,"All wild animals spawn outside the 48 metre village buffer")
	var village: Dictionary = main.world_data.villages[0]
	var old_home := Vector3(village.p.x,float(village.h),village.p.y)
	var wild: Node = main.wildlife.by_id[19]
	wild.restore({"home":old_home,"p":old_home,"hp":wild.max_health()},true)
	check(main.wildlife.village_clear(wild.home) and main.wildlife.village_clear(wild.position),"Old saves relocate unsafe wild animal spawns outside villages")
	var pen_hens := 0
	for animal in main.wildlife.animals:
		if animal.species=="chicken" and animal.pen_rect.has_area(): pen_hens += 1
	check(pen_hens>=8,"Village protection preserves domestic hens and chicks")
	var first: Node = main.generator.life.doors.values()[0]
	var id: String = first.door_id
	main.generator.life.toggle_door(id)
	for i in 24: await physics_frame
	check(first.opened and absf(first.leaf.rotation.y)>1,"Door opens physically")
	var key: Vector2i = main.generator.chunk_of(main.player.position)
	var point: Vector3i = main.vworld.to_voxel(main.player.position-Vector3(0,1.5,0))
	main.vworld.set_list(PackedInt32Array([point.x,point.y,point.z,54<<2]))
	main._save()
	main.generator.unload_chunk(key)
	check(not main.vworld.vol.has_chunk(key.x,key.y),"Distant terrain can be unloaded")
	main.generator.ensure_sync(key)
	check(main.vworld.vol.get_voxel(point)>>2==54,"Unloaded voxel changes survive regeneration")
	var far_key := Vector2i(90,-70)
	main.generator.ensure_sync(far_key)
	check(main.vworld.vol.has_chunk(far_key.x,far_key.y),"Terrain generates far beyond old boundaries, including negative coordinates")
	var raw_a: PackedByteArray = main.vworld.vol.get_chunk_data(far_key.x,far_key.y)
	main.generator.unload_chunk(far_key)
	main.generator.ensure_sync(far_key)
	check(main.vworld.vol.get_chunk_data(far_key.x,far_key.y)==raw_a,"Coordinate generation is deterministic on revisit")
	var life: Node = main.generator.life
	life.clock = 100
	for resident in life.residents.values():
		if resident.role=="farmer":
			resident.route_phase = -1
			var offset := float(abs(resident.resident_id.hash())%17)
			life.clock = 80-offset
			var start_position: Vector3 = resident.position
			for i in 120:
				resident._process(.25)
				life.clock += .25
			check(resident.position.distance_to(start_position)>10,"Farmer walks to the hen yard as part of its daily routine")
			check(resident.task=="feeding" and resident.grain.visible,"Farmer scatters visible grain while feeding")
			check(life.feeding.has(resident.village.id),"Feeding attracts hens in the enclosed pen")
			break
	check(life.door_states.get(id,false),"Open door state remains after chunk unload and reload")
	for animal in main.wildlife.animals:
		if animal.pen_rect.has_area(): check(animal.pen_rect.grow(.1).has_point(Vector2(animal.position.x,animal.position.z)),"Farm chicken stays in its fenced yard")
	main._save()
	var descriptor: Dictionary = worlds.config.duplicate(true)
	var far_position := Vector3(far_key.x*16+8,main.generator.land.height(Vector2(far_key)*16+Vector2(8,8))+1,far_key.y*16+8)
	main.player.set_physics_process(false)
	main.player.position = far_position
	main._save()
	main.queue_free()
	await process_frame
	worlds.resume_world(descriptor)
	root.get_node("Settings").session_mode = "continue"
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene==null or not current_scene.world_ready: await process_frame
	main = current_scene
	check(main.player.position.distance_to(far_position)<1,"Resume loads the actual distant saved location")
	check(main.generator.life.door_states.get(id,false),"Saved doors restore after restarting the world")
	main.generator.ensure_sync(key)
	check(main.vworld.vol.get_voxel(point)>>2==54,"Fine voxel edits restore after restarting the world")
	check(main.player.spawn_point==main.generator.land.spawn(),"Resume preserves the original village respawn point")
	print("STREAM_TEST_FAILURES ",failures)
	quit(failures)
