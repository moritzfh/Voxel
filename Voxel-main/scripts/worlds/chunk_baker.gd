extends RefCounted
## Each worker owns its volume, noise and physics shape. Only scene/GPU uploads run on the main thread.
const LAND := preload("res://scripts/worlds/infinite_land.gd")
var land: RefCounted
var vol: VoxelVolume
var key := Vector2i.ZERO
var vs := .125
var count := 128
var ylo := 0
var cy := 0
var x0 := 0.0
var z0 := 0.0
var solid := PackedByteArray()
var water := PackedByteArray()
var hard := PackedByteArray()
var cache_dir := ""
const CACHE_REVISION := 10
const SCATTER := preload("res://scripts/worlds/scatter_plan.gd")

func setup(options: Dictionary, s: PackedByteArray, w: PackedByteArray, h: PackedByteArray) -> void:
	land = LAND.new()
	land.setup(options)
	solid = s; water = w; hard = h
	var signature := []
	for name in ["seed","size","landscape","forest","rivers","villages","caves","ruins","encounter_version","terrain_version"]:
		signature.append(options.get(name,0))
	signature.append(CACHE_REVISION)
	signature.append(s); signature.append(w); signature.append(h)
	cache_dir = "user://worlds/terrain-cache/%s" % var_to_bytes(signature).hex_encode().sha256_text().left(24)
	DirAccess.make_dir_recursive_absolute(cache_dir)

