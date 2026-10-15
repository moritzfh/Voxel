extends CanvasLayer
## In-game HUD modelled on the concept image: character panel, title + compass, minimap, quests, hotbar, key hints.

const PANEL := preload("res://scripts/ui/ornate_panel.gd")
const BAR := preload("res://scripts/ui/stat_bar.gd")
const COMPASS := preload("res://scripts/ui/compass.gd")
const MINIMAP := preload("res://scripts/ui/minimap.gd")

var f_title: Font = preload("res://assets/fonts/cinzel-latin-700-normal.woff2")
var f_head: Font = preload("res://assets/fonts/alegreya-latin-700-normal.woff2")
var f_body: Font = preload("res://assets/fonts/alegreya-latin-500-normal.woff2")
var f_sc: Font = preload("res://assets/fonts/alegreya-sc-latin-700-normal.woff2")

const CREAM := Color(0.96, 0.93, 0.84)
const CREAM_DIM := Color(0.86, 0.83, 0.74)
const GOLD := Color(0.80, 0.65, 0.37)

var player: Node
var cam_rig: Node
var root: Control
var hp_bar: Control
var mana_bar: Control
var st_bar: Control
var compass: Control
var minimap: Control
var clock_label: Label
var quest_rows := []
var slot_counts := {}
var slot_panels := []
var prompt: Label
var toast: Label
var toast_t := 0.0
var portrait_vp: SubViewport
var menu: Control
var level_label: Label
var xp_bar: Control
var crosshair: Control
var target_label: Label
var feed: VBoxContainer
var _feed_lines: Array = []
var game_minutes := 16 * 60 + 24.0
var _flash := {}
var build_controls: Array = []
var hint_box: Control
var _world_enabled := false
var combat_hint: Label
var combat_counts := {}
var _attack_icon: TextureRect

func set_world_features(enabled: bool) -> void:
	_world_enabled = enabled
	for control in build_controls:
		control.visible = enabled
	if _attack_icon:
		_attack_icon.texture = load("res://assets/ui/icon_pickaxe.png" if enabled else "res://assets/ui/icon_sword.png")
	if hint_box:
		root.remove_child(hint_box)
		hint_box.queue_free()
		_build_key_hints()
		_refresh_key_labels()

var options: CanvasLayer

