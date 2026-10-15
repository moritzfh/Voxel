extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("world_features",false)
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene==null or current_scene.get("world_ready")!=true: await process_frame
	var game := current_scene
	var combat: Node = game.combat
	var player: Node = game.player
	for animal in game.wildlife.animals: animal.set_physics_process(false)
	var wolf: Node = game.wildlife.by_id[19]
	player.position = Vector3(0,3,0)
	for i in 60: await physics_frame
	game.cam_rig.yaw = 0
	wolf.position = player.position+Vector3(0,0,-2)
	wolf.hp = 1000
	check(combat.request("attack"),"Actual attack request starts a sword swing")
	check(wolf.hp==1000,"Wind-up does not deal instantaneous aim damage")
	for i in 28: await physics_frame
	check(wolf.hp==977,"Timed swing deals damage during animation")
	check(combat.request("attack"),"Second combo swing starts in time window")
	for i in 28: await physics_frame
	check(combat.request("attack") and combat.combo==3,"Third combo chains into spin finisher")
	for i in 43: await physics_frame
	check(wolf.hp==908,"Full three-hit combo deals 23 + 23 + 46")
	player.mana = 50
	check(combat.request("spin"),"Spin ability starts")
	check(player.mana<35,"Spin consumes 16 mana")
	for i in 70: await physics_frame
	check(wolf.hp==866,"Spin damages nearby targets on all three turns")
	check(not combat.request("spin"),"Ability cooldown prevents immediate recast")
	player.mana = 50
	var start: Vector3 = player.position
	wolf.position = start+Vector3(0,0,-4)
	check(combat.request("slam"),"Grounded leap attack starts")
	for i in 20: await physics_frame
	check(player.position.y>start.y+.4 and player.position.z<start.z-1,"Leap moves physically forward and upward")
	for i in 38: await physics_frame
	check(wolf.hp==828 and wolf._lift==7,"Leap lands with damage and upward knockback")
	check(player.is_on_floor() and player.position.y<start.y+1.8,"Leap lands on ground or a solid enemy body")
	player.stamina = 100
	start = player.position
	check(combat.request("dodge"),"Control roll starts when grounded")
	var health: float = player.hp
	player.take_damage(10,"test")
	check(player.hp==health,"Roll has a short invulnerability window")
	for i in 34: await physics_frame
	check(player.position.distance_to(start)>3 and player.stamina<90,"Roll travels and consumes stamina")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_1
	event.pressed = true
	combat.toggle_sword()
	check(not combat.sword_equipped,"First slot key switches to fists")
	combat.toggle_sword()
	check(combat.sword_equipped,"Pressing slot 1 again draws sword")
	game.panels.open_tab(4)
	check(not combat.request("attack"),"Map blocks combat inputs")
	game.panels.close()
	print("COMBAT_LIVE_FAILURES ",failures)
	quit(failures)
