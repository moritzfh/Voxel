extends RefCounted
## Pure coordinate-based world description, shared by streaming workers and every network peer.
var config := {}
var span := 256
var seed := 0
var noise := FastNoiseLite.new()
var small := FastNoiseLite.new()
var woods := FastNoiseLite.new()
var regions := {}
var biomes: RefCounted
var modern := false
var chunk_heights := {}

func setup(options: Dictionary) -> void:
	config = options.duplicate(true)
	seed = int(config.seed)
	modern = int(config.get("terrain_version",0))>=2
	if modern:
		biomes = preload("res://scripts/worlds/biome_land.gd").new()
		biomes.setup(seed)
	span = [192,256,320][int(config.size)]
	noise.seed = seed
	noise.frequency = .009
	noise.fractal_octaves = 3
	small.seed = seed^18931
	small.frequency = .048
	woods.seed = seed^78903
	woods.frequency = .018

func region_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x/span),floori(p.y/span))

func coordinate_seed(key: Vector2i, salt := 0) -> int:
	return (seed ^ (key.x*73856093) ^ (key.y*19349663) ^ salt)&0x7fffffff

func river_x(z: float, band: int) -> float:
	var phase := float((seed^band*731)%1024)*.013
	if modern: return band*span*2+sin(z*.0023+phase)*65+sin(z*.0081+phase*1.7)*25+sin(z*.024+phase)*6
	return band*span*2+sin(z*.009+phase)*26+sin(z*.027+phase)*8

func river_distance(p: Vector2) -> float:
	if not config.rivers: return INF
	var band := roundi(p.x/(span*2.0))
	return minf(absf(p.x-river_x(p.y,band)),minf(absf(p.x-river_x(p.y,band-1)),absf(p.x-river_x(p.y,band+1))))

func base_height(p: Vector2) -> float:
	var h: float = biomes.sample(p).x if modern else 9.0+noise.get_noise_2d(p.x,p.y)*[3.0,9.0,24.0][int(config.landscape)]+small.get_noise_2d(p.x,p.y)*.7
	if config.rivers:
		var d := river_distance(p)
		if modern:
			var valley_width := maxf(32.0,minf(230.0,h*1.1))
			if d<valley_width: h = lerpf(5.0,h,smoothstep(10,valley_width,d))
		elif d<24: h = lerpf(5.0,h,smoothstep(10,24,d))
		if d < 7: h = lerpf(1.0,5.0,smoothstep(4.5,8,d))
	return maxf(-2.0 if modern else 1.0,h)

