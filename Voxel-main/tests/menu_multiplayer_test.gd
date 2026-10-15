extends SceneTree
var failures := 0
var peer: Node
var messages := {}
var connection_file := ProjectSettings.globalize_path("res://../test-data/menu-multiplayer-connection.json")
var done_file := ProjectSettings.globalize_path("res://../test-data/menu-multiplayer-done.json")
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	print(("PASS " if ok else "FAIL ")+title)
	if not ok: failures += 1
func receive(from_id: int, op: Dictionary) -> void:
	if str(op.get("op","")).begins_with("menu_test_"): messages[op.op] = {"from":from_id,"op":op}
func wait_until(condition: Callable, timeout := 75.0) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call():
		await process_frame
		if Time.get_ticks_msec()-start>timeout*1000: return false
	return true
func ready_world() -> Node:
	if not await wait_until(func(): return current_scene!=null and current_scene.get("world_ready")==true):
		check(false,"Shared world loads before timeout"); quit(1); return null
	current_scene.player.set_physics_process(false)
	return current_scene
func menu_lobby() -> Control:
	current_scene._multiplayer()
	for node in current_scene.get_children():
		if node.get_script()==load("res://scripts/ui/multiplayer_setup.gd"): return node
	return null
func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()
func read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
func run() -> void:
	peer = root.get_node("Net")
	peer.broker_override = "ws://127.0.0.1:18081"
	peer.op_received.connect(receive)
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Settings").update("world_features",false)
	if "--server" in OS.get_cmdline_user_args(): await host_test()
	else: await guest_test()
	print("MENU_MULTIPLAYER_FAILURES ",failures)
	quit(failures)
func host_test() -> void:
	root.get_node("Worlds").new_world({"seed_text":"Die-echte-Host-Welt","size":0,"villages":1,"difficulty":0})
	change_scene_to_file("res://scenes/main.tscn")
	var game := await ready_world()
	if game==null: return
	var descriptor: Dictionary = root.get_node("Worlds").config.duplicate(true)
	var probe: Vector3i = game.vworld.to_voxel(game.player.spawn_point-Vector3(0,1.5,0))
	game.vworld.set_list(PackedInt32Array([probe.x,probe.y,probe.z,54<<2]))
	check(peer.host_online("MenuHost"),"Host opens friend-code session in its own world")
	check(await wait_until(func(): return peer.active()),"Local MQTT mailbox accepts host")
	write_json(connection_file,{"stage":1,"code":peer.online_code,"world":descriptor.id,"probe":[probe.x,probe.y,probe.z]})
	check(await wait_until(func(): return messages.has("menu_test_loaded1")),"Guest joins through title-menu Beitreten button")
	if not messages.has("menu_test_loaded1"): return
	var id: int = messages.menu_test_loaded1.from
	var report: Dictionary = messages.menu_test_loaded1.op
	check(report.world==descriptor.id and report.edited,"Guest receives host identity and edited terrain")
	check(await wait_until(func(): return game.remotes.has(id) and game.remotes[id].visible),"Host sees guest avatar in the shared world")
	game._offer_world(id)
	game._offer_world(id)
	peer.send_op_to(id,{"op":"menu_test_duplicates"})
	check(await wait_until(func(): return messages.has("menu_test_loaded2")),"Joining from a different single-player world switches to host world")
	if not messages.has("menu_test_loaded2"): return
	check(messages.menu_test_loaded2.op.world==descriptor.id,"Second join uses the original host map")
	await game.hud._return_to_title()
	check(await wait_until(func(): return current_scene!=null and current_scene.name=="MainMenu"),"Host leaves through the real pause-menu action")
	check(await wait_until(func(): return FileAccess.file_exists(done_file)),"Guest returns to title after host leaves")
	if FileAccess.file_exists(done_file): check(read_json(done_file).get("stage",0)==2,"Guest confirms no disconnected world remains playable")
	# Close the next session while the guest is still generating its map.
	root.get_node("Worlds").resume_world(descriptor)
	change_scene_to_file("res://scenes/main.tscn")
	game = await ready_world()
	if game==null: return
	check(peer.host_online("MenuHost"),"Host can open a fresh session after returning to title")
	check(await wait_until(func(): return peer.active()),"Fresh MQTT session is connected")
	write_json(connection_file,{"stage":3,"code":peer.online_code,"world":descriptor.id})
	check(await wait_until(func(): return messages.has("menu_test_loading")),"Guest begins loading the next host session")
	await game.hud._return_to_title()
	check(await wait_until(func(): return FileAccess.file_exists(done_file) and read_json(done_file).get("stage",0)==3),"Host departure also cancels guest world generation")
