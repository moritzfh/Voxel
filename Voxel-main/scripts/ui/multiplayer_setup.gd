extends Control
signal host_requested
const K := preload("res://scripts/ui/ui_kit.gd")
var address: LineEdit
var player_name: LineEdit
var status: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color("081911")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 850
	column.add_theme_constant_override("separation",20)
	center.add_child(column)
	column.add_child(K.label("Mit Freunden spielen",K.F_TITLE,44))
	column.add_child(K.label("Der Host bestimmt Seed und Weltregeln. Freunde erhalten die Welt automatisch.",K.F_BODY,23,K.CREAM_DIM))
	player_name = _edit(column,"Dein Name")
	player_name.text = Net.player_name
	player_name.max_length = 16
	_button(column,"Neue oder gespeicherte Welt hosten",func(): Net.player_name = player_name.text; host_requested.emit(); queue_free())
	column.add_child(K.label("Einem Freund beitreten",K.F_HEAD,31,K.GOLD))
	address = _edit(column,"Freundescode oder IP, z. B. K7P2QA / 192.168.0.23")
	address.text_submitted.connect(func(_value: String): join())
	_button(column,"Beitreten",join)
	status = K.label("",K.F_BODY,22,K.GOLD)
	status.custom_minimum_size.y = 60
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	Net.status_changed.connect(func(text: String): status.text = text)
	_button(column,"Zurück",func(): Net.leave(); queue_free())
	address.grab_focus()

func _edit(parent: Node,hint: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = hint
	field.custom_minimum_size.y = 58
	field.add_theme_font_override("font",K.F_BODY)
	field.add_theme_font_size_override("font_size",25)
	parent.add_child(field)
	return field

func _button(parent: Node,title: String,action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 62
	K.style(button,26)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	parent.add_child(button)

func join() -> void:
	var value := address.text.strip_edges()
	if value.contains(".") or value.contains(":"): Net.join(value,player_name.text)
	else: Net.join_code(value,player_name.text)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		Net.leave()
		queue_free()
