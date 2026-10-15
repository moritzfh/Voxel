extends Control
## Pan and zoom independently of the minimap; sample the seed without loading terrain chunks.
const LAND := preload("res://scripts/worlds/infinite_land.gd")
const K := preload("res://scripts/ui/ui_kit.gd")
var main: Node
var center := Vector2.ZERO
var extent := 256.0
var view_rect := Rect2()
var texture: Texture2D
var texture_rect := Rect2()
var landmarks: Array = []
var land: RefCounted
var dragging := false
var dirty := true
var debounce := 0.0
var image: Image
var row := 0
var column := 0
var sample_rect := Rect2()
var status: Label

func setup(game: Node) -> void:
	main = game
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	center = Vector2(main.player.position.x,main.player.position.z)
	if main.world_data.get("streamed",false):
		land = LAND.new()
		land.setup(Worlds.config)
	else:
		texture = main.hud.minimap.map_tex
		texture_rect = main.hud.minimap.world_rect
		extent = maxf(texture_rect.size.x,texture_rect.size.y)
		center = texture_rect.get_center()
	gui_input.connect(_map_input)

func recenter() -> void:
	center = Vector2(main.player.position.x,main.player.position.z)
	dirty = true
	debounce = .08
	queue_redraw()

func zoom(factor: float, anchor := Vector2(-1,-1)) -> void:
	if anchor.x<0: anchor = size*.5
	var before := screen_world(anchor)
	extent = clampf(extent*factor,48,4096 if land else maxf(texture_rect.size.x,texture_rect.size.y)*4)
	center += before-screen_world(anchor)
	dirty = true
	debounce = .15
	queue_redraw()

func screen_world(point: Vector2) -> Vector2:
	return center+(point/size-Vector2.ONE*.5)*extent

func world_screen(point: Vector2) -> Vector2:
	return (point-center)/extent*size+size*.5

func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed: zoom(1/1.3,event.position)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom(1.3,event.position)
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]: dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		center -= event.relative/size*extent
		dirty = true
		debounce = .12
		queue_redraw()
		accept_event()

func _process(dt: float) -> void:
	if not is_visible_in_tree(): return
	debounce = maxf(0,debounce-dt)
	view_rect = Rect2(center-Vector2.ONE*extent*.5,Vector2.ONE*extent)
	if land and dirty and debounce<=0:
		dirty = false
		image = Image.create(192,192,false,Image.FORMAT_RGB8)
		sample_rect = view_rect
		row = 0
		column = 0
		# Overview caches can be discarded; no gameplay state lives in these descriptions.
		land.regions.clear()
	if image and not dirty:
		var deadline := Time.get_ticks_usec()+1800
		while row<192 and Time.get_ticks_usec()<deadline:
			var p := sample_rect.position+Vector2(column+.5,row+.5)*sample_rect.size/192.0
			var h: float = land.height(p)
			var color := Color("638b42") if land.forest_cover(p)<.35 else Color("355d36")
			if land.modern and h>83: color = Color("81858b")
			if land.modern and h>143: color = Color("e8edf0")
			if land.road(p): color = Color("c0a375")
			if h<3 and (land.modern or land.config.rivers): color = Color("4a9ab5")
			image.set_pixel(column,row,color)
			column += 1
			if column==192: column = 0; row += 1
		if row>=192:
			texture = ImageTexture.create_from_image(image)
			texture_rect = sample_rect
			landmarks.clear()
			for region in land.regions.values(): landmarks.append_array(region.landmarks)
			image = null
	if status:
		status.text = "Ausschnitt: %.0f m\nMitte: %.0f / %.0f\n%s\n\nMausrad: Zoom\nMaus ziehen: Verschieben\n\nTierlevel: +1 je 180 m\nEntfernung vom Startpunkt\nerhöht Leben und Schaden.\n\nGold: Dörfer\nBlau: Höhlen\nOrange: Ruinen\nWeiß: Lager" % [extent,center.x,center.y,"Karte wird gezeichnet …" if image or dirty and land else "Seed-Vorschau" if land else "Testkarte"]
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("19362b"))
	if texture:
		var p := world_screen(texture_rect.position)
		draw_texture_rect(texture,Rect2(p,texture_rect.size/extent*size),false)
	for mark in landmarks:
		var p := world_screen(mark.p)
		if not Rect2(Vector2.ONE*8,size-Vector2.ONE*16).has_point(p): continue
		var color: Color = {"village":Color("eed58b"),"cave":Color("73c8ed"),"ruin":Color("df9567"),"dungeon":Color("df777e")}.get(str(mark.kind),Color.WHITE)
		draw_circle(p,5,color)
		if extent<700: draw_string(K.F_BODY,p+Vector2(9,-6),str(mark.name),HORIZONTAL_ALIGNMENT_LEFT,-1,16,K.CREAM)
	if not land:
		for house in main.hud.minimap.houses:
			draw_circle(world_screen(Vector2(house[0],house[1])),4,K.GOLD)
		var markers: Dictionary = main.world_data.get("markers",{})
		for i in markers.get("runes",[]).size():
			if i in Game.runes_found or Game.rank("runen")>0:
				var rune: Array = markers.runes[i]
				draw_circle(world_screen(Vector2(rune[0],rune[2])),5,Color("82cbed"))
	for other in main.hud.minimap.others: draw_circle(world_screen(other[0]),6,other[1])
	var spawn: Vector3 = main.player.spawn_point
	draw_arc(world_screen(Vector2(spawn.x,spawn.z)),9,0,TAU,24,K.GOLD,2)
	var p := world_screen(Vector2(main.player.position.x,main.player.position.z))
	if Rect2(Vector2.ZERO,size).has_point(p):
		draw_circle(p,9,Color("16271d"))
		draw_circle(p,6,Color.WHITE)
		var dir := Vector2(-sin(main.player._facing),-cos(main.player._facing))
		draw_line(p,p+dir*18,Color.WHITE,3)
	draw_rect(Rect2(Vector2.ONE,size-Vector2.ONE*2),K.GOLD,false,2)
