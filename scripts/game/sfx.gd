extends Node
## Sound effects (autoload "Sfx"): small pool of 3D and UI players, random variants, pitch jitter.

var _streams := {}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _last := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in ["dig0", "dig1", "dig2", "chip0", "chip1", "chip2", "chop0", "chop1", "chop2", "crack", "crash", "crumble",
			"pickup", "place", "remove", "clink", "levelup", "click", "whoosh", "treasure"]:
		var p := "res://assets/audio/sfx_%s.wav" % n
		if ResourceLoader.exists(p):
			_streams[n] = load(p)
	for i in 12:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 6.0
		a.max_distance = 60.0
		a.attenuation_filter_cutoff_hz = 9000.0
		add_child(a)
		_pool3d.append(a)
	for i in 6:
		var b := AudioStreamPlayer.new()
		add_child(b)
		_pool2d.append(b)

func _pick(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var vars := []
	for i in 3:
		if _streams.has(name + str(i)):
			vars.append(_streams[name + str(i)])
	return vars[randi() % vars.size()] if not vars.is_empty() else null

## play at a world position (or as UI sound when pos is null); min_gap avoids machine-gun repeats
func play(name: String, pos: Variant = null, db := 0.0, pitch_jitter := 0.08, min_gap := 0.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if min_gap > 0.0 and now - float(_last.get(name, -10.0)) < min_gap:
		return
	_last[name] = now
	var s := _pick(name)
	if s == null:
		return
	if pos == null:
		var b := _pool2d[_i2]
		_i2 = (_i2 + 1) % _pool2d.size()
		b.stream = s
		b.volume_db = db
		b.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		b.play()
	else:
		var a := _pool3d[_i3]
		_i3 = (_i3 + 1) % _pool3d.size()
		a.stream = s
		a.volume_db = db
		a.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		a.global_position = pos
		a.play()
