extends SceneTree
func _initialize() -> void: run.call_deferred()
func capture(name: String) -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/"+name+".png"))
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("graphics",1)
	root.size = Vector2i(1600,1000)
	root.get_node("Worlds").new_world({"seed_text":"Dorfleben","size":0,"villages":1,"difficulty":0})
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene==null or not current_scene.world_ready: await process_frame
	var main := current_scene
	main.panels.open_tab(4)
	for i in 36: await process_frame
	main.panels.map_view.zoom(4.0)
	for i in 45: await process_frame
	await capture("weltkarte-zoom")
	main.panels.open_tab(2)
	await capture("kriegerbaum")
	main.panels.close()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_1
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	print(("PASS " if not main.combat.sword_equipped else "FAIL ")+"Native key 1 switches sword to fists")
	key = InputEventKey.new(); key.physical_keycode = KEY_1; key.pressed = false; Input.parse_input_event(key)
	await process_frame
	key = InputEventKey.new(); key.physical_keycode = KEY_1; key.pressed = true; Input.parse_input_event(key)
	await process_frame
	print(("PASS " if main.combat.sword_equipped else "FAIL ")+"Native key 1 draws sword again")
	key = InputEventKey.new(); key.physical_keycode = KEY_1; key.pressed = false; Input.parse_input_event(key)
	main.hud.visible = false
	main.player.set_physics_process(false)
	main.combat.set_physics_process(false)
	main.player.position += Vector3(0,0,-24)
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.position = main.player.position+Vector3(3.8,2.4,-4)
	camera.look_at(main.player.position+Vector3.UP)
	camera.current = true
	main.player._facing = 0
	main.player.model.rotation.y = 0
	main.player.anim.update_pose(.016,0,true,0,false)
	print("HERO_MODEL ",main.player.model.scale," ARM ",main.player.model.get_node("arm_r").position," WEAPON ",main.tools.tool_mesh.global_position)
	await capture("schwert-in-hand")
	main.player.anim.combat_pose("attack",1,.44)
	main.player.anim.update_pose(.2,0,true,0,false)
	await capture("schwert-hieb")
	main.player.anim.combat_pose("dodge",0,.52)
	main.player.anim.update_pose(.24,0,true,0,false)
	await capture("ausweichrolle")
	print("COMBAT_PREVIEW_DONE")
	quit()
