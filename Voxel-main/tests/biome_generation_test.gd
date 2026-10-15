extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures += 1
func run() -> void:
	var worlds := root.get_node("Worlds")
	worlds.new_world({"seed_text":"Naturwelten-2026","size":1,"villages":1})
	check(worlds.config.terrain_version==2,"New worlds always enable mixed biomes")
	var land = load("res://scripts/worlds/infinite_land.gd").new()
	land.setup(worlds.config)
	var counts := {"plain":0,"forest":0,"lake":0,"mountain":0,"alpine":0}
	var highest := -INF
	var points := {}
	var image := Image.create(240,240,false,Image.FORMAT_RGB8)
	for x in 240:
		for z in 240:
			var p := Vector2(x-120,z-120)*32
			var sample: Vector4 = land.biomes.sample(p)
			highest = maxf(highest,sample.x)
			var category := "plain"
			if sample.y>.65: category = "forest"
			if sample.x<3: category = "lake"
			if sample.x>55: category = "mountain"
			if sample.x>145: category = "alpine"
			counts[category] += 1
			points[category] = p
			var color: Color = {"plain":Color("8ca95d"),"forest":Color("355b37"),"lake":Color("468eaf"),"mountain":Color("777f89"),"alpine":Color("edf0ee")}[category]
			image.set_pixel(x,z,color*(.8+clampf(sample.x/250,0,.2)))
	for category in counts: check(counts[category]>20,"Mixed landscape contains "+category+": "+str(counts[category]))
	check(highest>170,"Giant mountain peaks exceed 170 metres: "+str(highest))
	image.resize(960,960,Image.INTERPOLATE_NEAREST)
	image.save_png(ProjectSettings.globalize_path("res://../test-data/biom-verteilung.png"))
	var legacy: Dictionary = worlds.config.duplicate(true)
	legacy.erase("terrain_version")
	worlds.resume_world(legacy)
	check(not worlds.config.has("terrain_version"),"Continuing older worlds preserves their generator version")
	var old_land = load("res://scripts/worlds/infinite_land.gd").new()
	old_land.setup(legacy)
	check(not old_land.modern,"Old terrain remains on its original generator")
	worlds.resume_world(land.config)
	var voxel = load("res://scripts/voxel/voxel_world.gd").new()
	var world := Node3D.new()
	root.add_child(world); world.add_child(voxel)
	var template: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/world_data.json"))
	voxel.setup(world,{"materials":template.materials,"near_vox":{"origin":[0,0,0],"vs":.125,"chunks":[]}})
	var baker = load("res://scripts/worlds/chunk_baker.gd").new()
	baker.setup(land.config,voxel.solid,voxel.water,voxel.hard)
	baker.cache_dir += "/cold_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(baker.cache_dir)
	var total_cold := 0
	var total_cached := 0
	for category in ["plain","forest","lake","alpine"]:
		var p: Vector2 = points[category]
		var key := Vector2i(floori(p.x/16),floori(p.y/16))
		var result: Dictionary = baker.bake(key,true)
		check(not result.cache_hit,"First visit generates a new "+category+" chunk")
		check(result.raw.size()>0 and not result.mesh.is_empty(),"Fine terrain, collision and mesh for "+category)
		var second = load("res://scripts/worlds/chunk_baker.gd").new()
		second.setup(land.config,voxel.solid,voxel.water,voxel.hard)
		second.cache_dir = baker.cache_dir
		var cached: Dictionary = second.bake(key,true)
		check(cached.cache_hit and result.raw==cached.raw and result.mesh==cached.mesh and result.scatter==cached.scatter,"Fresh worker reads identical persisted mesh/voxels/decor for "+category)
		print("CACHE_PROFILE ",category," cold_ms=",result.work_us/1000.0," cached_ms=",cached.work_us/1000.0," bytes=",result.raw.size()," triangles=",result.collision.size()/3)
		total_cold += int(result.work_us); total_cached += int(cached.work_us)
		var dry_trees := true
		for prefix in result.scatter.trees:
			for tree in result.scatter.trees[prefix]:
				var t: Transform3D = tree.t
				if land.water_level(Vector2(t.origin.x,t.origin.z))>-50 or t.origin.y<4.2: dry_trees = false
		check(dry_trees,"Trees stand on dry ground in "+category)
		if category=="lake":
			check(not result.water.is_empty(),"Lakes contain actual water voxels")
			check(result.scatter.decor.has("plant_lily"),"Lake water carries voxel lily pads")
			var sound: Vector3 = land.nearest_water(p)
			check(Vector2(sound.x,sound.z).distance_to(p)<34,"Lake audio uses a nearby water surface")
		# Modified chunks have a separate cache entry and can never reuse stale base geometry.
		var bytes: PackedByteArray = result.raw.duplicate()
		bytes[bytes.size()/2] = 54<<2
		var edited := [result.ylo,result.cy,bytes.size(),bytes.compress(FileAccess.COMPRESSION_ZSTD)]
		var modified: Dictionary = second.bake(key,true,edited)
		check(modified.raw==bytes,"Saved edits override cached terrain for "+category)
		var modified_again: Dictionary = second.bake(key,true,edited)
		check(modified_again.cache_hit and modified_again.raw==bytes,"Edited mesh cache restores identical terrain for "+category)
	check(total_cached<total_cold,"Cached sections load faster than cold generation")
	print("BIOME_CACHE_TOTAL cold_ms=",total_cold/1000.0," cached_ms=",total_cached/1000.0)
	print("BIOME_GENERATION_FAILURES ",failures)
	world.queue_free()
	await process_frame
	quit(failures)
