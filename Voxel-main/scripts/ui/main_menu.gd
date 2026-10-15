extends Control
const K := preload("res://scripts/ui/ui_kit.gd")
const OPTIONS := preload("res://scripts/ui/options.gd")
const CREATION := preload("res://scripts/ui/world_creation.gd")
var options: CanvasLayer
var content: VBoxContainer
var busy := false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_F11 or (event.physical_keycode == KEY_ENTER and event.alt_pressed)):
		Settings.update("fullscreen", not Settings.get_value("fullscreen"))
		get_viewport().set_input_as_handled()

func _ready() -> void:
	get_tree().auto_accept_quit = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Existing command-line testing and direct multiplayer launches still enter the world.
	if not Net.direct_launch_consumed and not OS.get_cmdline_user_args().is_empty() and not "--menu-test" in OS.get_cmdline_user_args():
		Net.direct_launch_consumed = true
		Worlds.test_map()
		var generated := {}
		var resume_generated := false
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--world-seed="): generated.seed_text = arg.trim_prefix("--world-seed=")
			elif arg.begins_with("--world-size="): generated.size = int(arg.trim_prefix("--world-size="))
			elif arg.begins_with("--world-difficulty="): generated.difficulty = int(arg.trim_prefix("--world-difficulty="))
			elif arg == "--world-continue": resume_generated = true
		if generated.has("seed_text"): Worlds.new_world(generated)
		if resume_generated and not Worlds.saved_worlds().is_empty(): Worlds.resume_world(Worlds.saved_worlds()[0].config)
		_start("continue" if Worlds.continuing else "direct")
		return
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists("res://assets/ui/menu_background.png"):
		background.texture = load("res://assets/ui/menu_background.png")
	else:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color("102d29"), Color("426c50"), Color("c6b773")])
		gradient.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill_from = Vector2(0, 1)
		texture.fill_to = Vector2(1, 0)
		background.texture = texture
	add_child(background)
	var shade := TextureRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0.015, 0.045, 0.035, 0.97), Color(0.015, 0.04, 0.03, 0.75), Color(0.015, 0.03, 0.025, 0.12)])
	fade.offsets = PackedFloat32Array([0.0, 0.43, 1.0])
	var overlay := GradientTexture2D.new()
	overlay.gradient = fade
	shade.texture = overlay
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_top", 110)
	margin.add_theme_constant_override("margin_bottom", 80)
	margin.add_theme_constant_override("margin_right", 80)
	add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	content.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(content)
	content.add_child(K.label("ENTDECKE. ERSCHAFFE. BLEIBE.", K.F_SC, 21, K.GOLD))
	content.add_child(K.label("Grünweiten", K.F_TITLE, 72))
	var sub := K.label("Dein Abenteuer beginnt mit einer eigenen Welt.", K.F_BODY, 24, K.CREAM_DIM)
	if not Net.menu_notice.is_empty():
		sub.text = Net.menu_notice
		sub.modulate = K.GOLD
		Net.menu_notice = ""
	content.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 48
	content.add_child(gap)
	_button("Einzelspieler", func(): _single())
	_button("Testmap", func(): _test_map())
	_button("Mehrspieler", _multiplayer)
	_button("Optionen", func(): options.open())
	_button("Verlassen", func(): get_tree().quit())
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(space)
	content.add_child(K.label("Eine Welt aus kleinen Würfeln. Platz für große Ideen.", K.F_BODY, 21, K.CREAM_DIM))
	content.add_child(K.label("GRÜNWEITEN  /  WINDOWS", K.F_SC, 16, K.GOLD))
	options = CanvasLayer.new()
	options.set_script(OPTIONS)
	add_child(options)
	options.closed.connect(func(): content.get_child(4).grab_focus())
	content.get_child(4).grab_focus()

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(440, 62)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	K.style(button, 27)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func(): Sfx.play("click", null, -6.0); callback.call())
	content.add_child(button)
	return button

func _single(multiplayer_mode := false) -> void:
	if busy or Net.joining():
		return
	var creation := Control.new()
	creation.set_script(CREATION)
	creation.multiplayer_mode = multiplayer_mode
	creation.start_requested.connect(func(): _start("host" if multiplayer_mode else "continue" if Worlds.continuing else "single"))
	creation.closed.connect(func(): content.get_child(4).grab_focus())
	add_child(creation)

func _multiplayer() -> void:
	if busy or Net.joining(): return
	var lobby := Control.new()
	lobby.set_script(load("res://scripts/ui/multiplayer_setup.gd"))
	lobby.host_requested.connect(func(): _single(true))
	add_child(lobby)

func _test_map() -> void:
	if busy or Net.joining(): return
	var saved := FileAccess.file_exists("user://spielstand.dat") or FileAccess.file_exists("user://savegame.json")
	Worlds.test_map(saved)
	_start("continue" if saved else "test")

func _start(mode: String) -> void:
	if busy or Net.joining():
		return
	if mode in ["test","multi"]: Worlds.test_map()
	busy = true
	Settings.session_mode = mode
	Net.leave()
	Game.reset()
	if content:
		for child in content.get_children():
			if child is Button:
				child.disabled = true
		content.add_child(K.label("Die Welt wird geladen …", K.F_HEAD, 24, K.GOLD))
	await get_tree().process_frame
	await get_tree().process_frame
	var error := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if error != OK:
		busy = false
		push_error("Welt konnte nicht geladen werden: %s" % error_string(error))
