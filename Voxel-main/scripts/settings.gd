extends Node
## Shared, persistent options for the title screen and the running game.
signal changed(key: String)
signal bindings_changed

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"master": 100.0, "effects": 100.0, "ambience": 80.0, "wildlife": 80.0,
	"graphics": 2, "fov": 0, "fullscreen": true, "vsync": true, "aa": 1,
	"shadows": true, "gi": true, "ssao": true, "glow": true,
	"borders": true, "border_strength": 0.2, "saturation": 1.24, "wind": true,
	"sensitivity": 1.0, "invert_y": false,
	"world_features": false,
}
const KEYS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "skill_sprint": [],
	"equip_sword": [KEY_1], "dodge": [KEY_CTRL],
	"skill_spin": [KEY_Q], "skill_slam": [KEY_R], "skill_cleave": [KEY_C], "skill_dash": [KEY_V],
	"skill_guard": [KEY_X], "skill_heal": [KEY_Z], "skill_berserk": [KEY_U], "skill_execution": [KEY_K],
	"glide": [KEY_F], "attack": [], "use_potion": [KEY_2], "use_food": [KEY_G],
	"interact": [KEY_E], "menu": [KEY_ESCAPE],
	"inventory": [KEY_I], "talents": [KEY_T], "journal": [KEY_J], "map": [KEY_M],
	"build_toggle": [KEY_B], "first_person": [KEY_H], "build_panel": [KEY_TAB],
	"build_rotate": [KEY_R], "build_variant": [KEY_V], "build_mode": [KEY_X],
	"build_grid": [KEY_G], "build_blueprint": [KEY_P],
	"look_left": [], "look_right": [], "look_up": [], "look_down": [],
}
const LABELS := {
	"move_forward": "Vorwärts", "move_back": "Rückwärts", "move_left": "Nach links", "move_right": "Nach rechts",
	"jump": "Springen", "sprint": "Sprinten", 
	"equip_sword": "Slot 1: Schwert / Fäuste", "dodge": "Ausweichrolle",
	"skill_spin": "Wirbelklinge", "skill_slam": "Sprungschlag", "skill_cleave": "Spaltender Hieb", "skill_dash": "Klingensturm",
	"skill_guard": "Klingenwacht", "skill_heal": "Zweiter Atem", "skill_berserk": "Kriegsrausch", "skill_execution": "Hinrichtung",
	"glide": "Gleiten", "attack": "Angreifen / Abbauen (linke Maus)", "use_potion": "Manatrank", "use_food": "Essen",
	"interact": "Interagieren", "inventory": "Inventar", "talents": "Talente", "journal": "Journal", "map": "Karte",
	"build_toggle": "Baumodus", "first_person": "Ego-Perspektive", "build_panel": "Baukasten",
	"build_rotate": "Bauform drehen (Shift: spiegeln)", "build_variant": "Bauvariante", "build_mode": "Bauen / Färben / Kopieren",
	"build_grid": "Bauraster", "build_blueprint": "Bauplan wechseln",
}
var values: Dictionary = DEFAULTS.duplicate()
var bindings := {}
var session_mode := "single"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in DEFAULTS:
			values[key] = cfg.get_value("options", key, DEFAULTS[key])
		# Keep graphics and FOV from older versions of the game.
		for key in ["graphics", "fov", "fullscreen"]:
			values[key] = cfg.get_value("options", key, cfg.get_value("video", key, DEFAULTS[key]))
		for action in LABELS:
			if cfg.has_section_key("bindings", action):
				# Migrate the former hotbar attack binding to the new equipment toggle.
				if action=="attack" and int(cfg.get_value("bindings",action))==KEY_1: continue
				_set_binding(action, int(cfg.get_value("bindings", action)))
	else:
		var screen := DisplayServer.screen_get_size()
		if screen.x * screen.y > 5000000:
			values["graphics"] = 1
	for bus in ["Effects", "Ambience", "Wildlife"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	apply_global()

func _setup_input() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	var pads := {"jump": [JOY_BUTTON_A], "interact": [JOY_BUTTON_Y], "glide": [JOY_BUTTON_B], "attack": [JOY_BUTTON_X],
		"sprint": [JOY_BUTTON_LEFT_STICK], "skill_spin": [JOY_BUTTON_LEFT_SHOULDER], "skill_slam": [JOY_BUTTON_RIGHT_SHOULDER], "dodge": [JOY_BUTTON_RIGHT_STICK], "equip_sword": [JOY_BUTTON_DPAD_LEFT], "use_potion": [JOY_BUTTON_DPAD_UP],
		"use_food": [JOY_BUTTON_DPAD_DOWN], "menu": [JOY_BUTTON_START]}
	for action in pads:
		for button in pads[action]:
			var event := InputEventJoypadButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
		"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
		"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0], "attack": [JOY_AXIS_TRIGGER_RIGHT, 1.0]}
	for action in axes:
		var event := InputEventJoypadMotion.new()
		event.axis = axes[action][0]
		event.axis_value = axes[action][1]
		InputMap.action_add_event(action, event)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mouse)