func bake(at: Vector2i, fine := true, edited: Array = []) -> Dictionary:
	key = at
	var started := Time.get_ticks_usec()
	var edit_hash := hash(edited) if not edited.is_empty() else 0
	var path := "%s/%d_%d_%d_%s.bin" % [cache_dir,key.x,key.y,int(fine),edit_hash]
	var cached := read_cache(path,key,fine)
	if not cached.is_empty():
		cached.cache_hit = true
		cached.work_us = Time.get_ticks_usec()-started
		return prepare_physics(cached)
	vs = .125 if fine else .5
	count = 128 if fine else 32
	x0 = key.x*16.0
	z0 = key.y*16.0
	var columns := PackedFloat32Array()
	columns.resize(count*count)
	var types := PackedByteArray()
	types.resize(count*count)
	var min_h := INF
	var max_h := -INF
	var nearby := nearby_layouts()
	# Quarter-metre height sampling is interpolated onto the fine voxel grid.
	var grid := PackedFloat32Array()
	grid.resize(33*33)
	for x in 33:
		for z in 33: grid[x*33+z] = land.height(Vector2(x0+x*.5,z0+z*.5))
	var surface_grid := PackedByteArray()
	surface_grid.resize(33*33)
	if land.modern:
		for x in 33:
			for z in 33:
				var slope := absf(grid[mini(32,x+1)*33+z]-grid[maxi(0,x-1)*33+z])+absf(grid[x*33+mini(32,z+1)]-grid[x*33+maxi(0,z-1)])
				surface_grid[x*33+z] = land.surface(Vector2(x0+x*.5,z0+z*.5),grid[x*33+z],slope)
	for x in count:
		for z in count:
			var p := Vector2(x0+(x+.5)*vs,z0+(z+.5)*vs)
			var fx := (x+.5)*vs*2
			var fz := (z+.5)*vs*2
			var ix := mini(31,floori(fx))
			var iz := mini(31,floori(fz))
			var h := snappedf(lerpf(lerpf(grid[ix*33+iz],grid[(ix+1)*33+iz],fx-ix),lerpf(grid[ix*33+iz+1],grid[(ix+1)*33+iz+1],fx-ix),fz-iz),vs)
			var material := 1
			if land.modern:
				material = surface_grid[roundi(fx)*33+roundi(fz)]
			else:
				var river_d: float = land.river_distance(p)
				if river_d<8: material = 22 if h<3 else 21
				elif land.road(p): material = 3
			columns[x*count+z] = h
			types[x*count+z] = material
			min_h = minf(min_h,h)
			max_h = maxf(max_h,h)
	for layout in nearby:
		for cave in layout.caves:
			if Rect2(Vector2(x0,z0),Vector2(16,16)).grow(17).has_point(cave.p): min_h = minf(min_h,float(cave.h)-1)
	ylo = floori((min_h-2)/vs)
	cy = ceili((maxf(max_h,3.0 if land.modern else max_h)+10)/vs)-ylo
	var carved := false
	for layout in nearby:
		for cave in layout.caves:
			if Rect2(Vector2(x0,z0),Vector2(16,16)).grow(17).has_point(cave.p): carved = true
	var raw := fast_terrain(columns,types) if land.modern and not carved else PackedByteArray()
	if raw.is_empty():
		raw.resize(count*cy*count)
		for x in count:
			for z in count:
				var h := columns[x*count+z]
				var top := roundi(h/vs)-ylo
				var p := Vector2(x0+(x+.5)*vs,z0+(z+.5)*vs)
				var hollow := Vector2(-100,-100)
				for layout in nearby:
					for cave in layout.caves:
						var local: Vector2 = p-cave.p
						if absf(local.x)<1.8 and local.y>-12 and local.y<9: hollow = Vector2(float(cave.h),float(cave.h)+3.2)
						var d := local.distance_to(Vector2(0,8))
						if d<4.8: hollow = Vector2(float(cave.h),maxf(hollow.y,float(cave.h)+sqrt(maxf(0,1-pow(d/4.8,2)))*4))
				for y in top:
					var wy := (ylo+y)*vs
					if wy>=hollow.x and wy<hollow.y: continue
					var m := 4 if y<top-roundi(.6/vs) else 2
					if y>=top-maxi(1,roundi(.15/vs)): m = int(types[x*count+z])
					var gx := key.x*count+x
					var gz := key.y*count+z
					var variant := 0 if land.modern else ((gx*13 ^ gz*7 ^ y*3)&1023)%4
					raw[(x*cy+y)*count+z] = (m<<2)|variant
				if h<3 and (land.modern or land.config.rivers):
					for y in range(top,roundi(3/vs)-ylo): raw[(x*cy+y)*count+z] = 33<<2

	vol = VoxelVolume.new()
	vol.setup(Vector3.ZERO,vs,count)
	vol.set_tables(solid,water,hard,16)
	vol.load_chunk(0,0,ylo,cy,raw)
	for layout in nearby: architecture(layout,fine)
	if not edited.is_empty():
		var bytes: PackedByteArray = edited[3].decompress(int(edited[2]),FileAccess.COMPRESSION_ZSTD)
		vol.load_chunk(0,0,int(edited[0]),int(edited[1]),bytes)
	var range_y := vol.get_chunk_range(0,0)
	var lo := Vector3i(0,range_y.x,0)
	var size := Vector3i(count,range_y.y,count)
	var result := {"key":key,"fine":fine,"ylo":range_y.x,"cy":range_y.y,"vs":vs,
		"raw":vol.get_chunk_data(0,0),"mesh":vol.mesh_region(lo,size,0,false,not land.modern,Vector3.ZERO),
		"water":vol.mesh_region(lo,size,0,true,false,Vector3.ZERO),"collision":terrain_collision(grid) if land.modern and not carved and edited.is_empty() and not has_structures(nearby) else vol.collision_region(lo,size,Vector3.ZERO)}
	vol = null
	result.layouts = []
	var region_key: Vector2i = land.region_of(Vector2(x0+8,z0+8))
	for dx in range(-1,2):
		for dz in range(-1,2): result.layouts.append(land.region(region_key+Vector2i(dx,dz)))
	result.height_grid = grid
	result.scatter = SCATTER.build(land,key,fine)
	result.cache_revision = CACHE_REVISION
	write_cache(path,result)
	result.cache_hit = false
	result.work_us = Time.get_ticks_usec()-started
	if land.modern: land.biomes.trim(Vector2(x0,z0))
	if land.regions.size()>25:
		var here: Vector2i = land.region_of(Vector2(x0+8,z0+8))
		for region in land.regions.keys():
			if (Vector2(region)-Vector2(here)).length()>3: land.regions.erase(region)
	return prepare_physics(result)

