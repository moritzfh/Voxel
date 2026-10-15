extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene==null or current_scene.get("world_ready")!=true: await process_frame
	var game := current_scene
	game.player.set_physics_process(false)
	game.player.position = Vector3(5000,100,5000)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(90,1,90)
	shape.shape = box
	floor_body.add_child(shape)
	game.add_child(floor_body)
	floor_body.position = Vector3(1000,99.5,1000)
	var tested := []
	for i in 6:
		var species: String = ["goblin","witch","bandit","cyclops","dragon","sandworm"][i]
		var p := Vector3(980+(i%3)*18,100,990+(i/3)*18)
		var enemy: Node = game.wildlife.spawn_external(91000000000000+i,{"species":species},p)
		enemy.position.y += .8
		tested.append(enemy)
	for i in 70: await physics_frame
	for enemy in tested:
		check(enemy.is_on_floor() and absf(enemy.position.y-100)<.08,"Physical body settles with feet at floor: "+enemy.species)
		var transform := Transform3D(Basis(),enemy.position+Vector3(0,0,-8))
		check(game.player.test_move(transform,Vector3(0,0,12)),"Standing body blocks walking through: "+enemy.species)
	print("ENEMY_CONTACT_FAILURES ",failures)
	quit(failures)
