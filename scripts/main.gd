extends Node3D
## Scene root: input setup, NPCs, interactions, quests, saving, graphics presets and the screenshot mode
## used to compare against the concept image:
##   godot --path . -- --shot=out.png --frames=30 [--cam=px,pz,yaw,pitch,dist] [--nohud]

const NPC_SCRIPT := preload("res://scripts/npc.gd")
const REMOTE_SCRIPT := preload("res://scripts/remote_player.gd")

@onready var player: CharacterBody3D = $Player
@onready var cam_rig: Node3D = $CameraRig
@onready var hud: CanvasLayer = $HUD
@onready var env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun

var interactables: Array = []
var crates_found := 3
var elder_talked := false
var _shot_path := ""
var _shot_frames := 30
var _frame := 0
var _t0 := 0
var _current: Variant = null
var remotes := {}            # peer id -> remote hero node
var _net_t := 0.0
var _mp_test := 0.0
var _mp_log_t := 0.0

func _enter_tree() -> void:
	_setup_input()

func _ready() -> void:
	player.cam_rig = cam_rig
	player.model = player.get_node("Model")
	player.anim = player.model
	cam_rig.set_target(player)
	hud.player = player
	hud.cam_rig = cam_rig
	hud.save_requested.connect(_save)
	hud.load_requested.connect(_load)
	hud.quit_requested.connect(func(): get_tree().quit())
	hud.graphics_changed.connect(_apply_graphics)
	hud.fov_changed.connect(_apply_fov)
	player.item_used.connect(func(i): hud.flash_slot(i))
	var data := {}
	var f := FileAccess.open("res://generated/world_data.json", FileAccess.READ)
	if f:
		data = JSON.parse_string(f.get_as_text())
	# let the physics server register the world colliders before ray casting
	await get_tree().physics_frame
	await get_tree().physics_frame
	if data.has("water_meta") and ResourceLoader.exists("res://generated/water_level.res"):
		player.water_img = load("res://generated/water_level.res")
		player.water_meta = data["water_meta"]
	_spawn_npcs(data.get("markers", {}))
	_spawn_crates()
	_spawn_mist(data.get("markers", {}).get("waterfalls", []))
	_spawn_motes()
	var amb := AudioStreamPlayer.new()
	amb.stream = load("res://assets/audio/ambience.wav")
	amb.volume_db = -6.0
	amb.autoplay = true
	add_child(amb)
	hud.minimap.houses = _house_markers()
	Net.roster_changed.connect(_sync_remotes)
	Net.player_state.connect(_on_player_state)
	Net.player_left.connect(_remove_remote)
	_load_settings()
	_parse_args()
	if _shot_path == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_setup_perf()
	_t0 = Time.get_ticks_msec()

# ------------------------------------------------------------------ input
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "skill_sprint": [KEY_Q],
		"glide": [KEY_F], "attack": [KEY_1], "use_potion": [KEY_2], "use_food": [KEY_G],
		"interact": [KEY_E], "menu": [KEY_ESCAPE], "look_left": [], "look_right": [], "look_up": [], "look_down": [],
	}
	var pads := {"jump": [JOY_BUTTON_A], "interact": [JOY_BUTTON_Y], "glide": [JOY_BUTTON_B], "attack": [JOY_BUTTON_X],
		"sprint": [JOY_BUTTON_LEFT_STICK], "skill_sprint": [JOY_BUTTON_LEFT_SHOULDER], "use_potion": [JOY_BUTTON_DPAD_UP],
		"use_food": [JOY_BUTTON_DPAD_DOWN], "menu": [JOY_BUTTON_START]}
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
		"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
		"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for action in pads:
		for b in pads[action]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			InputMap.action_add_event(action, e)
	for action in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = axes[action][0]
		e.axis_value = axes[action][1]
		InputMap.action_add_event(action, e)
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", lmb)
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	InputMap.action_add_event("attack", rt)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3 and _fps_label:
		_fps_label.visible = not _fps_label.visible
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not hud.menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact") and _current != null:
		_interact(_current)

