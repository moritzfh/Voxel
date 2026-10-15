extends Control
## Health / mana / stamina bar with centred "value / max" text.

@export var fill_color := Color(0.85, 0.15, 0.17)
@export var value := 100.0
@export var max_value := 100.0
var font: Font
var font_size := 15
var _shown := 100.0

func _process(delta: float) -> void:
	var target := value
	if abs(_shown - target) > 0.01:
		_shown = lerp(_shown, target, 1.0 - exp(-12.0 * delta))
		queue_redraw()

func set_values(v: float, m: float) -> void:
	value = v
	max_value = m
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.07, 0.07, 0.07, 0.95))
	var f: float = clamp(_shown / max(max_value, 0.001), 0.0, 1.0)
	var fr := Rect2(Vector2(2, 2), Vector2((size.x - 4) * f, size.y - 4))
	if fr.size.x > 0:
		draw_rect(fr, fill_color)
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.42)), fill_color.lightened(0.28))
		draw_rect(Rect2(fr.position + Vector2(0, fr.size.y - 2), Vector2(fr.size.x, 2)), fill_color.darkened(0.35))
	draw_rect(r.grow(-0.5), Color(0.55, 0.44, 0.24), false, 1.0)
	if font:
		var txt := "%d / %d" % [roundi(value), roundi(max_value)]
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var p := Vector2((size.x - ts.x) * 0.5, (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
		draw_string(font, p + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
		draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1))
