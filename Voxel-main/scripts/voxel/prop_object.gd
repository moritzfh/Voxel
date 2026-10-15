extends Node3D
## A tree or rock that the player started to work on. Replaces its instanced mesh with an editable voxel object.
## Trees: each axe hit cuts a notch into the trunk; once it is deep enough the tree topples (away from the player)
## and the stump stays. Rocks: each hit breaks a chunk off; loose parts fall, the rest crumbles at the end.

const VOXEL_WORLD := preload("res://scripts/voxel/voxel_world.gd")
const BLOCK := 32

var kind := "tree"
var obj: VoxelObject
var vs := 0.125
var scale_f := 1.0
var o_vox := Vector3i.ZERO      # model origin offset in voxels (voxel (0,0,0) sits at o_vox * vs in model space)
var vmat: Material
var meta := {}
var blocks := {}                # Vector3i -> MeshInstance3D
var body: StaticBody3D
var notch_y := -1
var section0 := 0
var initial := 0
var felled := false
var trunk_c := Vector2.ZERO     # trunk centre (voxels, x/z)
var trunk_r := 3

func setup(p_kind: String, p_meta: Dictionary, model: Dictionary, data: PackedByteArray, p_vmat: Material, world: Node) -> void:
	kind = p_kind
	meta = p_meta
	vmat = p_vmat
	var dims: Array = model["dims"]
	var org: Array = model["origin"]
	o_vox = Vector3i(int(org[0]), int(org[1]), int(org[2]))
	vs = float(model["vs"])
	scale_f = float(meta.get("scale", 1.0))
	obj = world.new_object()
	obj.set_voxel_size(vs)
	obj.set_data(Vector3i(int(dims[0]), int(dims[1]), int(dims[2])), data)
	var p: Array = meta["pos"]
	transform = Transform3D(Basis(Vector3.UP, float(meta.get("yaw", 0.0))).scaled(Vector3.ONE * scale_f), Vector3(p[0], p[1], p[2]))
	initial = obj.solid_count()
	trunk_c = Vector2(-o_vox.x, -o_vox.z)
	_remesh_all()
	body = StaticBody3D.new()
	body.set_meta(kind, meta)
	body.set_meta("prop_object", self)
	add_child(body)
	_update_collider()

func _remesh_all() -> void:
	var size := obj.get_size()
	for bx in range(0, size.x, BLOCK):
		for by in range(0, size.y, BLOCK):
			for bz in range(0, size.z, BLOCK):
				_remesh_block(Vector3i(bx / BLOCK, by / BLOCK, bz / BLOCK))

func _remesh_block(b: Vector3i) -> void:
	var lo := b * BLOCK
	var d := obj.mesh_region(lo, Vector3i(BLOCK, BLOCK, BLOCK), 0, true, Vector3.ZERO)
	var mi: MeshInstance3D = blocks.get(b)
	if d.is_empty():
		if mi:
			mi.queue_free()
			blocks.erase(b)
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.position = Vector3(o_vox + lo) * vs
		add_child(mi)
		blocks[b] = mi
	mi.mesh = VOXEL_WORLD.array_mesh(d, vmat)

func _remesh_range(lo: Vector3i, hi: Vector3i) -> void:
	for bx in range(floori((lo.x - 1) / float(BLOCK)), floori((hi.x + 1) / float(BLOCK)) + 1):
		for by in range(floori((lo.y - 1) / float(BLOCK)), floori((hi.y + 1) / float(BLOCK)) + 1):
			for bz in range(floori((lo.z - 1) / float(BLOCK)), floori((hi.z + 1) / float(BLOCK)) + 1):
				if bx >= 0 and by >= 0 and bz >= 0:
					_remesh_block(Vector3i(bx, by, bz))

func _update_collider() -> void:
	for c in body.get_children():
		c.queue_free()
	var bx := obj.boxes(4 if kind == "tree" else 2, 10)
	for i in range(0, bx.size(), 6):
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		var sz := Vector3(bx[i + 3], bx[i + 4], bx[i + 5]) * vs
		if kind == "tree":
			# only the trunk blocks the player; the crown stays walk-through like before
			if (Vector3(bx[i], bx[i + 1], bx[i + 2]) - Vector3(trunk_c.x, bx[i + 1], trunk_c.y)).length() > 6.0:
				continue
		b.size = sz
		cs.shape = b
		cs.position = (Vector3(bx[i], bx[i + 1], bx[i + 2]) + Vector3(o_vox)) * vs
		body.add_child(cs)

