extends Node
signal progress(message: String,fraction: float)
const LAND := preload("res://scripts/worlds/infinite_land.gd")
const BAKER := preload("res://scripts/worlds/chunk_baker.gd")
const VX := preload("res://scripts/voxel/voxel_world.gd")
var land: RefCounted
var voxel: Node3D
var world: Node3D
var main: Node
var data := {}
var config := {}
var chunks := {}
var archived := {}
var queue: Array = []
var wanted := {}
var workers: Array = []
var map_image: Image
var water_image: Image
var stream_ready := false
var life: Node3D
var _center := Vector2i(2147483647,2147483647)
var _timer := 0.0
var _map_timer := 0.0
var _last_safe := Vector3.ZERO
var _tree_meshes := {}
var remote_interests := {}
var completed: Array = []
var decorating: Array = []
var cache_hits := 0
var generated_chunks := 0
var max_install_us := 0
var max_decoration_us := 0
var max_horizon_us := 0
var _map_row := 128
var _map_column := 0
var _map_center := Vector2.ZERO
var _map_work: Image
var _unload_pending: Array = []
var _horizon_baker: RefCounted
var _horizon_thread: Thread
var _horizon_center := Vector2i(2147483647,2147483647)
var _horizon_root: Node3D
var _coverage_image: Image
var _coverage_texture: ImageTexture
var _coverage_origin := Vector2i.ZERO
var _coverage_dirty := false
var _horizon_materials: Array = []


