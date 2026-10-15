extends SceneTree
const MODELS := preload("res://scripts/wildlife/models.gd")
var failures := 0
var game: Node
var render := false

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, text: String) -> void:
	print(("PASS " if condition else "FAIL ")+text)
	if not condition:
		failures += 1

func frames(count := 4) -> void:
	for i in count:
		await process_frame

func screenshot(name: String) -> void:
	if render:
		await frames(8)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/"+name+".png"))

func _run() -> void:
	render = "--render-test" in OS.get_cmdline_user_args()
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("graphics",1)
	root.size = Vector2i(1280,720)
	change_scene_to_file("res://scenes/main.tscn")
	await frames(16)
	game = current_scene
	for i in 300:
		if game.get("soundscape") != null:
			break
		await process_frame
	check(game.wildlife != null and game.soundscape != null,"Wildlife and spatial audio systems start")
	game.set_process(false)
	game.player.set_physics_process(false)
	game.wildlife.set_physics_process(false)
	game.soundscape.set_process(false)
	game.tools.set_process(false)
	var counts := {}
	var species := {}
	for animal in game.wildlife.animals:
		animal.set_physics_process(false)
		counts[animal.species] = int(counts.get(animal.species,0))+1
		if not animal.young: species[animal.species] = animal
		check(animal.global_position.y > -15.0,animal.name+" spawns above world floor")
	check(counts == {"bird":42,"bee":12,"bear":5,"wolf":12,"rabbit":12,"turtle":7,"chicken":12},"All seven species / 102 animals spawn")
	check(MODELS.cache.size() == 8,"Species meshes are shared through model cache")
	for kind in species:
		var model: Node3D = species[kind].model
		check(model.get_child_count() >= 3,kind+" has a complete animated model")
		check(species[kind].voice.bus == "Wildlife" and species[kind].voice.max_distance > 0,kind+" has positional animal audio")
	var wolf: Node = species["wolf"]
	var bear: Node = species["bear"]
	var rabbit: Node = species["rabbit"]
	var turtle: Node = species["turtle"]
	var bird: Node = species["bird"]
	# Use an unobstructed meadow for repeatable perception / combat tests.
	var ground: Dictionary = game.wildlife.ground_at(Vector3(-4,0,9),70)
	var origin: Vector3 = ground["position"]+Vector3.UP*0.1
	wolf.global_position = origin
	wolf.home = origin
	wolf.hp = 65.0
	wolf.state = "idle"
	game.player.global_position = origin+Vector3(5,0,0)
	_tick(wolf,0.016)
	check(wolf.state == "chase" and wolf.velocity.length() > 0,"Wolf detects and chases nearby player")
	game.player.global_position = origin+Vector3(1.2,0,0)
	game.player.hp = 100.0
	game.player.hurt_cooldown = 0.0
	wolf._attack_cd = 0.0
	_tick(wolf,0.016)
	check(game.player.hp == 89.0 and wolf.state == "attack","Wolf bite deals 11 damage")
	_tick(wolf,0.016)
	check(game.player.hp == 89.0,"Enemy attack cooldown prevents per-frame damage")
	game.player.hurt_cooldown = 0.0
	game.player.take_damage(100,"Wolf")
	check(game.player.hp == 100.0 and game.player.global_position.distance_to(Vector3(0,2,0)) < 0.01,"Defeat respawns player safely in village")
	check(game.player.hurt_cooldown >= 4.9,"Respawn grants temporary protection")
	game.player.global_position = origin+Vector3(70,0,0)
	wolf.state = "chase"
	_tick(wolf,0.016)
	check(wolf.target_player == 0,"Predator stops pursuing distant player")
	game.player.global_position = origin+Vector3(1.2,0,0)
	wolf.global_position = origin
	wolf.home = origin
	wolf.hp = 65.0
	wolf.show()
	wolf.collision_layer = 8
	game.wildlife._hit_cooldowns.clear()
	game.wildlife.hit(wolf.animal_id)
	check(wolf.hp == 42.0,"Player sword damages nearby hostile animal")
	game.wildlife.hit(wolf.animal_id)
	check(wolf.hp == 42.0,"Sword hit cooldown prevents duplicate damage")
	game.wildlife._hit_cooldowns.clear()
	game.player.global_position = origin+Vector3(10,0,0)
	game.wildlife.hit(wolf.animal_id)
	check(wolf.hp == 42.0,"Melee cannot damage distant animals")
	game.player.global_position = origin+Vector3(1.2,0,0)
	game.wildlife._hit_cooldowns.clear()
	wolf.hp = 10.0
	var food_before: int = game.player.food
	game.wildlife.hit(wolf.animal_id)
	check(wolf.hp == 0 and not wolf.visible and wolf.collision_layer == 0,"Defeated wolf disappears and stops colliding")
	check(game.player.food == food_before+1,"Predator defeat rewards player")
	wolf._respawn = 0.01
	_tick(wolf,0.02)
	check(wolf.hp == 65 and wolf.visible,"Wildlife repopulates after respawn delay")
	bear.home = origin+Vector3(0,0,5)
	bear.global_position = bear.home
	game.player.global_position = bear.home+Vector3(1,0,0)
	game.player.hp = 100
	game.player.hurt_cooldown = 0.0
	bear._attack_cd = 0.0
	_tick(bear,0.016)
	check(game.player.hp == 77.0,"Bear swipe deals 23 damage")
	rabbit.home = origin
	rabbit.global_position = origin
	game.player.global_position = origin+Vector3(2,0,0)
	_tick(rabbit,0.016)
	check(rabbit.state == "flee","Rabbit flees from nearby player")
	turtle.home = origin
	turtle.global_position = origin
	_tick(turtle,0.016)
	check(turtle.state == "hide","Turtle retracts near player")
	bird._flee = 3.0
	bird.home = origin+Vector3.UP*2
	bird.global_position = bird.home
	_tick(bird,0.016)
	check(bird.state == "flee" and bird.target.y > bird.global_position.y,"Bird takes flight away from player")
	# New save fields and old-save compatibility use native Vector3 serialization.
	var state: Array = game.wildlife.save_state()
	var wolf_position: Vector3 = wolf.global_position
	wolf.global_position += Vector3(12,0,0)
	game.wildlife.load_state(state)
	check(wolf.global_position.is_equal_approx(wolf_position),"Wildlife positions and health round-trip through saved state")
	game._save()
	wolf.hp = 3
	game._load()
	check(wolf.hp == 65,"Game save/load includes wildlife")
	var hp_before: float = game.player.hp
	game.wildlife.apply_remote(99,{"op":"wild_damage","amount":23,"id":wolf.animal_id})
	check(game.player.hp == hp_before,"Non-host cannot inject wildlife damage")
	# Actual engine physics over time, including roaming, collision, terrain and animation.
	game.player.global_position = origin+Vector3(10,0,0)
	game.player.hurt_cooldown = 1000.0
	wolf.global_position = origin
	wolf.home = origin
	wolf.state = "idle"
	var start_position: Vector3 = wolf.global_position
	for animal in game.wildlife.animals:
		animal.set_physics_process(true)
	await create_timer(2.2).timeout
	check(wolf.global_position.distance_to(start_position) > 0.5,"Wolf pursuit moves over terrain with real physics")
	for animal in game.wildlife.animals:
		animal.set_physics_process(false)
		check(animal.global_position.is_finite() and animal.global_position.y > -18.0,animal.name+" stays on valid terrain during simulation")
	wolf.global_position = Vector3(0,-19,0)
	_tick(wolf,0.016)
	check(wolf.global_position.y > -15.0,"Animals recover if editable terrain drops them below world")
	check(game.soundscape.distance_gain(1.0,34.0) > .99 and game.soundscape.distance_gain(50.0,34.0) == 0,"River fade curve reaches silence beyond hearing distance")
	game.player.global_position = Vector3(10,0.0,-8)
	game.soundscape.update_environment(1.0)
	check(game.soundscape.river_gain > .2 and game.soundscape.river.playing,"River audible at riverbank")
	print("River near gain: ",game.soundscape.river_gain)
	game.player.global_position = Vector3(-70,14,25)
	game.soundscape.update_environment(1.0)
	check(game.soundscape.river_gain == 0 and not game.soundscape.river.playing,"River completely stops far from water")
	check(game.soundscape.listener.get_parent() == game.player,"Spatial audio listener follows hero, independent of camera zoom")
	root.get_node("Settings").update("wildlife",0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Wildlife")),"Animal volume slider mutes animal bus")
	root.get_node("Settings").update("wildlife",80)
	if render:
		await _visuals(species,origin)
	print("WILDLIFE TEST RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _visuals(species: Dictionary, origin: Vector3) -> void:
	# A temporary lineup makes proportions, winding, animation and all six models reviewable.
	for animal in game.wildlife.animals:
		animal.hide()
	var positions := {"bear":Vector3(-2.3,0,-3),"wolf":Vector3(0.1,0,-3),"rabbit":Vector3(2.0,0,-2.7),"turtle":Vector3(2.8,0,-1.5),"bird":Vector3(-0.4,2.0,-2.7),"bee":Vector3(1.5,1.0,-1.7)}
	for kind in positions:
		var animal: Node3D = species[kind]
		animal.global_position = origin+positions[kind]
		animal.show()
		animal.rotation.y = PI-0.35
		animal.state = "idle"
		animal.hp = animal.HEALTH[kind]
	game.player.global_position = origin+Vector3(0,0,4)
	game.cam_rig.yaw = 0
	game.cam_rig.pitch = deg_to_rad(-12)
	game.cam_rig.distance = 7
	game.cam_rig.global_position = game.player.global_position+Vector3(0,2,0)
	game.hud.hide()
	await screenshot("wildlife-in-world")
	# Read the actual audio mix, isolated to the river source, on the rendered engine.
	var capture := AudioEffectCapture.new()
	var bus := AudioServer.get_bus_index("Ambience")
	AudioServer.add_bus_effect(bus,capture)
	game.soundscape.wind.stop()
	game.soundscape.forest.stop()
	for source in game.soundscape.falls:
		source.stop()
	game.player.global_position = Vector3(10,0,-8)
	game.soundscape.update_environment(1.0)
	await create_timer(.5).timeout
	capture.clear_buffer()
	await create_timer(.35).timeout
	var near := _rms(capture.get_buffer(capture.get_frames_available()))
	game.player.global_position = Vector3(-70,14,25)
	game.soundscape.update_environment(1.0)
	await create_timer(.4).timeout
	capture.clear_buffer()
	await create_timer(.35).timeout
	var far := _rms(capture.get_buffer(capture.get_frames_available()))
	print("River audio RMS near=%f far=%f" % [near,far])
	check(near > 0.00001 and far < near*.02,"Rendered audio mix confirms river silence far away")
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)

func _rms(samples: PackedVector2Array) -> float:
	var energy := 0.0
	for sample in samples:
		energy += sample.length_squared()
	return sqrt(energy/maxi(samples.size()*2,1))

func _tick(animal: Node, delta: float) -> void:
	animal._think_clock = 0.0
	animal._intent = {}
	animal._simulate(delta)