signal save_requested
signal load_requested
signal quit_requested

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_char_panel()
	_build_save_button()
	_build_title_compass()
	_build_minimap()
	_build_quests()
	_build_hotbar()
	_build_key_hints()
	_build_prompt_toast()
	_build_aim()
	_build_feed()
	_build_chat()
	_build_menu()
	options = CanvasLayer.new()
	options.set_script(load("res://scripts/ui/options.gd"))
	add_child(options)
	options.closed.connect(func():
		if menu.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
	Settings.bindings_changed.connect(_refresh_key_labels)
	_refresh_key_labels()
	Net.chat_received.connect(add_chat)
	Game.notify.connect(add_feed)
	Game.xp_changed.connect(func():
		level_label.text = "Stufe %d" % Game.level
		xp_bar.queue_redraw())
	Game.leveled_up.connect(func(_l): Sfx.play("levelup", null, -4.0))
	Net.status_changed.connect(func(t):
		if mp_status:
			mp_status.text = t
		_refresh_mp())
	Net.roster_changed.connect(_refresh_mp)
	Net.lan_list_changed.connect(_refresh_mp)

# ---------------------------------------------------------------- helpers
func _label(text: String, font: Font, size: int, color := CREAM, shadow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _panel(parent: Control, rect: Rect2, ornaments := true) -> Control:
	var p := Control.new()
	p.set_script(PANEL)
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.ornaments = ornaments
	parent.add_child(p)
	return p

func _anchored(preset: int, rect: Rect2) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	c.set_anchors_preset(preset)
	match preset:
		Control.PRESET_TOP_LEFT:
			c.position = rect.position
		Control.PRESET_TOP_RIGHT:
			c.offset_left = -rect.position.x - rect.size.x
			c.offset_top = rect.position.y
		Control.PRESET_CENTER_TOP:
			c.offset_left = rect.position.x - rect.size.x * 0.5
			c.offset_top = rect.position.y
		Control.PRESET_CENTER_BOTTOM:
			c.offset_left = rect.position.x - rect.size.x * 0.5
			c.offset_top = -rect.position.y - rect.size.y
	c.size = rect.size
	return c

func _icon(path: String, rect: Rect2, parent: Control) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = rect.position
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

# ---------------------------------------------------------------- character panel
func _build_char_panel() -> void:
	var box := _anchored(Control.PRESET_TOP_LEFT, Rect2(28, 22, 414, 162))
	var p := _panel(box, Rect2(Vector2.ZERO, box.size))
	# portrait
	var pf := _panel(p, Rect2(9, 9, 130, 144), false)
	pf.bg_color = Color(0.18, 0.24, 0.22, 1)
	pf.bg_color_top = Color(0.30, 0.38, 0.34, 1)
	var svc := SubViewportContainer.new()
	svc.position = Vector2(4, 4)
	svc.size = Vector2(122, 136)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pf.add_child(svc)
	portrait_vp = SubViewport.new()
	portrait_vp.own_world_3d = true
	portrait_vp.transparent_bg = true
	portrait_vp.msaa_3d = Viewport.MSAA_4X
	portrait_vp.size = Vector2i(244, 272)
	svc.add_child(portrait_vp)
	_build_portrait_scene()
	# name + level
	var nm := _label("Abenteurer  ·  Krieger", f_head, 25)
	nm.position = Vector2(154, 12)
	p.add_child(nm)
	var lv := _label("Stufe 1", f_body, 19, CREAM_DIM)
	lv.position = Vector2(155, 42)
	p.add_child(lv)
	level_label = lv
	xp_bar = Control.new()
	xp_bar.position = Vector2(232, 52)
	xp_bar.size = Vector2(166, 8)
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar.draw.connect(func():
		var f := clampf(float(Game.xp) / float(Game.xp_needed(Game.level)), 0.0, 1.0)
		xp_bar.draw_rect(Rect2(Vector2.ZERO, xp_bar.size), Color(0.04, 0.07, 0.06, 0.9))
		xp_bar.draw_rect(Rect2(Vector2(1, 1), Vector2((xp_bar.size.x - 2) * f, xp_bar.size.y - 2)), Color(0.55, 0.85, 0.4))
		xp_bar.draw_rect(Rect2(Vector2.ZERO, xp_bar.size), Color(GOLD, 0.8), false, 1.0))
	p.add_child(xp_bar)
	var rows := [["res://assets/ui/icon_heart.png", Color(0.86, 0.13, 0.15)],
		["res://assets/ui/icon_mana.png", Color(0.12, 0.42, 0.92)],
		["res://assets/ui/icon_bolt.png", Color(0.92, 0.72, 0.12)]]
	var bars := []
	for i in 3:
		var y := 74.0 + i * 29.0
		_icon(rows[i][0], Rect2(152, y - 1, 26, 26), p)
		var b := Control.new()
		b.set_script(BAR)
		b.position = Vector2(186, y)
		b.size = Vector2(212, 23)
		b.fill_color = rows[i][1]
		b.font = f_body
		b.font_size = 17
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(b)
		bars.append(b)
	hp_bar = bars[0]
	mana_bar = bars[1]
	st_bar = bars[2]
	mana_bar.set_values(50, 50)

func _build_portrait_scene() -> void:
	var w := Node3D.new()
	portrait_vp.add_child(w)
	var model: Node3D = load("res://generated/char_hero.scn").instantiate()
	model.set_script(load("res://scripts/character_anim.gd"))
	model.name = "PortraitModel"
	w.add_child(model)
	model.rotation.y = deg_to_rad(18)
	var cam := Camera3D.new()
	cam.fov = 26.0
	cam.position = Vector3(0.0, 1.55, -2.35)
	cam.rotation_degrees = Vector3(-4, 180, 0)
	w.add_child(cam)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 150, 0)
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.92, 0.8)
	w.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -20, 0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.7, 0.8, 1.0)
	w.add_child(rim)
	set_meta("portrait_model", model)

# ---------------------------------------------------------------- save button
func _build_save_button() -> void:
	var box := _anchored(Control.PRESET_TOP_LEFT, Rect2(532, 11, 188, 40))
	var b := Button.new()
	b.size = box.size
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.1, 0.09, 0.88)
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.12, 0.18, 0.15, 0.95)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.add_theme_stylebox_override("focus", sb)
	box.add_child(b)
	_icon("res://assets/ui/icon_floppy.png", Rect2(12, 7, 26, 26), b)
	var l := _label("Spiel speichern", f_body, 19)
	l.position = Vector2(48, 6)
	b.add_child(l)
	b.pressed.connect(func(): save_requested.emit())

