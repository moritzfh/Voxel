extends RefCounted
## A cheap, non-colliding distant silhouette. Resident voxel chunks mask it in the shader.
var land: RefCounted
var cache_dir := ""
func setup(config: Dictionary, directory: String) -> void:
	land = preload("res://scripts/worlds/infinite_land.gd").new()
	land.setup(config)
	cache_dir = directory
func bake(center: Vector2i) -> Dictionary:
	var path := "%s/horizon_%d_%d.bin" % [cache_dir,center.x,center.y]
	if FileAccess.file_exists(path):
		var file := FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
		if file:
			var cached: Variant = file.get_var(false)
			if cached is Dictionary and cached.get("center") == center and cached.has("terrain") and cached.has("water"): return cached
	var grid := PackedFloat32Array()
	grid.resize(161*161)
	var origin := Vector2(center)*64-Vector2.ONE*640
	for x in 161:
		for z in 161: grid[x*161+z] = land.base_height(origin+Vector2(x,z)*8)
	var terrain := {"pos":PackedVector3Array(),"nrm":PackedVector3Array(),"cus":PackedByteArray(),"idx":PackedInt32Array()}
	var water := {"pos":PackedVector3Array(),"nrm":PackedVector3Array(),"cus":PackedByteArray(),"idx":PackedInt32Array()}
	for x in 160:
		for z in 160:
			var p := origin+Vector2(x,z)*8
			var heights := Vector4(grid[x*161+z],grid[(x+1)*161+z],grid[(x+1)*161+z+1],grid[x*161+z+1])
			var h := (heights.x+heights.y+heights.z+heights.w)*.25
			var material := 18 if h>143 else 41 if h>83 else 21 if h<4 else 1
			quad(terrain,p,heights-Vector4.ONE*.25,material)
			if minf(minf(heights.x,heights.y),minf(heights.z,heights.w))<3:
				quad(water,p,Vector4.ONE*2.98,33)
	var result := {"center":center,"terrain":terrain,"water":water}
	var temporary := path+".tmp"
	var file := FileAccess.open_compressed(temporary,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
	if file:
		file.store_var(result,false); file.close()
		if DirAccess.rename_absolute(temporary,path)!=OK: DirAccess.remove_absolute(temporary)
	land.biomes.trim(Vector2(center)*64)
	return result

func quad(mesh: Dictionary, p: Vector2, h: Vector4, material: int) -> void:
	var a := Vector3(p.x,h.x,p.y)
	var b := Vector3(p.x+8,h.y,p.y)
	var c := Vector3(p.x+8,h.z,p.y+8)
	var d := Vector3(p.x,h.w,p.y+8)
	var normal := (c-a).cross(b-a).normalized()
	var first: int = mesh.pos.size()
	mesh.pos.append_array(PackedVector3Array([a,b,c,d]))
	for i in 4:
		mesh.nrm.append(normal)
		mesh.cus.append_array(PackedByteArray([material<<2,3,2,255]))
	mesh.idx.append_array(PackedInt32Array([first,first+1,first+2,first,first+2,first+3]))
