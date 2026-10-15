extends SceneTree
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures += 1
func _run() -> void:
	var worlds := root.get_node("Worlds")
	worlds.new_world({"seed_text":"Gruenweiten-2026","size":0,"villages":2,"difficulty":0})
	worlds.config.version = 1 # Regression coverage for existing finite-world saves.
	root.get_node("Settings").session_mode = "single"
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null: quit(1); return
	var main := scene.instantiate()
	root.add_child(main)
	current_scene = main
	var start := Time.get_ticks_msec()
	while not main.world_ready:
		await process_frame
		if Time.get_ticks_msec()-start > 120000: print("FAIL generation timeout"); quit(1); return
	print("GENERATION_MS ",Time.get_ticks_msec()-start)
	check(main.world_data.get("procedural",false),"Runtime procedural world loaded")
	check(main.world_data.villages.size()==2,"Two generated villages")
	check(main.world_data.caves.size()>=2,"Walkable caves generated")
	check(main.world_data.bridges.size()>0,"Road network crosses river with bridges")
	check(main.world_data.houses.size()==8,"Village houses built")
	var water_point := Vector3(generator_river_x(main),2.5,0)
	var water_at: Vector3i = main.vworld.to_voxel(water_point)
	print("WATER_DEBUG ",water_point," ",main.vworld.vol.get_voxel(water_at)," table=",main.vworld.water[132]," h=",main.generator.height_at(Vector2(water_point.x,water_point.z)))
	check(main.vworld.vol.get_voxel(water_at)>>2==33,"River contains water voxels")
	check(main.player.water_level_at(water_point)==3.0,"Generated river supports swimming and spatial audio")
	for bridge in main.generator.bridges.slice(0,5):
		var deck: Vector3i = main.vworld.to_voxel(Vector3(bridge.p.x,5.25,bridge.p.y))
		check(main.vworld.vol.get_voxel(deck)>>2==12,"River crossing has a solid wooden deck")
	check(main.wildlife.animals.size()==102,"All animal families populate generated world")
	check(main.player.global_position.distance_to(main.player.spawn_point)<2,"Safe village spawn")
	check(worlds.damage_multiplier()==0.0,"Peaceful difficulty disables incoming animal damage")
	check(FileAccess.file_exists(worlds.save_path()),"New world automatically saved separately")
	var generator = main.generator
	for cave in generator.caves:
		var center: Vector2 = cave.p+Vector2(0,9)
		var at: Vector3i = main.vworld.to_voxel(Vector3(center.x,float(cave.h)+1.5,center.y))
		check(main.vworld.vol.get_voxel(at)==0,"Cave chamber contains actual empty voxels")
		check(main.vworld.vol.get_voxel(at+Vector3i(0,10,0))!=0,"Cave has solid ceiling")
		var clear := true
		for z in range(-9,10):
			var passage: Vector3i = main.vworld.to_voxel(Vector3(cave.p.x,float(cave.h)+1.5,cave.p.y+z))
			if main.vworld.vol.get_voxel(passage)!=0: clear = false
		check(clear,"Open entrance connects to cave chamber")
	main.player.hp = 73
	main._save()
	main.player.hp = 20
	main._load()
	check(main.player.hp==73,"Generated world save restores health")
	var saves: Array = worlds.saved_worlds()
	check(not saves.is_empty() and saves[0].config.seed_text=="Gruenweiten-2026","World list preserves seed and map settings")
	var first = load("res://scripts/worlds/generator.gd").new()
	var second = load("res://scripts/worlds/generator.gd").new()
	first.plan(worlds.config)
	second.plan(worlds.config)
	check(first.sites==second.sites and first.roads==second.roads,"Same seed reproduces settlement and road layout")
	var different: Dictionary = worlds.config.duplicate()
	different.seed = int(different.seed)+1
	var other = load("res://scripts/worlds/generator.gd").new()
	other.plan(different)
	check(other.sites!=first.sites and other.height_at(Vector2(55,33))!=first.height_at(Vector2(55,33)),"Different seed changes terrain and destinations")
	if "--render-test" in OS.get_cmdline_user_args():
		root.get_node("Settings").update("fullscreen",false)
		root.size = Vector2i(1440,900)
		var camera := Camera3D.new()
		main.add_child(camera)
		var spawn: Vector3 = main.player.spawn_point
		camera.position = spawn+Vector3(45,55,60)
		camera.look_at(spawn+Vector3(12,0,0))
		camera.current = true
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/neue-welt.png"))
		main.panels.open_tab(4)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/neue-welt-karte.png"))
	var fingerprint: int = main.world_data.fingerprint
	var descriptor: Dictionary = worlds.config.duplicate(true)
	var tree_holder: Node = main.get_node("World").find_child("TreeColliders",true,false)
	var tree_collider: CollisionShape3D = tree_holder.get_child(0)
	var tree_meta: Dictionary = tree_collider.get_meta("tree")
	var edited_tree: Node = main.tools.get_prop("tree",tree_meta,tree_collider)
	check(edited_tree!=null and edited_tree.global_position.distance_to(Vector3(tree_meta.pos[0],tree_meta.pos[1],tree_meta.pos[2]))<.01,"Generated trees can become editable at their actual positions")
	var tree_key := "tree:%s:%d" % [tree_meta.chunk,tree_meta.index]
	var edit_point: Vector3i = main.vworld.to_voxel(main.player.spawn_point-Vector3(0,1.5,0))
	main.vworld.set_list(PackedInt32Array([edit_point.x,edit_point.y,edit_point.z,54<<2]))
	main._save()
	main.queue_free()
	await process_frame
	worlds.resume_world(descriptor)
	root.get_node("Settings").session_mode = "continue"
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	while not main.world_ready: await process_frame
	check(main.world_data.fingerprint==fingerprint,"Continue regenerates identical terrain from saved descriptor")
	check(main.player.hp==73,"Continue restores player progress after regeneration")
	check(main.vworld.vol.get_voxel(edit_point)>>2==54,"Voxel edits survive leaving and regenerating a world")
	check(main.tools.props.has(tree_key),"Edited generated trees restore from their own world save")
	main.queue_free()
	await process_frame
	worlds.new_world({"seed_text":"Berge ohne Wasser","size":2,"landscape":2,"forest":0,"villages":3,"rivers":false,"caves":false,"ruins":false,"difficulty":3})
	worlds.config.version = 1
	root.get_node("Settings").session_mode = "single"
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	while not main.world_ready: await process_frame
	check(main.player.world_bounds.size.x==316,"Largest map setting generates 320 m terrain")
	check(main.world_data.villages.size()==3 and main.world_data.houses.size()==18,"Three villages and their buildings generated")
	check(main.world_data.caves.is_empty() and main.generator.ruins.is_empty(),"Cave and ruin switches affect actual generation")
	check(main.world_data.river.is_empty() and main.world_data.bridges.is_empty(),"River switch removes water and crossings")
	check(worlds.damage_multiplier()==1.6,"Hard difficulty scales animal damage")
	check(main.world_data.descriptor.seed_text=="Berge ohne Wasser","Text seeds work in map variants")
	var save_a := "user://worlds/%s.dat" % descriptor.id
	check(FileAccess.file_exists(save_a) and worlds.save_path()!=save_a,"Multiple generated worlds keep independent saves")
	print("WORLD_TEST_FAILURES ",failures)
	quit(failures)

func generator_river_x(main: Node) -> float:
	return main.generator.river_x(0)
