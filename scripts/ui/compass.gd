extends Control
## Heading strip: W . N . E . S with ticks, gold diamond marker in the middle.

var heading := 0.0 # degrees, 0 = north
var font: Font
var font_size := 18
var span := 180.0 # degrees visible across the width
var center_frac := 0.5 # where the heading marker sits along the strip
var gold := Color(0.85, 0.70, 0.40)
var ink := Color(0.97, 0.95, 0.88)

func set_heading(h: float) -> void:
	if abs(angle_difference(deg_to_rad(h), deg_to_rad(heading))) > 0.002:
		heading = h
		queue_redraw()

func _draw() -> void:
	var w := size.x
	var cy := 10.0
	# fading baseline
	var segs := 24
	for i in segs:
		var x0 := w * i / segs
		var x1 := w * (i + 1) / segs
		var m: float = 1.0 - abs((x0 + x1) * 0.5 / w - 0.5) * 2.0
		draw_line(Vector2(x0, cy), Vector2(x1, cy), Color(ink, 0.25 + 0.6 * m), 2.0)
	var labels := {0: "N", 90: "E", 180: "S", 270: "W"}
	var start := int(floor((heading - span * center_frac) / 15.0)) * 15
	for a in range(start, int(heading + span * (1.0 - center_frac)) + 15, 15):
		var rel: float = angle_difference(deg_to_rad(heading), deg_to_rad(float(a)))
		var x := w * center_frac + rad_to_deg(rel) / span * w
		if x < 0 or x > w:
			continue
		var m: float = clampf(1.0 - absf(x / w - 0.5) * 1.6, 0.25, 1.0)
		var key := posmod(a, 360)
		if labels.has(key):
			draw_line(Vector2(x, cy - 7), Vector2(x, cy + 7), Color(ink, 0.9 * m + 0.1), 2.0)
			if font:
				var t: String = labels[key]
				var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				var p := Vector2(x - ts.x * 0.5, cy + 12 + font.get_ascent(font_size))
				draw_string(font, p + Vector2(1, 1.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.75 * m))
				draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(ink, m))
		elif key % 45 == 0:
			draw_line(Vector2(x, cy - 5), Vector2(x, cy + 5), Color(ink, 0.7 * m), 1.5)
		else:
			draw_line(Vector2(x, cy - 3), Vector2(x, cy + 3), Color(ink, 0.5 * m), 1.0)
	# centre marker
	var c := Vector2(w * center_frac, cy)
	var s := 8.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, 0), c + Vector2(0, s), c + Vector2(-s * 0.7, 0)]), gold)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, 0), c + Vector2(0, 0)]), gold.lightened(0.3))
