extends SceneTree
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, text: String) -> void:
	print(("PASS " if condition else "FAIL ")+text)
	if not condition: failures += 1

func _run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	change_scene_to_file("res://scenes/main.tscn")
	var game: Node
	for i in 300:
		await process_frame
		game = current_scene
		if game != null and game.get("soundscape") != null: break
	game.player.set_physics_process(false)
	game.player.global_position = Vector3(-45,14,30)
	game.player.hurt_cooldown = 100000
	game.tools.set_process(false)
	var world: Node = game.wildlife
	for animal in world.animals:
		if animal.species not in ["wolf","bird"]:
			animal.set_physics_process(false)
			animal.hp = 0
			animal.hide()
	world._update_packs()
	var starts := {}
	for group in world.packs:
		starts[group] = world.packs[group]["leader"].global_position
		print("Pack start ",group,": ",starts[group]," path ",world.packs[group]["points"].slice(0,12))
	Engine.time_scale = 4.0
	await create_timer(40.0).timeout
	Engine.time_scale = 1.0
	for group in world.packs:
		var pack: Dictionary = world.packs[group]
		var leader: Node = pack["leader"]
		var progress: float = leader.global_position.distance_to(starts[group])
		print("Pack ",group," progressed ",progress,"m, waypoint ",pack["waypoint"]," leader ",leader.global_position)
		print("Current goal ",pack["points"][pack["waypoint"]]," trail ",pack["trail"].slice(0,5))
		check(progress > 15.0,"Pack %d patrol leader moves along river/forest route" % group)
		var followers := 0
		for member in pack["members"]:
			if member == leader or member.young: continue
			var distance: float = member.global_position.distance_to(leader.global_position)
			print("Follower ",member.animal_id," distance ",distance," state ",member.state)
			if distance < 13.0: followers += 1
		check(followers >= 3,"Pack %d keeps at least three adults following its leader" % group)
		var separated := true
		for i in pack["members"].size()-1:
			if not pack["members"][i].young and not pack["members"][i+1].young:
				separated = separated and pack["members"][i].global_position.distance_to(pack["members"][i+1].global_position) > .65
		check(separated,"Pack %d adults stay spaced in following order" % group)
	var errors := []
	for animal in world.by_species["bird"]:
		var error: float = animal.global_position.distance_to(world.flock_target(animal.flock_id,animal.group_slot))
		errors.append(error)
	var maximum := 0.0
	for value in errors: maximum = maxf(maximum,value)
	print("Maximum live flock formation error: ",maximum)
	check(maximum < 4.0,"All 42 birds track their moving formation slots")
	for animal in world.animals:
		if animal.hp > 0:
			check(animal.global_position.is_finite() and animal.global_position.y > -15.0,animal.name+" remains valid after twenty seconds")
	print("ECOLOGY LIVE TEST RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
