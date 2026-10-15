extends SceneTree
var failures := 0
var game: Node
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ")+label)
	if not value: failures += 1
func frames(n: int) -> void:
	for i in n: await process_frame
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("world_features",false)
	for path in ["game/warrior_skills","game/warrior_combat","game/combat_fx","player","character_anim","remote_player","wildlife/animal","ui/world_overview","ui/game_panels"]:
		var script: Script = load("res://scripts/"+path+".gd")
		check(script!=null and script.can_instantiate(),"Compile "+path)
	change_scene_to_file("res://scenes/main.tscn")
	await frames(20)
	game = current_scene
	for i in 600:
		if game.get("world_ready"): break
		await process_frame
	check(game.get("world_ready")==true,"Test world starts with combat")
	if not game.get("world_ready"): quit(1); return
	var combat: Node = game.combat
	game.set_process(false)
	game.player.set_physics_process(false)
	combat.set_physics_process(false)
	game.wildlife.set_physics_process(false)
	for animal in game.wildlife.animals: animal.set_physics_process(false)
	check(combat.sword_equipped and game.tools.tool_mesh.visible and game.tools._tool_kind=="sword","Sword remains in hand at rest")
	var wolf: Node3D = game.wildlife.by_id[19]
	var base: float = wolf.max_health()
	wolf.level = 6
	check(wolf.max_health()>base*1.8,"Distant animal levels scale health")
	check(wolf.level_at(game.player.spawn_point+Vector3(900,0,0))==6,"Level increases every 180 metres from spawn")
	wolf.level = 1
	wolf.global_position = game.player.global_position+Vector3(0,0,-2)
	wolf.hp = 1000
	var other: Node3D = game.wildlife.by_id[20]
	other.global_position = game.player.global_position+Vector3(0,0,2)
	other.hp = 1000
	combat.server_peers.clear()
	var net: Node = root.get_node("Net")
	var pid: int = net.my_id()
	combat.server_peers[pid] = {"mana":20.0,"ranks":{},"rage":0.0}
	var job := {"peer":pid,"kind":"attack","stage":1,"sword":true,"yaw":0.0,"ranks":{},"rage":false}
	combat._impact(job)
	check(wolf.hp==977 and other.hp==1000,"Sword sweep hits in front, excludes behind")
	check(wolf._knock.length()>2 and wolf._hurt>0,"Hit creates knockback and blink interval")
	job.stage = 3
	combat._impact(job)
	check(wolf.hp==931 and other.hp==954,"Third combo spins and guarantees double damage")
	check(game.player.mana>=24,"Combo finisher restores mana when it hits")
	job.kind = "slam"
	combat._impact(job)
	check(wolf._lift==7 and other._lift==7,"Slam launches all nearby animals")
	wolf.hp = 1
	job.kind = "attack"
	job.stage = 1
	var mana_before: float = game.player.mana
	combat._impact(job)
	check(wolf.hp==0 and not wolf.visible and wolf.collision_layer==0,"Defeated enemy stops colliding and disappears")
	check(combat.fx.pieces.size()>20,"Defeated animal becomes coloured voxel fragments")
	check(game.player.mana>mana_before,"Kills restore mana")
	combat.fx._process(3.3)
	check(combat.fx.pieces.is_empty(),"Death fragments disappear after falling and fading")
	var state: Node = root.get_node("Game")
	state.level = 2
	state.talent_points = 20
	check(not state.can_learn("cleave"),"Skill level gates are enforced")
	check(state.learn("edge"),"Warrior passive can be learned")
	state.level = 3
	check(state.learn("cleave"),"Skill unlock requires level and prerequisite")
	var saved: Dictionary = state.to_dict()
	state.reset()
	state.from_dict(saved)
	check(state.rank("cleave")==1 and state.rank("edge")==1,"Warrior unlocks survive save and restore")
	var settings: Node = root.get_node("Settings")
	check(settings.keycode("equip_sword")==KEY_1 and settings.keycode("dodge")==KEY_CTRL and settings.keycode("sprint")==KEY_SHIFT,"Equipment, sprint and roll defaults")
	check(settings.keycode("attack")!=KEY_1,"Slot 1 no longer triggers attacks")
	game.panels.open_tab(2)
	check(game.panels.talent_page=="Krieger","Skill book opens warrior tree by default")
	game.panels.open_tab(4)
	await frames(3)
	var map: Control = game.panels.map_view
	var extent: float = map.extent
	var anchor := Vector2(200,180)
	var point: Vector2 = map.screen_world(anchor)
	map.zoom(1.3,anchor)
	check(map.extent>extent and map.screen_world(anchor).distance_to(point)<.01,"Map zoom preserves the point under the cursor")
	map.center += Vector2(100,40)
	map.recenter()
	check(map.center.distance_to(Vector2(game.player.position.x,game.player.position.z))<.01,"Map returns to player after panning")
	game.panels.close()
	print("Combat test failures: ",failures)
	quit(1 if failures else 0)
