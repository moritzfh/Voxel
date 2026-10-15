extends CanvasLayer
signal closed
const K := preload("res://scripts/ui/ui_kit.gd")
const TABS := ["Sound", "Grafik", "Shader", "Steuerung", "Spiel"]
var root: Control
var body: VBoxContainer
var status: Label
var selected := 0
var pending := ""
var pending_button: Button
var tabs: Array[Button] = []
var scroll: ScrollContainer

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var theme := Theme.new()
	theme.default_font = K.F_BODY
	theme.default_font_size = 21
	root.theme = theme
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.03, 0.025, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(1080, 840)
	box.add_theme_stylebox_override("panel", K._sb(Color("101d18"), K.GOLD, 2))
	center.add_child(box)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 32)
	box.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)
	content.add_child(K.label("Optionen", K.F_TITLE, 36))
	content.add_child(K.label("Deine Einstellungen werden automatisch gespeichert.", K.F_BODY, 20, K.CREAM_DIM))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	content.add_child(bar)
	for i in TABS.size():
		var button := Button.new()
		button.text = TABS[i]
		button.custom_minimum_size = Vector2(184, 48)
		K.style(button, 23)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(func(): show_tab(i))
		bar.add_child(button)
		tabs.append(button)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 490
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	status = K.label("", K.F_BODY, 19, K.GOLD)
	status.custom_minimum_size.y = 48
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status)
	var footer := HBoxContainer.new()
	content.add_child(footer)
	var back := Button.new()
	back.text = "Zurück"
	back.custom_minimum_size = Vector2(220, 48)
	K.style(back, 23)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(close)
	footer.add_child(back)
	show_tab(0)
	hide()

func open() -> void:
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_tab(selected)
	tabs[selected].grab_focus()

func close() -> void:
	pending = ""
	hide()
	closed.emit()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if pending != "" and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			pending_button.text = Settings.key_name(pending)
			pending = ""
			status.text = "Tastenbelegung abgebrochen."
		else:
			var message: String = Settings.bind_key(pending, event.physical_keycode)
			if message == "":
				pending_button.text = Settings.key_name(pending)
				pending = ""
				status.text = "Tastenbelegung gespeichert."
			else:
				status.text = message
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu"):
		close()
		get_viewport().set_input_as_handled()

