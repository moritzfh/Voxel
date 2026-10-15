extends SceneTree
var failures := 0
var game: Node
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("world_features",false)
	for path in ["enemies/enemy_types","enemies/enemy","enemies/enemy_manager","wildlife/animal","wildlife/wildlife","worlds/infinite_land","worlds/chunk_baker","main"]:
		var script: Script = load("res://scripts/"+path+".gd")
		check(script!=null and script.can_instantiate(),"Compile "+path)
	if failures>0: quit(failures); return
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene==null or current_scene.get("world_ready")!=true: await process_frame
	game = current_scene
	game.player.set_physics_process(false)
	for animal in game.wildlife.all_actors(): animal.set_physics_process(false)
	check(game.wildlife.animals.size()==102,"Wildlife population stays separate from enemy encounters")
	var kinds := {}
	for enemy in game.wildlife.foes:
		kinds[enemy.species] = true
		check(enemy.collision_layer==16 and (enemy.collision_mask&32)!=0,"Solid enemy body: "+enemy.species)
		check(game.wildlife.village_clear(enemy.home),"Enemy spawn respects village protection")
	check(kinds.size()==6,"Test map contains all six requested enemy types")
	check((game.player.collision_mask&16)!=0 and game.player.collision_layer==32,"Player collides with enemies on its own actor layer")
	var catalogue: Script = load("res://scripts/enemies/enemy_types.gd")
	check(catalogue.group_size(1)==1 and catalogue.group_size(5)==3 and catalogue.group_size(9)==5 and catalogue.group_size(100)==5,"Normal group sizes grow with level and never exceed five")
	var model_script: Script = load("res://scripts/wildlife/models.gd")
	for species in catalogue.TYPES:
		check(model_script.cache.has(species) and model_script.definitions[species].parts.size()>=3,"Distinct pixel model exists for "+species)
	var goblin: Node
	var dragon: Node
	for enemy in game.wildlife.foes:
		if enemy.species=="goblin": goblin = enemy
		if enemy.species=="dragon": dragon = enemy
	goblin.position = Vector3(0,2,-2)
	game.player.position = Vector3(0,2,0)
	for i in 3: await physics_frame
	check(game.player.test_move(game.player.global_transform,Vector3(0,0,-3)),"Movement sweep cannot run through goblin body")
	var body: Node = goblin.get_child(0)
	var close: Transform3D = game.player.global_transform
	close.origin = goblin.position+Vector3(0,0,float(goblin._radius)+.32+.02)
	check(not game.player.test_move(close,Vector3(0,0,-.005)),"Player can touch the enemy without an invisible oversized barrier")
	check(dragon.get_children().filter(func(n: Node): return n is CollisionShape3D).size()==4,"Dragon torso, head and tail have fitted collision shapes")
	var combat: Node = game.combat
	combat.set_physics_process(false)
	combat.server_peers[root.get_node("Net").my_id()] = {"mana":10.0,"ranks":{},"rage":0.0}
	goblin.hp = 10
	combat._impact({"peer":root.get_node("Net").my_id(),"kind":"attack","stage":1,"sword":true,"yaw":0.0,"ranks":{},"rage":false})
	check(goblin.hp==0 and goblin.collision_layer==0,"Sword defeats goblin and releases physical obstruction")
	check(combat.fx.pieces.size()>0,"Enemies use the pixel death effect")
	check(root.get_node("Game").xp>0 and game.player.mana>10,"Enemy kills award experience and mana")
	dragon.receive_hit(100000,game.player.position)
	dragon._simulate(1000)
	check(dragon.hp==0,"Dungeon boss stays defeated rather than respawning as a group")
	var state: Array = game.wildlife.save_state()
	var record: Dictionary = dragon.snapshot()
	dragon.hp = dragon.max_health()
	game.wildlife.load_state(state)
	check(dragon.hp==0 and record.enemy and record.species=="dragon","Enemy identity and boss defeat survive save and restore")
	print("ENEMIES_TEST_FAILURES ",failures)
	quit(failures)