func generate(root: Node3D, terrain: Node3D, options: Dictionary, template: Dictionary) -> Dictionary:
	world = root
	voxel = terrain
	main = world.get_parent()
	config = options.duplicate(true)
	land = LAND.new()
	land.setup(config)
	var spawn: Vector3 = land.spawn()
	var home := spawn
	if Worlds.continuing and not Worlds.remote:
		var file := FileAccess.open(Worlds.save_path(),FileAccess.READ)
		if file:
			var save: Variant = file.get_var(false)
			if save is Dictionary:
				var p: Array = save.get("pos",[spawn.x,spawn.y,spawn.z])
				spawn = Vector3(p[0],p[1]+.2,p[2])
				archived = save.get("world",{}).duplicate(true)
	elif Worlds.remote and not Worlds.join_spawn.is_empty():
		var p: Array = Worlds.join_spawn
		spawn = Vector3(p[0],p[1],p[2])
	data = {"procedural":true,"streamed":true,"descriptor":config.duplicate(true),"materials":template.materials,"models_vox":template.models_vox,
		"home_spawn":[home.x,home.y,home.z],
		"near_vox":{"origin":[0,0,0],"vs":.125,"chunks":[]},"bounds":[spawn.x-128,spawn.x+128,spawn.z-128,spawn.z+128],
		"markers":{"spawn":[spawn.x,spawn.y,spawn.z],"runes":[],"treasures":[],"waterfalls":[],"crates":[],"build_site":[spawn.x-23,spawn.y,spawn.z+20]},
		"houses":[],"villages":land.region(land.region_of(Vector2(spawn.x,spawn.z))).villages,"caves":[],"roads":[],"bridges":[],"landmarks":[],"river":[],"forests":[]}
	voxel.setup(world,data)
	for camp in land.region(Vector2i.ZERO).camps:
		data.markers.crates.append([camp.p.x+1,float(camp.h),camp.p.y+2])
	if data.markers.crates.size()<2:
		var village: Dictionary = land.region(Vector2i.ZERO).villages[0]
		for side in [-1,1]:
			if data.markers.crates.size()>=2: break
			data.markers.crates.append([village.p.x+side*3,float(village.h),village.p.y+14])
	voxel.stream_provider = self
	# Apply the chosen render format before warming GPU pipelines, not after world creation.
	main._apply_graphics(int(Settings.values.graphics))
	main.env.environment.sdfgi_enabled = bool(Settings.values.gi) and main.gfx_level>=2
	main.env.environment.ssao_enabled = bool(Settings.values.ssao) and main.gfx_level>=1
	main.env.environment.glow_enabled = bool(Settings.values.glow)
	main.sun.shadow_enabled = bool(Settings.values.shadows)
	main.get_viewport().msaa_3d = [Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X,Viewport.MSAA_8X][int(Settings.values.aa)]
	voxel.vmat = voxel.vmat.duplicate()
	voxel.vmat.set_shader_parameter("natural_surfaces",land.modern)
	voxel.wmat = voxel.wmat.duplicate()
	var water_params := {"shallow_tint":Color(.5,.86,.92),"deep_color":Color(.03,.27,.46),"foam_color":Color(.92,.97,1),"absorption":.75,"refraction":.035,"flow":Vector2(-.25,1),"pixel_density":8.0}
	for parameter in water_params: voxel.wmat.set_shader_parameter(parameter,water_params[parameter])
	# Load reusable resources while the loading screen is visible, never on a sprint frame.
	for kind in ["pine0","pine1","pine2","pine3","pine4","pine5","oak0","oak1","oak2"]:
		for lod in [0,1,3]:
			var path := "res://generated/tree_%s_lod%d.res" % [kind,lod]
			_tree_meshes[path] = load(path)
	for kind in ["plant_grass_a","plant_daisy","plant_fern","plant_bluebell","plant_lily","rock_stone_a","rock_pebble_b","rock_boulder_a","rock_boulder_b","rock_boulder_c","rock_boulder_d","rock_boulder_e","rock_boulder_f"]:
		for lod in [0,1]:
			var path := "res://generated/%s_lod%d.res" % [kind,lod]
			_tree_meshes[path] = load(path)
	for kind in ["bird","bee","bear","wolf","rabbit","turtle","chicken","chick","goblin","witch","bandit","cyclops","dragon","sandworm"]:
		preload("res://scripts/wildlife/models.gd").warm(kind)
		await get_tree().process_frame
	for i in clampi(OS.get_processor_count()/4,2,3):
		var baker := BAKER.new()
		baker.setup(config,voxel.solid,voxel.water,voxel.hard)
		workers.append({"thread":null,"baker":baker,"key":Vector2i.ZERO,"fine":false})
	if land.modern:
		_horizon_baker = preload("res://scripts/worlds/terrain_horizon.gd").new()
		_horizon_baker.setup(config,workers[0].baker.cache_dir)
		_coverage_image = Image.create(128,128,false,Image.FORMAT_R8)
		_coverage_image.fill(Color.BLACK)
		_coverage_texture = ImageTexture.create_from_image(_coverage_image)
	_last_safe = spawn
	var center := chunk_of(spawn)
	var initial := {}
	for x in range(-1,2):
		for z in range(-1,2): initial[center+Vector2i(x,z)] = true
	wanted = initial.duplicate()
	for key in initial: queue.append({"key":key,"fine":true})
	while true:
		_pump()
		_pump_horizon()
		var loaded := 0
		for key in initial:
			if chunks.has(key) and chunks[key].fine and chunks[key].get("decorated",false): loaded += 1
		progress.emit("Feine Voxelwelt und Dorf laden …",.05+.85*loaded/9.0)
		if loaded==9 and (not land.modern or (_horizon_root!=null and _horizon_thread==null)): break
		await get_tree().process_frame
	await _warm_rendering()
	main.player.water_provider = land
	main.player.infinite_world = true
	main.player.stream_world = self
	_refresh_metadata(spawn)
	stream_ready = true
	return data


func attach_game() -> void:
	life = Node3D.new()
	life.name = "VillageLife"
	life.set_script(load("res://scripts/worlds/village_life.gd"))
	main.add_child(life)
	life.setup(main,self)
	for key in chunks:
		if chunks[key].fine: life.load_chunk(key)
	_retarget()


func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x/16),floori(p.z/16))


func _process(delta: float) -> void:
	if not stream_ready: return
	_pump()
	_pump_map()
	_pump_horizon()
	if not _unload_pending.is_empty():
		var key: Vector2i = _unload_pending.pop_front()
		if not wanted.has(key): unload_chunk(key)
	_timer -= delta
	if _timer<=0:
		_timer = .4
		_retarget()
	_map_timer -= delta
	if chunk_of(main.player.global_position)!=_center and _map_timer<=0 and _map_row>=128:
		_map_timer = 2
		_refresh_metadata(main.player.global_position)


