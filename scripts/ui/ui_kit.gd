extends RefCounted
## Shared look of the game's panels (dark green glass, double gold frame, Alegreya / Cinzel fonts).

const PANEL := preload("res://scripts/ui/ornate_panel.gd")
const CREAM := Color(0.96, 0.93, 0.84)
const CREAM_DIM := Color(0.80, 0.77, 0.68)
const GOLD := Color(0.80, 0.65, 0.37)
const GREEN := Color(0.62, 0.92, 0.5)
const RED := Color(1.0, 0.5, 0.42)
const F_TITLE := preload("res://assets/fonts/cinzel-latin-700-normal.woff2")
const F_HEAD := preload("res://assets/fonts/alegreya-latin-700-normal.woff2")
const F_BODY := preload("res://assets/fonts/alegreya-latin-500-normal.woff2")
const F_SC := preload("res://assets/fonts/alegreya-sc-latin-700-normal.woff2")

static func label(text: String, font: Font, size: int, color := CREAM, shadow := true) -> Label:
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

static func put(parent: Control, c: Control, pos: Vector2, size := Vector2.ZERO) -> Control:
	c.position = pos
	if size != Vector2.ZERO:
		c.size = size
	parent.add_child(c)
	return c

static func panel(parent: Control, rect: Rect2, ornaments := true) -> Control:
	var p := Control.new()
	p.set_script(PANEL)
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.ornaments = ornaments
	parent.add_child(p)
	return p

static func _sb(bg: Color, border: Color, bw := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	return sb

static func style(b: Button, size := 19, selected := false) -> void:
	b.add_theme_font_override("font", F_HEAD)
	b.add_theme_font_size_override("font_size", size)
	var base := Color(0.08, 0.13, 0.11, 0.95)
	var sel := Color(0.24, 0.30, 0.17, 1.0)
	var n := _sb(sel if selected else base, Color(1.0, 0.85, 0.5) if selected else Color(GOLD, 0.85))
	var h := _sb(Color(0.16, 0.24, 0.19, 1.0), Color(1.0, 0.85, 0.5))
	var d := _sb(Color(0.05, 0.07, 0.06, 0.8), Color(GOLD, 0.3))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.8))
	b.add_theme_color_override("font_disabled_color", Color(CREAM_DIM, 0.45))
	b.focus_mode = Control.FOCUS_NONE

static func button(parent: Control, text: String, rect: Rect2, cb: Callable, size := 19, selected := false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	style(b, size, selected)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

## checkbox drawn by hand (the fonts have no check glyphs)
static func check(parent: Control, text: String, pos: Vector2, on: bool, cb: Callable, w := 300.0) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.position = pos
	b.size = Vector2(w, 34)
	b.add_theme_font_override("font", F_BODY)
	b.add_theme_font_size_override("font_size", 19)
	var e := StyleBoxEmpty.new()
	e.content_margin_left = 36
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, e)
	b.add_theme_color_override("font_color", CREAM_DIM)
	b.add_theme_color_override("font_pressed_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.8))
	b.add_theme_color_override("font_hover_pressed_color", Color(1, 0.95, 0.8))
	b.focus_mode = Control.FOCUS_NONE
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(4, 6)
	box.size = Vector2(22, 22)
	box.draw.connect(func():
		box.draw_rect(Rect2(Vector2.ZERO, box.size), Color(0.03, 0.06, 0.05, 0.95))
		box.draw_rect(Rect2(Vector2.ZERO, box.size), GOLD, false, 2.0)
		if b.button_pressed:
			box.draw_polyline(PackedVector2Array([Vector2(5, 11), Vector2(9, 16), Vector2(17, 5)]), GREEN, 3.0, true))
	b.add_child(box)
	b.toggled.connect(func(v: bool):
		box.queue_redraw()
		cb.call(v))
	parent.add_child(b)
	return b

static func line_edit(parent: Control, rect: Rect2, text := "", placeholder := "") -> LineEdit:
	var e := LineEdit.new()
	e.position = rect.position
	e.size = rect.size
	e.text = text
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", F_BODY)
	e.add_theme_font_size_override("font_size", 18)
	var sb := _sb(Color(0.03, 0.06, 0.05, 0.95), Color(GOLD, 0.6), 1)
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	e.add_theme_color_override("font_color", CREAM)
	parent.add_child(e)
	return e

static func separator(parent: Control, pos: Vector2, w: float) -> Control:
	var sep := Control.new()
	sep.position = pos
	sep.size = Vector2(w, 6)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.draw.connect(func():
		sep.draw_line(Vector2(6, 3), Vector2(w - 6, 3), Color(GOLD, 0.6), 1.0)
		for x in [3.0, w - 3.0]:
			sep.draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 3, 3), Vector2(x, 6), Vector2(x - 3, 3)]), GOLD))
	parent.add_child(sep)
	return sep

static func key_cap(parent: Control, key: String, pos: Vector2, size := 16) -> Control:
	var w := 26.0 if key.length() <= 1 else 12.0 + F_HEAD.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var k := Control.new()
	k.set_script(PANEL)
	k.ornaments = false
	k.inner_inset = 0
	k.position = pos
	k.size = Vector2(w, 24)
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(k)
	var l := label(key, F_HEAD, size)
	l.size = k.size
	l.position.y = -1
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	k.add_child(l)
	return k

static func srgb(c: Color) -> Color:
	return c.linear_to_srgb()
