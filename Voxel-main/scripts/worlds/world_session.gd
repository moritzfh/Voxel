extends Node
## A world descriptor is separate from player progress and the untouched demonstration map.
const VERSION := 2
const DEFAULTS := {"name":"Meine Grünweiten", "seed_text":"", "size":1, "landscape":1,
	"forest":1, "rivers":true, "villages":2, "caves":true, "ruins":true, "difficulty":2,"encounter_version":1,"terrain_version":2}
var config: Dictionary = {}
var continuing := false
var remote := false
var join_spawn: Array = []

func new_world(options: Dictionary) -> void:
	config = DEFAULTS.duplicate()
	config.merge(options,true)
	var text := str(config.seed_text).strip_edges()
	if text.is_empty(): text = str(randi_range(1,2147483646))
	config.seed_text = text
	config.seed = int(text) if text.is_valid_int() else int(text.hash())
	config.name = str(config.name).strip_edges().left(40)
	if str(config.name).is_empty(): config.name = "Meine Grünweiten"
	for key in ["size","landscape","forest"]: config[key] = clampi(int(config[key]),0,2)
	config.villages = clampi(int(config.villages),1,3)
	config.difficulty = clampi(int(config.difficulty),0,3)
	config.terrain_version = 2
	config.version = VERSION
	config.id = "%d_%d" % [Time.get_unix_time_from_system(),randi()]
	continuing = false
	remote = false
	join_spawn = []

func test_map(load_saved := false) -> void:
	config = {}
	continuing = load_saved
	remote = false
	join_spawn = []

func save_path() -> String:
	return "user://spielstand.dat" if config.is_empty() else "user://worlds/%s.dat" % config.id

func remember() -> Error:
	if config.is_empty(): return OK
	DirAccess.make_dir_recursive_absolute("user://worlds")
	var file := ConfigFile.new()
	file.set_value("world","config",config)
	file.set_value("world","played",Time.get_datetime_string_from_system())
	return file.save("user://worlds/%s.cfg" % config.id)

func saved_worlds() -> Array:
	var result := []
	var dir := DirAccess.open("user://worlds")
	if dir == null: return result
	for name in dir.get_files():
		if not name.ends_with(".cfg"): continue
		var file := ConfigFile.new()
		if file.load("user://worlds/"+name) != OK: continue
		var descriptor: Variant = file.get_value("world","config",{})
		if descriptor is Dictionary and int(descriptor.get("version",0)) in [1,VERSION] and FileAccess.file_exists("user://worlds/%s.dat" % descriptor.get("id","")):
			result.append({"config":descriptor,"played":file.get_value("world","played","")})
	result.sort_custom(func(a: Dictionary,b: Dictionary): return a.played > b.played)
	return result

func resume_world(descriptor: Dictionary) -> void:
	config = descriptor.duplicate(true)
	continuing = true
	remote = false
	join_spawn = []

func damage_multiplier() -> float:
	return 1.0 if config.is_empty() else [0.0,0.55,1.0,1.6][int(config.difficulty)]
