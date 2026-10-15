extends Node3D
## Editable voxel terrain of the playable area (12.5 cm voxels).
## Chunks (16 x 16 m) stay as baked meshes until something changes them. Then they go "live": the voxel data is
## loaded from generated/near_vox.bin, meshed in 4 m sub-chunks by the C++ core and gets exact collision.

signal island_detached(obj: VoxelObject, origin_voxel: Vector3i)
signal voxels_changed(lo: Vector3i, hi: Vector3i)

const CS := 128          # voxels per chunk side
const SUB := 32          # voxels per sub-chunk side
const WATER_MATS := [33, 37]
const STONE_VALUE := 16  # STONE << 2 (fill below stored data)

var vs := 0.125
var origin := Vector3(-96.0, -8.0, -160.0)
var vol := VoxelVolume.new()
var info := {}           # Vector2i -> {y_lo, cy, off, size, raw}
var materials := {}      # int -> {name, hard, res, color}
var solid := PackedByteArray()
var water := PackedByteArray()
var hard := PackedByteArray()
var vmat: Material
var wmat: Material
## crafted building materials: building costs 1 resource per 4 voxels, mining them gives the same back
const PROCESSED := ["bricks", "bricks_dark", "cobble", "cobble_mossy", "plaster", "timber", "planks", "planks_dark", "slate",
	"cloth_w", "cloth_b", "cloth_g", "banner", "iron", "lantern", "window", "window_d", "hay", "crate", "cloth_r", "glass",
	"brick_red", "cloth_y"]
var processed := PackedByteArray()     # per value: 1 = crafted building material
var yield_tab := PackedFloat32Array()  # per value: resources per voxel (1.0 natural, 0.25 crafted)
var mat_ids := {}                      # material name -> id
var baked := {}          # Vector2i -> [Node] (baked meshes + colliders of the chunk)
var live := {}           # Vector2i -> {"root": Node3D, "body": StaticBody3D, "ready": bool}
var subs := {}           # Vector3i -> {"mesh": MeshInstance3D, "water": MeshInstance3D, "shape": CollisionShape3D}
var modified := {}       # Vector2i -> true (needs saving)
var plant_cells := {}    # Vector2i (16 m cell) -> [MultiMeshInstance3D]
var mm_by_prefix := {}   # instance-group prefix -> [MultiMeshInstance3D] (trees, rocks)
var _warm: Array = []    # pending [key, Vector3i sub] for progressive live conversion
var _file: FileAccess
var _stats := {"live_ms": 0.0}
var stream_provider: Node

func setup(world_root: Node, data: Dictionary) -> void:
	var nv: Dictionary = data.get("near_vox", {})
	if nv.is_empty():
		push_warning("no near_vox data")
		return
	vs = float(nv.get("vs", 0.125))
	var o: Array = nv.get("origin", [-96, -8, -160])
	origin = Vector3(float(o[0]), float(o[1]), float(o[2]))
	for c in nv["chunks"]:
		info[Vector2i(int(c["ix"]), int(c["iz"]))] = {"y_lo": int(c["y_lo"]), "cy": int(c["cy"]), "off": int(c["off"]),
			"size": int(c["size"]), "raw": int(c["raw"])}
	_file = FileAccess.open("res://generated/near_vox.bin", FileAccess.READ)
	for k in data.get("materials", {}):
		materials[int(k)] = data["materials"][k]
	solid.resize(256)
	water.resize(256)
	hard.resize(256)
	processed.resize(256)
	yield_tab.resize(256)
	for m in materials:
		mat_ids[str(materials[m].get("name", ""))] = m
	for v in range(4, 255):
		var m := v >> 2
		if not materials.has(m):
			continue
		var crafted: bool = str(materials[m].get("name", "")) in PROCESSED
		processed[v] = 1 if crafted else 0
		yield_tab[v] = 0.25 if crafted else 1.0
		if m in WATER_MATS:
			water[v] = 1
		else:
			solid[v] = 1
		hard[v] = clampi(int(materials[m].get("hard", 9)), 0, 255)
	vol.set_tables(solid, water, hard, STONE_VALUE)
	vol.setup(origin, vs, CS)
	vmat = load("res://generated/voxel_mat.tres")
	wmat = load("res://generated/water_mat.tres")
	_index_world(world_root)

