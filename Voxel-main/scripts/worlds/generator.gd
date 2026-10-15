extends RefCounted
## Runtime generation: no editor, external process or prebuilt terrain required.
## All randomness is local to the descriptor; terrain and architecture share the editable volume.
signal progress(message: String, fraction: float)
const VX := preload("res://scripts/voxel/voxel_world.gd")
const VS := 0.5
const CS := 128
const FLOOR := -8.0
var config := {}
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var forest_noise := FastNoiseLite.new()
var side := 256
var half := 128.0
var phase := 0.0
var river_width := 5.0
var villages: Array = []
var caves: Array = []
var ruins: Array = []
var camps: Array = []
var sites: Array[Vector2] = []
var roads: Array = []
var bridges: Array = []
var houses: Array = []
var landmarks: Array = []
var forests: Array = []
var river_points: Array[Vector2] = []
var road_cells := {}
var heights := PackedFloat32Array()
var surface := PackedByteArray()
var water_image: Image
var map_image: Image
var voxel: Node3D
var world: Node3D
var data := {}
var fingerprint := 0

func plan(options: Dictionary) -> void:
	config = options.duplicate(true)
	rng.seed = int(config.seed)
	side = [192,256,320][int(config.size)]
	half = side*.5
	phase = rng.randf_range(-PI,PI)
	river_width = rng.randf_range(4.0,6.0)
	noise.seed = int(config.seed)
	noise.frequency = .014
	noise.fractal_octaves = 3
	detail.seed = int(config.seed)^9173
	detail.frequency = .075
	forest_noise.seed = int(config.seed)^48391
	forest_noise.frequency = .024
	if config.rivers:
		for z in range(-side/2,side/2+1,2): river_points.append(Vector2(river_x(z),z))
	for i in int(config.villages):
		var p := Vector2((-1.0 if i%2 == 0 else 1.0)*half*.40,(-.43+float(i)*.40)*half)
		p += Vector2(rng.randf_range(-9,9),rng.randf_range(-8,8))
		if config.rivers:
			p.x = river_x(p.y)+(-1.0 if i%2 == 0 else 1.0)*half*.40
		p = p.clamp(Vector2.ONE*(-half+30),Vector2.ONE*(half-30))
		var h := snappedf(maxf(5.5,base_height(p)),VS)
		villages.append({"p":p,"h":h,"name":["Weidenhain","Fichtenfurt","Sonnenau"][i],"style":rng.randi_range(0,2)})
		sites.append(p)
		landmarks.append({"p":p,"name":villages.back().name,"kind":"village"})
	if config.caves:
		for i in (2 if side < 300 else 3):
			var p := find_site(25)
			var h := snappedf(base_height(p),VS)
			caves.append({"p":p,"h":h})
			sites.append(p-Vector2(0,4))
			landmarks.append({"p":p,"name":"Kristallhöhle" if i == 0 else "Fuchsbau-Höhle","kind":"cave"})
	if config.ruins:
		for i in (2 if side < 300 else 3):
			var p := find_site(22)
			ruins.append({"p":p,"h":snappedf(base_height(p),VS),"variant":i%2})
			sites.append(p)
			landmarks.append({"p":p,"name":"Alter Wachturm" if i%2 == 0 else "Vergessener Schrein","kind":"ruin"})
	for i in 2:
		var p := find_site(17)
		camps.append({"p":p,"h":snappedf(base_height(p),VS)})
		sites.append(p)
		landmarks.append({"p":p,"name":"Wandererlager","kind":"camp"})
	_make_roads()
	for village in villages:
		var count := 4 if side == 192 else 6
		for i in count:
			var offset := Vector2((-1 if i%2 == 0 else 1)*9, float(i/2-1)*10)
			var p: Vector2 = village.p+offset
			houses.append({"p":p,"h":village.h,"rotation":1 if i%2 == 0 else 3,"style":village.style,"barn":i == count-1})
			_add_road([village.p+Vector2(0,offset.y),p],1.2)
		_add_road([village.p+Vector2(0,-14),village.p+Vector2(0,14)],2.3)
	_raster_roads()

func river_x(z: float) -> float:
	return sin(z/(float(side)*.19)+phase)*half*.20+sin(z*.038+phase*2.0)*4.0