# ---------------------------------------------------------------- title + compass
func _build_title_compass() -> void:
	var box := _anchored(Control.PRESET_CENTER_TOP, Rect2(0, 12, 460, 100))
	var t := _label("GRÜNWEITEN", f_title, 33, CREAM)
	t.add_theme_constant_override("outline_size", 6)
	t.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.07, 0.75))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(460, 44)
	box.add_child(t)
	compass = Control.new()
	compass.set_script(COMPASS)
	compass.position = Vector2(36, 54)
	compass.size = Vector2(388, 44)
	compass.font = f_head
	compass.span = 290.0
	compass.center_frac = 0.34
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(compass)

# ---------------------------------------------------------------- minimap
func _build_minimap() -> void:
	var box := _anchored(Control.PRESET_TOP_RIGHT, Rect2(28, 24, 284, 262))
	var p := _panel(box, Rect2(Vector2.ZERO, box.size))
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(10, 10)
	clip.size = Vector2(264, 206)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(clip)
	minimap = Control.new()
	minimap.set_script(MINIMAP)
	minimap.size = clip.size
	minimap.map_tex = load("res://assets/ui/minimap.png")
	minimap.arrow_tex = load("res://assets/ui/icon_arrow.png")
	minimap.house_tex = load("res://assets/ui/icon_house.png")
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(minimap)
	# frame letters
	for d in [["N", Vector2(142, 2)], ["S", Vector2(142, 196)], ["W", Vector2(4, 104)], ["E", Vector2(270, 104)]]:
		var l := _label(d[0], f_head, 19)
		l.size = Vector2(20, 22)
		l.position = d[1] - Vector2(10, 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(l)
	# footer
	var nm := _label("Grünweiten", f_body, 19)
	nm.position = Vector2(14, 226)
	p.add_child(nm)
	_icon("res://assets/ui/icon_sun.png", Rect2(188, 225, 26, 26), p)
	clock_label = _label("16:24", f_body, 19)
	clock_label.position = Vector2(220, 226)
	p.add_child(clock_label)

# ---------------------------------------------------------------- quests
func _build_quests() -> void:
	var box := _anchored(Control.PRESET_TOP_RIGHT, Rect2(28, 314, 284, 230))
	var p := _panel(box, Rect2(Vector2.ZERO, box.size))
	_icon("res://assets/ui/icon_book.png", Rect2(18, 12, 30, 30), p)
	var t := _label("Aufträge", f_head, 23)
	t.position = Vector2(56, 12)
	p.add_child(t)
	var quests := [["", ""], ["", ""], ["", ""]]
	for i in quests.size():
		var y := 48.0 + i * 60.0
		var sep := Control.new()
		sep.position = Vector2(16, y)
		sep.size = Vector2(252, 6)
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sep.draw.connect(func():
			sep.draw_line(Vector2(6, 3), Vector2(246, 3), Color(GOLD, 0.7), 1.0)
			for x in [3.0, 249.0]:
				sep.draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 3, 3), Vector2(x, 6), Vector2(x - 3, 3)]), GOLD))
		p.add_child(sep)
		var ring := Control.new()
		ring.position = Vector2(18, y + 16)
		ring.size = Vector2(22, 22)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_meta("done", false)
		ring.draw.connect(func():
			ring.draw_arc(Vector2(11, 11), 8.5, 0, TAU, 32, GOLD, 2.0, true)
			if ring.get_meta("done"):
				ring.draw_polyline(PackedVector2Array([Vector2(6, 11), Vector2(10, 15), Vector2(17, 6)]), Color(0.55, 0.9, 0.45), 3.0, true))
		p.add_child(ring)
		var qt := _label(quests[i][0], f_head, 19)
		qt.position = Vector2(48, y + 8)
		p.add_child(qt)
		var qs := _label(quests[i][1], f_body, 16, CREAM_DIM)
		qs.position = Vector2(48, y + 31)
		p.add_child(qs)
		quest_rows.append({"ring": ring, "title": qt, "sub": qs})

## village quests (talk to the elder, find the crates); the adventure quests come from Game
var village_quests := [["Ein neuer Anfang", "Mit dem Dorfältesten sprechen.", false],
	["Verlorene Vorräte", "3 / 5 Kisten finden.", false]]

func set_quest(i: int, sub: String, done: bool) -> void:
	village_quests[i][1] = sub
	village_quests[i][2] = done
	refresh_quests()