func new_object() -> VoxelObject:
	var o := VoxelObject.new()
	o.set_tables(solid, water, hard, STONE_VALUE)
	o.set_voxel_size(vs)
	return o

func _index_world(world_root: Node) -> void:
	for part in world_root.get_children():
		var pn := String(part.name)
		if pn.begins_with("TerrainNear"):
			for n in part.get_children():
				var parts := String(n.name).split("_")
				if parts.size() < 3:
					continue
				var key := Vector2i(int(parts[1]) / CS, int(parts[2]) / CS)
				if not baked.has(key):
					baked[key] = []
				baked[key].append(n)
		elif pn.begins_with("Plants"):
			for n in part.get_children():
				var parts := String(n.name).split("_")
				if parts.size() < 4:
					continue
				var cx := int(parts[parts.size() - 3])
				var cz := int(parts[parts.size() - 2])
				var cell := Vector2i(floori(cx / 16.0), floori(cz / 16.0))
				if not plant_cells.has(cell):
					plant_cells[cell] = []
				plant_cells[cell].append(n)
		elif pn.begins_with("Trees") or pn.begins_with("Rocks"):
			for n in part.get_children():
				if not (n is MultiMeshInstance3D):
					continue
				var s := String(n.name)
				var cut := s.rfind("_l")
				if cut < 0:
					continue
				var prefix := s.substr(0, cut)
				if not mm_by_prefix.has(prefix):
					mm_by_prefix[prefix] = []
				mm_by_prefix[prefix].append(n)

# ------------------------------------------------------------------ coordinates
func to_voxel(p: Vector3) -> Vector3i:
	return Vector3i(floori((p.x - origin.x) / vs), floori((p.y - origin.y) / vs), floori((p.z - origin.z) / vs))

func to_world(v: Vector3i) -> Vector3:
	return origin + Vector3(v) * vs

func chunk_of(v: Vector3i) -> Vector2i:
	return Vector2i(floori(v.x / float(CS)), floori(v.z / float(CS)))

func in_area(v: Vector3i) -> bool:
	return info.has(chunk_of(v))

# ------------------------------------------------------------------ loading
func ensure_loaded(key: Vector2i) -> bool:
	if vol.has_chunk(key.x, key.y):
		return true
	if stream_provider: return stream_provider.ensure_sync(key)
	if not info.has(key) or _file == null:
		return false
	var c: Dictionary = info[key]
	_file.seek(c["off"])
	var comp := _file.get_buffer(c["size"])
	var raw := comp.decompress(c["raw"], FileAccess.COMPRESSION_DEFLATE)
	vol.load_chunk(key.x, key.y, c["y_lo"], c["cy"], raw)
	return true

func ensure_loaded_around(key: Vector2i) -> void:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			ensure_loaded(key + Vector2i(dx, dz))

## load data for chunks the player is close to (cheap, lets the first hit feel instant)
func preload_near(p: Vector3) -> void:
	var key := chunk_of(to_voxel(p))
	ensure_loaded_around(key)

# ------------------------------------------------------------------ live chunks
func is_live(key: Vector2i) -> bool:
	return live.has(key) and live[key]["ready"]

func _sub_keys_of_chunk(key: Vector2i) -> Array:
	var r := vol.get_chunk_range(key.x, key.y)
	var y0 := floori(r.x / float(SUB))
	var y1 := floori((r.x + r.y - 1) / float(SUB))
	var out := []
	for sx in CS / SUB:
		for sz in CS / SUB:
			for sy in range(y0, y1 + 1):
				out.append(Vector3i(key.x * (CS / SUB) + sx, sy, key.y * (CS / SUB) + sz))
	return out

func _begin_live(key: Vector2i) -> void:
	if live.has(key) or not info.has(key):
		return
	ensure_loaded_around(key)
	var root := Node3D.new()
	root.name = "live_%d_%d" % [key.x, key.y]
	root.visible = false
	add_child(root)
	var body := StaticBody3D.new()
	body.name = "body"
	body.set_meta("terrain", true)
	root.add_child(body)
	live[key] = {"root": root, "body": body, "ready": false}
	for sk in _sub_keys_of_chunk(key):
		_warm.append([key, sk])

