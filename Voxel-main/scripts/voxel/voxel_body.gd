extends RigidBody3D
## A piece of voxels that broke loose (undercut overhang, felled tree, chunk of a rock).
## Falls with physics, then shatters into debris (and logs for trees) when it comes to rest or hits hard.

signal shattered(body: Node, counts: PackedInt32Array, at: Vector3)

const VOXEL_WORLD := preload("res://scripts/voxel/voxel_world.gd")

var obj: VoxelObject
var kind := "chunk"          # chunk / tree / rock
var vs := 0.125
var vis_scale := 1.0
var com := Vector3.ZERO      # centre of mass in object metres (unscaled)
var _life := 0.0
var _still := 0.0
var _done := false
var _impact_v := 0.0

func setup(o: VoxelObject, origin_world: Vector3, rot: Basis, scale_f: float, vmat: Material, p_kind := "chunk") -> void:
	obj = o
	kind = p_kind
	vs = o.get_voxel_size()
	vis_scale = scale_f
	com = o.center_of_mass() * vs
	var n := o.solid_count()
	# visual: object mesh in model space, scaled as a child so the voxel grid stays aligned for the shader
	var mi := MeshInstance3D.new()
	mi.name = "mesh"
	var d := o.mesh(0, true, Vector3.ZERO)
	if not d.is_empty():
		mi.mesh = VOXEL_WORLD.array_mesh(d, vmat)
	mi.scale = Vector3.ONE * scale_f
	mi.position = -com * scale_f
	add_child(mi)
	# collision: coarse boxes, shrunk a little so neighbours never start overlapping
	var bx := o.boxes(2, 14)
	for i in range(0, bx.size(), 6):
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		var sz := Vector3(bx[i + 3], bx[i + 4], bx[i + 5]) * vs * scale_f
		b.size = Vector3(maxf(0.06, sz.x - 0.05), maxf(0.06, sz.y - 0.05), maxf(0.06, sz.z - 0.05))
		cs.shape = b
		cs.position = (Vector3(bx[i], bx[i + 1], bx[i + 2]) * vs - com) * scale_f
		add_child(cs)
	mass = clampf(n * 0.004 * (0.6 if kind == "tree" else 2.2) * scale_f * scale_f * scale_f, 1.0, 6000.0)
	global_transform = Transform3D(rot, origin_world + rot * (com * scale_f) + Vector3(0, 0.03, 0))
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 4
	collision_mask = 1 | 4
	continuous_cd = kind == "chunk" and n < 400
	linear_damp = 0.05
	angular_damp = 0.4 if kind == "tree" else 0.1
	body_entered.connect(_on_hit)

func _on_hit(_other: Node) -> void:
	_impact_v = maxf(_impact_v, linear_velocity.length())

func _physics_process(delta: float) -> void:
	if _done:
		return
	_life += delta
	var v := linear_velocity.length()
	var w := angular_velocity.length()
	if kind == "tree":
		# a felled tree breaks once it has swung down (or after a while)
		var up := global_transform.basis.y.normalized()
		if (_life > 0.6 and up.y < 0.35) or _life > 7.0 or (_life > 1.2 and v < 0.3 and w < 0.3):
			shatter()
		return
	if _life > 0.35 and (_impact_v > 4.0 or (v < 0.4 and w < 0.6)):
		_still += delta
	if _still > 0.25 or _life > 6.0 or global_position.y < -30.0:
		shatter()

func shatter() -> void:
	if _done:
		return
	_done = true
	shattered.emit(self, obj.value_counts(), global_position)
	queue_free()

## world positions + values of up to n sampled voxels (for debris)
func sample_voxels(n: int) -> Array:
	var out := []
	var size := obj.get_size()
	var tries := 0
	var t := global_transform
	while out.size() < n and tries < n * 12:
		tries += 1
		var p := Vector3i(randi() % size.x, randi() % size.y, randi() % size.z)
		var v := obj.get_voxel(p)
		if v == 0:
			continue
		var local := ((Vector3(p) + Vector3(0.5, 0.5, 0.5)) * vs - com) * vis_scale
		out.append([t * local, v])
	return out