func _retarget() -> void:
	var points: Array[Vector3] = [main.player.global_position]
	if Net.is_host():
		for id in main.remotes:
			if remote_interests.has(id): points.append(remote_interests[id])
			elif main.remotes[id].visible: points.append(main.remotes[id].global_position)
	wanted.clear()
	var fine := {}
	# Prepare the direction of travel several seconds ahead, including fine collision terrain.
	var velocity: Vector3 = main.player.velocity
	var prediction: Vector3 = main.player.global_position+Vector3(velocity.x,0,velocity.z)*3.0
	var projected := chunk_of(prediction)
	for x in range(-3,4):
		for z in range(-3,4):
			var key := projected+Vector2i(x,z)
			wanted[key] = true
			if abs(x)<=2 and abs(z)<=2: fine[key] = true
	for point in points:
		var center := chunk_of(point)
		for x in range(-5,6):
			for z in range(-5,6):
				var key := center+Vector2i(x,z)
				wanted[key] = true
				if abs(x)<=2 and abs(z)<=2: fine[key] = true
	# Drop obsolete pending work when players move, and prioritize fine terrain.
	queue.clear()
	var missing := []
	for key in wanted:
		var detail: bool = fine.has(key)
		if chunks.has(key) and (chunks[key].fine or not detail): continue
		var working := false
		for worker in workers:
			if worker.thread!=null and worker.key==key and (worker.fine or not detail): working = true
		for result in completed:
			if result.key==key and (result.fine or not detail): working = true
		if working: continue
		var distance := INF
		for point in points: distance = minf(distance,Vector2(key).distance_squared_to(Vector2(chunk_of(point))))
		if detail:
			distance = minf(distance,Vector2(key).distance_squared_to(Vector2(projected))+.75)
		missing.append({"key":key,"fine":detail,"distance":distance})
	missing.sort_custom(func(a: Dictionary,b: Dictionary): return a.distance<b.distance if a.fine==b.fine else a.fine)
	queue = missing
	for key in chunks.keys():
		if chunks[key].fine:
			var distance := (Vector2(key)*16+Vector2(8,8)).distance_to(Vector2(main.player.position.x,main.player.position.z))
			for mesh in chunks[key].root.get_children():
				if mesh is MultiMeshInstance3D and mesh.has_meta("tree_kind"):
					var path := "res://generated/tree_%s_lod%d.res" % [mesh.get_meta("tree_kind"),0 if distance<24 else 1]
					if not _tree_meshes.has(path): _tree_meshes[path] = load(path)
					if mesh.multimesh.mesh!=_tree_meshes[path]: mesh.multimesh.mesh = _tree_meshes[path]
		var keep := false
		for point in points:
			var d: Vector2i = key-chunk_of(point)
			if maxi(abs(d.x),abs(d.y))<=7: keep = true; break
		if not keep and not wanted.has(key) and not _unload_pending.has(key): _unload_pending.append(key)
	# Keep worker and main-thread plan caches bounded during long exploration.
	var active := {}
	for key in wanted:
		var r: Vector2i = land.region_of(Vector2(key)*16)
		for dx in range(-1,2):
			for dz in range(-1,2): active[r+Vector2i(dx,dz)] = true
	for r in land.regions.keys():
		if not active.has(r): land.regions.erase(r)
	if land.modern: land.biomes.trim(Vector2(main.player.position.x,main.player.position.z))


func _pump() -> void:
	for worker in workers:
		if worker.thread!=null and not worker.thread.is_alive():
			var result: Dictionary = worker.thread.wait_to_finish()
			worker.thread = null
			if bool(result.get("cache_hit",false)): cache_hits += 1
			else: generated_chunks += 1
			if wanted.has(result.key): completed.append(result)
		if worker.thread==null and not queue.is_empty() and completed.size()<3:
			var job: Dictionary = queue.pop_front()
			if chunks.has(job.key) and (chunks[job.key].fine or not job.fine): continue
			worker.key = job.key
			worker.fine = job.fine
			worker.thread = Thread.new()
			var edited: Array = archived.get("%d,%d" % [job.key.x,job.key.y],[]) if job.fine else []
			worker.thread.start(worker.baker.bake.bind(job.key,job.fine,edited),Thread.PRIORITY_LOW)
	# At most one terrain/physics upload per frame; decoration follows on separate frames.
	if not completed.is_empty() and decorating.size()<5:
		var result: Dictionary = completed.pop_front()
		if wanted.has(result.key):
			var started := Time.get_ticks_usec()
			_install(result,true)
			max_install_us = maxi(max_install_us,Time.get_ticks_usec()-started)
	else:
		_pump_decoration()