func guest_test() -> void:
	change_scene_to_file("res://scenes/menu.tscn")
	check(await wait_until(func(): return FileAccess.file_exists(connection_file)),"Host publishes a local test friend code")
	if not FileAccess.file_exists(connection_file): return
	var connection := read_json(connection_file)
	var title := current_scene
	var lobby := menu_lobby()
	check(lobby!=null,"Title multiplayer opens the actual joining form")
	if lobby==null: return
	lobby.player_name.text = "MenuGuest"
	lobby.address.text = connection.code
	lobby.join_button.pressed.emit()
	check(lobby.join_button.disabled and peer.joining(),"Joining displays pending state and prevents duplicate clicks")
	title._single()
	check(current_scene==title,"Single-player creation cannot interrupt a pending join")
	var game := await ready_world()
	if game==null: return
	check(root.get_node("Worlds").remote and root.get_node("Worlds").config.id==connection.world,"Menu join loads host seed and settings automatically")
	var probe := Vector3i(connection.probe[0],connection.probe[1],connection.probe[2])
	check(await wait_until(func(): return game.vworld.vol.get_voxel(probe)>>2==54),"Host's saved terrain change arrives after generation")
	check(await wait_until(func(): return game.remotes.has(1) and game.remotes[1].visible),"Guest sees the host avatar")
	var instance := game.get_instance_id()
	peer.send_op_to(1,{"op":"menu_test_loaded1","world":root.get_node("Worlds").config.id,"edited":game.vworld.vol.get_voxel(probe)>>2==54})
	check(await wait_until(func(): return messages.has("menu_test_duplicates")),"Duplicate host offers arrive")
	for i in 15: await process_frame
	check(current_scene.get_instance_id()==instance,"Repeated world offers do not reload or reset the guest scene")
	await game.hud._return_to_title()
	check(await wait_until(func(): return current_scene!=null and current_scene.name=="MainMenu"),"Guest can return to title voluntarily")
	current_scene._single()
	var form: Control
	for node in current_scene.get_children():
		if node.get_script()==load("res://scripts/ui/world_creation.gd"): form = node
	form.fields.seed_text.text = "Meine-andere-Einzelspielerwelt"
	form.fields.size.select(0); form.fields.villages.select(0)
	form.create()
	game = await ready_world()
	if game==null: return
	check(not peer.active() and not root.get_node("Worlds").remote,"Own single-player world starts disconnected")
	var own_id: String = root.get_node("Worlds").config.id
	game.player.hp = 77
	root.get_node("Game").inv.gold = 456
	game.hud.mp_name.text = "MenuGuest"
	game.hud.mp_ip.text = connection.code
	game.hud._join_from_field()
	check(await wait_until(func(): return current_scene!=null and current_scene.get("world_ready")==true and root.get_node("Worlds").remote),"In-game join replaces the unrelated single-player map")
	game = await ready_world()
	if game==null: return
	check(root.get_node("Worlds").config.id==connection.world and root.get_node("Worlds").config.id!=own_id,"Guest and host share the same world after switching")
	check(await wait_until(func(): return game.vworld.vol.get_voxel(probe)>>2==54),"World switch restores the host's terrain edits")
	peer.send_op_to(1,{"op":"menu_test_loaded2","world":root.get_node("Worlds").config.id})
	check(await wait_until(func(): return current_scene!=null and current_scene.name=="MainMenu",15),"Host leaving ejects guest to the main menu")
	check(not peer.active() and not root.get_node("Worlds").remote and not peer.world_loading,"Disconnected guest session and loading state are cleared")
	check(not root.get_node("Worlds").saved_worlds().is_empty(),"Guest's separate single-player save is preserved")
	var solo_save := FileAccess.open("user://worlds/%s.dat" % own_id,FileAccess.READ)
	var saved: Dictionary = solo_save.get_var(false)
	check(float(saved.vitals.hp)==77 and int(saved.game.inv.gold)==456,"Joining saves the latest solo progress under its own world identity")
	write_json(done_file,{"stage":2})
	check(await wait_until(func(): return read_json(connection_file).get("stage",0)==3),"Host starts the cancellation test")
	connection = read_json(connection_file)
	lobby = menu_lobby()
	lobby.player_name.text = "MenuGuest"
	lobby.address.text = connection.code
	lobby.join_button.pressed.emit()
	check(await wait_until(func(): return peer.world_loading),"Guest receives the next world offer")
	peer.send_op_to(1,{"op":"menu_test_loading"})
	check(await wait_until(func(): return current_scene!=null and current_scene.name=="MainMenu" and not peer.joining(),15),"Departure during loading returns guest to title")
	check(not peer.active() and not root.get_node("Worlds").remote,"Cancelled loading cannot reconnect or create a local ghost world")
	write_json(done_file,{"stage":3})
