extends Control
## North-up minimap centred on the player with house markers and a heading arrow.

var map_tex: Texture2D
var arrow_tex: Texture2D
var house_tex: Texture2D
var world_rect := Rect2(-160, -220, 320, 320) # metres (x, z)
var map_res := 0.5 # metres per pixel in the texture
var view_metres := 130.0
var player_pos := Vector2.ZERO # x,z
var facing := 0.0 # radians, 0 = north
var houses: Array = []
var others: Array = []  # [[Vector2 x/z, Color]] other players (multiplayer)

func update_player(p: Vector2, f: float) -> void:
	player_pos = p
	facing = f
	queue_redraw()

func _draw() -> void:
	if map_tex == null:
		return
	var px_per_m := size.x / view_metres
	var tex_size := map_tex.get_size()
	# source rect in texture pixels
	var src_w := view_metres / map_res
	var src_h := src_w * size.y / size.x
	var cx := (player_pos.x - world_rect.position.x) / map_res
	var cz := (player_pos.y - world_rect.position.y) / map_res
	var src := Rect2(cx - src_w * 0.5, cz - src_h * 0.5, src_w, src_h)
	var dst := Rect2(Vector2.ZERO, size)
	# clip source to texture bounds
	var clipped := src.intersection(Rect2(Vector2.ZERO, tex_size))
	if clipped.size.x > 0 and clipped.size.y > 0:
		var scale := size.x / src.size.x
		var d := Rect2((clipped.position - src.position) * scale, clipped.size * scale)
		draw_rect(dst, Color(0.25, 0.42, 0.2))
		draw_texture_rect_region(map_tex, d, clipped)
	# houses
	if house_tex:
		for h in houses:
			var rel := (Vector2(h[0], h[1]) - player_pos) * px_per_m + size * 0.5
			if Rect2(Vector2(-8, -8), size + Vector2(16, 16)).has_point(rel):
				var s := 22.0
				draw_texture_rect(house_tex, Rect2(rel - Vector2(s, s) * 0.5, Vector2(s, s)), false)
	# other players
	for o in others:
		var rel2: Vector2 = (o[0] - player_pos) * px_per_m + size * 0.5
		rel2 = rel2.clamp(Vector2(6, 6), size - Vector2(6, 6))
		draw_circle(rel2, 7.0, Color(0.05, 0.07, 0.06, 0.9))
		draw_circle(rel2, 5.0, o[1])
	# vignette edge
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.15), false, 6.0)
	# player arrow
	if arrow_tex:
		var c := size * 0.5
		var s := 26.0
		draw_set_transform(c, facing, Vector2.ONE)
		draw_texture_rect(arrow_tex, Rect2(-Vector2(s, s) * 0.5, Vector2(s, s)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