func show_tab(index: int) -> void:
	pending = ""
	selected = index
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical = 0
	status.text = ""
	for i in tabs.size():
		K.style(tabs[i], 23, i == selected)
		tabs[i].focus_mode = Control.FOCUS_ALL
	match selected:
		0:
			_slider("Gesamtlautstärke", "master", 0, 100, 1, "%")
			_slider("Effekte & Menü", "effects", 0, 100, 1, "%")
			_slider("Umgebungsgeräusche", "ambience", 0, 100, 1, "%")
			_slider("Tiergeräusche", "wildlife", 0, 100, 1, "%")
			_note("Effekte: Werkzeuge, Schritte und Kämpfe. Umgebung: Wasser, Wasserfälle und Wind. Tiergeräusche: Rufe und Summen in deiner Nähe.")
		1:
			_choice("Grafikqualität", "graphics", ["Niedrig", "Mittel", "Hoch"])
			_choice("Sichtfeld", "fov", ["Normal", "Weit", "Maximal"])
			_choice("Kantenglättung", "aa", ["Aus", "2× MSAA", "4× MSAA", "8× MSAA"])
			_toggle("Vollbild", "fullscreen")
			_toggle("V-Sync", "vsync")
			_toggle("Schatten", "shadows")
			_note("Niedrig / Mittel verringert Renderauflösung und Sichtweite. Änderungen gelten sofort im Spiel.")
		2:
			_toggle("Schwarze Ränder zwischen den Voxeln", "borders")
			_slider("Stärke der Voxel-Ränder", "border_strength", 0.05, 1.0, 0.05, "")
			_toggle("Leuchteffekte (Bloom)", "glow")
			_toggle("Umgebungsverdeckung (SSAO)", "ssao")
			_toggle("Indirektes Licht (SDFGI)", "gi")
			_toggle("Pflanzen im Wind", "wind")
			_slider("Farbsättigung", "saturation", 0.5, 1.8, 0.02, "")
			_note("SSAO ist ab Grafikqualität Mittel aktiv, SDFGI bei Hoch. Der Ränder-Schalter gilt für Gelände, Bauten und Pflanzen.")
		3:
			_slider("Mausempfindlichkeit", "sensitivity", 0.25, 3.0, 0.05, "×")
			_toggle("Maus-Y-Achse umkehren", "invert_y")
			_note("Klicke auf eine Taste und drücke die neue Taste. Esc bricht ab. Controller und Maustasten bleiben erhalten.")
			for action in Settings.LABELS:
				var row := _row(Settings.LABELS[action])
				var button := Button.new()
				button.text = Settings.key_name(action)
				button.custom_minimum_size = Vector2(300, 42)
				K.style(button, 21)
				button.focus_mode = Control.FOCUS_ALL
				button.pressed.connect(func():
					if pending != "":
						pending_button.text = Settings.key_name(pending)
					pending = action
					pending_button = button
					button.text = "Taste drücken …"
					status.text = "Neue Taste für %s drücken. Esc: abbrechen." % Settings.LABELS[action])
				row.add_child(button)
			_note("Bauen: 1–0 Formen · Maus links/rechts Bauen/Ausschneiden · Rad Höhe · Shift+Rad Wandstärke · Strg+Z/Y Rückgängig/Wiederholen. Esc Menü · Enter Chat · F11 Vollbild · F3 FPS.")
			var reset := Button.new()
			reset.text = "Standardbelegung wiederherstellen"
			reset.custom_minimum_size.y = 46
			K.style(reset, 21)
			reset.focus_mode = Control.FOCUS_ALL
			reset.pressed.connect(func(): Settings.reset_controls(); show_tab(3))
			body.add_child(reset)
		4:
			_toggle("Abbauen, Holzfällen & Bauen", "world_features")
			_note("Aus: Gelände und Bäume bleiben erhalten. Baumodus, Baukasten und zugehörige Aufträge werden ausgeblendet. Tierkämpfe und Erkundung bleiben verfügbar.")
			_note("Du kannst die Funktionen jederzeit wieder einschalten. Dein bisheriger Bau- und Questfortschritt bleibt gespeichert. Im Mehrspieler entscheidet der Host.")

func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 48
	body.add_child(row)
	var label := K.label(text, K.F_HEAD, 22)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row

func _toggle(text: String, key: String) -> void:
	var row := _row(text)
	var button := CheckButton.new()
	button.custom_minimum_size.x = 300
	button.button_pressed = bool(Settings.get_value(key))
	button.text = "An" if button.button_pressed else "Aus"
	if key == "world_features" and Net.active() and not Net.is_host():
		var game: Node = get_tree().current_scene
		if game.has_method("world_features_enabled"):
			button.button_pressed = game.world_features_enabled()
			button.text = "An (Host)" if button.button_pressed else "Aus (Host)"
		button.disabled = true
	button.toggled.connect(func(on: bool):
		button.text = "An" if on else "Aus"
		Settings.update(key, on))
	row.add_child(button)

func _choice(text: String, key: String, items: Array) -> void:
	var row := _row(text)
	var select := OptionButton.new()
	select.custom_minimum_size = Vector2(300, 44)
	K.style(select, 21)
	select.focus_mode = Control.FOCUS_ALL
	for item in items:
		select.add_item(item)
	select.select(clampi(int(Settings.get_value(key)), 0, items.size() - 1))
	select.item_selected.connect(func(index: int): Settings.update(key, index))
	row.add_child(select)

func _slider(text: String, key: String, lo: float, hi: float, step: float, suffix: String) -> void:
	var row := _row(text)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 220
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = float(Settings.get_value(key))
	row.add_child(slider)
	var label := K.label("", K.F_BODY, 20)
	label.custom_minimum_size.x = 80
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.text = ("%d" % slider.value if step >= 1.0 else "%.2f" % slider.value) + suffix
	row.add_child(label)
	slider.value_changed.connect(func(value: float):
		label.text = ("%d" % value if step >= 1.0 else "%.2f" % value) + suffix
		Settings.update(key, value))
	if key == "effects":
		slider.drag_ended.connect(func(_changed: bool): Sfx.play("click"))

func _note(text: String) -> void:
	var label := K.label(text, K.F_BODY, 19, K.CREAM_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 54
	body.add_child(label)