func _pump_decoration() -> void:
	var deadline := Time.get_ticks_usec()+2500
	while not decorating.is_empty() and Time.get_ticks_usec()<deadline:
		var job: Dictionary = decorating[0]
		if not chunks.has(job.key) or chunks[job.key].root!=job.holder:
			decorating.pop_front(); continue
		if job.parts.is_empty():
			if job.fine and life:
				var started := Time.get_ticks_usec()
				life.load_chunk(job.key,true)
				max_decoration_us = maxi(max_decoration_us,Time.get_ticks_usec()-started)
			chunks[job.key].decorated = true
			decorating.pop_front()
			continue
		var part: Dictionary = job.parts.pop_front()
		_scatter_part(job.key,job.holder,job.fine,part)


func _install(result: Dictionary, deferred := false) -> void:
	var key: Vector2i = result.key
	for layout in result.layouts: land.regions[layout.key] = layout
	if voxel.modified.has(key) and voxel.vol.has_chunk(key.x,key.y): return
	if chunks.has(key):
		if chunks[key].fine and not result.fine: return
		chunks[key].root.queue_free()
	var holder := Node3D.new()
	holder.name = "Chunk_%d_%d" % [key.x,key.y]
	world.add_child(holder)
	var terrain_holder := Node3D.new()
	holder.add_child(terrain_holder)
	var pos := Vector3(key.x*16,float(result.ylo)*float(result.vs),key.y*16)
	if not result.mesh.is_empty():
		var mesh := MeshInstance3D.new()
		mesh.position = pos
		mesh.mesh = VX.array_mesh(result.mesh,voxel.vmat)
		terrain_holder.add_child(mesh)
	if not result.water.is_empty():
		var mesh := MeshInstance3D.new()
		mesh.position = pos
		mesh.mesh = VX.array_mesh(result.water,voxel.wmat)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		terrain_holder.add_child(mesh)
	var body := StaticBody3D.new()
	body.set_meta("terrain",true)
	terrain_holder.add_child(body)
	var collision := CollisionShape3D.new()
	collision.position = pos
	var shape: ConcavePolygonShape3D = result.physics
	collision.shape = shape
	body.add_child(collision)
	chunks[key] = {"root":holder,"fine":result.fine,"decorated":false}
	if land.modern: land.chunk_heights[key] = result.height_grid
	_coverage_dirty = true
	if result.fine:
		voxel.info[key] = {"y_lo":result.ylo,"cy":result.cy,"raw":result.raw.size(),"off":0,"size":0}
		voxel.vol.load_chunk(key.x,key.y,result.ylo,result.cy,result.raw)
		voxel.baked[key] = [terrain_holder]
	var parts := []
	for category in ["trees","plants","decor"]:
		for kind in result.scatter[category]:
			parts.append({"category":category,"kind":kind,"entries":result.scatter[category][kind]})
	if deferred:
		decorating.append({"key":key,"holder":holder,"fine":result.fine,"parts":parts})
	else:
		for part in parts: _scatter_part(key,holder,result.fine,part)
		if result.fine and life: life.load_chunk(key)
		chunks[key].decorated = true
	if result.fine and main.tools:
		for prop in main.tools.props.values():
			if is_instance_valid(prop):
				var meta: Dictionary = prop.meta
				if chunk_of(Vector3(meta.pos[0],meta.pos[1],meta.pos[2]))==key:
					voxel.hide_instance(str(meta.chunk),int(meta.index))
					main.tools._disable_original_collider(prop.kind,meta)


func ensure_sync(key: Vector2i) -> bool:
	if voxel.vol.has_chunk(key.x,key.y): return true
	var baker := BAKER.new()
	baker.setup(config,voxel.solid,voxel.water,voxel.hard)
	var result: Dictionary = baker.bake(key,true,archived.get("%d,%d" % [key.x,key.y],[]))
	_install(result)
	return true


