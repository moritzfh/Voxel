extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("graphics",1)
	root.size = Vector2i(1280,720)
	change_scene_to_file("res://scenes/main.tscn")
	var game: Node
	for i in 300:
		await process_frame
		game = current_scene
		if game != null and game.get("soundscape") != null: break
	game.hud.hide()
	game.player.set_physics_process(false)
	game.player.hurt_cooldown = 10000
	var camera := Camera3D.new()
	camera.fov = 62
	game.add_child(camera)
	camera.make_current()
	for i in 40:
		var focus: Vector3 = game.wildlife.flock_target(0,0)
		var direction: Vector3 = game.wildlife.flock_velocity(0,0).normalized()
		camera.global_position = focus-direction*26.0+Vector3.UP*6.0
		camera.look_at(focus-direction*4.0)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/vogelschwarm.png"))
	print("Saved live flock preview")
	quit()