func nearby_layouts() -> Array:
	var center := Vector2(x0+8,z0+8)
	var region: Vector2i = land.region_of(center)
	var layouts := []
	for dx in range(-1,2):
		for dz in range(-1,2):
			var k := region+Vector2i(dx,dz)
			if Rect2(Vector2(k)*land.span,Vector2.ONE*land.span).grow(16).has_point(center): layouts.append(land.region(k))
	return layouts

func box(center: Vector3, size: Vector3, material: int) -> void:
	var start := center-size*.5-Vector3(x0,0,z0)
	var end := center+size*.5-Vector3(x0,0,z0)-Vector3.ONE*.001
	var a := Vector3i(floori(start.x/vs),floori(start.y/vs),floori(start.z/vs))
	var b := Vector3i(floori(end.x/vs),floori(end.y/vs),floori(end.z/vs))
	if b.x<0 or b.z<0 or a.x>=count or a.z>=count: return
	for x in range(maxi(0,a.x),mini(count-1,b.x)+1):
		for y in range(a.y,b.y+1):
			for z in range(maxi(0,a.z),mini(count-1,b.z)+1): vol.set_voxel(Vector3i(x,y,z),(material<<2)|(0 if land.modern else ((x*3^y*7^z*13)&3)) if material else 0)

func fence(rect: Rect2, h: float, gate_x: float) -> void:
	for z in [rect.position.y,rect.end.y]:
		for x in range(ceili(rect.position.x),floori(rect.end.x)+1):
			if z==rect.position.y and absf(x-gate_x)<1.1: continue
			for y in [.5,1.0]: box(Vector3(x,h+y,z),Vector3(1.1,.125,.125),11)
		for x in range(ceili(rect.position.x),floori(rect.end.x)+1,2):
			if z==rect.position.y and absf(x-gate_x)<1.1: continue
			box(Vector3(x,h+.65,z),Vector3(.25,1.3,.25),15)
	for x in [rect.position.x,rect.end.x]:
		for y in [.5,1.0]: box(Vector3(x,h+y,rect.get_center().y),Vector3(.125,.125,rect.size.y),11)
		for z in range(ceili(rect.position.y),floori(rect.end.y)+1,2): box(Vector3(x,h+.65,z),Vector3(.25,1.3,.25),15)