func river_distance(p: Vector2) -> float:
	return absf(p.x-river_x(p.y)) if config.rivers else 10000.0

func base_height(p: Vector2) -> float:
	var amplitude: float = [2.5,6.0,14.0][int(config.landscape)]
	var h := 8.0+noise.get_noise_2d(p.x,p.y)*amplitude+detail.get_noise_2d(p.x,p.y)*.65
	if int(config.landscape) == 2: h += pow(maxf(0,noise.get_noise_2d(p.x*.55+500,p.y*.55)),2)*24.0
	var d := river_distance(p)
	if d < river_width+16.0:
		h = lerpf(5.0,h,smoothstep(river_width+3.0,river_width+16.0,d))
		if d < river_width: h = lerpf(1.0,4.5,smoothstep(river_width-2.0,river_width+1.0,d))
	return maxf(4.0 if not config.rivers else 0.5,h)

func height_at(p: Vector2) -> float:
	var h := base_height(p)
	for village in villages:
		h = lerpf(float(village.h),h,smoothstep(24.0,32.0,p.distance_to(village.p)))
	for cave in caves:
		var center: Vector2 = cave.p+Vector2(0,9)
		var distance := p.distance_to(center)
		if distance < 16.0:
			h = maxf(h,float(cave.h)+8.0*(1.0-smoothstep(4.0,16.0,distance)))
	for site in ruins+camps:
		h = lerpf(float(site.h),h,smoothstep(7.0,12.0,p.distance_to(site.p)))
	return snappedf(h,VS)

func find_site(spacing: float) -> Vector2:
	var best := Vector2.ZERO
	var score := -INF
	for attempt in 180:
		var p := Vector2(rng.randf_range(-half+22,half-22),rng.randf_range(-half+22,half-22)).snapped(Vector2.ONE*2)
		var distance := river_distance(p)-river_width-18.0
		for existing in sites: distance = minf(distance,p.distance_to(existing)-spacing)
		if distance > score: score = distance; best = p
		if score > 2.0: break
	return best

func _make_roads() -> void:
	var nav := AStar3D.new()
	var n := side/4
	for x in n:
		for z in n:
			var p := Vector2(-half+x*4+2,-half+z*4+2)
			var h := height_at(p)
			var weight := 1.0+absf(h-7)*.08+(2.0 if river_distance(p)<river_width else 0.0)
			for village in villages:
				var local: Vector2 = p-village.p
				if absf(local.x)>4 and absf(local.x)<14 and absf(local.y)<15:
					weight += 70.0
			nav.add_point(x*n+z,Vector3(p.x,h,p.y),weight)
	for x in n:
		for z in n:
			for d in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1)]:
				var a: Vector2i = Vector2i(x,z)+d
				if a.x >= 0 and a.x < n and a.y >= 0 and a.y < n: nav.connect_points(x*n+z,a.x*n+a.y)
	# A minimum spanning tree connects every destination; one extra edge makes a useful loop.
	var connected := [0]
	var edges := []
	while connected.size() < sites.size():
		var distance := INF
		var edge := Vector2i.ZERO
		for a in connected:
			for b in sites.size():
				if b in connected: continue
				var d := sites[a].distance_squared_to(sites[b])
				if d < distance: distance = d; edge = Vector2i(a,b)
		connected.append(edge.y)
		edges.append(edge)
	if sites.size() > 3: edges.append(Vector2i(0,sites.size()-1))
	for edge: Vector2i in edges:
		var a := sites[edge.x]
		var b := sites[edge.y]
		var path := nav.get_point_path(nav.get_closest_point(Vector3(a.x,height_at(a),a.y)),nav.get_closest_point(Vector3(b.x,height_at(b),b.y)))
		var points: Array = [a]
		for p in path: points.append(Vector2(p.x,p.z))
		points.append(b)
		_add_road(points,1.8)

func _add_road(points: Array, width: float) -> void:
	roads.append({"points":points,"width":width})

