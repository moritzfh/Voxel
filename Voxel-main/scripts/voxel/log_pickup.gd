extends RigidBody3D
## A log from a felled tree. Rolls around, gets collected when the player walks close (or after a while).

const VOXEL_WORLD := preload("res://scripts/voxel/voxel_world.gd")

var value := 0
var player: Node3D
var _t := 0.0
var _taken := false

func setup(world: Node, pos: Vector3, axis: Vector3, p_value: int, p_player: Node3D) -> void:
	value = p_value
	player = p_player
	var o: VoxelObject = world.new_object()
	o.create(Vector3i(5, 5, 11))
	for z in 11:
		for x in 5:
			for y in 5:
				var d := Vector2(x - 2, y - 2).length()
				if d <= 2.3:
					var v := (15 << 2) | (3 if (z == 0 or z == 10) else (randi() % 3))
					o.set_voxel(Vector3i(x, y, z), v)
	var mi := MeshInstance3D.new()
	mi.mesh = VOXEL_WORLD.array_mesh(o.mesh(0, true, Vector3(-2.5, -2.5, -5.5) * 0.125), world.vmat)
	add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.55, 0.55, 1.3)
	cs.shape = bs
	add_child(cs)
	collision_layer = 4
	collision_mask = 1 | 4
	mass = 25.0
	var fwd := axis.normalized()
	var side := fwd.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	global_transform = Transform3D(Basis(side.normalized(), Vector3.UP, fwd).orthonormalized(), pos)
	linear_velocity = Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1))
	angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))

func _physics_process(delta: float) -> void:
	_t += delta
	if _taken or player == null:
		return
	var d := global_position.distance_to(player.global_position + Vector3(0, 0.8, 0))
	if (_t > 0.8 and d < 1.9) or _t > 90.0:
		_taken = true
		freeze = true
		if value > 0:
			Game.add("holz", value)
		Sfx.play("pickup", null, -6.0)
		var tw := create_tween()
		tw.tween_property(self, "global_position", player.global_position + Vector3(0, 1.0, 0), 0.25)
		tw.parallel().tween_property(self, "scale", Vector3.ONE * 0.2, 0.25)
		tw.tween_callback(queue_free)