func _finish_live(key: Vector2i) -> void:
	var L: Dictionary = live[key]
	if L["ready"]:
		return
	L["ready"] = true
	L["root"].visible = true
	for n in baked.get(key, []):
		if is_instance_valid(n):
			n.queue_free()
	baked.erase(key)

## make a chunk live right now (finishes a progressive conversion if one is running)
func make_live(key: Vector2i) -> void:
	if not info.has(key):
		return
	if not live.has(key):
		_begin_live(key)
	if live[key]["ready"]:
		return
	var t0 := Time.get_ticks_usec()
	var rest := []
	for w in _warm:
		if w[0] == key:
			_rebuild_sub(w[1])
		else:
			rest.append(w)
	_warm = rest
	_finish_live(key)
	_stats["live_ms"] = (Time.get_ticks_usec() - t0) / 1000.0

## start converting a chunk in the background (a few sub-chunks per frame)
func prewarm(key: Vector2i) -> void:
	if info.has(key) and not live.has(key):
		_begin_live(key)

func _process(_dt: float) -> void:
	if _warm.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	while not _warm.is_empty() and Time.get_ticks_usec() - t0 < 3000:
		var w: Array = _warm.pop_front()
		_rebuild_sub(w[1])
		var key: Vector2i = w[0]
		var pending := false
		for x in _warm:
			if x[0] == key:
				pending = true
				break
		if not pending:
			_finish_live(key)