func architecture(layout: Dictionary, fine: bool) -> void:
	var bounds := Rect2(x0,z0,16,16)
	for house in layout.houses:
		if not bounds.grow(6).has_point(house.p): continue
		var p := Vector3(house.p.x,float(house.h),house.p.y)
		var wall := 10 if int(house.style)!=1 else 62
		var roof := 14 if int(house.style)==0 else 61
		box(p+Vector3(0,.1,0),Vector3(7,.25,7),8)
		for x in [-3.4,3.4]: box(p+Vector3(x,1.9,0),Vector3(.25,3.8,7),wall)
		for z in [-3.4,3.4]: box(p+Vector3(0,1.9,z),Vector3(7,3.8,.25),wall)
		for x in [-3.4,0,3.4]:
			for z in [-3.4,3.4]: box(p+Vector3(x,2,z),Vector3(.25,4,.3),11)
		for x in [-3.4,3.4]:
			for z in [-3.4,0,3.4]: box(p+Vector3(x,2,z),Vector3(.3,4,.25),11)
		for y in [.4,3.6]:
			for z in [-3.4,3.4]: box(p+Vector3(0,y,z),Vector3(7,.25,.35),11)
		for layer in range(0,25 if fine else 7):
			var step := .125 if fine else .5
			box(p+Vector3(0,3.9+layer*step,0),Vector3(8-layer*step*2,step,8),roof)
		box(p+Vector3(-2,5.8,-2),Vector3(.75,3,.75),6)
		var side: int = house.side
		box(p+Vector3(side*3.4,1.45,0),Vector3(.8,2.8,1.4),0)
		box(p+Vector3(side*3.8,.08,0),Vector3(.9,.25,1.9),8)
		for x in [-1.7,1.7]:
			for z in [-3.45,3.45]:
				box(p+Vector3(x,2,z),Vector3(1.15,1.4,.4),29)
				if fine:
					box(p+Vector3(x,2,z),Vector3(.125,1.5,.45),11)
					box(p+Vector3(x,2,z),Vector3(1.3,.125,.45),11)
					for sign_value in [-1,1]: box(p+Vector3(x+sign_value*.8,2,z),Vector3(.375,1.6,.25),12)
					box(p+Vector3(x,1.1,z*1.03),Vector3(1.5,.35,.5),12)
					for flower in range(-2,3): box(p+Vector3(x+flower*.25,1.4,z*1.03),Vector3(.125,.3,.125),46 if flower%2 else 45)
		if fine:
			box(p+Vector3(side*3.65,2.5,1.1),Vector3(.3,.5,.3),28)
			box(p+Vector3(1,.65,2),Vector3(2,.25,1),12)
			for x in [.3,1.7]: box(p+Vector3(x,.3,2),Vector3(.25,.7,.75),11)
			box(p+Vector3(-2,.6,-2),Vector3(1.5,1.2,2),31)
			box(p+Vector3(-2,1.3,-2),Vector3(1.5,.25,2),23)
			for sign_value in [-1,1]: box(p+Vector3(side*4.4,.5,sign_value*2.5),Vector3(.75,1,.75),32)
	for village in layout.villages:
		if not bounds.grow(32).has_point(village.p): continue
		var h := float(village.h)
		var pen: Rect2 = village.pen
		var field: Rect2 = village.field
		fence(pen,h,pen.get_center().x)
		fence(field,h,field.get_center().x)
		var p := Vector3(village.p.x-2.7,h,village.p.y+3)
		box(p+Vector3(0,.4,0),Vector3(2.5,.8,2.5),8)
		box(p+Vector3(0,.8,0),Vector3(1.8,.7,1.8),0)
		box(p+Vector3(0,.5,0),Vector3(1.6,.125,1.6),33)
		for x in [-1,1]: box(p+Vector3(x,1.8,0),Vector3(.25,3.5,.25),11)
		box(p+Vector3(0,3.3,0),Vector3(3.5,.25,3),14)
		var coop := Vector3(pen.end.x-2,h,pen.end.y-2)
		box(coop+Vector3(0,.8,0),Vector3(2.5,1.6,2.5),12)
		box(coop+Vector3(0,1.8,0),Vector3(3,.375,3),14)
		box(coop+Vector3(0,.7,-1.3),Vector3(.75,1,.5),0)
		box(Vector3(pen.get_center().x,h+.2,pen.position.y+2),Vector3(2,.4,.7),13)
		if fine:
			for x in range(ceili(field.position.x)+1,floori(field.end.x)):
				for z in range(ceili(field.position.y)+1,floori(field.end.y)):
					box(Vector3(x,h+.4,z),Vector3(.125,.8,.125),49)
					box(Vector3(x,h+.85,z),Vector3(.25,.25,.25),45)
			var market := Vector3(village.p.x+2.5,h,village.p.y+7)
			box(market+Vector3(0,.9,0),Vector3(2.5,.25,1.5),12)
			for x in [-1.3,1.3]: box(market+Vector3(x,1.4,0),Vector3(.125,2.8,.125),11)
			box(market+Vector3(0,2.7,0),Vector3(3,.125,2),34)
			for x in [-.7,0,.7]: box(market+Vector3(x,1.15,0),Vector3(.375,.25,.375),46 if x<0 else 45)
	# Bridges are part of the voxel volume and span every road/river intersection.
	if land.config.rivers:
		for x in range(int(x0),int(x0)+16):
			for z in range(int(z0),int(z0)+16):
				var p := Vector2(x+.5,z+.5)
				if land.region_of(p)!=layout.key: continue
				if land.river_distance(p)>10 or not land.road(p): continue
				box(Vector3(p.x,5.15,p.y),Vector3(1.2,.3,1.2),12)
				if fine and (x+z)%3==0: box(Vector3(p.x,3.6,p.y),Vector3(.25,3,.25),15)
				if fine:
					var distance := INF
					var direction := Vector2.RIGHT
					for path in layout.roads:
						for i in path.size()-1:
							var nearest := Geometry2D.get_closest_point_to_segment(p,path[i],path[i+1])
							var d := p.distance_to(nearest)
							if d<distance:
								distance = d
								direction = (path[i+1]-path[i]).normalized()
					if distance>1.1:
						box(Vector3(p.x,5.85,p.y),Vector3(.125,.125,1.2) if absf(direction.y)>.5 else Vector3(1.2,.125,.125),11)
						if (x+z)%2==0: box(Vector3(p.x,5.65,p.y),Vector3(.25,1,.25),15)
	for cave in layout.caves:
		if not bounds.grow(10).has_point(cave.p): continue
		for i in 8:
			var angle := i*TAU/8
			if absf(cos(angle))<.3: continue
			box(Vector3(cave.p.x+cos(angle)*3.5,float(cave.h)+.8,cave.p.y+8+sin(angle)*3.5),Vector3(.25,1.6,.25),59)
	for dungeon in layout.get("dungeons",[]):
		if not bounds.grow(19).has_point(dungeon.p): continue
		var p := Vector3(dungeon.p.x,float(dungeon.h),dungeon.p.y)
		if dungeon.species=="cyclops":
			box(p+Vector3(0,.1,0),Vector3(18,.25,20),8)
			for x in [-8.5,8.5]:
				box(p+Vector3(x,3,0),Vector3(.75,6,20),9)
				for z in [-8,-4,0,4,8]: box(p+Vector3(x,3,z),Vector3(1.25,6.5,1.25),8)
			box(p+Vector3(0,3,9.5),Vector3(18,6,.75),9)
			for x in [-6.0,6.0]: box(p+Vector3(x,3,-9.5),Vector3(6,6,.75),9)
			box(p+Vector3(0,5.5,-9.5),Vector3(6,1.5,1),8)
			for x in [-6.5,6.5]: box(p+Vector3(x,6.25,0),Vector3(5,.5,20),8)
			for z in [-7.5,7.5]: box(p+Vector3(0,6.25,z),Vector3(8,.5,5),8)
			for x in [-7,7]: box(p+Vector3(x,1.2,6),Vector3(.5,2.4,.5),59)
		else:
			var material := 21 if dungeon.species=="sandworm" else 4
			for x in range(-16,17):
				for z in range(-16,17):
					if Vector2(x,z).length()>16: continue
					box(p+Vector3(x,.08,z),Vector3(1,.25,1),material)
			for i in 12:
				var a := i*TAU/12
				if absf(cos(a))<.2 and sin(a)<0: continue
				var pillar := p+Vector3(cos(a)*16,1.5,sin(a)*16)
				box(pillar,Vector3(1.5,3+float(i%3),1.5),8 if material==4 else 23)
				if fine: box(pillar+Vector3(0,2,0),Vector3(.5,.75,.5),28 if material==4 else 54)
	for ruin in layout.ruins:
		if not bounds.grow(6).has_point(ruin.p): continue
		var p := Vector3(ruin.p.x,float(ruin.h),ruin.p.y)
		box(p,Vector3(8,.25,8),8)
		for x in [-3.7,3.7]:
			for z in range(-3,4): box(p+Vector3(x,1.6,z),Vector3(.5,2.5+float((z+3)%3)*.5,1),9)
		for x in [-2.5,2.5]: box(p+Vector3(x,1.8,-3.7),Vector3(2,3.6,.5),8)
		box(p+Vector3(0,3.5,-3.7),Vector3(4,1,.5),9)
		box(p+Vector3(0,1,1),Vector3(.5,2,.5),59)
	for camp in layout.camps:
		if not bounds.grow(5).has_point(camp.p): continue
		var p := Vector3(camp.p.x,float(camp.h),camp.p.y)
		box(p+Vector3(0,.15,0),Vector3(2,.3,2),8)
		box(p+Vector3(0,.5,0),Vector3(.5,.7,.5),28)
		for x in [-2,2]: box(p+Vector3(x,.4,0),Vector3(.5,.8,3),15)

