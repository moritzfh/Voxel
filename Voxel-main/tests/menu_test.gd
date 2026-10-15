extends SceneTree
var failures := 0
var renders := false
var settings: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1

func frames(count := 3) -> void:
	for i in count:
		await process_frame

func capture(name: String) -> void:
	if not renders:
		return
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/" + name + ".png"))

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func _run() -> void:
	settings = root.get_node("Settings")
	renders = "--render-test" in OS.get_cmdline_user_args()
	settings.update("fullscreen", false)
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/menu.tscn")
	await frames()
	var title: Control = current_scene
	check(title.name == "MainMenu", "Startup opens main menu")
	var names: Array[String] = []
	for child in title.content.get_children():
		if child is Button:
			names.append(child.text)
	check(names == ["Einzelspieler", "Testmap", "Mehrspieler", "Optionen", "Verlassen"], "Main menu includes separate Testmap")
	await capture("hauptmenue")
	if "--menu-preview" in OS.get_cmdline_user_args():
		title.options.open()
		title.options.show_tab(2)
		await capture("optionen-shader")
		quit()
		return
	var options: CanvasLayer = title.options
	options.open()
	await frames()
	check(options.visible, "Options open from title")
	check(options.tabs.size() == 5, "Sound, graphics, shaders, controls and gameplay tabs")
	# Exercise the actual audio slider and check the real bus, then restore it.
	var master_slider: HSlider = options.body.get_child(0).get_child(1)
	master_slider.value = 0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master slider mutes audio")
	master_slider.value = 72
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master slider unmutes audio")
	var cfg := ConfigFile.new()
	cfg.load(settings.PATH)
	check(float(cfg.get_value("options", "master")) == 72.0, "Sound setting saved to disk")
	settings.update("master", 100.0)
	for pair in [["effects", "Effects"], ["ambience", "Ambience"]]:
		var previous: float = settings.get_value(pair[0])
		settings.update(pair[0], 0.0)
		check(AudioServer.is_bus_mute(AudioServer.get_bus_index(pair[1])), "%s sound bus mutes independently" % pair[1])
		settings.update(pair[0], previous)
	await capture("optionen-sound")
	for i in [1, 2, 3]:
		options.show_tab(i)
		await frames()
		check(options.body.get_child_count() > 5, "Options tab %d populated" % i)
		await capture("optionen-" + ["sound", "grafik", "shader", "steuerung"][i])
	# Press a binding button, then feed its input event through the engine.
	var binding: Button = options.body.get_child(3).get_child(1)
	binding.pressed.emit()
	await key(KEY_N)
	check(settings.keycode("move_forward") == KEY_N, "Rebinding through options captures new key")
	check(settings.bind_key("move_forward", KEY_ESCAPE) != "", "Escape remains available to close menus")
	check(settings.bind_key("move_forward", KEY_S) != "", "Conflicting key is rejected")
	check(settings.bind_key("inventory", KEY_L) == "", "Inventory action can be rebound")
	check(settings.bind_key("build_toggle", KEY_C) != "", "Combat ability keys cannot collide with build-mode toggle")
	check(settings.bind_key("build_toggle", KEY_COMMA) == "", "Build mode action can be rebound")
	check(settings.bind_key("first_person", KEY_O) == "", "Camera action can be rebound")
	options.close()
	check(not options.visible, "Options close to title")
	title._single()
	await frames()
	var creation: Control
	for child in title.get_children():
		if child.get_script() == load("res://scripts/ui/world_creation.gd"): creation = child
	check(creation != null and creation.fields.size()==9, "Single-player offers seed, map and difficulty settings")
	await capture("welterstellung")
	creation.queue_free()
	root.get_node("Worlds").test_map()
	title._start("test")
	await frames(6)
	var main: Node = current_scene
	for i in 240:
		if main.get("vworld") != null and main.get("panels") != null:
			break
		await process_frame
	check(main.name != "MainMenu" and main.get("vworld") != null, "Testmap loads existing gameplay")
	await frames(6)
	settings.update("world_features",true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await key(KEY_L)
	check(main.panels.visible, "Rebound inventory key opens inventory in game")
	main.panels.close()
	await key(KEY_COMMA)
	if renders:
		check(main.builder.active, "Rebound build-mode key works in game")
	main.builder.set_active(false)
	await key(KEY_O)
	if renders:
		check(main.cam_rig.first_person, "Rebound camera key switches perspective")
	main.cam_rig.set_first_person(false)
	for level in [0, 1, 2]:
		settings.update("graphics", level)
		check(main.gfx_level == level, "Graphics preset %d applied" % level)
	settings.update("gi", false)
	check(not main.env.environment.sdfgi_enabled, "GI shader switch affects scene")
	settings.update("gi", true)
	settings.update("glow", false)
	check(not main.env.environment.glow_enabled, "Bloom shader switch affects scene")
	settings.update("glow", true)
	settings.update("shadows", false)
	check(not main.sun.shadow_enabled, "Shadow switch affects sun")
	settings.update("shadows", true)
	settings.update("borders", false)
	if renders:
		await capture("welt-ohne-raender")
	settings.update("borders", true)
	if renders:
		await capture("welt-mit-raendern")
	main.hud.toggle_menu(true)
	check(paused and main.player.input_blocked, "Pause menu blocks gameplay")
	main.hud.options.open()
	await key(KEY_ESCAPE)
	check(not main.hud.options.visible and main.hud.menu.visible and paused, "Escape returns from options to paused game")
	main.hud._return_to_title()
	await frames(8)
	check(current_scene.name == "MainMenu" and not paused, "Return to main menu unpauses scene tree")
	check(FileAccess.file_exists("user://spielstand.dat"), "Return to menu saves world")
	title = current_scene
	title._test_map()
	await frames(14)
	check(current_scene.get("vworld") != null and root.get_node("Worlds").continuing, "Testmap directly continues the existing saved world")
	current_scene.hud._return_to_title()
	await frames(8)
	title = current_scene
	title._start("multi")
	await frames(16)
	check(current_scene.hud.mp_panel.visible and current_scene.hud.menu.visible, "Multiplayer entry opens existing lobby")
	check(current_scene.player.input_blocked, "Lobby blocks local player input")
	current_scene.hud._show_mp(false)
	check(not current_scene.hud.mp_panel.visible, "Lobby Back returns to pause menu")
	current_scene.hud.toggle_menu(false)
	check(not paused, "Resume from multiplayer setup works offline")
	settings.update("world_features",false)
	settings.reset_controls()
	check(InputMap.action_get_events("move_forward").size() == 3, "Reset restores W, arrow key and controller axis")
	settings.update("fullscreen", false)
	print("MENU TEST RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
