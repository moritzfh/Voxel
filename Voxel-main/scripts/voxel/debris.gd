extends Node3D
## Flying voxel crumbs: spawned by mining, falling chunks and felled trees. They burst out, bounce on the ground,
## then get pulled to the player (resources are already booked; this is the satisfying part).

const MAX := 900

var target: Node3D          # the player
var palette: PackedVector3Array
var mmi: MultiMeshInstance3D
var mm: MultiMesh
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _rot := PackedVector3Array()
var _floor := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _col: Array[Color] = []
var _mode := PackedByteArray()   # 0 free, 1 flying, 2 magnet, 3 fade
var _count := 0
var _plink_t := 0.0
signal collected(n: int)

func _ready() -> void:
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(0.125, 0.125, 0.125)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	box.material = mat
	mm.mesh = box
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mmi.custom_aabb = AABB(Vector3(-400, -100, -400), Vector3(800, 400, 800))
	add_child(mmi)
	_pos.resize(MAX)
	_vel.resize(MAX)
	_rot.resize(MAX)
	_floor.resize(MAX)
	_life.resize(MAX)
	_size.resize(MAX)
	_mode.resize(MAX)
	_col.resize(MAX)

func color_of(value: int) -> Color:
	if palette.is_empty() or value <= 0 or value >= palette.size():
		return Color(0.6, 0.55, 0.5)
	var c := palette[value]
	# palette is linear; vertex colours of StandardMaterial3D are sRGB
	return Color(c.x, c.y, c.z).linear_to_srgb()

## burst from removed voxels: list = PackedInt32Array (x, y, z, v ...) in voxel coords; to_world converts
func burst_voxels(list: PackedInt32Array, world: Node, normal: Vector3, magnet := true, max_n := 40) -> void:
	var n := list.size() / 4
	if n == 0:
		return
	var step := maxi(1, n / max_n)
	var i := 0
	while i < n:
		var p: Vector3 = world.to_world(Vector3i(list[i * 4], list[i * 4 + 1], list[i * 4 + 2])) + Vector3(0.0625, 0.0625, 0.0625)
		spawn(p, list[i * 4 + 3], normal, magnet)
		i += step

func spawn(p: Vector3, value: int, normal: Vector3, magnet := true, speed := 1.0, size := 1.0) -> void:
	var i := _alloc()
	if i < 0:
		return
	_pos[i] = p
	var dir := (normal * 1.6 + Vector3(randf_range(-1, 1), randf_range(0.2, 1.4), randf_range(-1, 1))).normalized()
	_vel[i] = dir * randf_range(1.5, 4.5) * speed
	_rot[i] = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_floor[i] = p.y - randf_range(0.0, 0.35)
	_life[i] = 0.0
	_size[i] = randf_range(0.55, 1.05) * size
	_mode[i] = 1 if magnet else 3
	_col[i] = color_of(value)

func _alloc() -> int:
	for k in 2:
		for i in range(_count, MAX):
			if _mode[i] == 0:
				_count = i + 1
				return i
		_count = 0
	return -1

func _process(delta: float) -> void:
	var tgt := target.global_position + Vector3(0, 1.0, 0) if target else Vector3.ZERO
	var visible := 0
	var got := 0
	_plink_t -= delta
	for i in MAX:
		var m := _mode[i]
		if m == 0:
			continue
		_life[i] += delta
		var p := _pos[i]
		var v := _vel[i]
		if m == 1 or m == 3:
			v.y -= 14.0 * delta
			p += v * delta
			if p.y < _floor[i] and v.y < 0.0:
				p.y = _floor[i]
				v = Vector3(v.x * 0.45, -v.y * 0.35, v.z * 0.45)
			if m == 1 and _life[i] > 0.75 and target:
				_mode[i] = 2
			if m == 3 and _life[i] > 1.6:
				_mode[i] = 0
				continue
		else:
			var to := tgt - p
			var d := to.length()
			if d < 0.35 or _life[i] > 4.0:
				_mode[i] = 0
				got += 1
				continue
			v = v.lerp(to.normalized() * clampf(d * 6.0, 6.0, 26.0), 1.0 - exp(-7.0 * delta))
			p += v * delta
		_pos[i] = p
		_vel[i] = v
		var r := _rot[i] + v * delta * 2.0
		_rot[i] = r
		var s := _size[i]
		if m == 3:
			s *= clampf(1.6 - _life[i], 0.0, 1.0)
		elif m == 2:
			s *= clampf((tgt - p).length() * 0.8, 0.25, 1.0)
		var b := Basis.from_euler(r).scaled(Vector3(s, s, s))
		mm.set_instance_transform(visible, Transform3D(b, p))
		mm.set_instance_color(visible, _col[i])
		visible += 1
	mm.visible_instance_count = visible
	if got > 0:
		collected.emit(got)