func _raster_roads() -> void:
	for road in roads:
		var points: Array = road.points
		for i in points.size()-1:
			var a: Vector2 = points[i]
			var b: Vector2 = points[i+1]
			for k in maxi(1,ceili(a.distance_to(b)/1.0)):
				var p := a.lerp(b,float(k)/maxi(1,ceili(a.distance_to(b))))
				var cell := Vector2i(floori(p.x/8),floori(p.y/8))
				for dx in range(-1,2):
					for dz in range(-1,2):
						var key := cell+Vector2i(dx,dz)
						if not road_cells.has(key): road_cells[key] = []
						road_cells[key].append([p,float(road.width)])
				if river_distance(p) < river_width+2.0:
					bridges.append({"p":p.snapped(Vector2.ONE*.5),"dir":(b-a).normalized()})

func on_road(p: Vector2, padding := 0.0) -> bool:
	for sample in road_cells.get(Vector2i(floori(p.x/8),floori(p.y/8)),[]):
		if p.distance_squared_to(sample[0]) < pow(float(sample[1])+padding,2): return true
	return false

func generate(root: Node3D, terrain: Node3D, options: Dictionary, template: Dictionary) -> Dictionary:
	world = root
	voxel = terrain
	progress.emit("Landschaft und Orte planen …",.02)
	plan(options)
	data = {"procedural":true,"descriptor":config.duplicate(true),"materials":template.materials,
		"models_vox":template.models_vox,"bounds":[-half,half,-half,half],"markers":{},"houses":[],
		"river":river_points,"forests":forests,"landmarks":landmarks,"roads":roads,"bridges":bridges,"caves":caves,"villages":villages}
	data.near_vox = {"origin":[-half,FLOOR,-half],"vs":VS,"chunks":[]}
	voxel.setup(world,data)
	voxel.wmat = voxel.wmat.duplicate()
	for parameter in {"shallow_tint":Color(.50,.86,.92),"deep_color":Color(.03,.27,.46),"foam_color":Color(.92,.97,1),"absorption":.75,"refraction":.035,"flow":Vector2(-.25,1),"pixel_density":8.0}:
		voxel.wmat.set_shader_parameter(parameter,{"shallow_tint":Color(.50,.86,.92),"deep_color":Color(.03,.27,.46),"foam_color":Color(.92,.97,1),"absorption":.75,"refraction":.035,"flow":Vector2(-.25,1),"pixel_density":8.0}[parameter])
	var dim := side*2
	heights.resize(dim*dim)
	surface.resize(dim*dim)
	water_image = Image.create(dim,dim,false,Image.FORMAT_RF)
	water_image.fill(Color(-100,0,0))
	map_image = Image.create(side,side,false,Image.FORMAT_RGB8)
	for x in dim:
		for z in dim:
			var p := Vector2(-half+x*VS+VS*.5,-half+z*VS+VS*.5)
			var h := height_at(p)
			var d := river_distance(p)
			var value := 1
			if d < river_width+1: value = 22 if h < 3.0 else 21
			elif on_road(p): value = 3
			heights[x*dim+z] = h
			surface[x*dim+z] = value
			if h < 3.0 and config.rivers: water_image.set_pixel(x,z,Color(3,0,0))
			if x%2 == 0 and z%2 == 0:
				var color := Color("658342").lightened(clampf(h/65.0,0,.35))
				if forest_noise.get_noise_2d(p.x,p.y) > .10: color = Color("365c36")
				if value == 3: color = Color("b5a07b")
				if h < 3.0: color = Color("4b91a3")
				map_image.set_pixel(x/2,z/2,color)
		if x%24 == 0:
			progress.emit("Hügel, Flussufer und Wege formen …",.05+.22*float(x)/dim)
			await root.get_tree().process_frame
	var chunks := dim/CS
	for ix in chunks:
		for iz in chunks:
			_load_chunk(ix,iz,dim)
			progress.emit("Voxel-Landschaft aufbauen …",.28+.26*float(ix*chunks+iz+1)/(chunks*chunks))
			await root.get_tree().process_frame
	progress.emit("Häuser, Brücken und Entdeckungen bauen …",.55)
	_build_architecture()
	await root.get_tree().process_frame
	for key: Vector2i in voxel.info:
		var range_y: Vector2i = voxel.vol.get_chunk_range(key.x,key.y)
		var lo := Vector3i(key.x*CS,range_y.x,key.y*CS)
		var size := Vector3i(CS,range_y.y,CS)
		var holder := Node3D.new()
		world.add_child(holder)
		var position: Vector3 = voxel.to_world(lo)
		var m: Dictionary = voxel.vol.mesh_region(lo,size,0,false,true,Vector3.ZERO)
		if not m.is_empty():
			var mesh := MeshInstance3D.new()
			mesh.mesh = VX.array_mesh(m,voxel.vmat)
			mesh.position = position
			holder.add_child(mesh)
		var w: Dictionary = voxel.vol.mesh_region(lo,size,0,true,false,Vector3.ZERO)
		if not w.is_empty():
			var mesh := MeshInstance3D.new()
			mesh.mesh = VX.array_mesh(w,voxel.wmat)
			mesh.position = position
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mesh)
		var body := StaticBody3D.new()
		body.set_meta("terrain",true)
		holder.add_child(body)
		var collision := CollisionShape3D.new()
		collision.position = position
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(voxel.vol.collision_region(lo,size,Vector3.ZERO))
		collision.shape = shape
		body.add_child(collision)
		voxel.baked[key] = [holder]
		progress.emit("Oberflächen und begehbare Welt erstellen …",.57+.22*float(key.x*chunks+key.y+1)/(chunks*chunks))
		await root.get_tree().process_frame
	progress.emit("Wälder, Blumen und Tierlebensräume pflanzen …",.82)
	_vegetation()
	_distant_landscape()
	_markers()
	data.forests = forests
	data.water_meta = {"x0":-half,"z0":-half,"res":VS}
	data.fingerprint = fingerprint
	progress.emit("Welt bereit …",.97)
	return data