# ------------------------------------------------------------------ NPCs & interactables
func _spawn_npcs(markers: Dictionary) -> void:
	var defs := [
		["npc_market", "elder", "Dorfältester Aldric", 0.6, [
			"Ah, ein neues Gesicht! Willkommen in Grünweiten, Abenteurer.",
			"Seit die Wölfe aus dem Nordwald kommen, ist es unruhig hier.",
			"Bring uns die verlorenen Vorratskisten zurück – eine liegt bei den Häusern am Hang, eine drüben beim Fluss.",
			"Die Burg da oben hat schon bessere Tage gesehen. Wie wir alle."], 0.0],
		["npc_square", "merchant", "Händlerin Mira", 2.2, [
			"Frische Äpfel, Brot und Heiltränke! Nur das Beste vom Markt.",
			"Ein Trank gefällig? Die blauen füllen dein Mana wieder auf.",
			"Hast du den Wasserfall im Norden schon gesehen? Atemberaubend."], 0.0],
		["npc_bridge", "guard", "Wache Bertolt", -1.4, [
			"Halt! ... Ach, nur ein Reisender. Weiter, weiter.",
			"Hinter der Brücke beginnt der Wald. Bleib auf dem Weg.",
			"Ich hab gehört, man kann von der Burg aus bis zu den Gipfeln sehen."], 0.0],
		["npc_castle", "farmer", "Bauer Jost", 0.4, [
			"Der Weizen steht gut dieses Jahr.",
			"Wenn du Hunger hast: Mit G isst du was. Hält Leib und Seele zusammen."], 1.5],
	]
	for d in defs:
		if not markers.has(d[0]):
			continue
		var m: Array = markers[d[0]]
		var npc := StaticBody3D.new()
		npc.set_script(NPC_SCRIPT)
		npc.name = d[2].replace(" ", "")
		npc.display_name = d[2]
		npc.lines = PackedStringArray(d[4])
		npc.model_scene = load("res://generated/char_%s.scn" % d[1])
		npc.rotation.y = d[3]
		npc.wander_radius = d[5]
		npc.player = player
		npc.position = _ground(Vector3(m[0], m[1] + 3.0, m[2]))  # before add_child so _ready() sees its home spot
		add_child(npc)
		npc.talked.connect(_on_npc_talked)
		interactables.append({"node": npc, "kind": "npc", "label": "[E] Mit %s sprechen" % d[2]})

func _spawn_crates() -> void:
	var spots := [Vector3(-20.2, 10.0, -16.8), Vector3(38.6, 10.0, -16.4)]
	for s in spots:
		var c := Node3D.new()
		add_child(c)
		c.global_position = _ground(s)
		var mi := MeshInstance3D.new()
		mi.mesh = load("res://generated/prop_crate.res")
		mi.scale = Vector3.ONE * 1.25
		mi.position.y = 0.0
		c.add_child(mi)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.45)
		l.light_energy = 1.5
		l.omni_range = 3.0
		l.position.y = 0.9
		c.add_child(l)
		var sparkle := Label3D.new()
		sparkle.text = "✦"
		sparkle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sparkle.modulate = Color(1.0, 0.85, 0.4)
		sparkle.font_size = 64
		sparkle.pixel_size = 0.006
		sparkle.position.y = 1.35
		c.add_child(sparkle)
		interactables.append({"node": c, "kind": "crate", "label": "[E] Vorratskiste aufheben"})

func _spawn_mist(falls: Array) -> void:
	# spray as small translucent voxel cubes
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.98, 1.0, 0.42)
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	for f in falls:
		var drop: float = f[3]
		var p := GPUParticles3D.new()
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(float(f[4]) * 0.8, 0.3, float(f[4]) * 0.8)
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 60.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.8 + drop * 0.05
		pm.gravity = Vector3(0, 0.15, 0)
		pm.damping_min = 0.4
		pm.damping_max = 0.8
		pm.scale_min = 1.2 + drop * 0.04
		pm.scale_max = 2.6 + drop * 0.08
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.4))
		sc.add_point(Vector2(1, 1.0))
		var sct := CurveTexture.new()
		sct.curve = sc
		pm.scale_curve = sct
		var cr := Gradient.new()
		cr.set_color(0, Color(1, 1, 1, 0.0))
		cr.add_point(0.2, Color(1, 1, 1, 0.8))
		cr.set_color(cr.get_point_count() - 1, Color(1, 1, 1, 0.0))
		var crt := GradientTexture1D.new()
		crt.gradient = cr
		pm.color_ramp = crt
		p.process_material = pm
		var q := BoxMesh.new()
		q.size = Vector3(0.5, 0.5, 0.5)
		q.material = mat
		p.draw_pass_1 = q
		p.amount = int(clamp(20 + drop * 6.0, 20, 260))
		p.lifetime = 3.0
		p.preprocess = 3.0
		p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 40, 40))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		p.global_position = Vector3(float(f[0]), float(f[1]) + 0.2, float(f[2]))