func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))

func update(key: String, value: Variant) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	apply_global(key)
	save()
	changed.emit(key)

func save() -> void:
	var cfg := ConfigFile.new()
	# Preserve unrelated settings from previous versions.
	cfg.load(PATH)
	for key in values:
		cfg.set_value("options", key, values[key])
	if cfg.has_section("bindings"):
		cfg.erase_section("bindings")
	for action in bindings:
		cfg.set_value("bindings", action, bindings[action])
	var error := cfg.save(PATH)
	if error != OK:
		push_warning("Einstellungen konnten nicht gespeichert werden: %s" % error_string(error))

func apply_global(key := "") -> void:
	for pair in [["Master", "master"], ["Effects", "effects"], ["Ambience", "ambience"], ["Wildlife", "wildlife"]]:
		var index := AudioServer.get_bus_index(pair[0])
		if index >= 0:
			var volume := clampf(float(values[pair[1]]) / 100.0, 0.0, 1.0)
			AudioServer.set_bus_mute(index, volume <= 0.0)
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
	if key == "" or key == "fullscreen":
		var window := get_window()
		window.mode = Window.MODE_FULLSCREEN if values["fullscreen"] else Window.MODE_WINDOWED
	if key == "" or key == "vsync":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
	if key == "" or key in ["borders", "border_strength"]:
		RenderingServer.global_shader_parameter_set("voxel_borders", float(values["border_strength"]) if values["borders"] else 0.0)
	if key == "" or key == "wind":
		RenderingServer.global_shader_parameter_set("plant_motion", 1.0 if values["wind"] else 0.0)

func apply_game(main: Node, key := "") -> void:
	if key == "" or key == "world_features":
		main.apply_world_features()
	if key == "" or key == "graphics":
		main._apply_graphics(clampi(int(values["graphics"]), 0, 2))
	if key == "" or key == "fov":
		main._apply_fov(clampi(int(values["fov"]), 0, 2))
	var env: Environment = main.env.environment
	env.sdfgi_enabled = bool(values["gi"]) and main.gfx_level >= 2
	env.ssao_enabled = bool(values["ssao"]) and main.gfx_level >= 1
	env.glow_enabled = bool(values["glow"])
	env.adjustment_saturation = float(values["saturation"])
	main.sun.shadow_enabled = bool(values["shadows"])
	main.get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(int(values["aa"]), 0, 3)]
	main.cam_rig.mouse_sensitivity = 0.0032 * float(values["sensitivity"])
	main.hud.gfx_level = main.gfx_level
	main.hud.fov_level = main.fov_level
	main.hud.set_menu_labels()

func keycode(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.physical_keycode
	return 0

func key_name(action: String) -> String:
	return OS.get_keycode_string(keycode(action))

func _set_binding(action: String, code: int) -> void:
	if not LABELS.has(action) or code <= 0:
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var event := InputEventKey.new()
	event.physical_keycode = code
	InputMap.action_add_event(action, event)
	bindings[action] = code

func bind_key(action: String, code: int) -> String:
	if code in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_F11, KEY_F3] or code <= 0:
		return "Diese Taste ist für Menü, Chat oder Anzeige reserviert."
	# Builder keys share a separate context (G is food while exploring and grid while building).
	var builder_keys := ["build_panel", "build_rotate", "build_variant", "build_mode", "build_grid", "build_blueprint"]
	for other in LABELS:
		if other == action:
			continue
		var same_context: bool = (other in builder_keys) == (action in builder_keys)
		var shared := ["build_toggle", "inventory", "talents", "journal", "map", "first_person"]
		if same_context or other in shared or action in shared:
			for event in InputMap.action_get_events(other):
				if event is InputEventKey and event.physical_keycode == code:
					return "Bereits belegt: %s. Bitte wähle eine andere Taste." % LABELS[other]
	if action in builder_keys and code >= KEY_0 and code <= KEY_9:
		return "Die Zifferntasten wählen Bauformen. Bitte wähle eine andere Taste."
	if action in builder_keys and code in [KEY_Z, KEY_Y]:
		return "Z und Y bleiben für Rückgängig / Wiederholen reserviert."
	_set_binding(action, code)
	save()
	bindings_changed.emit()
	return ""

func reset_controls() -> void:
	for action in LABELS:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		for code in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action, event)
	bindings.clear()
	save()
	bindings_changed.emit()