func _load_chunk(ix: int, iz: int, dim: int) -> void:
	var top := 0.0
	for x in CS:
		for z in CS: top = maxf(top,heights[(ix*CS+x)*dim+iz*CS+z])
	var cy := ceili((top-FLOOR+14.0)/VS)
	var raw := PackedByteArray()
	raw.resize(CS*cy*CS)
	for x in CS:
		for z in CS:
			var gx := ix*CS+x
			var gz := iz*CS+z
			var h := heights[gx*dim+gz]
			var count := roundi((h-FLOOR)/VS)
			var p := Vector2(-half+gx*VS+VS*.5,-half+gz*VS+VS*.5)
			var cave_range := Vector2(-100,-100)
			for cave in caves:
				var local: Vector2 = p-cave.p
				if absf(local.x) < 2 and local.y > -11 and local.y < 10: cave_range = Vector2(float(cave.h),float(cave.h)+3.5)
				var room_distance := local.distance_to(Vector2(0,9))
				if room_distance < 5.0:
					var ceiling := sqrt(maxf(0,1.0-pow(room_distance/5.0,2)))*4.5
					cave_range = Vector2(float(cave.h),maxf(cave_range.y,float(cave.h)+ceiling))
			for y in count:
				var world_y := FLOOR+y*VS
				if world_y >= cave_range.x and world_y < cave_range.y: continue
				var material := 4 if y < count-4 else 2
				if y == count-1: material = int(surface[gx*dim+gz])
				if cave_range.x > -50 and world_y < cave_range.x and world_y > cave_range.x-2 and (gx*13+gz*7+y)%19 == 0: material = 59
				raw[(x*cy+y)*CS+z] = (material<<2)|(((gx*gx+gx*gz+gz*gz+y*7)>>2)%3)
			if h < 3.0 and config.rivers:
				for y in range(count,roundi((3.0-FLOOR)/VS)): raw[(x*cy+y)*CS+z] = 33<<2
	voxel.info[Vector2i(ix,iz)] = {"y_lo":0,"cy":cy,"off":0,"size":0,"raw":raw.size()}
	voxel.vol.load_chunk(ix,iz,0,cy,raw)
	fingerprint = (fingerprint*31+hash(raw))&0x7fffffff

func box(center: Vector3, size: Vector3, material: int) -> void:
	var lo: Vector3i = voxel.to_voxel(center-size*.5)
	var hi: Vector3i = voxel.to_voxel(center+size*.5-Vector3.ONE*.01)
	for x in range(lo.x,hi.x+1):
		for y in range(lo.y,hi.y+1):
			for z in range(lo.z,hi.z+1): voxel.vol.set_voxel(Vector3i(x,y,z),(material<<2)|((x+y+z)%3) if material else 0)

