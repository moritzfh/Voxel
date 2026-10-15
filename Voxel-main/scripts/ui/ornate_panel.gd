@tool
extends Control
## Dark translucent panel with a double gold frame and corner ornaments (matches the concept HUD).

@export var bg_color := Color(0.055, 0.09, 0.08, 0.86)
@export var bg_color_top := Color(0.08, 0.125, 0.11, 0.88)
@export var gold := Color(0.80, 0.65, 0.37)
@export var gold_dark := Color(0.52, 0.41, 0.22)
@export var corner_size := 7.0
@export var ornaments := true
@export var inner_inset := 4.0

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# vertical gradient background
	var steps := 8
	for i in steps:
		var t := float(i) / steps
		var c := bg_color_top.lerp(bg_color, t)
		draw_rect(Rect2(0, size.y * t, size.x, size.y / steps + 1), c)
	# outer + inner frame
	draw_rect(r.grow(-1), gold, false, 2.0)
	if inner_inset > 0:
		draw_rect(r.grow(-inner_inset), gold_dark, false, 1.0)
	if ornaments:
		for p in [Vector2(0, 0), Vector2(size.x, 0), Vector2(0, size.y), Vector2(size.x, size.y)]:
			_diamond(p, corner_size, gold)
			_diamond(p, corner_size * 0.45, gold_dark.darkened(0.3))

func _diamond(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)])
	draw_colored_polygon(pts, col)
