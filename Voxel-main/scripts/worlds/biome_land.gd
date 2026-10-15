extends RefCounted
## Large irregular landforms and smaller habitat islands; independent of village/chunk grids.
var seed := 0
var features := {}
var relief := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var moisture := FastNoiseLite.new()

func setup(value: int) -> void:
	seed = value
	relief.seed = seed ^ 7713; relief.frequency = .0035; relief.fractal_octaves = 3
	detail.seed = seed ^ 1927; detail.frequency = .027; detail.fractal_octaves = 2
	moisture.seed = seed ^ 6317; moisture.frequency = .0018; moisture.fractal_octaves = 2

func feature(key: Vector2i, size: int) -> Dictionary:
	var id := Vector3i(key.x,key.y,size)
	if features.has(id): return features[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed ^ key.x*92837111 ^ key.y*689287499 ^ size*311)&0x7fffffff
	var result := {"p":Vector2(key)*size+Vector2(rng.randf_range(.22,.78),rng.randf_range(.22,.78))*size,
		"radius":rng.randf_range(.17,.43)*size,"kind":rng.randi_range(0,5) if size==896 else rng.randi_range(0,2),
		"aspect":rng.randf_range(.7,1.3),"angle":rng.randf()*TAU}
	features[id] = result
	return result

func sample(p: Vector2) -> Vector4:
	# x height, y forest cover, z lake influence, w mountain influence.
	var n := relief.get_noise_2d(p.x,p.y)
	var d := detail.get_noise_2d(p.x,p.y)
	var h := 9.0+n*2.4+d*.35
	var forest := smoothstep(-.25,.35,moisture.get_noise_2d(p.x,p.y))*.38
	var lake := 0.0
	var mountain := 0.0
	var warped := p+warp(p)
	for size in [896,288]:
		var cell := Vector2i(floori(warped.x/size),floori(warped.y/size))
		for dx in range(-1,2):
			for dz in range(-1,2):
				var f := feature(cell+Vector2i(dx,dz),size)
				var delta: Vector2 = (warped-Vector2(f.p)).rotated(float(f.angle))
				delta.x *= float(f.aspect)
				var distance := delta.length()+d*9
				var radius := float(f.radius)
				var blend := 1.0-smoothstep(radius*.38,radius+float(size)*.13,distance)
				if blend<=0: continue
				match int(f.kind):
					0: forest *= 1.0-blend*.8
					1: forest = maxf(forest,blend)
					2:
						var basin := 1.0-smoothstep(radius*.35,radius,distance)
						lake = maxf(lake,basin)
					3: h += blend*(14+n*11)
					4,5:
						var peak := 1.0-smoothstep(0,radius+116,distance)
						var height := 82.0 if int(f.kind)==4 else 230.0
						var ridge := 1.0-absf(relief.get_noise_2d(p.x*2.7,p.y*2.7))
						h += peak*height*(.42+ridge*.65)+blend*d*5
						mountain = maxf(mountain,peak)
	# Mountain lakes become sheltered valleys; broad shore shelves avoid vertical water walls.
	lake *= 1.0-smoothstep(18,42,h)
	h = lerpf(h,-1.5,smoothstep(.08,.92,lake))
	return Vector4(h,forest,lake,mountain)

func trim(p: Vector2) -> void:
	if features.size()<180: return
	for key: Vector3i in features.keys():
		if (Vector2(key.x,key.y)*key.z-p).length()>key.z*3: features.erase(key)

func warp(p: Vector2) -> Vector2:
	return Vector2(relief.get_noise_2d(p.x+9781,p.y),relief.get_noise_2d(p.x,p.y+4721))*100

func world_center(f: Dictionary) -> Vector2:
	var p: Vector2 = f.p
	for i in 4: p = Vector2(f.p)-warp(p)
	return p