func _build_architecture() -> void:
	for house in houses: _house(house)
	for village in villages:
		var p := Vector3(village.p.x-2.5,float(village.h),village.p.y+2)
		box(p+Vector3(0,.25,0),Vector3(3,.5,3),8)
		box(p+Vector3(0,.75,0),Vector3(2.5,1,2.5),8)
		box(p+Vector3(0,1.2,0),Vector3(1.5,.5,1.5),0)
		for x in [-1,1]: box(p+Vector3(x,2,0),Vector3(.5,3,.5),11)
		box(p+Vector3(0,3.5,0),Vector3(3,.5,3),14)
		var farm := Vector3(village.p.x+19,float(village.h),village.p.y)
		box(farm,Vector3(7,.5,13),2)
		for z in [-6,6]: box(farm+Vector3(0,1,z),Vector3(8,.5,.5),11)
		for x in [-4,4]:
			box(farm+Vector3(x,1,0),Vector3(.5,.5,13),11)
			for z in [-6,0,6]: box(farm+Vector3(x,.75,z),Vector3(.5,1.5,.5),11)
		for x in range(-2,3):
			for z in range(-5,6): box(farm+Vector3(x,.75,z),Vector3(.5,1,.5),49)
	# Rasterised bridge decks follow each road across the entire wet valley.
	var bridge_cells := {}
	for bridge in bridges:
		var p: Vector2 = bridge.p
		if bridge_cells.has(p): continue
		bridge_cells[p] = true
		box(Vector3(p.x,5.25,p.y),Vector3(4.5,.5,4.5),12)
		var perpendicular := Vector2(-bridge.dir.y,bridge.dir.x)
		for sign_value in [-1,1]:
			var rail: Vector2 = p+perpendicular*2.4*sign_value
			box(Vector3(rail.x,6,rail.y),Vector3(.5,.5,.5),11)
		if int(p.x*2+p.y*2)%4 == 0: box(Vector3(p.x,3.75,p.y),Vector3(.5,3,.5),11)
	for ruin in ruins:
		var p := Vector3(ruin.p.x,float(ruin.h),ruin.p.y)
		box(p,Vector3(9,.5,9),8)
		for x in [-4,4]:
			for z in range(-4,5):
				var h := rng.randf_range(1.5,4)
				box(p+Vector3(x,h*.5,z),Vector3(1,h,1),9)
		for x in range(-4,5):
			box(p+Vector3(x,1.25,4),Vector3(1,2.5,1),9)
			if abs(x)>1: box(p+Vector3(x,2,-4),Vector3(1,4,1),8)
		box(p+Vector3(0,4,-4),Vector3(4,1,1),8)
		if int(ruin.variant) == 0:
			for x in [-3,3]: box(p+Vector3(x,4.5,3),Vector3(1,9,1),8)
		box(p+Vector3(0,1,1),Vector3(1,2,1),59)
	for cave in caves:
		var p := Vector3(cave.p.x,float(cave.h),cave.p.y+9)
		for i in 8:
			var a := float(i)*TAU/8
			if absf(cos(a)) < .3: continue
			box(p+Vector3(cos(a)*3.5,1,sin(a)*3.5),Vector3(.5,rng.randf_range(1,2.5),.5),59)
		var light := OmniLight3D.new()
		light.position = p+Vector3.UP*2
		light.light_color = Color(.25,.7,1)
		light.light_energy = 1.4
		light.omni_range = 9
		world.add_child(light)
	for camp in camps:
		var p := Vector3(camp.p.x,float(camp.h),camp.p.y)
		box(p+Vector3(0,.25,0),Vector3(2,.5,2),8)
		box(p+Vector3(0,.75,0),Vector3(.5,1,.5),28)
		for x in [-3,3]: box(p+Vector3(x,.5,0),Vector3(1,1,4),15)
		box(p+Vector3(0,1,4),Vector3(3,2,2),31)
		var light := OmniLight3D.new()
		light.position = p+Vector3.UP*1.5
		light.light_color = Color(1,.55,.2)
		light.omni_range = 7
		world.add_child(light)