static func array_mesh(d: Dictionary, mat: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d["pos"]
	arrays[Mesh.ARRAY_NORMAL] = d["nrm"]
	arrays[Mesh.ARRAY_CUSTOM0] = d["cus"]
	arrays[Mesh.ARRAY_INDEX] = d["idx"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	am.surface_set_material(0, mat)
	return am

func _sub_chunk_key(sk: Vector3i) -> Vector2i:
	return Vector2i(floori(sk.x / float(CS / SUB)), floori(sk.z / float(CS / SUB)))

func _rebuild_sub(sk: Vector3i) -> void:
	var key := _sub_chunk_key(sk)
	if not live.has(key):
		return
	var L: Dictionary = live[key]
	var lo := sk * SUB
	var size := Vector3i(SUB, SUB, SUB)
	var t0 := Time.get_ticks_usec()
	var m := vol.mesh_region(lo, size, 0, false, true, Vector3.ZERO)
	var w := vol.mesh_region(lo, size, 0, true, false, Vector3.ZERO)
	var c := vol.collision_region(lo, size, Vector3.ZERO)
	_prof("cxx_mesh", t0)
	prof["subs"] = prof.get("subs", 0) + 1
	var e: Dictionary = subs.get(sk, {})
	var pos := to_world(lo)
	# visible mesh
	if m.is_empty():
		if e.has("mesh"):
			e["mesh"].queue_free()
			e.erase("mesh")
	else:
		var mi: MeshInstance3D = e.get("mesh")
		if mi == null:
			mi = MeshInstance3D.new()
			mi.position = pos
			L["root"].add_child(mi)
			e["mesh"] = mi
		mi.mesh = array_mesh(m, vmat)
	# water surface
	if w.is_empty():
		if e.has("water"):
			e["water"].queue_free()
			e.erase("water")
	else:
		var wi: MeshInstance3D = e.get("water")
		if wi == null:
			wi = MeshInstance3D.new()
			wi.position = pos
			wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			L["root"].add_child(wi)
			e["water"] = wi
		wi.mesh = array_mesh(w, wmat)
	# collision
	if c.is_empty():
		if e.has("shape"):
			e["shape"].queue_free()
			e.erase("shape")
	else:
		var cs: CollisionShape3D = e.get("shape")
		if cs == null:
			cs = CollisionShape3D.new()
			cs.position = pos
			cs.shape = ConcavePolygonShape3D.new()
			L["body"].add_child(cs)
			e["shape"] = cs
		(cs.shape as ConcavePolygonShape3D).set_faces(c)
	if e.is_empty():
		subs.erase(sk)
	else:
		subs[sk] = e

func _rebuild_range(lo: Vector3i, hi: Vector3i) -> void:
	# lo/hi in voxels (inclusive), widened by one voxel so neighbours' exposed faces update too
	var a := Vector3i(floori((lo.x - 1) / float(SUB)), floori((lo.y - 1) / float(SUB)), floori((lo.z - 1) / float(SUB)))
	var b := Vector3i(floori((hi.x + 1) / float(SUB)), floori((hi.y + 1) / float(SUB)), floori((hi.z + 1) / float(SUB)))
	var chunks := {}
	for sx in range(a.x, b.x + 1):
		for sz in range(a.z, b.z + 1):
			chunks[Vector2i(floori(sx / float(CS / SUB)), floori(sz / float(CS / SUB)))] = true
	for key in chunks:
		if info.has(key):
			make_live(key)
			modified[key] = true
	for sx in range(a.x, b.x + 1):
		for sy in range(a.y, b.y + 1):
			for sz in range(a.z, b.z + 1):
				_rebuild_sub(Vector3i(sx, sy, sz))

# ------------------------------------------------------------------ edits
## make every chunk that a voxel box touches live before editing it
func prepare(lo: Vector3i, hi: Vector3i) -> void:
	for cx in range(floori((lo.x - 1) / float(CS)), floori((hi.x + 1) / float(CS)) + 1):
		for cz in range(floori((lo.z - 1) / float(CS)), floori((hi.z + 1) / float(CS)) + 1):
			make_live(Vector2i(cx, cz))

var prof := {}

func _prof(k: String, t0: int) -> void:
	prof[k] = prof.get(k, 0.0) + (Time.get_ticks_usec() - t0) / 1000.0

func after_edit(lo: Vector3i, hi: Vector3i, islands := true) -> void:
	var t0 := Time.get_ticks_usec()
	_rebuild_range(lo, hi)
	_prof("rebuild", t0)
	t0 = Time.get_ticks_usec()
	if islands:
		var found := vol.find_islands(lo - Vector3i(1, 1, 1), hi + Vector3i(1, 1, 1), 12000)
		_prof("islands", t0)
		for isl in found:
			var o: Vector3i = isl["origin"]
			var obj: VoxelObject = isl["object"]
			var sz := obj.get_size()
			_rebuild_range(o, o + sz - Vector3i(1, 1, 1))
			island_detached.emit(obj, o)
			_update_plants(o, o + sz)
	t0 = Time.get_ticks_usec()
	_update_plants(lo, hi)
	_prof("plants", t0)
	voxels_changed.emit(lo, hi)

func carve(at: Vector3i, normal: Vector3i, count: int, max_hard: int, seed: int, jitter: float,
		blo := Vector3i(1, 1, 1), bhi := Vector3i(0, 0, 0)) -> Dictionary:
	prepare(at - Vector3i(8, 8, 8), at + Vector3i(8, 8, 8))
	var r := vol.carve_cluster(at, normal, count, max_hard, seed, jitter, blo, bhi)
	if r.has("lo"):
		after_edit(r["lo"], r["hi"])
	return r

func apply_object(obj: VoxelObject, at: Vector3i, mode: int, pattern: int, natural := false) -> Dictionary:
	var hi := at + obj.get_size() - Vector3i(1, 1, 1)
	prepare(at, hi)
	var r := vol.apply_object(obj, at, mode, pattern, natural)
	if r.has("lo"):
		after_edit(r["lo"], r["hi"], mode == 1)
	return r

## replay a change list from apply_object (x, y, z, old, new): column 3 = undo, 4 = redo
func apply_changes(list: PackedInt32Array, column: int) -> void:
	if list.size() < 5:
		return
	var r := vol.apply_changes(list, column)
	if r.has("lo"):
		after_edit(r["lo"], r["hi"], false)

## raw list (x, y, z, value, ...) — undo / redo / network sync
func set_list(list: PackedInt32Array, islands := false) -> PackedInt32Array:
	if list.size() < 4:
		return PackedInt32Array()
	var lo := Vector3i(list[0], list[1], list[2])
	var hi := lo
	for i in range(0, list.size(), 4):
		var p := Vector3i(list[i], list[i + 1], list[i + 2])
		lo = Vector3i(mini(lo.x, p.x), mini(lo.y, p.y), mini(lo.z, p.z))
		hi = Vector3i(maxi(hi.x, p.x), maxi(hi.y, p.y), maxi(hi.z, p.z))
	prepare(lo, hi)
	var prev := vol.set_voxels(list)
	after_edit(lo, hi, islands)
	return prev

func get_value(v: Vector3i) -> int:
	var key := chunk_of(v)
	if not ensure_loaded(key):
		return 0
	return vol.get_voxel(v)

func material_of(value: int) -> int:
	return value >> 2

func res_of(value: int) -> String:
	var m := value >> 2
	return str(materials.get(m, {}).get("res", ""))

# ------------------------------------------------------------------ ray picking
## precise voxel under a world-space ray (call after a physics hit near the terrain)
func voxel_ray(from: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var a := chunk_of(to_voxel(from))
	var b := chunk_of(to_voxel(from + dir * max_dist))
	ensure_loaded_around(a)
	if b != a:
		ensure_loaded_around(b)
	return vol.raycast(from, dir, max_dist, false)

# ------------------------------------------------------------------ plants on edited ground
func _update_plants(lo: Vector3i, hi: Vector3i) -> void:
	var wlo := to_world(lo) - Vector3(0.4, 0.4, 0.4)
	var whi := to_world(hi + Vector3i(1, 1, 1)) + Vector3(0.4, 0.4, 0.4)
	for cx in range(floori(wlo.x / 16.0), floori(whi.x / 16.0) + 1):
		for cz in range(floori(wlo.z / 16.0), floori(whi.z / 16.0) + 1):
			for mmi in plant_cells.get(Vector2i(cx, cz), []):
				if not is_instance_valid(mmi):
					continue
				var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
				for i in mm.instance_count:
					var t := mm.get_instance_transform(i)
					var p := t.origin
					if t.basis.get_scale().x < 0.01:
						continue
					if p.x < wlo.x or p.x > whi.x or p.z < wlo.z or p.z > whi.z or p.y < wlo.y - 0.5 or p.y > whi.y + 0.5:
						continue
					var base := to_voxel(p + Vector3(0, -0.06, 0))
					var here := to_voxel(p + Vector3(0, 0.06, 0))
					var under := vol.get_voxel(base)
					var at := vol.get_voxel(here)
					if not (under != 0 and solid[under]) or (at != 0 and solid[at]):
						mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), p))