func unload_chunk(key: Vector2i) -> void:
	if not chunks.has(key): return
	_unload_pending.erase(key)
	decorating = decorating.filter(func(job: Dictionary): return job.key!=key)
	if voxel.modified.has(key) and voxel.vol.has_chunk(key.x,key.y):
		var range_y: Vector2i = voxel.vol.get_chunk_range(key.x,key.y)
		var raw: PackedByteArray = voxel.vol.get_chunk_data(key.x,key.y)
		archived["%d,%d" % [key.x,key.y]] = [range_y.x,range_y.y,raw.size(),raw.compress(FileAccess.COMPRESSION_ZSTD)]
	if life: life.unload_chunk(key)
	chunks[key].root.queue_free()
	chunks.erase(key)
	land.chunk_heights.erase(key)
	_coverage_dirty = true
	if voxel.live.has(key):
		voxel.live[key].root.queue_free()
		voxel.live.erase(key)
	for sub: Vector3i in voxel.subs.keys():
		if voxel._sub_chunk_key(sub)==key: voxel.subs.erase(sub)
	voxel._warm = voxel._warm.filter(func(entry: Array): return entry[0]!=key)
	voxel.vol.unload_chunk(key.x,key.y)
	voxel.info.erase(key)
	voxel.baked.erase(key)
	voxel.modified.erase(key)
	voxel.plant_cells.erase(key)
	for prefix: String in voxel.mm_by_prefix.keys():
		if prefix.ends_with("_%d_%d" % [key.x,key.y]): voxel.mm_by_prefix.erase(prefix)


func apply_saved(changes: Dictionary) -> void:
	archived.merge(changes,true)
	for text: String in changes:
		var parts := text.split(",")
		var key := Vector2i(int(parts[0]),int(parts[1]))
		if voxel.vol.has_chunk(key.x,key.y): voxel.load_state({text:changes[text]},true)


func _scatter_part(key: Vector2i, holder: Node3D, fine: bool, part: Dictionary) -> void:
	var trees: bool = part.category=="trees"
	var boulders: bool = fine and part.category=="decor" and str(part.kind).begins_with("rock_boulder_")
	var prefix: String = part.kind
	var kind: String = prefix.split("_")[1] if trees else prefix
	var distance := (Vector2(key)*16+Vector2(8,8)).distance_to(Vector2(main.player.position.x,main.player.position.z))
	var lod := (0 if distance<24 else 1) if fine else (3 if trees else 1)
	var path := "res://generated/%s_lod%d.res" % ["tree_"+kind if trees else ("plant_"+kind if part.category=="plants" else kind),lod]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tree_meshes[path]
	mm.instance_count = part.entries.size()
	var body: StaticBody3D
	if (trees and fine) or boulders:
		body = StaticBody3D.new()
		body.name = "TreeColliders"
		holder.add_child(body)
	for i in mm.instance_count:
		var transform: Transform3D = part.entries[i].t if trees else part.entries[i]
		var removed := false
		if trees and main.tools:
			var prop_key := "tree:%s:%d" % [prefix,i]
			removed = main.tools.props.has(prop_key) or main.tools.gone.has(prop_key)
		if trees and fine and not removed:
			var shape := CollisionShape3D.new()
			shape.name = "tree_%s_%d" % [kind,i]
			var cylinder := CylinderShape3D.new()
			cylinder.radius = .4; cylinder.height = 5
			shape.shape = cylinder
			shape.position = transform.origin+Vector3.UP*2.5
			var pos := transform.origin
			shape.set_meta("tree",{"chunk":prefix,"index":i,"mesh":kind,"pos":[pos.x,pos.y,pos.z],"yaw":part.entries[i].yaw,"scale":part.entries[i].scale})
			body.add_child(shape)
		if boulders:
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			var bounds: AABB = mm.mesh.get_aabb()
			box.size = bounds.size*.8*transform.basis.get_scale()
			shape.shape = box
			shape.transform = transform
			shape.scale = Vector3.ONE
			shape.position = transform*bounds.get_center()
			body.add_child(shape)
		if removed: transform.basis = Basis().scaled(Vector3.ONE*.0001)
		mm.set_instance_transform(i,transform)
	var mesh := MultiMeshInstance3D.new()
	mesh.multimesh = mm
	if trees: mesh.set_meta("tree_kind",kind)
	else: mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not fine: mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mesh)
	if trees and fine: voxel.mm_by_prefix[prefix] = [mesh]
	elif fine:
		if not voxel.plant_cells.has(key): voxel.plant_cells[key] = []
		voxel.plant_cells[key].append(mesh)


