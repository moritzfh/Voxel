extends Node3D
var door_id := ""
var life: Node
var opened := false
var leaf: AnimatableBody3D
var turn := 1.0
var animation: Tween
static var mesh_cache := {}

func setup(owner_life: Node, id: String, at: Vector3, yaw: float, gate := false, direction := 1.0) -> void:
	life = owner_life
	door_id = id
	position = at
	rotation.y = yaw
	turn = direction
	leaf = AnimatableBody3D.new()
	add_child(leaf)
	var width := 2.0 if gate else 1.25
	var height := 1.2 if gate else 2.75
	if not mesh_cache.has(gate):
		var object: VoxelObject = life.main.vworld.new_object()
		var dims := Vector3i(roundi(width/.125),roundi(height/.125),1)
		object.create(dims)
		for x in dims.x:
			for y in dims.y:
				if gate and y not in [2,6,9] and x not in [0,dims.x-1]: continue
				object.set_voxel(Vector3i(x,y,0),(11 if y in [3,dims.y-4] or x in [0,dims.x-1] else 12)<<2)
		if not gate: object.set_voxel(Vector3i(dims.x-2,10,0),27<<2)
		mesh_cache[gate] = life.main.vworld.array_mesh(object.mesh(0,true,Vector3.ZERO),life.main.vworld.vmat)
	var mesh := MeshInstance3D.new()
	mesh.mesh = mesh_cache[gate]
	mesh.material_override = life.main.vworld.vmat
	leaf.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width,height,.125)
	collision.shape = shape
	collision.position = Vector3(width*.5,height*.5,.0625)
	leaf.add_child(collision)
	life.main.interactables.append({"node":self,"kind":"door","label":"[E] %s öffnen / schließen" % ("Hoftor" if gate else "Tür")})
	set_open(bool(life.door_states.get(door_id,false)),true)

func request_toggle() -> void:
	if Net.active() and not Net.is_host(): Net.send_op_to(1,{"op":"door_request","id":door_id})
	else: life.toggle_door(door_id)

func set_open(value: bool, immediate := false) -> void:
	opened = value
	if animation: animation.kill()
	var angle := turn*PI*.5 if opened else 0.0
	if immediate: leaf.rotation.y = angle
	else:
		animation = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		animation.tween_property(leaf,"rotation:y",angle,.28).set_trans(Tween.TRANS_SINE)
		Sfx.play("click",global_position+Vector3.UP,-15)