func read_cache(path: String, at: Vector2i, fine: bool) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
	if not file: return {}
	var value: Variant = file.get_var(false)
	if not value is Dictionary: return {}
	if value.get("cache_revision",0)!=CACHE_REVISION or value.get("key")!=at or value.get("fine")!=fine: return {}
	for field in ["raw","mesh","water","collision","scatter","layouts","height_grid","ylo","cy","vs"]:
		if not value.has(field): return {}
	var width := 128 if fine else 32
	if not value.raw is PackedByteArray or int(value.cy)<=0 or value.raw.size()!=width*width*int(value.cy): return {}
	if not value.height_grid is PackedFloat32Array or value.height_grid.size()!=1089: return {}
	if not value.collision is PackedVector3Array or not value.scatter is Dictionary: return {}
	return value

func write_cache(path: String, result: Dictionary) -> void:
	# Unique temporary files make simultaneous synchronous/background requests safe.
	var temporary := path+".%d.tmp" % Time.get_ticks_usec()
	var file := FileAccess.open_compressed(temporary,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
	if not file: return
	file.store_var(result,false)
	file.close()
	if DirAccess.rename_absolute(temporary,path)!=OK: DirAccess.remove_absolute(temporary)

func fast_terrain(columns: PackedFloat32Array, types: PackedByteArray) -> PackedByteArray:
	var raw := PackedByteArray()
	var dirt := maxi(1,roundi(.6/vs))
	var skin := maxi(1,roundi(.15/vs))
	for x in count:
		var low := cy
		for z in count: low = mini(low,roundi(columns[x*count+z]/vs)-ylo-dirt)
		low = maxi(0,low)
		var foundation := PackedByteArray()
		foundation.resize(low*count)
		foundation.fill(4<<2)
		raw.append_array(foundation)
		var upper := PackedByteArray()
		upper.resize((cy-low)*count)
		for z in count:
			var h := columns[x*count+z]
			var top := roundi(h/vs)-ylo
			for y in range(low,top):
				var m := 4 if y<top-dirt else 2
				if y>=top-skin: m = types[x*count+z]
				upper[(y-low)*count+z] = m<<2
			if h<3:
				for y in range(top,roundi(3/vs)-ylo): upper[(y-low)*count+z] = 33<<2
		raw.append_array(upper)
	return raw

func has_structures(layouts: Array) -> bool:
	var bounds := Rect2(x0,z0,16,16)
	for layout in layouts:
		for house in layout.houses:
			if bounds.grow(6).has_point(house.p): return true
		for village in layout.villages:
			if bounds.grow(32).has_point(village.p): return true
		for site in layout.caves+layout.ruins+layout.camps+layout.get("dungeons",[]):
			if bounds.grow(20).has_point(site.p): return true
	# Bridges keep their precise walkable decks and railings.
	if land.config.rivers:
		for x in range(0,17,4):
			for z in range(0,17,4):
				var p := Vector2(x0+x,z0+z)
				if land.river_distance(p)<12 and land.road(p): return true
	return false

func terrain_collision(grid: PackedFloat32Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	faces.resize(32*32*6)
	var index := 0
	var base := ylo*vs
	for x in 32:
		for z in 32:
			var a := Vector3(x*.5,grid[x*33+z]-base,z*.5)
			var b := Vector3((x+1)*.5,grid[(x+1)*33+z]-base,z*.5)
			var c := Vector3((x+1)*.5,grid[(x+1)*33+z+1]-base,(z+1)*.5)
			var d := Vector3(x*.5,grid[x*33+z+1]-base,(z+1)*.5)
			for p in [a,b,c,a,c,d]: faces[index] = p; index += 1
	return faces

func prepare_physics(result: Dictionary) -> Dictionary:
	# Unique physics resources are prepared off the scene tree, after serializing plain cache data.
	var started := Time.get_ticks_usec()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(result.collision)
	result.physics = shape
	result.work_us = int(result.get("work_us",0))+Time.get_ticks_usec()-started
	return result
