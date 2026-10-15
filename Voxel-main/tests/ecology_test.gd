extends SceneTree
var game: Node
var world: Node
var failures := 0
var render := false

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ")+message)
	if not condition: failures += 1

func frames(count := 4) -> void:
	for i in count: await process_frame

func _run() -> void:
	render = "--render-test" in OS.get_cmdline_user_args()
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("world_features",false)
	root.get_node("Settings").update("graphics",1)
	root.size = Vector2i(1280,720)
	change_scene_to_file("res://scenes/main.tscn")
	await frames(12)
	game = current_scene
	for i in 300:
		if game.get("soundscape") != null: break
		await process_frame
	world = game.wildlife
	check(world.animals.size() == 102,"102 animals populate the world")
	game.set_process(false)
	game.player.set_physics_process(false)
	game.tools.set_process(false)
	world.set_physics_process(false)
	for animal in world.animals: animal.set_physics_process(false)
	var counts := {}
	for animal in world.animals:
		var key: String = animal.species+(" young" if animal.young else " adult")
		counts[key] = int(counts.get(key,0))+1
		if animal.young:
			check(animal.parent_id >= 0 and world.by_id.has(animal.parent_id),animal.name+" has a valid adult parent")
	for species in ["bear","wolf","rabbit","turtle","bird","bee","chicken"]:
		check(counts.get(species+" adult",0)>0 and counts.get(species+" young",0)>0,species+" has adult and juvenile variants")
	check(counts["bird adult"]+counts["bird young"] == 42,"42 birds populate three formation flocks")
	var wolf: Node = world.by_id[19]
	check(is_equal_approx(wolf.size_factor,.76),"Adult wolves are 24 percent smaller")
	world._update_packs()
	for group in world.packs:
		var pack: Dictionary = world.packs[group]
		var adults := 0
		for member in pack["members"]:
			if not member.young: adults += 1
		check(adults == 4,"Pack %d contains four adult wolves" % group)
		var points: PackedVector3Array = pack["points"]
		var valid := points.size() >= 8
		for i in points.size():
			valid = valid and not world.underwater(points[i])
			if world.underwater(points[i]): print("Wet route point ",group," ",points[i])
			if i>0: valid = valid and points[i].distance_to(points[i-1]) < 5.0
			if i>0 and points[i].distance_to(points[i-1]) >= 5.0: print("Route gap ",group," ",points[i-1]," -> ",points[i])
		check(valid,"Pack %d follows a continuous dry-land route" % group)
		print("Trail separation ",group,": ",world.trail_point(group,0).distance_to(world.trail_point(group,4.35)))
		check(world.trail_point(group,0).distance_to(world.trail_point(group,4.35)) > 1.5,"Pack %d has a spaced following trail" % group)
	for group in world.flocks:
		var leader: Vector3 = world.flock_target(group,0)
		var follower: Vector3 = world.flock_target(group,4)
		check(leader.y > 20.0 and leader.distance_to(follower)>1.0,"Flock %d flies in a distinct elevated formation" % group)
	# Disable unrelated animals for isolated ecology scenarios on a flat meadow.
	var saved: Array = world.save_state()
	for animal in world.animals:
		animal.hp = 0.0
		animal.hide()
		animal.collision_layer = 0
	var ground: Dictionary = world.ground_at(Vector3(-4,0,9),70)
	var origin: Vector3 = ground["position"]+Vector3.UP*.1
	game.player.global_position = origin+Vector3(40,0,0)
	var rabbit: Node = world.by_id[23]
	_place(wolf,origin)
	_place(rabbit,origin+Vector3(5,0,0))
	var plan: Dictionary = world.plan_for(wolf)
	check(plan["victim"] == rabbit and plan["state"] == "hunt","A lone wolf hunts rabbits")
	wolf.global_position = rabbit.global_position+Vector3.RIGHT
	world.attack_animal(wolf,rabbit,30)
	check(rabbit.hp == 0 and wolf.feeding_time > 0 and world.plan_for(wolf)["state"] == "feeding","Wolf eats hunted rabbit and pauses to feed")
	wolf.feeding_time = 0
	wolf.global_position = origin
	var bear: Node = world.by_id[18]
	_place(bear,origin+Vector3(4,0,0))
	rabbit.hp = 0
	plan = world.plan_for(wolf)
	check(plan["victim"] != bear,"Lone wolf avoids attacking adult bear")
	_place(world.by_id[20],origin+Vector3(1.5,0,0))
	_place(world.by_id[62],origin+Vector3(3,0,0))
	plan = world.plan_for(wolf)
	check(world.pack_strength(wolf) == 3 and plan["victim"] == bear,"Three nearby adult pack members can hunt a bear")
	var hp_before: float = bear.hp
	wolf.global_position = bear.global_position+Vector3(1,0,0)
	world.attack_animal(wolf,bear,11)
	check(bear.hp == hp_before-11 and bear.aggro_animal == wolf.animal_id,"Animal attacks damage prey and trigger retaliation")
	# Passive solitary bears and protective parents have different perception radii.
	for animal in world.animals: animal.hp = 0
	_place(bear,origin)
	game.player.global_position = origin+Vector3(7,0,0)
	plan = world.plan_for(bear)
	check(plan["player"] == 0,"Solitary bear stays passive at a respectful distance")
	game.player.global_position = origin+Vector3(2,0,0)
	plan = world.plan_for(bear)
	check(plan["player"] != 0,"Solitary bear reacts when player gets too close")
	var parent: Node = world.by_id[16]
	var cub: Node
	for child in world.children[16]: cub = child
	_place(parent,origin)
	_place(cub,origin+Vector3(1,0,0))
	game.player.global_position = origin+Vector3(7,0,0)
	plan = world.plan_for(parent)
	check(world.has_cub(parent) and plan["player"] != 0 and plan["state"] == "guard","Bear with cub guards a wider area against player")
	game.player.global_position = origin+Vector3(40,0,0)
	bear.hp = 0
	_place(rabbit,origin+Vector3(5,0,0))
	plan = world.plan_for(parent)
	check(plan["victim"] == rabbit,"Protective bear reacts to other animal species near cub")
	world.provoke(cub,1)
	check(parent.aggro_player == 1 and parent.anger_time > 0,"Hitting a cub alerts its parent")
	var juvenile: Node = world.children[23][0]
	_place(juvenile,origin)
	var before: float = juvenile.hp
	juvenile.receive_hit(3,origin+Vector3.RIGHT)
	check(juvenile.hp == before-3,"Small animals take real melee damage")
	juvenile.receive_hit(100,origin)
	check(juvenile.hp == 0 and not juvenile.visible,"Small animals can be defeated")
	# Bees are passive until provoked, then a nearby colony retaliates.
	var bee: Node = world.by_id[8]
	var friend: Node = world.by_id[9]
	_place(bee,origin+Vector3.UP)
	_place(friend,origin+Vector3(1,1,0))
	game.player.global_position = origin+Vector3(2,0,0)
	plan = world.plan_for(bee)
	check(plan["player"] == 0,"Unprovoked bees stay peaceful")
	world.provoke(bee,1)
	plan = world.plan_for(bee)
	check(plan["player"] == 1 and friend.aggro_player == 1,"Provoking a bee alerts nearby bees")
	var health: float = game.player.hp
	game.player.hurt_cooldown = 0
	world.damage_player(1,2,bee.animal_id)
	check(game.player.hp == health-2,"Angry bee sting damages player")
	# Shared feature switch blocks every user entry point and hides related quests.
	check(not game.world_features_enabled(),"World editing starts disabled")
	game.builder.set_active(true)
	game.builder.open_panel()
	check(not game.builder.active and not game.builder._panel_open,"Disabled builder cannot be opened")
	check(not root.get_node("Game").quest_visible("erste_schritte") and not root.get_node("Game").quest_visible("wachturm"),"Mining and building quests are hidden")
	check(root.get_node("Game").quest_visible("runen"),"Unrelated exploration quests remain visible")
	check(not game.hud.build_controls[0].visible,"Building hotbar item is hidden")
	root.get_node("Settings").update("world_features",true)
	game.builder.set_active(true)
	check(game.builder.active and root.get_node("Game").quest_visible("erste_schritte"),"Option restores building and existing quests")
	root.get_node("Settings").update("world_features",false)
	check(not game.builder.active and not game.builder._panel_open,"Disabling feature closes active build mode")
	var stats_before: Dictionary = root.get_node("Game").stats.duplicate()
	game.tools.target = {"kind":"voxel"}
	game.tools._use()
	check(root.get_node("Game").stats == stats_before,"Disabled mining action cannot mutate resource statistics")
	world.load_state(saved)
	game._save()
	game._load()
	check(world.animals.size() == 102 and world.children[16][0].young,"Save/load preserves adult and juvenile population")
	if render:
		game.hud.options.open()
		game.hud.options.show_tab(4)
		await frames(8)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../test-data/optionen-spiel.png"))
	print("ECOLOGY TEST RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _place(animal: Node, point: Vector3) -> void:
	animal.global_position = point
	animal.home = point
	animal.hp = animal.max_health()
	animal.state = "idle"
	animal._intent = {}
	animal._think_clock = 0
	animal.anger_time = 0
	animal.aggro_player = 0
	animal.aggro_animal = -1
	animal._flee = 0
	animal.show()
	animal.collision_layer = 8