## up to three rows: active adventure quests first, then open village quests, then finished ones
func refresh_quests() -> void:
	var rows := []
	for id in Game.active_quests():
		rows.append([Game.QUESTS[id]["title"], Game.quest_progress(id), false])
	for v in village_quests:
		if not v[2]:
			rows.append(v)
	for v in village_quests:
		if v[2]:
			rows.append(v)
	for i in quest_rows.size():
		var q: Dictionary = quest_rows[i]
		var r: Array = rows[i] if i < rows.size() else ["", "", false]
		q["title"].text = r[0]
		q["sub"].text = r[1]
		q["ring"].set_meta("done", r[2])
		q["ring"].visible = r[0] != ""
		q["ring"].queue_redraw()
		q["title"].add_theme_color_override("font_color", Color(0.72, 0.9, 0.6) if r[2] else CREAM)

# ---------------------------------------------------------------- hotbar + keys
func _build_hotbar() -> void:
	var slots := [["res://assets/ui/icon_sword.png", "1", ""], ["res://assets/ui/icon_potion.png", "2", "3"],
		["res://assets/ui/icon_spin.svg", "Q", ""], ["res://assets/ui/icon_glider.png", "F", ""],
		["res://assets/ui/icon_meat.png", "G", "3"], ["res://assets/ui/icon_hammer.png", "B", ""], ["res://assets/ui/icon_slam.svg", "R", ""]]
	var sw := 80.0
	var gap := 9.0
	var total := slots.size() * sw + (slots.size() - 1) * gap
	var box := _anchored(Control.PRESET_CENTER_BOTTOM, Rect2(0, 64, total, 112))
	for i in slots.size():
		var x := i * (sw + gap)
		var p := _panel(box, Rect2(x, 0, sw, 76))
		p.bg_color = Color(0.05, 0.09, 0.08, 0.9)
		p.bg_color_top = Color(0.09, 0.14, 0.12, 0.9)
		p.corner_size = 4.0
		slot_panels.append(p)
		if i == 5: build_controls.append(p)
		if slots[i][0] != "":
			var icon := _icon(slots[i][0], Rect2(10, 7, 60, 60), p)
			if i == 0: _attack_icon = icon
		if slots[i][2] != "":
			var c := _label(slots[i][2], f_head, 19)
			c.position = Vector2(58, 46)
			p.add_child(c)
			slot_counts[i] = c
		if i in [2,6]:
			var count := _label("",f_head,17)
			count.position = Vector2(40,48)
			p.add_child(count)
			combat_counts["spin" if i==2 else "slam"] = count
		if slots[i][1] != "":
			var k := _panel(box, Rect2(x + sw * 0.5 - 15, 82, 30, 26), false)
			if i == 5: build_controls.append(k)
			k.inner_inset = 0
			var kl := _label(slots[i][1], f_head, 17)
			kl.size = Vector2(30, 26)
			kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			kl.position = Vector2(0, -1)
			kl.set_meta("key_action", ["equip_sword", "use_potion", "skill_spin", "glide", "use_food", "build_toggle", "skill_slam"][i])
			k.add_child(kl)

func _build_key_hints() -> void:
	if combat_hint==null:
		combat_hint = _label("",f_head,17,CREAM)
		combat_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		combat_hint.position = Vector2(-700,-276)
		combat_hint.size = Vector2(1400,74)
		combat_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(combat_hint)
	var items := [["I", "Inventar"], ["J", "Journal"], ["T", "Talente"], ["M", "Karte"], ["B", "Bauen"], ["H", "Ego-Sicht"], ["Esc", "Menü"]]
	var box := _anchored(Control.PRESET_CENTER_BOTTOM, Rect2(0, 16, 640, 30))
	hint_box = box
	var x := 0.0
	for i in items.size():
		if i == 4 and not _world_enabled: continue
		var kw := 30.0 if items[i][0].length() == 1 else 46.0
		var k := _panel(box, Rect2(x, 0, kw, 28), false)
		k.inner_inset = 0
		var kl := _label(items[i][0], f_head, 17)
		kl.size = Vector2(kw, 28)
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		kl.position.y = -1
		kl.set_meta("key_action", ["inventory", "journal", "talents", "map", "build_toggle", "first_person", "menu"][i])
		k.add_child(kl)
		var l := _label(items[i][1], f_head, 18)
		l.position = Vector2(x + kw + 10, 1)
		box.add_child(l)
		x += kw + 10 + f_head.get_string_size(items[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 14
		if i < items.size() - 1:
			var dot := _label("•", f_head, 16, CREAM_DIM)
			dot.position = Vector2(x - 6, 2)
			box.add_child(dot)
			x += 12
	box.offset_left = -x * 0.5
	box.size.x = x

func _build_prompt_toast() -> void:
	prompt = _label("", f_head, 22)
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.offset_top = -324
	prompt.offset_bottom = -290
	root.add_child(prompt)
	toast = _label("", f_head, 26, Color(1.0, 0.92, 0.7))
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.offset_left = -400
	toast.offset_right = 400
	toast.offset_top = 150
	toast.offset_bottom = 190
	toast.add_theme_constant_override("outline_size", 6)
	toast.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.07, 0.8))
	root.add_child(toast)