func _spawn_motes() -> void:
	# warm pollen / dust motes floating in the sunlight around the player
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 3, 14)
	pm.direction = Vector3(0.3, 0.2, 0.1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3(0, 0.02, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var cr := Gradient.new()
	cr.set_color(0, Color(1, 0.9, 0.6, 0))
	cr.add_point(0.3, Color(1, 0.92, 0.65, 1))
	cr.add_point(0.7, Color(1, 0.92, 0.65, 1))
	cr.set_color(cr.get_point_count() - 1, Color(1, 0.9, 0.6, 0))
	var crt := GradientTexture1D.new()
	crt.gradient = cr
	pm.color_ramp = crt
	p.process_material = pm
	var q := BoxMesh.new()
	q.size = Vector3(0.04, 0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.6, 1.4, 1.0)
	# fade motes out right in front of the lens so they never show up as big squares
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 1.2
	mat.distance_fade_max_distance = 3.5
	q.material = mat
	p.draw_pass_1 = q
	p.amount = 260
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-20, -6, -20), Vector3(40, 14, 40))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0, 1.8, 0)
	player.add_child(p)

func _house_markers() -> Array:
	return [[-22.5, -23.5], [-21.5, -10.0], [-12.5, -38.0], [-31.0, -33.0], [-31.0, -15.5], [-34.0, -5.5], [-8.0, -50.0], [-22.5, -49.5], [36.0, -10.0], [-28.0, -72.0]]

func _ground(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 6, 0), p + Vector3(0, -40, 0))
	q.exclude = [player.get_rid()]
	var r := space.intersect_ray(q)
	return r.position if r else p

func _process(delta: float) -> void:
	# nearest interactable
	var best: Variant = null
	var bd := 2.8
	for it in interactables:
		var n: Node3D = it["node"]
		if not is_instance_valid(n) or not n.visible:
			continue
		var d := n.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = it
	_current = best
	hud.set_prompt(best["label"] if best != null else "")
	for it in interactables:
		if it["kind"] == "crate" and is_instance_valid(it["node"]) and it["node"].visible:
			var c: Node3D = it["node"]
			c.get_child(0).rotation.y += delta * 0.6
			c.get_child(2).position.y = 1.35 + sin(Time.get_ticks_msec() / 400.0) * 0.08
	_perf_tick(delta)
	_net_tick(delta)
	_screenshot_tick()

