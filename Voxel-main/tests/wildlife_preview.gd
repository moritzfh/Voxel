extends SceneTree
const MODELS := preload("res://scripts/wildlife/models.gd")
var parts: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.size = Vector2i(1800,1000)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("142b28")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("d9e4d5")
	world.environment.ambient_light_energy = 0.8
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	light.light_energy = 1.8
	light.light_color = Color("ffe5bb")
	light.shadow_enabled = true
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	camera.position = Vector3(0,9,16)
	stage.add_child(camera)
	camera.look_at(Vector3(0,0.8,0))
	camera.make_current()
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40,40)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("45665a")
	material.roughness = 1
	plane.material = material
	floor_mesh.mesh = plane
	floor_mesh.position.y = -0.1
	stage.add_child(floor_mesh)
	var kinds := ["bear","wolf","rabbit","turtle","bird","bee","chicken"]
	var names := ["BÄR","WOLF","HASE","SCHILDKRÖTE","VOGEL","BIENE","HUHN"]
	var babies := ["BÄRENJUNGES","WELPE","JUNGHASE","JUNGTIER","JUNGVOGEL","JUNGTIER","KÜKEN"]
	var scales := [1.0,.95,2.0,2.3,4.0,5.4,1.65]
	for i in 14:
		var column := i%7
		var young := i >= 7
		var model := MODELS.create("chick" if young and column == 6 else kinds[column])
		model.position = Vector3((column-3)*2.9,0.0,2.3 if young else -2.4)
		model.scale = Vector3.ONE*scales[column]*(.55 if young else 1.0)
		model.rotation.y = PI-.35
		if young and model.has_node("head"): model.get_node("head").scale = Vector3.ONE*1.15
		stage.add_child(model)
		parts.append(model)
		var label := Label3D.new()
		label.text = babies[column] if young else names[column]
		label.font = load("res://assets/fonts/cinzel-latin-700-normal.woff2")
		label.font_size = 42
		label.pixel_size = .006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("ffe3ab")
		label.outline_size = 8
		label.position = model.position+Vector3(0,.1,1.65)
		stage.add_child(label)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/tierfamilien.png"))
	print("Saved wildlife model preview")
	quit()