## hide one instance of a tree / rock multimesh group (all LODs + shadow proxies)
func hide_instance(prefix: String, index: int) -> void:
	for mmi in mm_by_prefix.get(prefix, []):
		if not is_instance_valid(mmi):
			continue
		var mm: MultiMesh = mmi.multimesh
		if index < mm.instance_count:
			var t := mm.get_instance_transform(index)
			mm.set_instance_transform(index, Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), t.origin))

# ------------------------------------------------------------------ saving
func save_state() -> Dictionary:
	var out: Dictionary = stream_provider.archived.duplicate(true) if stream_provider else {}
	for key in modified:
		if not vol.has_chunk(key.x, key.y):
			continue
		var r := vol.get_chunk_range(key.x, key.y)
		var data := vol.get_chunk_data(key.x, key.y)
		out["%d,%d" % [key.x, key.y]] = [r.x, r.y, data.size(), data.compress(FileAccess.COMPRESSION_ZSTD)]
	return out

func load_state(d: Dictionary, from_stream := false) -> void:
	if stream_provider and not from_stream:
		stream_provider.apply_saved(d)
		return
	for k in d:
		var parts := String(k).split(",")
		var key := Vector2i(int(parts[0]), int(parts[1]))
		var e: Array = d[k]
		var raw: PackedByteArray = (e[3] as PackedByteArray).decompress(int(e[2]), FileAccess.COMPRESSION_ZSTD)
		vol.load_chunk(key.x, key.y, int(e[0]), int(e[1]), raw)
		modified[key] = true
		if live.has(key):
			for sk in _sub_keys_of_chunk(key):
				_rebuild_sub(sk)
		else:
			make_live(key)
		_update_plants(Vector3i(key.x * CS, int(e[0]), key.y * CS), Vector3i(key.x * CS + CS, int(e[0]) + int(e[1]), key.y * CS + CS))