func show_toast(text: String, seconds := 3.0) -> void:
	toast.text = text
	toast_t = seconds
	toast.modulate.a = 1.0

func set_prompt(text: String) -> void:
	prompt.text = text

func flash_slot(i: int) -> void:
	if i < slot_panels.size():
		_flash[i] = 0.25

# ---------------------------------------------------------------- pause menu
func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.visible = false
	root.add_child(menu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(dim)
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -190
	box.offset_top = -286
	box.size = Vector2(380, 572)
	menu.add_child(box)
	var p := _panel(box, Rect2(Vector2.ZERO, box.size))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var t := _label("Menü", f_title, 30)
	t.size = Vector2(380, 50)
	t.position = Vector2(0, 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(t)
	var entries := [["Weiter", "resume"], ["Mehrspieler", "mp"], ["Spiel speichern", "save"], ["Spielstand laden", "load"], ["Optionen", "options"], ["Hauptmenü", "title"], ["Verlassen", "quit"]]
	for i in entries.size():
		var b := Button.new()
		b.text = entries[i][0]
		b.position = Vector2(50, 84 + i * 58)
		b.size = Vector2(280, 46)
		b.add_theme_font_override("font", f_head)
		b.add_theme_font_size_override("font_size", 21)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.13, 0.11, 0.95)
		sb.border_color = GOLD
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		var sbh := sb.duplicate()
		sbh.bg_color = Color(0.16, 0.24, 0.19, 1.0)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sbh)
		b.add_theme_stylebox_override("pressed", sbh)
		b.add_theme_stylebox_override("focus", sbh)
		b.add_theme_color_override("font_color", CREAM)
		b.set_meta("action", entries[i][1])
		b.pressed.connect(_on_menu.bind(b))
		p.add_child(b)
	_build_mp_panel()

var gfx_level := 2
var fov_level := 0
const GFX_NAMES := ["Niedrig", "Mittel", "Hoch"]
const FOV_NAMES := ["Normal", "Weit", "Maximal"]
signal graphics_changed(level: int)
signal fov_changed(level: int)

func set_menu_labels() -> void:
	for b in menu.find_children("*", "Button", true, false):
		match b.get_meta("action", ""):
			"gfx":
				b.text = "Grafik: " + GFX_NAMES[gfx_level]
			"fov":
				b.text = "Sichtfeld: " + FOV_NAMES[fov_level]

func _on_menu(b: Button) -> void:
	match b.get_meta("action"):
		"resume":
			toggle_menu(false)
		"mp":
			_show_mp(true)
		"save":
			save_requested.emit()
		"load":
			load_requested.emit()
			toggle_menu(false)
		"gfx":
			gfx_level = (gfx_level + 2) % 3
			b.text = "Grafik: " + GFX_NAMES[gfx_level]
			graphics_changed.emit(gfx_level)
		"fov":
			fov_level = (fov_level + 1) % 3
			b.text = "Sichtfeld: " + FOV_NAMES[fov_level]
			fov_changed.emit(fov_level)
		"fullscreen":
			var w := get_window()
			Settings.update("fullscreen", not (w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN))
		"options":
			options.open()
		"title":
			_return_to_title()
		"quit":
			quit_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if get_parent().get("world_ready") == false: return
	if event.is_action_pressed("menu"):
		if mp_panel.visible:
			_show_mp(false)
		else:
			toggle_menu(not menu.visible)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and not menu.visible and \
			(event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER) and not event.alt_pressed:
		open_chat()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_F11 or (event.physical_keycode == KEY_ENTER and event.alt_pressed)):
		var w := get_window()
		Settings.update("fullscreen", not (w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN))
		get_viewport().set_input_as_handled()