func region(key: Vector2i) -> Dictionary:
	if regions.has(key): return regions[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = coordinate_seed(key)
	var origin := Vector2(key)*span
	var center := origin+Vector2.ONE*span*.5
	var result := {"key":key,"villages":[],"houses":[],"caves":[],"ruins":[],"camps":[],"dungeons":[],"roads":[],"landmarks":[]}
	regions[key] = result
	result.roads.append([origin+Vector2(0,span*.5),origin+Vector2(span,span*.5)])
	result.roads.append([origin+Vector2(span*.5,0),origin+Vector2(span*.5,span)])
	for i in int(config.villages):
		var fraction: Vector2 = [Vector2(.28,.25),Vector2(.73,.75),Vector2(.73,.25)][i]
		var p := origin+fraction*span
		p += Vector2(rng.randf_range(-8,8),rng.randf_range(-8,8))
		for attempt in 12:
			if river_distance(p)>35 and (not modern or base_height(p)>5): break
			p.x += 6 if p.x>river_x(p.y,roundi(p.x/(span*2.0))) else -6
		p = p.clamp(origin+Vector2.ONE*30,origin+Vector2.ONE*(span-30)).snapped(Vector2.ONE*.5)
		var h := snappedf(maxf(5,base_height(p)),.125)
		var uid := "%d_%d_%d" % [key.x,key.y,i]
		var name: String = ["Weiden","Fichten","Sonnen","Birken","Eichen","Moos"][rng.randi_range(0,5)]+["hain","furt","au","tal","grund"][rng.randi_range(0,4)]
		var village := {"p":p,"h":h,"id":uid,"name":name,"style":rng.randi_range(0,2),"pen":Rect2(p+Vector2(14,1),Vector2(9,11)),"field":Rect2(p+Vector2(14,-15),Vector2(10,12))}
		result.villages.append(village)
		result.landmarks.append({"p":p,"name":name,"kind":"village"})
		result.roads.append([p,p+Vector2(0,19),Vector2(center.x,p.y+19),center])
		result.roads.append([p+Vector2(0,-17),p+Vector2(0,17)])
		for j in 6:
			var house := {"p":p+Vector2(-9 if j%2==0 else 9,(j/2-1)*11),"h":h,"side":1 if j%2==0 else -1,"style":village.style,"id":uid+"_"+str(j)}
			result.houses.append(house)
			result.roads.append([p+Vector2(0,(j/2-1)*11),house.p])
	for kind in ["caves","ruins","camps"]:
		if (kind=="caves" and not config.caves) or (kind=="ruins" and not config.ruins): continue
		for i in (1 if span==192 and int(config.villages)>1 else 2):
			var p := origin+Vector2(rng.randf_range(22,span-22),rng.randf_range(22,span-22))
			var best := p
			var best_score := -INF
			for attempt in 90:
				var score := minf(river_distance(p)-29,base_height(p)-4) if modern else river_distance(p)-29
				for village in result.villages:
					score = minf(score,p.distance_to(village.p)-43)
				for other_kind in ["caves","ruins","camps"]:
					for place in result[other_kind]:
						score = minf(score,p.distance_to(place.p)-27)
				if score>best_score: best_score = score; best = p
				if score>=0: break
				p = origin+Vector2(rng.randf_range(22,span-22),rng.randf_range(22,span-22))
			if best_score<0: continue
			p = best
			p = p.snapped(Vector2.ONE*.5)
			var place := {"p":p,"h":snappedf(base_height(p),.125),"id":"%s_%d_%d_%d" % [kind,key.x,key.y,i]}
			result[kind].append(place)
			result.landmarks.append({"p":p,"name":{"caves":"Kristallhöhle","ruins":"Alte Ruine","camps":"Wandererlager"}[kind],"kind":kind.trim_suffix("s")})
			var entry := p-Vector2(0,12) if kind=="caves" else p-Vector2(0,7)
			result.roads.append(route(entry,center,result,origin))
	if int(config.get("encounter_version",0))>0:
		var dungeon_rng := RandomNumberGenerator.new()
		dungeon_rng.seed = coordinate_seed(key,838393)
		var chosen := Vector2.ZERO
		var score_best := -INF
		for attempt in 120:
			var point := origin+Vector2(dungeon_rng.randf_range(27,span-27),dungeon_rng.randf_range(27,span-27))
			var score := minf(river_distance(point)-29,base_height(point)-4) if modern else river_distance(point)-29
			for village in result.villages: score = minf(score,point.distance_to(village.p)-77)
			for site in result.caves+result.ruins+result.camps: score = minf(score,point.distance_to(site.p)-32)
			if score>score_best: score_best = score; chosen = point
			if score>=0: break
		if score_best>=0:
			var species: String = ["cyclops","dragon","sandworm"][coordinate_seed(key,817)%3]
			var point := chosen.snapped(Vector2.ONE*.5)
			var place := {"p":point,"h":snappedf(maxf(5,base_height(point)),.125),"species":species,"radius":18.0,"id":"dungeon_%d_%d" % [key.x,key.y]}
			result.dungeons.append(place)
			result.landmarks.append({"p":point,"kind":"dungeon","name":{"cyclops":"Zyklopengewölbe","dragon":"Drachenhorst","sandworm":"Sandwurmgrube"}[species]})
			result.roads.append(route(point-Vector2(0,19),center,result,origin))
	return result

func route(start: Vector2, finish: Vector2, layout: Dictionary, origin: Vector2) -> Array:
	var candidates := [[start,Vector2(finish.x,start.y),finish],[start,Vector2(start.x,finish.y),finish]]
	for x in [origin.x+8,origin.x+span-8]: candidates.append([start,Vector2(x,start.y),Vector2(x,finish.y),finish])
	for z in [origin.y+8,origin.y+span-8]: candidates.append([start,Vector2(start.x,z),Vector2(finish.x,z),finish])
	candidates.sort_custom(func(a: Array,b: Array): return path_length(a)<path_length(b))
	for path in candidates:
		if path_clear(path,layout): return path
	# A compact 4 m graph handles the rare case where both village rows obstruct an L-shaped road.
	var nav := AStar2D.new()
	var n := span/4
	for x in n:
		for z in n:
			var p := origin+Vector2(x*4+2,z*4+2)
			if path_clear([p,p+Vector2(.01,.01)],layout): nav.add_point(x*n+z,p)
	for id in nav.get_point_ids():
		var x := id/n
		var z := id%n
		for offset: Vector2i in [Vector2i(1,0),Vector2i(0,1)]:
			var neighbour := Vector2i(x,z)+offset
			var target := neighbour.x*n+neighbour.y
			if neighbour.x<n and neighbour.y<n and nav.has_point(target) and path_clear([nav.get_point_position(id),nav.get_point_position(target)],layout): nav.connect_points(id,target)
	var points := nav.get_point_path(nav.get_closest_point(start),nav.get_closest_point(finish))
	var path: Array = [start]
	for p in points: path.append(p)
	path.append(finish)
	return path

func path_length(path: Array) -> float:
	var distance := 0.0
	for i in path.size()-1: distance += Vector2(path[i]).distance_to(path[i+1])
	return distance

func path_clear(path: Array, layout: Dictionary) -> bool:
	var obstacles: Array[Rect2] = []
	for house in layout.houses: obstacles.append(Rect2(house.p-Vector2.ONE*4,Vector2.ONE*8))
	for village in layout.villages:
		obstacles.append(village.pen.grow(.5))
		obstacles.append(village.field.grow(.5))
	for i in path.size()-1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i+1]
		var area := Rect2(a.min(b),(a-b).abs()).grow(.01)
		for rect in obstacles:
			if not area.intersects(rect): continue
			if rect.has_point(a) or rect.has_point(b): return false
			var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
			for j in 4:
				if Geometry2D.segment_intersects_segment(a,b,corners[j],corners[(j+1)%4])!=null: return false
	return true