## world point -> object voxel coordinates
func to_local_voxel(p: Vector3) -> Vector3:
	return (global_transform.affine_inverse() * p) / vs - Vector3(o_vox)

## one hit. Returns {removed: PackedInt32Array (object voxel coords), felled: Array of detached parts}
func hit(world_point: Vector3, from_world: Vector3, power: int, seed: int, max_hard: int) -> Dictionary:
	var out := {"removed": PackedInt32Array(), "parts": []}
	if felled and kind == "tree" and obj.solid_count() == 0:
		return out
	var lp := to_local_voxel(world_point)
	var lf := to_local_voxel(from_world)
	var dir := (lp - lf).normalized()
	if kind == "tree":
		var size := obj.get_size()
		if notch_y < 0:
			notch_y = clampi(int(lp.y), 3, mini(size.y - 4, 14))
			section0 = obj.count_box(Vector3i(int(trunk_c.x) - 12, notch_y - 2, int(trunk_c.y) - 12), Vector3i(int(trunk_c.x) + 12, notch_y + 2, int(trunk_c.y) + 12))
		# aim horizontally at the trunk at notch height
		var start := Vector3(lp.x, notch_y + 0.5, lp.z)
		var hd := Vector3(trunk_c.x + 0.5, notch_y + 0.5, trunk_c.y + 0.5) - start
		hd.y = 0.0
		if hd.length() < 0.01:
			hd = Vector3(dir.x, 0, dir.z)
		var lo := Vector3i(int(trunk_c.x) - 14, notch_y - 2, int(trunk_c.y) - 14)
		var hi := Vector3i(int(trunk_c.x) + 14, notch_y + 2, int(trunk_c.y) + 14)
		var ray := obj.raycast(start - hd.normalized() * 4.0, hd.normalized(), 40.0)
		var at := Vector3i(-1, -1, -1)
		var nrm := Vector3i(0, 1, 0)
		if ray.get("hit", false) and (ray["voxel"] as Vector3i).y >= lo.y and (ray["voxel"] as Vector3i).y <= hi.y:
			at = ray["voxel"]
			nrm = ray["normal"]
		else:
			# the ray went through the notch: take the remaining trunk voxel closest to the swing
			var best := 1e9
			for x in range(lo.x, hi.x + 1):
				for z in range(lo.z, hi.z + 1):
					for y in range(lo.y, hi.y + 1):
						var v := obj.get_voxel(Vector3i(x, y, z))
						if v == 0:
							continue
						var d := Vector3(x + 0.5, y + 0.5, z + 0.5).distance_squared_to(start)
						if d < best:
							best = d
							at = Vector3i(x, y, z)
			if at.x < 0:
				return out
		var r := obj.carve_cluster(at, nrm, power, max_hard, seed, 0.35, lo, hi)
		out["removed"] = r["removed"]
		if r.has("lo"):
			_remesh_range(r["lo"], r["hi"])
		var left := obj.count_box(lo, hi)
		print_verbose("notch ", notch_y, " removed ", (out["removed"] as PackedInt32Array).size() / 4, " left ", left, "/", section0)
		if section0 > 0 and left <= int(section0 * 0.38):
			var rest := obj.remove_box(lo, hi, 9)
			var all := out["removed"] as PackedInt32Array
			all.append_array(rest)
			out["removed"] = all
			out["parts"] = obj.split(1)
			felled = true
			_remesh_all()
			_update_collider()
		return out
	# rock
	var ray2 := obj.raycast(lp - dir * 3.0, dir, 30.0)
	if not ray2.get("hit", false):
		return out
	var r2 := obj.carve_cluster(ray2["voxel"], ray2["normal"], power, max_hard, seed, 1.0, Vector3i(1, 1, 1), Vector3i(0, 0, 0))
	out["removed"] = r2["removed"]
	if r2.has("lo"):
		out["parts"] = obj.split(1)
		if obj.solid_count() < int(initial * 0.12):
			var rest2 := obj.remove_box(Vector3i(0, 0, 0), obj.get_size(), 9)
			var all2 := out["removed"] as PackedInt32Array
			all2.append_array(rest2)
			out["removed"] = all2
			out["gone"] = true
		if out["parts"].size() > 0 or out.has("gone"):
			_remesh_all()
		else:
			_remesh_range(r2["lo"], r2["hi"])
		_update_collider()
	return out

## world transform for a detached part with object-voxel origin `o`
func part_origin_world(o: Vector3i) -> Vector3:
	return global_transform * (Vector3(o_vox + o) * vs)

func voxel_world_pos(x: int, y: int, z: int) -> Vector3:
	return global_transform * ((Vector3(o_vox) + Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * vs)