func _house(house: Dictionary) -> void:
	var p := Vector3(house.p.x,float(house.h),house.p.y)
	var plaster := 10 if int(house.style) != 1 else 62
	var roof := 14 if int(house.style) == 0 else 61
	box(p,Vector3(7,.5,7),8)
	box(p+Vector3(0,2,0),Vector3(7,4,7),plaster)
	box(p+Vector3(0,2.25,0),Vector3(6,3.5,6),0)
	box(p+Vector3(0,.25,0),Vector3(6,.5,6),12)
	for x in [-3,0,3]:
		for z in [-3,3]: box(p+Vector3(x,2,z),Vector3(.5,4.5,.5),11)
	for z in [-3,0,3]:
		for x in [-3,3]: box(p+Vector3(x,2,z),Vector3(.5,4.5,.5),11)
	box(p+Vector3(0,3.75,0),Vector3(7,.5,7),11)
	for x in [-1,1]:
		box(p+Vector3(x*3.25,2,-1.5),Vector3(.5,1.5,1),29)
		box(p+Vector3(x*1.5,2,3.25),Vector3(1,1.5,.5),29)
	var door := Vector3(-3.25 if int(house.rotation) == 3 else 3.25,1.5,0)
	box(p+door,Vector3(1.5,3,1.5),0)
	for layer in 7:
		box(p+Vector3(0,4.25+layer*.5,0),Vector3(8-layer,.5,8),roof)
	box(p+Vector3(-2,6,-2),Vector3(1,4,1),6)
	data.houses.append([p.x,p.z])
	var pixel := Vector2i(house.p+Vector2.ONE*half)
	map_image.fill_rect(Rect2i(pixel-Vector2i(3,3),Vector2i(7,7)),Color("b18c62"))

func _vegetation() -> void:
	var groups := {}
	var trees := Node3D.new()
	trees.name = "TreesGenerated"
	world.add_child(trees)
	var colliders := StaticBody3D.new()
	colliders.name = "TreeColliders"
	trees.add_child(colliders)
	var plants := Node3D.new()
	plants.name = "PlantsGenerated"
	world.add_child(plants)
	var density: float = [.23,.48,.72][int(config.forest)]
	for x in range(-side/2+5,side/2-5,4):
		for z in range(-side/2+5,side/2-5,4):
			var p := Vector2(x+rng.randf_range(-1.5,1.5),z+rng.randf_range(-1.5,1.5))
			var h := height_at(p)
			if river_distance(p) < river_width+2 or on_road(p,2): continue
			var occupied := false
			for site in sites:
				if p.distance_to(site)<10: occupied = true; break
			for village in villages:
				if p.distance_to(village.p)<26: occupied = true; break
			if occupied: continue
			var patch := forest_noise.get_noise_2d(p.x,p.y)
			if rng.randf() > density+patch*.7: continue
			var kind := ("pine%d" % rng.randi_range(0,5)) if patch > .12 or int(config.landscape)==2 else ("oak%d" % rng.randi_range(0,2))
			var key := "tree_%s_%d_%d" % [kind,floori(p.x/24),floori(p.y/24)]
			if not groups.has(key): groups[key] = []
			var transform := Transform3D(Basis(Vector3.UP,rng.randf_range(-PI,PI)).scaled(Vector3.ONE*rng.randf_range(.75,1.10)),Vector3(p.x,h,p.y))
			var index: int = groups[key].size()
			groups[key].append(transform)
			var shape := CollisionShape3D.new()
			shape.name = "tree_%s_%d" % [kind,index]
			var cylinder := CylinderShape3D.new()
			cylinder.radius = .4
			cylinder.height = 5
			shape.shape = cylinder
			shape.position = transform.origin+Vector3.UP*2.5
			shape.set_meta("tree",{"chunk":key,"index":index,"mesh":kind,"pos":[p.x,h,p.y],"yaw":transform.basis.get_euler().y,"scale":transform.basis.get_scale().x})
			colliders.add_child(shape)
			if forests.size() < 80 and rng.randf()<.10: forests.append(transform.origin+Vector3.UP*2)
	for key: String in groups:
		voxel.mm_by_prefix[key] = []
		var parts := key.split("_")
		var center := Vector3(int(parts[2])*24+12,0,int(parts[3])*24+12)
		# Cell-local LODs preserve matching instance indices for chopping and save restoration.
		for lod in 4:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = load("res://generated/tree_%s_lod%d.res" % [parts[1],lod])
			mm.instance_count = groups[key].size()
			for i in mm.instance_count:
				var transform: Transform3D = groups[key][i]
				transform.origin -= center
				mm.set_instance_transform(i,transform)
			var mesh := MultiMeshInstance3D.new()
			mesh.name = key+"_l%d" % lod
			mesh.multimesh = mm
			mesh.position = center
			mesh.visibility_range_begin = [0,25,55,100][lod]
			mesh.visibility_range_end = [25,55,100,0][lod]
			mesh.visibility_range_begin_margin = 3
			mesh.visibility_range_end_margin = 3
			if lod >= 2: mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			trees.add_child(mesh)
			voxel.mm_by_prefix[key].append(mesh)
	if forests.is_empty(): forests.append(Vector3(half*.6,height_at(Vector2(half*.6,0)),0))
	for kind in ["grass_a","daisy","bluebell","fern","buttercup"]:
		var transforms: Array[Transform3D] = []
		for i in side*5:
			var p := Vector2(rng.randf_range(-half+2,half-2),rng.randf_range(-half+2,half-2))
			if river_distance(p)<river_width+1 or on_road(p,1): continue
			var occupied := false
			for village in villages:
				if p.distance_to(village.p)<24: occupied = true
			if occupied: continue
			transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU),Vector3(p.x,height_at(p),p.y)))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = load("res://generated/plant_%s_lod0.res" % kind)
		mm.instance_count = transforms.size()
		for i in transforms.size(): mm.set_instance_transform(i,transforms[i])
		var mesh := MultiMeshInstance3D.new()
		mesh.multimesh = mm
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plants.add_child(mesh)
		var cells := {}
		for transform: Transform3D in transforms:
			cells[Vector2i(floori(transform.origin.x/16),floori(transform.origin.z/16))] = true
		for cell: Vector2i in cells:
			if not voxel.plant_cells.has(cell): voxel.plant_cells[cell] = []
			voxel.plant_cells[cell].append(mesh)