func height(p: Vector2) -> float:
	var chunk := Vector2i(floori(p.x/16),floori(p.y/16))
	if modern and chunk_heights.has(chunk):
		var grid: PackedFloat32Array = chunk_heights[chunk]
		var f := (p-Vector2(chunk)*16)*2
		var x := clampi(floori(f.x),0,31)
		var z := clampi(floori(f.y),0,31)
		return snappedf(lerpf(lerpf(grid[x*33+z],grid[(x+1)*33+z],f.x-x),lerpf(grid[x*33+z+1],grid[(x+1)*33+z+1],f.x-x),f.y-z),.125)
	var h := base_height(p)
	var cell := region_of(p)
	for dx in range(-1,2):
		for dz in range(-1,2):
			var key := cell+Vector2i(dx,dz)
			# Only edge-neighbour plans can affect this point.
			var bounds := Rect2(Vector2(key)*span,Vector2.ONE*span).grow(2)
			if not bounds.has_point(p): continue
			var layout := region(key)
			for village in layout.villages:
				h = lerpf(float(village.h),h,smoothstep(26,34,p.distance_to(village.p)))
			for cave in layout.caves:
				var d := p.distance_to(cave.p+Vector2(0,8))
				if d<15: h = maxf(h,float(cave.h)+7*(1-smoothstep(4,15,d)))
			for place in layout.ruins+layout.camps:
				h = lerpf(float(place.h),h,smoothstep(7,12,p.distance_to(place.p)))
			for dungeon in layout.get("dungeons",[]):
				h = lerpf(float(dungeon.h),h,smoothstep(18,24,p.distance_to(dungeon.p)))
	return snappedf(h,.125)

func road(p: Vector2) -> bool:
	var layout := region(region_of(p))
	for path in layout.roads:
		for i in path.size()-1:
			if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,path[i],path[i+1]))<3.1: return true
	return false

func water_level(p: Vector2) -> float:
	if modern: return 3.0 if height(p)<3 else -100.0
	return 3.0 if config.rivers and river_distance(p)<7 and height(p)<3 else -100.0

func spawn() -> Vector3:
	var village: Dictionary = region(Vector2i.ZERO).villages[0]
	return Vector3(village.p.x,float(village.h)+.6,village.p.y-5)

func sample(p: Vector2) -> Dictionary:
	var layout := region(region_of(p))
	return {"h":height(p),"water":water_level(p),"road":road(p),"forest":woods.get_noise_2d(p.x,p.y),"layout":layout}

func forest_cover(p: Vector2) -> float:
	if not modern: return [.25,.47,.68][int(config.forest)]+woods.get_noise_2d(p.x,p.y)*.6
	var cover: float = biomes.sample(p).y
	var clumps := smoothstep(-.3,.35,woods.get_noise_2d(p.x,p.y))
	return clampf((.015+cover*.8)*(.15+clumps)*[.65,1.0,1.3][int(config.forest)],0,.96)

func surface(p: Vector2, h: float, slope: float = 0.0) -> int:
	if h<3: return 22
	if road(p): return 3
	if river_distance(p)<9 or (modern and h<4): return 21
	if modern:
		if h>143+small.get_noise_2d(p.x,p.y)*14: return 18
		if h>83 or slope>1.15: return 41
		if forest_cover(p)>.55: return 55 if small.get_noise_2d(p.x,p.y)>.2 else 2
	return 1

func nearest_water(p: Vector2) -> Vector3:
	if water_level(p)>-50: return Vector3(p.x,3.15,p.y)
	var candidates: Array[Vector2] = []
	if config.rivers:
		var band := roundi(p.x/(span*2.0))
		for offset in range(-1,2):
			var q := Vector2(river_x(p.y,band+offset),p.y)
			if q.distance_squared_to(p)<50*50: candidates.append(q)
	if modern:
		for size in [896,288]:
			var cell := Vector2i(floori(p.x/size),floori(p.y/size))
			for dx in range(-1,2):
				for dz in range(-1,2):
					var feature: Dictionary = biomes.feature(cell+Vector2i(dx,dz),size)
					if feature.kind!=2: continue
					if p.distance_to(feature.p)>float(feature.radius)/.7+145: continue
					candidates.append(biomes.world_center(feature))
	var best := Vector3(100000,-1000,100000)
	var distance := 34.0*34.0
	for candidate in candidates:
		if water_level(candidate)<-50: continue
		var dry := p
		var wet := candidate
		for step in 8:
			var mid := (dry+wet)*.5
			if water_level(mid)>-50: wet = mid
			else: dry = mid
		var d := p.distance_squared_to(wet)
		if d<distance:
			distance = d
			best = Vector3(wet.x,3.15,wet.y)
	return best