func toggle_menu(show: bool) -> void:
	menu.visible = show
	if not show:
		_show_mp(false)
	get_tree().paused = show and not Net.active()
	if player:
		player.input_blocked = show or chat_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show else Input.MOUSE_MODE_CAPTURED
	if show:
		var first: Button = menu.get_child(1).get_child(0).get_child(1) as Button
		if first:
			first.grab_focus()

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if player:
		if player.combat and combat_hint:
			combat_hint.text = player.combat.status_text()
			combat_hint.visible = not player.input_blocked
			if _attack_icon: _attack_icon.modulate = Color.WHITE if player.combat.sword_equipped else Color(.5,.5,.5)
			for id in combat_counts:
				var cd: float = player.combat.cooldowns.get(id,0)
				combat_counts[id].text = "%.1f" % cd if cd>.05 else "%dM" % roundi(player.combat.SKILLS.cost(id,Game.talents))
		hp_bar.set_values(player.hp, player.hp_max)
		mana_bar.set_values(player.mana, player.mana_max)
		st_bar.set_values(player.stamina, player.stamina_max)
		if slot_counts.has(1):
			slot_counts[1].text = str(player.potions)
		if slot_counts.has(4):
			slot_counts[4].text = str(player.food)
		var pos := Vector2(player.global_position.x, player.global_position.z)
		var face := 0.0
		if player.model:
			face = -player.model.rotation.y
		minimap.update_player(pos, face)
	if cam_rig:
		compass.set_heading(cam_rig.heading_degrees())
	if get_tree().paused:
		return
	game_minutes += delta * 0.5
	var m := int(game_minutes) % (24 * 60)
	clock_label.text = "%02d:%02d" % [m / 60, m % 60]
	_chat_tick(delta)
	_feed_tick(delta)
	if toast_t > 0.0:
		toast_t -= delta
		toast.modulate.a = clamp(toast_t, 0.0, 1.0)
	for i in _flash.keys():
		_flash[i] -= delta
		var p: Control = slot_panels[i]
		p.modulate = Color(1.6, 1.4, 1.0) if _flash[i] > 0.0 else Color.WHITE
		if _flash[i] <= 0.0:
			_flash.erase(i)
	if has_meta("portrait_model"):
		var pm = get_meta("portrait_model")
		pm.update_pose(delta, 0.0, true, 0.0, false)

# ---------------------------------------------------------------- multiplayer menu
var mp_panel: Control
var mp_name: LineEdit
var mp_ip: LineEdit
var mp_status: Label
var mp_lan: VBoxContainer
var mp_players: Label
var mp_leave: Button
var mp_code: Label

