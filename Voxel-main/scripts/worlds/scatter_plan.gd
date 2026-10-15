extends RefCounted
## Worker-only decoration data. No scene nodes or GPU resources are touched here.
static func build(land: RefCounted, key: Vector2i, fine: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = land.coordinate_seed(key,11941)
	var groups := {}
	var plants := {}
	var decor := {}
	var positions: Array[Vector2] = []
	for i in (40 if land.modern else 20):
		var p := Vector2(key)*16+Vector2(rng.randf_range(.5,15.5),rng.randf_range(.5,15.5))
		var layout: Dictionary = land.region(land.region_of(p))
		var occupied: bool = land.river_distance(p)<9 or land.road(p)
		for village in layout.villages:
			if p.distance_to(village.p)<30: occupied = true
		for site in layout.caves+layout.ruins+layout.camps:
			if p.distance_to(site.p)<12: occupied = true
		for dungeon in layout.get("dungeons",[]):
			if p.distance_to(dungeon.p)<24: occupied = true
		if occupied or rng.randf()>land.forest_cover(p): continue
		var h: float = land.height(p)
		if land.modern:
			if h<4.2 or h>100: continue
			for offset: Vector2 in [Vector2(2.3,0),Vector2(-2.3,0),Vector2(0,2.3),Vector2(0,-2.3)]:
				var other: float = land.height(p+offset)
				if other<3.5 or absf(other-h)>1.8: occupied = true
			for other in positions:
				if other.distance_squared_to(p)<3.2: occupied = true
			if occupied: continue
		var conifer: bool = land.woods.get_noise_2d(p.x,p.y)>.1
		if land.modern: conifer = h>32 or land.biomes.moisture.get_noise_2d(p.x,p.y)<-.1
		var kind := "pine%d" % rng.randi_range(0,5) if conifer else "oak%d" % rng.randi_range(0,2)
		var prefix := "tree_%s_%d_%d" % [kind,key.x,key.y]
		if not groups.has(prefix): groups[prefix] = []
		var scale_value := rng.randf_range(.7,1.2) if land.modern else rng.randf_range(.8,1.1)
		var yaw := rng.randf()*TAU
		var pos := Vector3(p.x,h,p.y)
		groups[prefix].append({"t":Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale_value),pos),"yaw":yaw,"scale":scale_value})
		positions.append(p)
	if fine:
		for kind in ["grass_a","daisy","fern","bluebell"]:
			plants[kind] = []
			for i in 70:
				var p := Vector2(key)*16+Vector2(rng.randf_range(0,16),rng.randf_range(0,16))
				if land.river_distance(p)<8 or land.road(p): continue
				var occupied := false
				var layout: Dictionary = land.region(land.region_of(p))
				for village in layout.villages:
					if p.distance_to(village.p)<25: occupied = true
				for dungeon in layout.get("dungeons",[]):
					if p.distance_to(dungeon.p)<19: occupied = true
				if occupied: continue
				var h: float = land.height(p)
				if land.modern and (h<3.5 or h>78 or absf(land.height(p+Vector2(.8,0))-h)>1 or absf(land.height(p+Vector2(0,.8))-h)>1): continue
				if land.modern and kind=="fern" and land.forest_cover(p)<.3: continue
				plants[kind].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU),Vector3(p.x,h,p.y)))
	if land.modern:
		for i in 36:
			var p := Vector2(key)*16+Vector2(rng.randf_range(.5,15.5),rng.randf_range(.5,15.5))
			var h: float = land.height(p)
			if land.road(p): continue
			var layout: Dictionary = land.region(land.region_of(p))
			var occupied := false
			for village in layout.villages:
				if p.distance_to(village.p)<31: occupied = true
			for site in layout.caves+layout.ruins+layout.camps+layout.get("dungeons",[]):
				if p.distance_to(site.p)<20: occupied = true
			if occupied: continue
			var kind := ""
			var scale_value := rng.randf_range(.55,1.25)
			if h<2.75:
				if fine and i%3!=0:
					kind = "plant_lily"; h = 3.035; scale_value = rng.randf_range(.65,1.15)
				else: kind = "rock_stone_a" if i%2 else "rock_pebble_b"
			elif i<5 or (h>65 and i<16):
				kind = "rock_boulder_"+["a","b","c","d","e","f"][rng.randi_range(0,5)]
			if kind.is_empty(): continue
			if not decor.has(kind): decor[kind] = []
			decor[kind].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_value),Vector3(p.x,h,p.y)))
	return {"trees":groups,"plants":plants,"decor":decor}