func _refresh_metadata(point: Vector3) -> void:
	_center = chunk_of(point)
	var center := Vector2(point.x,point.z)
	var extent := 256.0
	data.bounds = [center.x-extent*.5,center.x+extent*.5,center.y-extent*.5,center.y+extent*.5]
	data.houses.clear(); data.landmarks.clear(); data.caves.clear(); data.roads.clear(); data.forests.clear(); data.river.clear()
	var regions_seen := {}
	for key in chunks:
		var r: Vector2i = land.region_of(Vector2(key)*16+Vector2(8,8))
		if regions_seen.has(r): continue
		regions_seen[r] = true
		var layout: Dictionary = land.region(r)
		data.landmarks.append_array(layout.landmarks)
		data.caves.append_array(layout.caves)
		data.roads.append_array(layout.roads)
		for house in layout.houses: data.houses.append([house.p.x,house.p.y])
	for band in range(roundi(center.x/(land.span*2.0))-1,roundi(center.x/(land.span*2.0))+2):
		for z in range(floori(center.y-144),ceili(center.y+144),3): data.river.append(Vector2(land.river_x(z,band),z))
	if not config.rivers: data.river.clear()
	for key in chunks:
		var p := Vector2(key)*16+Vector2(8,8)
		if land.woods.get_noise_2d(p.x,p.y)>.0: data.forests.append(Vector3(p.x,land.height(p)+2,p.y))
	if data.forests.is_empty(): data.forests.append(point+Vector3(20,0,20))
	_map_center = center
	_map_row = 0
	_map_column = 0
	_map_work = Image.create(128,128,false,Image.FORMAT_RGB8)
	_map_work.fill(Color("58863e"))
	if map_image==null: map_image = _map_work
	if stream_ready and main.soundscape:
		main.soundscape.river_points = data.river
		main.soundscape.forest_points = data.forests


func _pump_map() -> void:
	if _map_row>=128: return
	var deadline := Time.get_ticks_usec()+1200
	while _map_row<128 and Time.get_ticks_usec()<deadline:
		var p := _map_center-Vector2.ONE*128+Vector2(_map_column,_map_row)*2
		var h: float = land.height(p)
		var color := Color("58863e") if land.forest_cover(p)<.35 else Color("315b35")
		if land.modern and h>83: color = Color("81858b")
		if land.modern and h>143: color = Color("e8edf0")
		if land.road(p): color = Color("b6a07a")
		if h<3 and (land.modern or config.rivers): color = Color("438ba8")
		_map_work.set_pixel(_map_column,_map_row,color)
		_map_column += 1
		if _map_column==128: _map_column = 0; _map_row += 1
	if _map_row==128:
		map_image = _map_work
		if stream_ready and main.hud:
			main.hud.minimap.map_tex = ImageTexture.create_from_image(map_image)
			main.hud.minimap.world_rect = Rect2(_map_center-Vector2.ONE*128,Vector2.ONE*256)
			main.hud.minimap.map_res = 2.0
			main.hud.minimap.houses = data.houses


func movement_ready(point: Vector3) -> bool:
	return chunks.has(chunk_of(point))


