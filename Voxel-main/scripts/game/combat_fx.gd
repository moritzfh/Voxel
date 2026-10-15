extends Node3D
## A bounded collection of voxel fragments and short-lived attack arcs.
var pieces: Array = []
var rings: Array = []
var material: StandardMaterial3D

func _ready() -> void:
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = .9

func death(animal: Node3D) -> void:
	var definition: Dictionary = animal.MODELS.definitions["chick" if animal.species=="chicken" and animal.young else animal.species]
	var cells := []
	for part in definition.parts:
		for cell in part.cells: cells.append(cell)
	var stride := maxi(1,ceili(cells.size()/90.0))
	var vs: float = definition.voxel*animal.size_factor
	for i in range(0,cells.size(),stride):
		if pieces.size()>=720: break
		var c: Array = cells[i]
		var p := animal.global_transform*Vector3((float(c[0])+.5)*vs,(float(c[1])+.5)*vs,(float(c[2])+.5)*vs)
		var ground: Dictionary = animal.manager.ground_at(p,p.y+2)
		var floor_y: float = float(ground.position.y) if not ground.is_empty() else animal.position.y
		var box := BoxMesh.new()
		box.size = Vector3.ONE*vs*1.2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_string("#"+str(c[3]),Color.WHITE)
		mat.roughness = .95
		box.material = mat
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		mesh.global_position = p
		pieces.append({"node":mesh,"v":Vector3(randf_range(-1.4,1.4),randf_range(.8,2.8),randf_range(-1.4,1.4)),"floor":floor_y+vs*.5,"t":0.0})

func wave(point: Vector3, radius: float, color := Color("85dfea"), arc := TAU, yaw := 0.0) -> void:
	var mesh := MeshInstance3D.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 48:
		var a := yaw-arc*.5+float(i)*arc/48
		var b := yaw-arc*.5+float(i+1)*arc/48
		var points := [Vector3(sin(a)*.85,0,-cos(a)*.85),Vector3(sin(a),0,-cos(a)),Vector3(sin(b),0,-cos(b)),Vector3(sin(b)*.85,0,-cos(b)*.85)]
		for j in [0,2,1,0,3,2]: surface.add_vertex(points[j])
	mesh.mesh = surface.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mesh.material_override = mat
	add_child(mesh)
	mesh.global_position = point+Vector3.UP*.15
	rings.append({"node":mesh,"mat":mat,"r":radius,"t":0.0})

func _process(dt: float) -> void:
	for i in range(pieces.size()-1,-1,-1):
		var p: Dictionary = pieces[i]
		p.t += dt
		p.v.y -= 16*dt
		p.node.position += p.v*dt
		if p.node.position.y<p.floor:
			p.node.position.y = p.floor
			p.v = Vector3(p.v.x*.65,absf(p.v.y)*.22,p.v.z*.65)
		p.node.rotate_x(dt*p.v.length())
		p.node.scale = Vector3.ONE*clampf(3.2-p.t,0,1)
		if p.t>=3.2: p.node.queue_free(); pieces.remove_at(i)
	for i in range(rings.size()-1,-1,-1):
		var r: Dictionary = rings[i]
		r.t += dt
		r.node.scale = Vector3.ONE*lerpf(.3,r.r,clampf(r.t/.32,0,1))
		r.mat.albedo_color.a = clampf(1-r.t/.45,0,1)
		if r.t>=.45: r.node.queue_free(); rings.remove_at(i)
