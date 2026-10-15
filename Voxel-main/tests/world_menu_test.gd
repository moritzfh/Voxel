extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures += 1
func frames(n := 4) -> void:
	for i in n: await process_frame
func capture(name: String) -> void:
	if not "--render-test" in OS.get_cmdline_user_args(): return
	await frames(15)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/"+name+".png"))
func creation() -> Control:
	for child in current_scene.get_children():
		if child.get_script()==load("res://scripts/ui/world_creation.gd"): return child
	return null
func wait_world() -> Node:
	while current_scene==null or current_scene.name=="MainMenu": await process_frame
	while not current_scene.world_ready: await process_frame
	return current_scene
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("graphics",1)
	root.size = Vector2i(1280,720)
	change_scene_to_file("res://scenes/menu.tscn")
	await frames()
	await capture("hauptmenue-welten")
	current_scene._single()
	await frames()
	var form := creation()
	check(form!=null,"Singleplayer opens world creation")
	check(form.fields.seed_text.text.is_empty(),"Seed is optional and initially blank")
	check(form.fields.difficulty.selected==2,"Normal difficulty is the default")
	await capture("welterstellung")
	form.fields.name.text = "Mein erstes Abenteuer"
	form.fields.seed_text.text = "Waldpfad"
	form.fields.size.select(0)
	form.fields.difficulty.select(1)
	form.create()
	var main := await wait_world()
	check(main.world_data.descriptor.seed_text=="Waldpfad","World creation button passes typed seed to generator")
	check(main.world_data.descriptor.difficulty==1,"Selected difficulty reaches actual game")
	var id: String = root.get_node("Worlds").config.id
	main.player.hp = 64
	main.hud._return_to_title()
	await frames(8)
	current_scene._single()
	await frames()
	form = creation()
	check(form.saved.get_child_count()>=1 and form.saved.get_child(0) is Button,"New world appears as a continue button")
	await capture("welten-spielstand")
	form.saved.get_child(0).pressed.emit()
	main = await wait_world()
	check(root.get_node("Worlds").config.id==id and main.player.hp==64,"Saved-world button rebuilds and restores the selected world")
	main.hud._return_to_title()
	await frames(8)
	current_scene._start("test")
	main = await wait_world()
	check(not main.world_data.get("procedural",false) and root.get_node("Worlds").config.is_empty(),"Testmap still opens the original world after generated gameplay")
	check(main.player.spawn_point==Vector3(0,2,0),"Testmap retains its original spawn")
	main.hud._return_to_title()
	await frames(8)
	current_scene._multiplayer()
	await frames()
	var lobby: Control
	for child in current_scene.get_children():
		if child.get_script()==load("res://scripts/ui/multiplayer_setup.gd"): lobby = child
	check(lobby!=null and lobby.address!=null,"Multiplayer offers direct joining from title")
	lobby.host_requested.emit()
	lobby.queue_free()
	await frames()
	form = creation()
	check(form.multiplayer_mode,"Host opens seed and world settings")
	form.fields.seed_text.text = "Gemeinschaftsspiel"
	form.fields.size.select(0)
	form.fields.villages.select(0)
	form.create()
	main = await wait_world()
	check(main.world_data.streamed and root.get_node("Worlds").config.seed_text=="Gemeinschaftsspiel","Host prepares its chosen unlimited world")
	check(main.hud.mp_panel.visible and paused,"Prepared host world opens code/LAN lobby")
	main.hud._return_to_title()
	await frames(8)
	print("WORLD_MENU_FAILURES ",failures)
	quit(failures)
