extends Control
signal start_requested
signal closed
const K := preload("res://scripts/ui/ui_kit.gd")
var fields := {}
var saved: VBoxContainer
var starting := false
var multiplayer_mode := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.015,0.035,0.025,1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right"]: margin.add_theme_constant_override("margin_"+edge,100)
	for edge in ["top","bottom"]: margin.add_theme_constant_override("margin_"+edge,45)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",65)
	margin.add_child(row)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",15)
	row.add_child(column)
	column.add_child(K.label("Gemeinsame Welt hosten" if multiplayer_mode else "Deine eigene Welt",K.F_TITLE,42))
	column.add_child(K.label("Gleicher Seed + gleiche Einstellungen = gleiche Landschaft.",K.F_BODY,23,K.CREAM_DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",28)
	grid.add_theme_constant_override("v_separation",13)
	scroll.add_child(grid)
	_line(grid,"name","Weltname","Meine Grünweiten","")
	_line(grid,"seed_text","Seed (optional)","","Leer lassen für eine zufällige Welt")
	_choice(grid,"size","Dorfabstände",["Nah · 192-m-Regionen","Ausgewogen · 256-m-Regionen","Weit · 320-m-Regionen"],1)
	_choice(grid,"forest","Waldanteil",["Licht","Ausgewogen","Dicht"],1)
	_choice(grid,"villages","Dörfer",["Ein Dorf","Zwei Dörfer","Drei Dörfer"],1)
	_choice(grid,"difficulty","Schwierigkeit",["Friedlich","Leicht","Normal","Schwer"],2)
	_toggle(grid,"rivers","Flüsse & Brücken")
	_toggle(grid,"caves","Begehbare Höhlen")
	_toggle(grid,"ruins","Ruinen & Entdeckungen")
	var info := K.label("Alle Biome: Wiesen, Wälder, Seen und große Gebirge.\nUnbegrenzte Welt · feine Voxel · erkundete Abschnitte bleiben gespeichert.\nDörfer mit Türen, Höfen und Bewohnern. Friedlich: kein Tierschaden.",K.F_BODY,21,K.CREAM_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(info)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation",16)
	column.add_child(buttons)
	_action(buttons,"Zurück",func(): closed.emit(); queue_free())
	_action(buttons,"Welt vorbereiten" if multiplayer_mode else "Welt erstellen",create,true)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 440
	right.add_theme_constant_override("separation",16)
	row.add_child(right)
	right.add_child(K.label("Deine Spielstände",K.F_HEAD,32,K.GOLD))
	var saves_scroll := ScrollContainer.new()
	saves_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(saves_scroll)
	saved = VBoxContainer.new()
	saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saved.add_theme_constant_override("separation",14)
	saves_scroll.add_child(saved)
	var worlds: Array = Worlds.saved_worlds()
	if worlds.is_empty():
		var empty := K.label("Hier erscheinen deine neuen Welten.\nJede Welt hat einen eigenen Spielstand.\n\nDie bisherige Welt findest du unter\n„Testmap“ im Hauptmenü.",K.F_BODY,23,K.CREAM_DIM)
		saved.add_child(empty)
	for entry: Dictionary in worlds:
		var config: Dictionary = entry.config
		var button := _action(saved,("Frühere Karte · " if int(config.get("version",1))==1 else "")+str(config.name)+"\nSeed: "+str(config.seed_text),func(): resume(config))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "Fortsetzen · zuletzt gespielt: "+str(entry.played)
	fields.name.grab_focus()

func _action(parent: Node, text: String, action: Callable, selected := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(205,64)
	K.style(button,24,selected)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _line(grid: GridContainer,key: String,title: String,value: String,hint: String) -> void:
	grid.add_child(K.label(title,K.F_HEAD,25))
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = hint
	edit.max_length = 64 if key == "seed_text" else 40
	edit.custom_minimum_size = Vector2(440,48)
	edit.add_theme_font_override("font",K.F_BODY)
	edit.add_theme_font_size_override("font_size",23)
	grid.add_child(edit)
	fields[key] = edit

func _choice(grid: GridContainer,key: String,title: String,choices: Array,index: int) -> void:
	grid.add_child(K.label(title,K.F_HEAD,25))
	var select := OptionButton.new()
	K.style(select,23)
	select.custom_minimum_size = Vector2(440,48)
	select.focus_mode = Control.FOCUS_ALL
	for choice in choices: select.add_item(choice)
	select.select(index)
	grid.add_child(select)
	fields[key] = select

func _toggle(grid: GridContainer,key: String,title: String) -> void:
	grid.add_child(K.label(title,K.F_HEAD,25))
	var check := CheckButton.new()
	check.text = "Aktiviert"
	check.button_pressed = true
	check.custom_minimum_size.y = 46
	check.add_theme_font_override("font",K.F_BODY)
	check.add_theme_font_size_override("font_size",23)
	check.toggled.connect(func(on: bool): check.text = "Aktiviert" if on else "Ausgeschaltet")
	grid.add_child(check)
	fields[key] = check

func create() -> void:
	if starting: return
	starting = true
	var options := {}
	for key in fields:
		var control: Control = fields[key]
		if control is LineEdit: options[key] = control.text
		elif control is OptionButton: options[key] = control.selected+(1 if key == "villages" else 0)
		else: options[key] = control.button_pressed
	Worlds.new_world(options)
	start_requested.emit()

func resume(config: Dictionary) -> void:
	if starting: return
	starting = true
	Worlds.resume_world(config)
	start_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()
