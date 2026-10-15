extends Node3D
## River and waterfalls are separate 3D sources, never part of a global ambience loop.
const RIVER := [Vector2(63,-152),Vector2(60,-130),Vector2(57,-114),Vector2(52,-103),Vector2(45,-88),Vector2(39,-73),Vector2(34,-62),Vector2(31.5,-56),Vector2(29,-50),Vector2(21.5,-42),Vector2(12,-31),Vector2(9.6,-20),Vector2(10,-8),Vector2(7.5,2),Vector2(4,14),Vector2(-2,28),Vector2(-9,44)]
const FORESTS := [Vector3(-48,12,-96),Vector3(38,5,-106),Vector3(65,8,-130),Vector3(-57,13,-35)]
var main: Node
var listener: AudioListener3D
var river: AudioStreamPlayer3D
var forest: AudioStreamPlayer3D
var falls: Array = []
var wind: AudioStreamPlayer
var river_gain := 0.0
var forest_gain := 0.0
var _timer := 0.0
var _step_timer := 0.0
var river_points: Array = RIVER
var forest_points: Array = FORESTS

func _exit_tree() -> void:
	for source in [river,forest,wind]+falls:
		if is_instance_valid(source):
			source.stop()
			source.stream = null

func setup(game: Node) -> void:
	main = game
	if main.world_data.get("procedural",false):
		river_points = main.world_data.river
		forest_points = main.world_data.forests
	listener = AudioListener3D.new()
	listener.position.y = 1.65
	main.player.add_child(listener)
	listener.make_current()
	river = _source("river", 34.0)
	forest = _source("forest", 42.0)
	for marker in main.world_data.get("markers", {}).get("waterfalls", []):
		# The last field is waterfall width, the fourth the vertical drop.
		var source := _source("waterfall", clampf(28.0 + float(marker[3]), 32.0, 65.0))
		source.position = Vector3(marker[0], marker[1] - float(marker[3]) * 0.35, marker[2])
		falls.append(source)
	wind = AudioStreamPlayer.new()
	wind.stream = _loop("wind")
	wind.bus = "Ambience"
	wind.volume_db = -34.0
	add_child(wind)
	wind.play()
	update_environment(1.0)

func _loop(sound: String) -> AudioStreamWAV:
	var stream: AudioStreamWAV = load("res://assets/audio/wildlife/%s.wav" % sound).duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream

func _source(sound: String, radius: float) -> AudioStreamPlayer3D:
	var source := AudioStreamPlayer3D.new()
	source.name = sound.capitalize()
	source.stream = _loop(sound)
	source.bus = "Ambience"
	# Explicit smooth distance curve, measured at the hero's listener, also allows a true cutoff.
	source.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	source.max_distance = 0.0
	source.volume_db = -80.0
	source.set_meta("radius", radius)
	source.set_meta("gain", 0.0)
	source.attenuation_filter_cutoff_hz = 6000.0
	add_child(source)
	return source

static func distance_gain(distance: float, radius: float) -> float:
	return 1.0 - smoothstep(2.5, radius, distance)

func nearest_water(point: Vector3) -> Vector3:
	if main.world_data.get("streamed",false) and main.generator.land.modern:
		return main.generator.land.nearest_water(Vector2(point.x,point.z))
	var best := Vector3.ZERO
	var distance := INF
	var flat := Vector2(point.x, point.z)
	for i in river_points.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(flat, river_points[i], river_points[i+1])
		var candidate := Vector3(closest.x, 0, closest.y)
		var level: float = main.player.water_level_at(candidate)
		if level < -50.0:
			continue
		candidate.y = level + 0.15
		var d := candidate.distance_squared_to(point)
		if d < distance:
			distance = d
			best = candidate
	return best if distance < INF else Vector3(1000, -1000, 1000)

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.15
		update_environment(0.15)
	_footsteps(delta)

func update_environment(delta: float) -> void:
	var point: Vector3 = listener.global_position
	river.global_position = nearest_water(point)
	river_gain = _mix_source(river, point, delta, -15.0)
	var closest: Vector3 = forest_points[0]
	for anchor: Vector3 in forest_points:
		if anchor.distance_squared_to(point) < closest.distance_squared_to(point):
			closest = anchor
	forest.global_position = closest
	forest_gain = _mix_source(forest, point, delta, -25.0)
	for source: AudioStreamPlayer3D in falls:
		_mix_source(source, point, delta, -11.0)
	var sheltered := _blocked(point, point + Vector3.UP * 4.0)
	wind.volume_db = lerpf(wind.volume_db, -46.0 if sheltered else -34.0, minf(delta * 4.0, 1.0))

func _mix_source(source: AudioStreamPlayer3D, point: Vector3, delta: float, base_db: float) -> float:
	var target := distance_gain(point.distance_to(source.global_position), source.get_meta("radius"))
	if target > 0.01 and _blocked(point, source.global_position + Vector3.UP * 0.5):
		target *= 0.35
	var gain := lerpf(float(source.get_meta("gain")), target, minf(delta * 5.0, 1.0))
	if target <= 0.0 and gain < 0.005:
		gain = 0.0
	source.set_meta("gain", gain)
	source.volume_db = base_db + linear_to_db(maxf(gain, 0.0001))
	if gain > 0.001 and not source.playing:
		source.play()
	elif gain == 0.0 and source.playing:
		source.stop()
	return gain

func _blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [main.player.get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _footsteps(delta: float) -> void:
	_step_timer -= delta
	var player: CharacterBody3D = main.player
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if _step_timer > 0.0 or speed < 1.0 or (not player.is_on_floor() and not player.swimming):
		return
	_step_timer = 0.31 if player.sprinting else 0.48
	var sound := "step_grass"
	if player.swimming:
		sound = "splash"
		_step_timer = 0.7
	else:
		var hit: Dictionary = main.vworld.voxel_ray(player.global_position + Vector3.UP * 0.2, Vector3.DOWN, 1.3)
		if hit.get("hit", false):
			var material: String = main.vworld.materials.get(int(hit["value"]) >> 2, {}).get("name", "")
			if material in ["stone", "cliff", "bricks", "bricks_dark", "cobble", "cobble_mossy", "slate", "planks", "planks_dark"]:
				sound = "step_stone"
	Sfx.play(sound, player.global_position + Vector3.UP * 0.15, -19.0 if sound == "step_grass" else -16.0, 0.08)