# ------------------------------------------------------------------ multiplayer
func _net_tick(delta: float) -> void:
	var dots := []
	for id in remotes:
		var r: Node3D = remotes[id]
		if r.visible:
			dots.append([Vector2(r.global_position.x, r.global_position.z), Net.color_of(id)])
	hud.minimap.others = dots
	if not Net.active():
		return
	_net_t -= delta
	if _net_t <= 0.0:
		_net_t = 0.05
		var flags := (1 if player.is_on_floor() else 0) | (2 if player.gliding else 0) | (4 if player.swimming else 0)
		Net.send_state(player.global_position, player._facing, player.velocity, flags, player.attack_count)
	if _mp_test > 0.0:
		_mp_test -= delta
		if fmod(_mp_test, 6.0) > 3.0:
			Input.action_press("move_forward")
		else:
			Input.action_release("move_forward")
		_mp_log_t -= delta
		if _mp_log_t <= 0.0:
			_mp_log_t = 1.0
			var info := []
			for id in remotes:
				info.append("%s@%s" % [Net.players.get(id, {}).get("name", "?"), str(remotes[id].global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
			print("[mptest] me=%s id=%d players=%d remotes=%s" % [Net.player_name, Net.my_id(), Net.players.size(), ", ".join(info)])
		if _mp_test <= 0.0:
			print("[mptest] done")
			Net.leave(true)
			get_tree().quit()

func _sync_remotes() -> void:
	var me := Net.my_id()
	for id in Net.players:
		if id == me:
			continue
		var info: Dictionary = Net.players[id]
		if not remotes.has(id):
			var r := Node3D.new()
			r.set_script(REMOTE_SCRIPT)
			add_child(r)
			r.setup(id, str(info["name"]), Net.color_of(id))
			remotes[id] = r
		else:
			remotes[id].apply_identity(str(info["name"]), Net.color_of(id))
	for id in remotes.keys():
		if not Net.players.has(id) or id == me:
			_remove_remote(id)
	# own scarf colour follows the roster colour in multiplayer
	var c := Net.color_of(me)
	var rc := Color(c.r, c.g, c.b, 1.0) if Net.active() and c != Net.COLORS[0] else Color(0, 0, 0, 0)
	for part in ["scarf", "head"]:
		var gi: Node = player.model.get_node_or_null(part)
		if gi is GeometryInstance3D:
			(gi as GeometryInstance3D).set_instance_shader_parameter("recolor", rc)

func _on_player_state(id: int, state: Dictionary) -> void:
	if remotes.has(id):
		remotes[id].push_state(state)

func _remove_remote(id: int) -> void:
	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)

func _interact(it: Dictionary) -> void:
	if it["kind"] == "npc":
		it["node"].interact()
	elif it["kind"] == "crate":
		it["node"].visible = false
		crates_found += 1
		hud.flash_slot(5)
		var done := crates_found >= 5
		hud.set_quest(1, "%d / 5 Kisten finden." % crates_found, done)
		hud.show_toast("Auftrag abgeschlossen: Verlorene Vorräte" if done else "Vorratskiste gefunden (%d / 5)" % crates_found)

func _on_npc_talked(npc: Node) -> void:
	if not elder_talked and npc.display_name.begins_with("Dorfältester"):
		elder_talked = true
		hud.set_quest(0, "Mit dem Dorfältesten gesprochen.", true)
		hud.show_toast("Auftrag abgeschlossen: Ein neuer Anfang")

# ------------------------------------------------------------------ save
func _save() -> void:
	var s := {"pos": [player.global_position.x, player.global_position.y, player.global_position.z],
		"crates": crates_found, "elder": elder_talked}
	var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s))
		hud.show_toast("Spiel gespeichert")

func _load() -> void:
	if not FileAccess.file_exists("user://savegame.json"):
		hud.show_toast("Kein Spielstand vorhanden")
		return
	var s = JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
	if typeof(s) != TYPE_DICTIONARY:
		return
	var p: Array = s.get("pos", [0, 0, 0])
	player.global_position = Vector3(p[0], p[1] + 0.2, p[2])
	player.velocity = Vector3.ZERO
	cam_rig.global_position = player.global_position + Vector3(0, cam_rig.pivot_height, 0)
	if s.get("elder", false) and not elder_talked:
		elder_talked = true
		hud.set_quest(0, "Mit dem Dorfältesten gesprochen.", true)
	var found: int = int(s.get("crates", 3))
	if found > crates_found:
		var to_hide := found - crates_found
		for it in interactables:
			if to_hide > 0 and it["kind"] == "crate" and it["node"].visible:
				it["node"].visible = false
				to_hide -= 1
		crates_found = found
		hud.set_quest(1, "%d / 5 Kisten finden." % crates_found, crates_found >= 5)
	hud.show_toast("Spielstand geladen")

# ------------------------------------------------------------------ graphics presets
const FOV_CAPS := [110.0, 125.0, 179.0]
var gfx_level := 2
var fov_level := 0

func _apply_graphics(level: int) -> void:
	gfx_level = level
	var e: Environment = env.environment
	e.sdfgi_enabled = level >= 2
	e.ssao_enabled = level >= 1
	e.ssil_enabled = false
	e.ambient_light_energy = 1.1 if level >= 2 else 1.35  # make up for the missing bounce light without SDFGI
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if level == 2 else Viewport.SCALING_3D_MODE_FSR2
	get_viewport().scaling_3d_scale = [0.67, 0.8, 1.0][level]
	sun.directional_shadow_max_distance = [120.0, 200.0, 260.0][level]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 8192][level], true)
	# detail distances (voxel LOD bands of terrain, trees, rocks and plants) scale with the preset
	var f: float = [0.7, 0.85, 1.0][level]
	_scale_ranges(f)
	var pmat: ShaderMaterial = load("res://generated/plant_mat.tres")
	pmat.set_shader_parameter("fade_start", 29.0 * f)
	pmat.set_shader_parameter("fade_end", 37.0 * f)
	_save_settings()

