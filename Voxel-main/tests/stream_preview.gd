extends SceneTree
func _initialize() -> void: run.call_deferred()
func capture(name: String) -> void:
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/"+name+".png"))
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("graphics",1)
	root.size = Vector2i(1440,900)
	root.get_node("Worlds").new_world({"seed_text":"Dorfleben","size":0,"villages":1,"difficulty":0})
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene==null or not current_scene.world_ready: await process_frame
	var main := current_scene
	main.hud.visible = false
	main.player.set_physics_process(false)
	var village: Dictionary = main.world_data.villages[0]
	var center := Vector3(village.p.x,float(village.h),village.p.y)
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.position = center+Vector3(32,24,32)
	camera.look_at(center+Vector3(5,0,0))
	camera.current = true
	await create_timer(8).timeout
	await capture("unendliches-dorf")
	var life: Node = main.generator.life
	for resident in life.residents.values():
		if resident.role=="farmer" and resident.village.id==village.id:
			life.clock = 80-float(abs(resident.resident_id.hash())%17)
			resident.route_phase = -1
			for i in 120:
				resident._process(.25)
				life.clock += .25
			break
	var pen: Rect2 = village.pen
	camera.position = Vector3(pen.end.x+6,float(village.h)+5,pen.position.y-6)
	camera.look_at(Vector3(pen.get_center().x,float(village.h)+.8,pen.get_center().y))
	await capture("huehnerhof")
	var house: Dictionary = main.generator.land.region(Vector2i.ZERO).houses[0]
	var door: Node = life.doors.get("house_"+str(house.id))
	if door:
		life.toggle_door(door.door_id)
		camera.position = door.position+Vector3(6,3,4)
		camera.look_at(door.position+Vector3(0,1.4,0))
		await capture("haustuer")
	print("STREAM_PREVIEW_DONE")
	quit()