func _mp_button(text: String, pos: Vector2, w: float, cb: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(w, 40)
	b.add_theme_font_override("font", f_head)
	b.add_theme_font_size_override("font_size", 19)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.13, 0.11, 0.95)
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.16, 0.24, 0.19, 1.0)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.add_theme_stylebox_override("focus", sbh)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_color_override("font_color", CREAM)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _mp_edit(pos: Vector2, w: float, placeholder: String, parent: Control) -> LineEdit:
	var e := LineEdit.new()
	e.position = pos
	e.size = Vector2(w, 40)
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", f_body)
	e.add_theme_font_size_override("font_size", 19)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.05, 0.95)
	sb.border_color = Color(GOLD, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	e.add_theme_color_override("font_color", CREAM)
	parent.add_child(e)
	return e

func _build_mp_panel() -> void:
	mp_panel = Control.new()
	mp_panel.set_anchors_preset(Control.PRESET_CENTER)
	mp_panel.offset_left = -270
	mp_panel.offset_top = -330
	mp_panel.size = Vector2(540, 660)
	mp_panel.visible = false
	menu.add_child(mp_panel)
	var p := _panel(mp_panel, Rect2(Vector2.ZERO, mp_panel.size))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var t := _label("Mehrspieler", f_title, 30)
	t.size = Vector2(540, 50)
	t.position = Vector2(0, 16)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(t)
	var l1 := _label("Dein Name", f_head, 18, CREAM_DIM)
	l1.position = Vector2(36, 70)
	p.add_child(l1)
	mp_name = _mp_edit(Vector2(36, 96), 468, "Name", p)
	mp_name.text = Net.player_name
	mp_name.max_length = 16
	_mp_button("Online hosten (Code für Freunde)", Vector2(36, 150), 468, func():
		if Net.host_online(mp_name.text):
			get_tree().paused = false
			_refresh_mp(), p)
	var l2 := _label("Beitreten: Code eingeben (oder IP im Heimnetz)", f_head, 18, CREAM_DIM)
	l2.position = Vector2(36, 206)
	p.add_child(l2)
	mp_ip = _mp_edit(Vector2(36, 232), 320, "z. B. K7P2QA", p)
	mp_ip.text_submitted.connect(func(_t): _join_from_field())
	_mp_button("Beitreten", Vector2(366, 232), 138, _join_from_field, p)
	mp_code = _label("", f_title, 34, Color(1.0, 0.86, 0.5))
	mp_code.position = Vector2(36, 284)
	mp_code.size = Vector2(468, 46)
	mp_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(mp_code)
	var l3 := _label("Spiele im Heimnetz", f_head, 18, CREAM_DIM)
	l3.position = Vector2(36, 336)
	p.add_child(l3)
	mp_lan = VBoxContainer.new()
	mp_lan.position = Vector2(36, 362)
	mp_lan.size = Vector2(468, 76)
	mp_lan.add_theme_constant_override("separation", 4)
	p.add_child(mp_lan)
	mp_players = _label("", f_body, 17, CREAM)
	mp_players.position = Vector2(36, 442)
	mp_players.size = Vector2(468, 50)
	mp_players.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(mp_players)
	mp_status = _label(Net.status, f_body, 16, Color(0.95, 0.85, 0.6))
	mp_status.position = Vector2(36, 494)
	mp_status.size = Vector2(468, 56)
	mp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(mp_status)
	_mp_button("Im Heimnetz hosten (ohne Code)", Vector2(36, 556), 468, func():
		if Net.host(mp_name.text):
			get_tree().paused = false
			_refresh_mp(), p).add_theme_font_size_override("font_size", 16)
	mp_leave = _mp_button("Trennen", Vector2(36, 604), 226, func():
		Net.leave()
		_refresh_mp(), p)
	_mp_button("Zurück", Vector2(278, 604), 226, func(): _show_mp(false), p)

func _join_from_field() -> void:
	var t := mp_ip.text.strip_edges()
	var ok := false
	if t.count(".") >= 1 or t.count(":") >= 1:
		ok = Net.join(t, mp_name.text)
	else:
		ok = Net.join_code(t, mp_name.text)
	if ok:
		get_tree().paused = false
	_refresh_mp()

func _show_mp(show: bool) -> void:
	if mp_panel == null:
		return
	mp_panel.visible = show
	menu.get_child(1).visible = not show
	if show:
		Net.start_lan_search()
		mp_status.text = Net.status
		_refresh_mp()
		mp_name.grab_focus()
	else:
		Net.stop_lan_search()

func _refresh_mp() -> void:
	if mp_panel == null:
		return
	for c in mp_lan.get_children():
		c.queue_free()
	var n := 0
	for ip in Net.lan_hosts:
		var h: Dictionary = Net.lan_hosts[ip]
		var b := _mp_button("%s  (%s, %d Spieler)" % [h["name"], ip, h["players"]], Vector2.ZERO, 448, func():
			mp_ip.text = ip
			_join_from_field(), mp_lan)
		b.custom_minimum_size = Vector2(448, 34)
		n += 1
		if n >= 2:
			break
	if n == 0:
		var l := _label("– keine gefunden –" if not Net.active() else "", f_body, 16, CREAM_DIM)
		mp_lan.add_child(l)
	if Net.active():
		var names := PackedStringArray()
		for id in Net.players:
			names.append(str(Net.players[id]["name"]) + (" (Host)" if id == 1 else ""))
		mp_players.text = "Im Spiel (%d/%d): %s" % [Net.players.size(), Net.MAX_PLAYERS, ", ".join(names)]
	else:
		mp_players.text = "Nicht verbunden. „Online hosten“ gibt dir einen Code, den deine Freunde hier eintippen."
	mp_leave.disabled = not Net.active() and Net.online_code == ""
	mp_code.text = ("Code: " + Net.online_code) if Net.online_code != "" and Net.is_host() else ""

# ---------------------------------------------------------------- chat
var chat_open := false
var chat_box: VBoxContainer
var chat_input: LineEdit
var _chat_lines: Array = []   # [{label, t}]

func _build_chat() -> void:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 28
	box.offset_top = -330
	box.size = Vector2(520, 300)
	chat_box = VBoxContainer.new()
	chat_box.alignment = BoxContainer.ALIGNMENT_END
	chat_box.size = Vector2(520, 250)
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_box.add_theme_constant_override("separation", 2)
	box.add_child(chat_box)
	chat_input = _mp_edit(Vector2(0, 258), 520, "Nachricht … (Enter senden, Esc abbrechen)", box)
	chat_input.visible = false
	chat_input.max_length = 160
	chat_input.text_submitted.connect(func(t):
		Net.send_chat(t)
		close_chat())
	chat_input.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
			close_chat()
			chat_input.accept_event())

func open_chat() -> void:
	chat_open = true
	chat_input.visible = true
	chat_input.text = ""
	chat_input.grab_focus()
	if player:
		player.input_blocked = true
	for l in _chat_lines:
		l["t"] = 0.0

func close_chat() -> void:
	chat_open = false
	chat_input.release_focus()
	chat_input.visible = false
	if player:
		player.input_blocked = menu.visible