var _range_nodes: Array = []

func _scale_ranges(f: float) -> void:
	if _range_nodes.is_empty():
		for n in get_node("World").find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if g.visibility_range_end > 0.0 or g.visibility_range_begin > 0.0:
				_range_nodes.append([g, g.visibility_range_begin, g.visibility_range_end])
	for e in _range_nodes:
		e[0].visibility_range_begin = e[1] * f
		e[0].visibility_range_end = e[2] * f

func _apply_fov(level: int) -> void:
	fov_level = level
	cam_rig.set_hfov_cap(FOV_CAPS[level])
	_save_settings()

func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("video", "graphics", gfx_level)
	cf.set_value("video", "fov", fov_level)
	cf.set_value("video", "fullscreen", get_window().mode == Window.MODE_FULLSCREEN or get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN)
	cf.save("user://settings.cfg")

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") != OK:
		# first start: very large screens (e.g. 5120x1440) start on "Mittel" (80 % render scale + FSR 2)
		var ws := DisplayServer.screen_get_size()
		if ws.x * ws.y > 5000000:
			hud.gfx_level = 1
			hud.set_menu_labels()
			_apply_graphics(1)
		return
	var g: int = cf.get_value("video", "graphics", 2)
	var f: int = cf.get_value("video", "fov", 0)
	hud.gfx_level = g
	hud.fov_level = f
	hud.set_menu_labels()
	_apply_graphics(g)
	_apply_fov(f)

# ------------------------------------------------------------------ performance overlay + log
var _fps_label: Label
var _perf_frames := 0
var _perf_time := 0.0
var _perf_worst := 0.0
var _perf_log_t := 0.0
var _perf_samples: Array = []
var _perf_path := ""

