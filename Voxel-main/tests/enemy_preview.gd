extends SceneTree
func _initialize() -> void: run.call_deferred()
func capture(name: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/"+name+".png"))
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("graphics",1)
	root.size = Vector2i(1440,900)
	root.get_node("Worlds").new_world({"seed_text":"Monster-und-Dungeons","size":1,"villages":1,"difficulty":0})
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene==null or not current_scene.world_ready: await process_frame
	var game := current_scene
	game.hud.visible = false
	game.player.set_physics_process(false)
	var camera := Camera3D.new()
	game.add_child(camera); camera.current = true
	var places := {}
	for x in range(-3,4):
		for z in range(-3,4):
			for dungeon in game.generator.land.region(Vector2i(x,z)).dungeons: places[dungeon.species] = dungeon
	for species in ["cyclops","dragon","sandworm"]:
		var dungeon: Dictionary = places[species]
		var p := Vector3(dungeon.p.x,float(dungeon.h)+.2,dungeon.p.y)
		game.player.position = p+Vector3(0,0,-14)
		var key: Vector2i = game.generator.chunk_of(p)
		for dx in range(-2,3):
			for dz in range(-2,3): game.generator.ensure_sync(key+Vector2i(dx,dz))
		for enemy in game.wildlife.foes: enemy.set_physics_process(false)
		camera.position = p+Vector3(12,9,-17) if species!="cyclops" else p+Vector3(0,4,-16)
		camera.look_at(p+Vector3.UP*2)
		await capture("gegner-"+species)
	# Put the standard models on the cleared sand arena for a readable scale comparison.
	var p: Vector3 = game.player.position+Vector3(0,0,-4)
	for i in 3:
		var enemy: Node = game.wildlife.spawn_external(90000000000300+i,{"species":["goblin","witch","bandit"][i]},p+Vector3((i-1)*2.3,0,0))
		enemy.set_physics_process(false)
		enemy.rotation.y = 0
	camera.position = p+Vector3(7,4,-9)
	camera.look_at(p+Vector3.UP*.9)
	await capture("gegner-standard")
	print("ENEMY_PREVIEW_DONE")
	quit()
