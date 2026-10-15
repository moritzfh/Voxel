extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("graphics",1)
	root.size = Vector2i(1440,900)
	root.get_node("Worlds").new_world({"seed_text":"Naturwelten-2026","size":1,"villages":1,"difficulty":0})
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene==null or not current_scene.world_ready: await process_frame
	var game := current_scene
	game.hud.visible = false
	game.player.set_physics_process(false)
	game.generator.stream_ready = false
	var camera := Camera3D.new()
	game.add_child(camera); camera.current = true
	var places := {}
	for x in range(-3,4):
		for z in range(-3,4):
			var f: Dictionary = game.generator.land.biomes.feature(Vector2i(x,z),288)
			if f.kind==1: places.forest = game.generator.land.biomes.world_center(f)
	for x in range(-2,3):
		for z in range(-2,3):
			var f: Dictionary = game.generator.land.biomes.feature(Vector2i(x,z),896)
			if f.kind==1: places.forest = game.generator.land.biomes.world_center(f)
			if f.kind==2: places.lake = game.generator.land.biomes.world_center(f)+Vector2(float(f.radius)*.6,0)
			if f.kind==5: places.alpine = game.generator.land.biomes.world_center(f)+Vector2(float(f.radius)*.4,0)
	# Select dry forest ground and a clear shore outside settlements.
	for kind in (["forest"] if "--only-forest" in OS.get_cmdline_user_args() else ["forest","lake","alpine"]):
		if not places.has(kind): continue
		var p: Vector2 = places[kind]
		var h: float = game.generator.land.height(p)
		game.player.position = Vector3(p.x,h+1,p.y)
		for key in game.generator.chunks.keys(): game.generator.unload_chunk(key)
		var center: Vector2i = game.generator.chunk_of(game.player.position)
		for dx in range(-4,5):
			for dz in range(-4,5):
				var key := center+Vector2i(dx,dz)
				if abs(dx)<=2 and abs(dz)<=2: game.generator.ensure_sync(key)
				else:
					var baker = load("res://scripts/worlds/chunk_baker.gd").new()
					baker.setup(game.generator.config,game.vworld.solid,game.vworld.water,game.vworld.hard)
					game.generator._install(baker.bake(key,false))
				await process_frame
		game.generator._last_safe = game.player.position
		game.generator._pump_horizon()
		while game.generator._horizon_thread!=null:
			game.generator._pump_horizon()
			await process_frame
		var target := Vector3(p.x,h+2,p.y)
		camera.position = target+Vector3(20,13,-24) if kind!="forest" else target+Vector3(18,35,-24)
		camera.look_at(target)
		for i in 15: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/natur-"+kind+".png"))
		print("BIOME_PREVIEW ",kind)
	print("BIOME_PREVIEW_DONE")
	quit()
