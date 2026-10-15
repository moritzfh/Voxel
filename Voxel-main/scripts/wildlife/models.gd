extends RefCounted
## Build each species once; all individuals share meshes and materials.
const SHADER := preload("res://shaders/wildlife.gdshader")
static var cache := {}
static var definitions := {}
const DIRECTIONS := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]
const CORNERS := [
	[Vector3(1,0,0),Vector3(1,1,0),Vector3(1,1,1),Vector3(1,0,1)],
	[Vector3(0,0,1),Vector3(0,1,1),Vector3(0,1,0),Vector3(0,0,0)],
	[Vector3(0,1,1),Vector3(1,1,1),Vector3(1,1,0),Vector3(0,1,0)],
	[Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1)],
	[Vector3(1,0,1),Vector3(1,1,1),Vector3(0,1,1),Vector3(0,0,1)],
	[Vector3(0,0,0),Vector3(0,1,0),Vector3(1,1,0),Vector3(1,0,0)],
]

static func warm(species: String) -> void:
	if definitions.is_empty():
		definitions = JSON.parse_string(FileAccess.get_file_as_string("res://assets/wildlife/models.json"))
		definitions.merge(JSON.parse_string(FileAccess.get_file_as_string("res://assets/enemies/models.json")))
	if not cache.has(species):
		_bake(species)

static func create(species: String) -> Node3D:
	warm(species)
	var model := Node3D.new()
	for part in cache[species]:
		var pivot := Node3D.new()
		pivot.name = part["name"]
		pivot.position = part["pivot"]
		model.add_child(pivot)
		var mesh := MeshInstance3D.new()
		mesh.mesh = part["mesh"]
		mesh.visibility_range_end = 100.0
		pivot.add_child(mesh)
	return model

static func _bake(species: String) -> void:
	var definition: Dictionary = definitions[species]
	var voxel: float = definition["voxel"]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("voxel_size", voxel)
	var parts := []
	for part in definition["parts"]:
		var pivot_data: Array = part["pivot"]
		var pivot := Vector3(pivot_data[0], pivot_data[1], pivot_data[2])
		var cells := {}
		for cell in part["cells"]:
			cells[Vector3i(cell[0], cell[1], cell[2])] = Color.from_string("#" + cell[3], Color.WHITE).srgb_to_linear()
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for cell: Vector3i in cells:
			for face in 6:
				if cells.has(cell + DIRECTIONS[face]):
					continue
				surface.set_normal(Vector3(DIRECTIONS[face]))
				surface.set_color(cells[cell])
				for index in [0, 2, 1, 0, 3, 2]:
					surface.add_vertex((Vector3(cell) + CORNERS[face][index] - pivot) * voxel)
		var mesh := surface.commit()
		mesh.surface_set_material(0, material)
		parts.append({"name": part["name"], "pivot": pivot * voxel, "mesh": mesh})
	cache[species] = parts
