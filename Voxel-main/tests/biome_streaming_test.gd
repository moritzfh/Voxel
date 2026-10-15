extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures += 1
func run() -> void:
	root.get_node("Settings").update("fullscreen",false)
	root.get_node("Worlds").new_world({"seed_text":"Streaming-Natur-2026","size":1,"villages":1,"difficulty":0})
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene==null or not current_scene.world_ready: await process_frame
	var game := current_scene
	game.player.set_physics_process(false)
	var generator: Node = game.generator
	var start: Vector3 = game.player.position
	# Velocity lookahead is independent of the follow camera and includes fine terrain.
	game.player.velocity = Vector3(26,0,0)
	generator._retarget()
	var prediction: Vector2i = generator.chunk_of(start+Vector3(78,0,0))
	check(generator.wanted.has(prediction),"Fast movement queues terrain three seconds ahead")
	var fine_ahead := false
	for job in generator.queue:
		if job.key==prediction and job.fine: fine_ahead = true
	for worker in generator.workers:
		if worker.key==prediction and worker.fine: fine_ahead = true
	if generator.chunks.has(prediction): fine_ahead = generator.chunks[prediction].fine
	check(fine_ahead,"Lookahead includes fine collision chunks")
	var durations: Array[float] = []
	var last := Time.get_ticks_usec()
	var ready := 0
	var travel_start := Time.get_ticks_usec()
	var pipeline_monitors := []
	for name in ClassDB.class_get_integer_constant_list("Performance"):
		if "PIPELINE" in name: pipeline_monitors.append(name)
	for frame in 480:
		var p := start+Vector3((Time.get_ticks_usec()-travel_start)/1000000.0*20.0,0,0)
		p.y = generator.land.height(Vector2(p.x,p.z))+1
		game.player.position = p
		game.player.velocity = Vector3(20,0,0)
		if generator.movement_ready(p): ready += 1
		await create_timer(1.0/60.0).timeout
		var now := Time.get_ticks_usec()
		if now-last>80000:
			var counters := {}
			for name in pipeline_monitors: counters[name] = Performance.get_monitor(ClassDB.class_get_integer_constant("Performance",name))
			print("FRAME_SPIKE ms=",(now-last)/1000.0," frame=",frame," x=",p.x," life_max=",generator.max_decoration_us/1000.0," pipelines=",counters)
		durations.append((now-last)/1000.0)
		last = now
	durations.sort()
	print("STREAM_PROFILE frames=",durations.size()," p50_ms=",durations[240]," p99_ms=",durations[475]," max_ms=",durations[-1]," install_max_ms=",generator.max_install_us/1000.0," horizon_max_ms=",generator.max_horizon_us/1000.0," life_max_ms=",generator.max_decoration_us/1000.0," ready=",ready," cache_hits=",generator.cache_hits," generated=",generator.generated_chunks)
	check(ready>=470,"Collision terrain remains available during sustained 20 m/s travel")
	check(generator.completed.size()<=4,"Completed worker uploads stay bounded")
	check(generator.land.regions.size()<40,"Long travel keeps layout memory bounded")
	var key: Vector2i = generator.chunk_of(game.player.position)
	generator.ensure_sync(key)
	# Exercise the simplified terrain collider with a real physics ray and falling character.
	var test_point: Vector3 = game.player.position
	test_point.y = generator.land.height(Vector2(test_point.x,test_point.z))+4
	game.player.position = test_point
	game.player.velocity = Vector3.ZERO
	game.player.set_physics_process(true)
	for i in 100: await physics_frame
	check(game.player.is_on_floor() and game.player.position.y>test_point.y-5,"Streamed terrain supports the physical player after landing")
	game.player.set_physics_process(false)
	check(generator.life.spawn_queue.is_empty(),"Deferred animal spawns finish after movement stops")
	var spawned := true
	for group in game.enemies.chunks.values():
		for id in group:
			if not game.wildlife.by_id.has(id): spawned = false
	check(spawned,"Deferred enemy groups actually appear in their resident chunks")
	var raw: PackedByteArray = game.vworld.vol.get_chunk_data(key.x,key.y)
	generator.unload_chunk(key)
	generator.ensure_sync(key)
	check(game.vworld.vol.get_chunk_data(key.x,key.y)==raw,"Visited terrain restores from persisted data after eviction")
	check(not game.vworld.modified.has(key),"Reading cached terrain does not create fake player edits")
	print("BIOME_STREAMING_FAILURES ",failures)
	quit(failures)