func add_chat(from_name: String, text: String, color: Color) -> void:
	var l := Label.new()
	l.add_theme_font_override("font", f_body)
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if from_name == "":
		l.text = text
		l.add_theme_color_override("font_color", color)
	else:
		l.text = "%s: %s" % [from_name, text]
		l.add_theme_color_override("font_color", CREAM)
	chat_box.add_child(l)
	if from_name != "":
		# coloured name via a small prefix label tint
		l.add_theme_color_override("font_color", CREAM.lerp(color, 0.35))
	_chat_lines.append({"label": l, "t": 0.0})
	while _chat_lines.size() > 8:
		_chat_lines[0]["label"].queue_free()
		_chat_lines.pop_front()

func _chat_tick(delta: float) -> void:
	for l in _chat_lines:
		l["t"] += delta
		var a := 1.0 if chat_open else clampf(1.0 - (float(l["t"]) - 10.0) / 2.0, 0.0, 1.0)
		l["label"].modulate.a = a

# ---------------------------------------------------------------- aim + pickup feed
func _build_aim() -> void:
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.size = Vector2(24, 24)
	crosshair.position = -crosshair.size * 0.5
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.visible = false
	crosshair.draw.connect(func():
		var c := crosshair.size * 0.5
		crosshair.draw_circle(c, 3.5, Color(0, 0, 0, 0.55))
		crosshair.draw_circle(c, 2.2, Color(1, 1, 1, 0.95))
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			crosshair.draw_line(c + d * 6.0, c + d * 10.0, Color(1, 1, 1, 0.8), 2.0))
	root.add_child(crosshair)
	target_label = _label("", f_head, 18)
	target_label.set_anchors_preset(Control.PRESET_CENTER)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.offset_left = -260
	target_label.offset_right = 260
	target_label.offset_top = 18
	target_label.offset_bottom = 44
	root.add_child(target_label)

func set_target_info(text: String, color: Color, show_cross: bool) -> void:
	if crosshair.visible != show_cross:
		crosshair.visible = show_cross
	if target_label.text != text:
		target_label.text = text
	target_label.add_theme_color_override("font_color", color)

func _build_feed() -> void:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -312
	box.offset_top = 556
	box.size = Vector2(284, 220)
	feed = VBoxContainer.new()
	feed.size = Vector2(284, 220)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_theme_constant_override("separation", 0)
	box.add_child(feed)

func add_feed(text: String, color: Color) -> void:
	# merge repeated pickups of the same resource into one growing line
	if text.begins_with("+") and not _feed_lines.is_empty():
		var last: Dictionary = _feed_lines[-1]
		var parts := text.split(" ", false, 1)
		if last.get("res", "") == (parts[1] if parts.size() > 1 else "") and float(last["t"]) < 2.0:
			last["n"] = int(last["n"]) + int(parts[0].substr(1))
			last["label"].text = "+%d %s" % [last["n"], last["res"]]
			last["t"] = 0.0
			return
	var l := _label(text, f_head, 20, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(284, 26)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feed.add_child(l)
	var e := {"label": l, "t": 0.0}
	if text.begins_with("+"):
		var parts2 := text.split(" ", false, 1)
		e["res"] = parts2[1] if parts2.size() > 1 else ""
		e["n"] = int(parts2[0].substr(1))
	else:
		e["t"] = -2.0
	_feed_lines.append(e)
	while _feed_lines.size() > 7:
		_feed_lines[0]["label"].queue_free()
		_feed_lines.pop_front()

func _feed_tick(delta: float) -> void:
	var i := 0
	while i < _feed_lines.size():
		var e: Dictionary = _feed_lines[i]
		e["t"] = float(e["t"]) + delta
		var a := clampf(3.2 - float(e["t"]), 0.0, 1.0)
		e["label"].modulate.a = a
		if a <= 0.0:
			e["label"].queue_free()
			_feed_lines.remove_at(i)
			continue
		i += 1

func _refresh_key_labels() -> void:
	for label in root.find_children("*", "Label", true, false):
		if label.has_meta("key_action"):
			var action: String = label.get_meta("key_action")
			label.text = Settings.key_name(action)
			label.add_theme_font_size_override("font_size", 17 if label.text.length() <= 3 else 11)

func _return_to_title() -> void:
	# Keep a recoverable save before leaving a world through the menu.
	save_requested.emit()
	if Worlds.remote and Net.active(): await get_tree().create_timer(.2,true).timeout
	Net.leave()
	Net.stop_lan_search()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