func _setup_perf() -> void:
	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 0.85))
	_fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_fps_label.add_theme_constant_override("shadow_offset_x", 1)
	_fps_label.add_theme_constant_override("shadow_offset_y", 1)
	_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fps_label.offset_left = -520
	_fps_label.offset_top = -28
	_fps_label.offset_right = -12
	_fps_label.offset_bottom = -6
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.root.add_child(_fps_label)
	if OS.has_feature("template"):
		_perf_path = OS.get_executable_path().get_base_dir().path_join("leistung.txt")
	else:
		_perf_path = "user://leistung.txt"
	var f := FileAccess.open(_perf_path, FileAccess.WRITE)
	if f:
		f.store_line("Grünweiten Leistungs-Log  %s" % Time.get_datetime_string_from_system())
		f.store_line("GPU: %s | %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()])
		f.store_line("CPU: %s (%d Threads)" % [OS.get_processor_name(), OS.get_processor_count()])
		f.close()

func _perf_tick(delta: float) -> void:
	if _fps_label == null:
		return
	_perf_frames += 1
	_perf_time += delta
	_perf_worst = maxf(_perf_worst, delta)
	if _perf_time >= 0.5:
		var fps := _perf_frames / _perf_time
		var s := get_viewport().get_visible_rect().size
		var win := get_window().size
		_fps_label.text = "%d FPS  ·  %dx%d  ·  Grafik %s  ·  Sichtfeld %d°  (F3)" % [roundi(fps), win.x, win.y, hud.GFX_NAMES[gfx_level], roundi(cam_rig.camera.fov if cam_rig.camera.keep_aspect == Camera3D.KEEP_WIDTH else rad_to_deg(2.0 * atan(tan(deg_to_rad(cam_rig.base_vfov) * 0.5) * s.x / s.y)))]
		_perf_samples.append([fps, 1.0 / maxf(_perf_worst, 0.0001)])
		_perf_frames = 0
		_perf_time = 0.0
		_perf_worst = 0.0
	_perf_log_t += delta
	if _perf_log_t >= 10.0 and _perf_samples.size() > 0 and _perf_path != "":
		_perf_log_t = 0.0
		var avg := 0.0
		var low := 9999.0
		for smp in _perf_samples:
			avg += smp[0]
			low = minf(low, smp[1])
		avg /= _perf_samples.size()
		_perf_samples.clear()
		var f := FileAccess.open(_perf_path, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
			var p := player.global_position
			f.store_line("%s  avg %.0f FPS  min %.0f FPS  %dx%d  Grafik=%s  Sichtfeld=%s  Pos=(%.0f, %.0f)" % [Time.get_time_string_from_system(), avg, low, get_window().size.x, get_window().size.y, hud.GFX_NAMES[gfx_level], hud.FOV_NAMES[fov_level], p.x, p.z])
			f.close()

# ------------------------------------------------------------------ screenshot mode
func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			_shot_frames = int(a.substr(9))
		elif a.begins_with("--cam="):
			var p := a.substr(6).split(",")
			player.global_position = _ground(Vector3(float(p[0]), 30.0, float(p[1])))
			cam_rig.yaw = deg_to_rad(float(p[2]))
			cam_rig.pitch = deg_to_rad(float(p[3]))
			if p.size() > 4:
				cam_rig.distance = float(p[4])
			player.model.rotation.y = cam_rig.yaw
			player._facing = cam_rig.yaw
			cam_rig.global_position = player.global_position + Vector3(0, cam_rig.pivot_height, 0)
		elif a == "--stats":
			_stats_mode = true
		elif a == "--nohud":
			hud.visible = false
		elif a == "--autotest":
			var at := Node.new()
			at.set_script(load("res://scripts/autotest.gd"))
			at.main = self
			at.player = player
			at.rig = cam_rig
			add_child(at)
		elif a.begins_with("--gfx="):
			_apply_graphics(int(a.substr(6)))
		elif a.begins_with("--name="):
			Net.player_name = a.substr(7)
		elif a == "--host":
			Net.host(Net.player_name)
		elif a.begins_with("--join="):
			var addr := a.substr(7)
			# join once the world runs smoothly (after the first frames)
			get_tree().create_timer(1.0).timeout.connect(func(): Net.join(addr, Net.player_name))
		elif a.begins_with("--mptest="):
			_mp_test = float(a.substr(9))
	if _shot_path != "":
		RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_5_FRAMES)

var _stats_mode := false
var _stats_queue: Array = []
var _stats_base := 0
var _stats_cur: Node3D = null
var _stats_wait := 0
var _stats_suffix := ""

func _prims() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)

## --stats: hide each world group in turn and report how many primitives it costs in this view
func _stats_tick() -> bool:
	if _stats_queue.is_empty() and _stats_cur == null:
		if _stats_base == 0:
			_stats_base = _prims()
			print("[stats] total primitives ", _stats_base, "  draw calls ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			var world := get_node("World")
			for part in world.get_children():
				_stats_queue.append(part)
			for extra in [player, $HUD]:
				pass
			return true
		return false
	if _stats_cur == null:
		var q = _stats_queue.pop_front()
		if q is Array:
			# [part, suffix]: hide only the children whose name ends with the suffix
			_stats_cur = q[0]
			_stats_suffix = q[1]
			for c in _stats_cur.get_children():
				if String(c.name).ends_with(_stats_suffix):
					c.visible = false
		else:
			_stats_cur = q
			_stats_suffix = ""
			_stats_cur.visible = false
			if String(q.name) == "Trees":
				for l in 5:
					_stats_queue.push_front([q, "_l%d" % l])
		_stats_wait = 2
		return true
	_stats_wait -= 1
	if _stats_wait > 0:
		return true
	print("[stats] %-28s %9d" % [String(_stats_cur.name) + _stats_suffix, _stats_base - _prims()])
	if _stats_suffix != "":
		for c in _stats_cur.get_children():
			c.visible = true
	_stats_cur.visible = true
	_stats_cur = null
	return true

func _screenshot_tick() -> void:
	if _shot_path == "":
		return
	if _stats_mode and _frame >= _shot_frames - 1:
		if _stats_tick():
			return
	_frame += 1
	if _frame % 5 == 0:
		print("frame ", _frame, " avg ms ", (Time.get_ticks_msec() - _t0) / float(_frame))
	if _frame >= _shot_frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("saved ", _shot_path, " player at ", player.global_position)
		print("render: primitives %d, draw calls %d, objects %d, video mem %d MB" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576])
		get_tree().quit()