func _markers() -> void:
	var village: Dictionary = villages[0]
	var p: Vector2 = village.p
	var h := float(village.h)
	var markers := {"spawn":[p.x,h+1,p.y-5],"npc_market":[p.x-1,h,p.y-7],"npc_square":[p.x+2,h,p.y+7],
		"npc_bridge":[p.x,h,p.y+13],"npc_castle":[p.x+19,h,p.y+8],"runes":[],"treasures":[],"waterfalls":[],
		"crates":[],"build_site":[p.x-23,h,p.y+20]}
	for site in camps+ruins: markers.crates.append([site.p.x,float(site.h),site.p.y+2])
	markers.crates.resize(2)
	for i in 8:
		var site := sites[i%sites.size()]+Vector2(6 if i%2 == 0 else -6,7)
		markers.runes.append([site.x,height_at(site),site.y])
	for cave in caves: markers.treasures.append([cave.p.x,float(cave.h)-.5,cave.p.y+9])
	data.markers = markers

func _distant_landscape() -> void:
	# Scenic terrain continues beyond the explicitly bounded, editable map.
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(-640,640,8):
		for z in range(-640,640,8):
			if x >= -half and x < half and z >= -half and z < half: continue
			var points: Array[Vector3] = []
			for offset: Vector2 in [Vector2(0,0),Vector2(0,8),Vector2(8,8),Vector2(8,0)]:
				var p := Vector2(x,z)+offset
				var distance := maxf(absf(p.x),absf(p.y))
				var h := height_at(p)+smoothstep(half+24,half+250,distance)*(18+absf(noise.get_noise_2d(p.x*.5+700,p.y*.5))*95)
				points.append(Vector3(p.x,snappedf(h,2.0),p.y))
			for i in [0,1,2,0,2,3]:
				var p: Vector3 = points[i]
				var color := Color("4f813d").lerp(Color("81877a"),smoothstep(20,90,p.y))
				surface_tool.set_color(color)
				surface_tool.add_vertex(p)
	surface_tool.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "DistantHills"
	mesh.mesh = surface_tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mesh)