func _pump_horizon() -> void:
	if not land.modern: return
	if _horizon_thread!=null and not _horizon_thread.is_alive():
		var result: Dictionary = _horizon_thread.wait_to_finish()
		var started := Time.get_ticks_usec()
		_horizon_thread = null
		if _horizon_root: _horizon_root.queue_free()
		_horizon_root = Node3D.new()
		world.add_child(_horizon_root)
		_horizon_materials.clear()
		for field in ["terrain","water"]:
			if result[field].pos.is_empty(): continue
			var material: ShaderMaterial = (voxel.vmat if field=="terrain" else voxel.wmat).duplicate()
			material.set_shader_parameter("distant_horizon",true)
			material.set_shader_parameter("terrain_coverage",_coverage_texture)
			_horizon_materials.append(material)
			var mesh := MeshInstance3D.new()
			mesh.mesh = VX.array_mesh(result[field],material)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_horizon_root.add_child(mesh)
		_coverage_origin = Vector2i(result.center)*4-Vector2i(64,64)
		max_horizon_us = maxi(max_horizon_us,Time.get_ticks_usec()-started)
		_coverage_dirty = true
	if _coverage_dirty and not _horizon_materials.is_empty():
		_coverage_image.fill(Color.BLACK)
		for key: Vector2i in chunks:
			var cell := key-_coverage_origin
			if cell.x>=0 and cell.x<128 and cell.y>=0 and cell.y<128: _coverage_image.set_pixel(cell.x,cell.y,Color.WHITE)
		_coverage_texture.update(_coverage_image)
		for material in _horizon_materials: material.set_shader_parameter("coverage_origin",Vector2(_coverage_origin))
		_coverage_dirty = false
	var point: Vector3 = main.player.position if stream_ready else _last_safe
	var center := Vector2i(floori(point.x/64),floori(point.z/64))
	if _horizon_thread==null and center!=_horizon_center:
		_horizon_center = center
		_horizon_thread = Thread.new()
		_horizon_thread.start(_horizon_baker.bake.bind(center),Thread.PRIORITY_LOW)


func _exit_tree() -> void:
	if _horizon_thread!=null:
		_horizon_thread.wait_to_finish()
		_horizon_thread = null
	_horizon_baker = null
	_horizon_materials.clear()
	for worker in workers:
		if worker.thread!=null:
			worker.thread.wait_to_finish()
			worker.thread = null
		worker.baker = null
	workers.clear()
	completed.clear()
	decorating.clear()
	_tree_meshes.clear()




func _warm_rendering() -> void:
	if DisplayServer.get_name()=="headless": return
	progress.emit("Grafik, Bäume und Figuren vorbereiten …",.94)
	# Submit the real mesh formats to the renderer behind the loading screen.
	# Loading a resource alone does not compile its first-use GPU pipeline.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64,64)
	viewport.own_world_3d = true
	viewport.msaa_3d = main.get_viewport().msaa_3d
	var environment := WorldEnvironment.new()
	environment.environment = main.env.environment.duplicate()
	viewport.add_child(environment)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0,2,8)
	camera.look_at(Vector3(0,.5,0))
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = bool(Settings.values.shadows)
	sun.rotation = main.sun.rotation
	viewport.add_child(sun)
	for resource in _tree_meshes.values():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = resource
		mm.instance_count = 1
		mm.set_instance_transform(0,Transform3D(Basis().scaled(Vector3.ONE*.12),Vector3.ZERO))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = mm
		viewport.add_child(instance)
	for kind in ["bird","bee","bear","wolf","rabbit","turtle","chicken","chick","goblin","witch","bandit","cyclops","dragon","sandworm"]:
		var model: Node3D = preload("res://scripts/wildlife/models.gd").create(kind)
		model.scale = Vector3.ONE*.2
		viewport.add_child(model)
	for kind in ["farmer","elder","merchant","guard"]:
		var model: Node3D = load("res://generated/char_%s.scn" % kind).instantiate()
		model.scale = Vector3.ONE*.25
		viewport.add_child(model)
	# Warm primitive attack effects as well as the world meshes.
	var effects = preload("res://scripts/game/combat_fx.gd").new()
	viewport.add_child(effects)
	effects.wave(Vector3.ZERO,1.0,Color(.7,.4,.9,.8))
	var projectile := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = .2; sphere.height = .4
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission = Color(.7,.4,.9)
	material.emission_energy_multiplier = 2
	sphere.material = material
	projectile.mesh = sphere
	viewport.add_child(projectile)
	var tag := Label3D.new()
	tag.text = "Stufe 123 · Bär"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	viewport.add_child(tag)
	for i in 5: await get_tree().process_frame
	viewport.queue_free()
