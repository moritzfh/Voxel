extends Node3D
## Scene root: input setup, NPCs, interactions, quests, saving, graphics presets and the screenshot mode
## used to compare against the concept image:
##   godot --path . -- --shot=out.png --frames=30 [--cam=px,pz,yaw,pitch,dist] [--nohud]

const NPC_SCRIPT := preload("res://scripts/npc.gd")
const REMOTE_SCRIPT := preload("res://scripts/remote_player.gd")
const VOXEL_WORLD := preload("res://scripts/voxel/voxel_world.gd")
const TOOLS := preload("res://scripts/game/tools.gd")
const BUILDER := preload("res://scripts/game/builder.gd")
const GAME_PANELS := preload("res://scripts/ui/game_panels.gd")
const GHOST_SHADER := preload("res://shaders/voxel_ghost.gdshader")
const XRAY_SHADER := preload("res://shaders/voxel_xray.gdshader")
## quest "Der Wachturm": a glowing outline of a round tower by the river that the player fills with voxels
const BUILD_SITE := [18.0, 0.0, 2.0]

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
var vworld: Node3D           # editable voxel terrain
var tools: Node              # mining / chopping
var builder: Node            # build mode
var panels: Control          # inventory / crafting / talents / journal / map
var world_data := {}
var build_site: Array = []   # [x, y, z] of the tower outline (world), empty when unused
var _site_obj: VoxelObject
var _site_at := Vector3i.ZERO
var _site_node: Node3D
var _bq_t := 0.0
var _snap := {}              # incoming world snapshot parts (late join)
var _bx_origin := Vector2(-18, 28)
var _bx_ui := ""
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
	world_data = data
	vworld = Node3D.new()
	vworld.name = "VoxelWorld"
	vworld.set_script(VOXEL_WORLD)
	add_child(vworld)
	vworld.setup($World, data)
	tools = Node.new()
	tools.name = "Tools"
	tools.set_script(TOOLS)
	add_child(tools)
	tools.setup(self)
	builder = Node.new()
	builder.name = "Builder"
	builder.set_script(BUILDER)
	add_child(builder)
	builder.setup(self)
	panels = Control.new()
	panels.name = "Panels"
	panels.set_script(GAME_PANELS)
	hud.root.add_child(panels)
	panels.setup(self)
	_spawn_runes(data.get("markers", {}))
	_setup_build_site()
	Net.op_received.connect(_on_net_op)
	Net.player_joined.connect(_send_snapshot)
	Game.quests_changed.connect(hud.refresh_quests)
	Game.quests_changed.connect(_update_build_site)
	hud.refresh_quests()
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
	_build_quest_tick(delta)
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

## world edits are sent to the other players as small deterministic operations
func net_op(op: Dictionary) -> void:
	if Net.active():
		Net.send_op(op)

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
	if it["kind"] == "rune":
		_touch_rune(it)
		return
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
const SAVE_PATH := "user://spielstand.dat"

func _save() -> void:
	var s := {"v": 2, "pos": [player.global_position.x, player.global_position.y, player.global_position.z],
		"crates": crates_found, "elder": elder_talked, "game": Game.to_dict(), "world": vworld.save_state(),
		"props": tools.save_props()}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_var(s, false)
		f.close()
		hud.show_toast("Spiel gespeichert")

func _load() -> void:
	var s: Variant = null
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			s = f.get_var(false)
	elif FileAccess.file_exists("user://savegame.json"):
		s = JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
	if typeof(s) != TYPE_DICTIONARY:
		hud.show_toast("Kein Spielstand vorhanden")
		return
	var p: Array = s.get("pos", [0, 0, 0])
	if s.has("world"):
		vworld.load_state(s["world"])
	if s.has("props"):
		tools.load_props(s["props"])
	if s.has("game"):
		Game.from_dict(s["game"])
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
	for it in interactables:
		if it["kind"] == "rune" and int(it["index"]) in Game.runes_found:
			_rune_glow(it, false)
	_update_build_site()
	hud.show_toast("Spielstand geladen")

# ------------------------------------------------------------------ runes
func _spawn_runes(markers: Dictionary) -> void:
	var runes: Array = markers.get("runes", [])
	for i in runes.size():
		var r: Array = runes[i]
		var n := Node3D.new()
		n.name = "Rune%d" % i
		add_child(n)
		n.global_position = Vector3(r[0], r[1] + 1.0, r[2])
		var l := OmniLight3D.new()
		l.light_color = Color(0.45, 0.7, 1.0)
		l.light_energy = 0.0
		l.omni_range = 5.0
		l.position.y = 0.6
		n.add_child(l)
		interactables.append({"node": n, "kind": "rune", "index": i, "label": "[E] Runenstein berühren"})

func _touch_rune(it: Dictionary) -> void:
	var i: int = it["index"]
	if i in Game.runes_found:
		return
	Game.runes_found.append(i)
	Game.add_xp(120)
	Game.notify.emit("Runenstein berührt (%d / 8)" % Game.runes_found.size(), Color(0.6, 0.8, 1.0))
	Sfx.play("treasure", null, -4.0)
	_rune_glow(it, true)
	Game._check_quests()

func _rune_glow(it: Dictionary, fx: bool) -> void:
	var n: Node3D = it["node"]
	it["label"] = "Runenstein (berührt)"
	var l: OmniLight3D = n.get_child(0)
	if fx:
		var tw := create_tween()
		tw.tween_property(l, "light_energy", 2.2, 0.6)
		for k in 36:
			tools.debris.spawn(n.global_position + Vector3(randf_range(-0.4, 0.4), randf_range(-0.6, 0.6), randf_range(-0.4, 0.4)), (59 << 2) | (k % 3), Vector3.UP, false, 0.9, 0.7)
	else:
		l.light_energy = 2.2

# ------------------------------------------------------------------ build quest site
func _setup_build_site() -> void:
	var g := _ground(Vector3(BUILD_SITE[0], 40.0, BUILD_SITE[2]))
	build_site = [g.x, g.y, g.z]
	_site_obj = vworld.new_object()
	_site_obj.fill_shape(2, Vector3i(32, 48, 32), {"hollow": true, "thick": 3, "open_top": true, "crenel": 4}, 4 << 2)
	var c: Vector3i = vworld.to_voxel(g)
	_site_at = Vector3i(c.x - 16, c.y + 1, c.z - 16)
	_site_node = Node3D.new()
	_site_node.name = "BuildSite"
	add_child(_site_node)
	var gm := ShaderMaterial.new()
	gm.shader = GHOST_SHADER
	var vm := vworld.vmat as ShaderMaterial
	for prm in ["palette", "emission_tab", "roughness_tab", "jitter_tab"]:
		gm.set_shader_parameter(prm, vm.get_shader_parameter(prm))
	gm.set_shader_parameter("tint", Color(1.0, 0.82, 0.35))
	gm.set_shader_parameter("solid_colors", false)
	gm.set_shader_parameter("alpha", 0.28)
	gm.set_shader_parameter("tint_mix", 0.8)
	gm.set_shader_parameter("height", 6.0)
	var xm := ShaderMaterial.new()
	xm.shader = XRAY_SHADER
	xm.set_shader_parameter("tint", Color(1.0, 0.82, 0.35))
	xm.set_shader_parameter("strength", 0.08)
	gm.next_pass = xm
	var mi := MeshInstance3D.new()
	mi.mesh = vworld.array_mesh(_site_obj.mesh(0, false, Vector3.ZERO), gm)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_site_node.add_child(mi)
	_site_node.global_position = vworld.to_world(_site_at)
	var lbl := Label3D.new()
	lbl.text = "Wachturm\nfülle den Umriss mit Voxeln"
	lbl.font = load("res://assets/fonts/alegreya-latin-700-normal.woff2")
	lbl.font_size = 64
	lbl.pixel_size = 0.008
	lbl.outline_size = 14
	lbl.modulate = Color(1.0, 0.9, 0.6)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(2.0, 7.2, 2.0)
	_site_node.add_child(lbl)
	_update_build_site()

func _update_build_site() -> void:
	if _site_node == null:
		return
	var on: bool = Game.quests.has("wachturm") and Game.quests["wachturm"]["state"] == "active"
	_site_node.visible = on

func _build_quest_tick(delta: float) -> void:
	if _site_node == null or not _site_node.visible:
		return
	_bq_t -= delta
	if _bq_t > 0.0:
		return
	_bq_t = 1.0
	var total := _site_obj.solid_count()
	var have: int = vworld.vol.count_overlap(_site_obj, _site_at)
	var prog := float(have) / float(maxi(1, total))
	if absf(prog - Game.build_quest_progress) > 0.004:
		Game.build_quest_progress = prog
		Game._check_quests()

# ------------------------------------------------------------------ multiplayer world sync
func _on_net_op(_from: int, op: Dictionary) -> void:
	match str(op.get("op", "")):
		"carve":
			var r: Dictionary = vworld.carve(op["at"], op["n"], int(op["c"]), int(op["h"]), int(op["s"]), float(op["j"]))
			var removed: PackedInt32Array = r.get("removed", PackedInt32Array())
			if not removed.is_empty():
				tools.debris.burst_voxels(removed, vworld, Vector3(op["n"]), false, 18)
				Sfx.play("dig", vworld.to_world(op["at"]), -4.0)
		"prop":
			var po: Node = tools.get_prop(op["k"], op["meta"], null)
			if po:
				tools.apply_prop_hit(po, op["p"], op["f"], int(op["pw"]), int(op["s"]), int(op["h"]), false)
		"obj", "chg":
			builder.apply_remote(op)
			print_verbose("[net] build op ", op["op"])
		"snap":
			_snap[int(op["i"])] = op["d"]
			if _snap.size() >= int(op["n"]):
				var all := PackedByteArray()
				for k in int(op["n"]):
					all.append_array(_snap[k])
				_snap = {}
				var d: Variant = bytes_to_var(all.decompress(int(op["raw"]), FileAccess.COMPRESSION_ZSTD))
				if d is Dictionary:
					print("[snap] world chunks %d, props %d" % [(d.get("w", {}) as Dictionary).size(), (d.get("p", []) as Array).size()])
					vworld.load_state(d.get("w", {}))
					tools.load_props(d.get("p", []))
					hud.show_toast("Welt vom Host übernommen", 2.0)

## the host sends a new player everything that changed (terrain chunks, felled trees, mined rocks)
func _send_snapshot(id: int) -> void:
	var w: Dictionary = vworld.save_state()
	var pr: Array = tools.save_props()
	if w.is_empty() and pr.is_empty():
		return
	var raw := var_to_bytes({"w": w, "p": pr})
	var comp := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var part := 48000
	var n := (comp.size() + part - 1) / part
	for k in n:
		Net.send_op_to(id, {"op": "snap", "i": k, "n": n, "raw": raw.size(), "d": comp.slice(k * part, mini(comp.size(), (k + 1) * part))})

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
		elif a == "--vxtest":
			get_tree().create_timer(0.5).timeout.connect(_vx_test)
		elif a == "--bxtest":
			get_tree().create_timer(0.5).timeout.connect(_bx_test)
		elif a.begins_with("--quest="):
			var qid := a.substr(8)
			get_tree().create_timer(0.3).timeout.connect(func():
				Game.start_quest(qid)
				Game.quests_changed.emit())
		elif a == "--savetest":
			get_tree().create_timer(4.0).timeout.connect(func():
				Game.add("gold", 77)
				_save()
				print("[save] saved, modified chunks ", vworld.modified.size())
				get_tree().quit())
		elif a == "--loadtest":
			get_tree().create_timer(1.0).timeout.connect(func():
				_load()
				print("[save] loaded, modified chunks ", vworld.modified.size(), " gold ", Game.count("gold"), " bp ", Game.blueprints.size())
				get_tree().quit())
		elif a == "--bxshow":
			get_tree().create_timer(0.5).timeout.connect(_bx_show)
		elif a.begins_with("--bxshow-at="):
			get_tree().create_timer(float(a.substr(12))).timeout.connect(_bx_show)
		elif a.begins_with("--bxorigin="):
			var bo := a.substr(11).split(",")
			_bx_origin = Vector2(float(bo[0]), float(bo[1]))
		elif a.begins_with("--bxui="):
			_bx_ui = a.substr(7)
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
		elif a == "--mpmenu":
			get_tree().create_timer(0.5).timeout.connect(func():
				hud.toggle_menu(true)
				hud._show_mp(true))
		elif a.begins_with("--broker="):
			Net.broker_override = a.substr(9)
		elif a == "--host-online":
			Net.host_online(Net.player_name)
		elif a.begins_with("--join-code="):
			var jc := a.substr(12)
			get_tree().create_timer(1.0).timeout.connect(func(): Net.join_code(jc, Net.player_name))
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

func _vx_test() -> void:
	# scripted mining / chopping test (headless): dig in front of the spawn, fell the nearest tree
	var p := player.global_position + Vector3(0, 0, -5)
	var hit: Dictionary = vworld.voxel_ray(p + Vector3(0, 4, 0), Vector3.DOWN, 20.0)
	print("[vx] ground ", hit.get("voxel"), " value ", hit.get("value"))
	for i in 8:
		var h: Dictionary = vworld.voxel_ray(p + Vector3(0, 4, 0), Vector3.DOWN, 20.0)
		tools._mine_voxel({"kind": "voxel", "voxel": h["voxel"], "normal": h["normal"], "value": int(h["value"]), "point": h["point"], "from": p + Vector3(0, 4, 0)})
	print("[vx] inv after digging ", Game.inv, " xp ", Game.xp, " lvl ", Game.level, " live ms ", vworld._stats)
	var best: CollisionShape3D = null
	var bd := 1e9
	for cs in $World.find_children("tree_*", "CollisionShape3D", true, false):
		var d := (cs as Node3D).global_position.distance_to(player.global_position)
		if d < bd and cs.has_meta("tree"):
			bd = d
			best = cs
	print("[vx] nearest tree ", best.get_meta("tree") if best else null, " at ", bd)
	if best:
		var m: Dictionary = best.get_meta("tree")
		var tp := Vector3(m["pos"][0], m["pos"][1], m["pos"][2])
		for i in 30:
			var po: Node = tools.get_prop("tree", m, best)
			if po.felled:
				print("[vx] felled after ", i, " hits")
				break
			var from := tp + Vector3(2.5, 1.2, 0.3)
			tools._cd = 0.0
			tools.target = {"kind": "tree", "prop": po, "point": tp + Vector3(0.25, 1.0, 0.0), "from": from}
			tools._hit_prop(tools.target)
	await get_tree().create_timer(6.0).timeout
	var logs := get_tree().get_nodes_in_group("logs")
	print("[vx] after fall: inv ", Game.inv, " trees ", Game.trees_felled, " bodies ", get_children().filter(func(c): return c is RigidBody3D).size())
	if _shot_path == "":
		get_tree().quit()

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

# ------------------------------------------------------------------ build test (headless or with --shot)
func _bx_aim(x: float, z: float) -> Dictionary:
	var h: Dictionary = vworld.voxel_ray(Vector3(x, 60.0, z), Vector3.DOWN, 120.0)
	return {"voxel": h["voxel"], "normal": h["normal"], "point": h["point"], "value": int(h["value"])}

func _bx_place(label: String, shape: String, variant: int, size: Vector3i, x: float, z: float, op := 0, drag_to := Vector2.INF) -> void:
	var b := builder
	for i in b.SHAPES.size():
		if b.SHAPES[i]["id"] == shape:
			b.shape_i = i
	b.bp_i = -1
	b.variants[shape] = variant
	b.sizes[shape] = size
	b.aim = _bx_aim(x, z)
	b._place_key = ""
	var t0 := Time.get_ticks_usec()
	if drag_to != Vector2.INF:
		var n: Vector3i = b.aim["normal"]
		var base: Vector3i = b.aim["voxel"] + n if op == 0 else b.aim["voxel"]
		var cur: Vector3i = vworld.to_voxel(Vector3(drag_to.x, 0, drag_to.y))
		cur.y = base.y
		b.dragging = 1 if op != 1 else 2
		b.drag = {"base": base, "n": n, "cur": base, "op": op}
		b.test_cur = cur
	else:
		var n2: Vector3i = b.aim["normal"]
		var base2: Vector3i = b.aim["voxel"] + n2 if op == 0 else b.aim["voxel"]
		b.dragging = 1 if op != 1 else 2
		b.drag = {"base": base2, "n": n2, "cur": base2, "op": op}
		b.test_cur = base2
	b._compute(true)
	var p: Dictionary = b.place
	var t1 := Time.get_ticks_usec()
	b._commit()
	var t2 := Time.get_ticks_usec()
	b.dragging = 0
	b.drag = {}
	print("[bx] %-22s valid=%s count=%d cost=%s ext=%s reason=%s  compute %.1f ms commit %.1f ms" % [label, p.get("valid"), int(p.get("count", 0)),
		str(p.get("cost", {})), str(p.get("ext")), p.get("reason", ""), (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])

func _bx_test() -> void:
	var b := builder
	b.test_mode = true
	b.set_active(true)
	Game.talents = {"formen1": 1, "formen2": 1, "formen3": 1, "pinsel": 1}
	Game.add_many({"stein": 30000, "holz": 20000, "ziegel": 6000, "glas": 3000, "erde": 8000, "stoff": 2000})
	var o := _ground(Vector3(_bx_origin.x, 30, _bx_origin.y))
	print("[bx] origin ", o)
	b.mat = vworld.mat_ids["cobble"]
	b.mat2 = vworld.mat_ids["slate"]
	_bx_place("haus", "haus", 0, Vector3i(48, 22, 40), o.x - 12.0, o.z - 10.0)
	b.mat = vworld.mat_ids["plaster"]
	b.mat2 = vworld.mat_ids["brick_red"]
	_bx_place("haus pult drag", "haus", 1, Vector3i(40, 20, 32), o.x - 20.0, o.z - 4.0, 0, Vector2(o.x - 15.0, o.z + 1.0))
	b.mat = vworld.mat_ids["bricks"]
	_bx_place("raum drag", "raum", 1, Vector3i(40, 20, 32), o.x - 4.0, o.z - 16.0, 0, Vector2(o.x + 1.0, o.z - 12.0))
	b.mat = vworld.mat_ids["bricks_dark"]
	_bx_place("wehrturm", "turm", 2, Vector3i(32, 56, 32), o.x - 8.0, o.z + 4.0)
	b.mat = vworld.mat_ids["cobble_mossy"]
	_bx_place("zinnenwand drag", "wand", 1, Vector3i(32, 20, 3), o.x - 2.0, o.z - 4.0, 0, Vector2(o.x + 6.0, o.z - 4.0))
	b.mat = vworld.mat_ids["planks"]
	_bx_place("treppe", "treppe", 0, Vector3i(12, 16, 24), o.x + 3.0, o.z + 2.0)
	b.mat = vworld.mat_ids["slate"]
	_bx_place("kuppel", "kugel", 1, Vector3i(24, 12, 24), o.x - 14.0, o.z + 6.0)
	b.mat = vworld.mat_ids["timber"]
	_bx_place("torbogen", "wand", 2, Vector3i(40, 28, 4), o.x - 2.0, o.z + 8.0, 0, Vector2(o.x + 4.0, o.z + 8.0))
	# cut a cellar entrance into the ground and paint the dome
	_bx_place("abziehen quader", "quader", 0, Vector3i(12, 10, 12), o.x + 6.0, o.z - 8.0, 1)
	b.mode = 1
	b.mat = vworld.mat_ids["brick_red"]
	_bx_place("faerben kuppel", "quader", 0, Vector3i(24, 16, 24), o.x - 14.0, o.z + 6.0, 2)
	b.mode = 0
	# brush strokes
	b.mat = vworld.mat_ids["grass"]
	for k in 6:
		_bx_place("pinsel %d" % k, "pinsel", 0, Vector3i(10, 10, 10), o.x + 8.0 + k * 0.5, o.z + 6.0)
	# copy the first house and paste it
	b.mode = 2
	b.aim = _bx_aim(o.x - 15.5, o.z - 13.0)
	var n: Vector3i = b.aim["normal"]
	b.dragging = 1
	b.drag = {"base": b.aim["voxel"], "n": n, "cur": b.aim["voxel"], "op": 3}
	b.test_cur = vworld.to_voxel(Vector3(o.x - 8.5, 0, o.z - 7.0))
	b.test_cur.y = (b.aim["voxel"] as Vector3i).y
	b.sizes["_sel"] = Vector3i(48, 64, 48)
	b._place_key = ""
	b._compute(true)
	print("[bx] select ", b.place.get("lo"), " ", b.place.get("ext"))
	b._commit()
	b.dragging = 0
	print("[bx] blueprints ", Game.blueprints.size(), " ", Game.blueprints[0]["size"] if Game.blueprints.size() > 0 else "")
	b.mode = 0
	if Game.blueprints.size() > 0:
		b.bp_i = 0
		b.aim = _bx_aim(o.x + 14.0, o.z - 12.0)
		b._place_key = ""
		b._compute(true)
		print("[bx] bauplan place valid=%s count=%d cost=%s" % [b.place.get("valid"), int(b.place.get("count", 0)), str(b.place.get("cost"))])
		b._commit()
	print("[bx] undo stack ", b.undo_stack.size())
	print("[bx] ui rect ", b.ui.get_rect(), " root ", hud.root.get_rect(), " bar ", b.ui.bar.get_rect(), " anchors ", b.ui.anchor_right, " ", b.ui.offset_right)
	b.undo()
	b.redo()
	print("[bx] inv ", Game.inv)
	print("[bx] stats ", Game.stats, " xp ", Game.xp, " lvl ", Game.level)
	# leave a ghost visible for the screenshot
	b.shape_i = 4
	b.bp_i = -1
	b.mat = vworld.mat_ids["planks_dark"]
	b.mat2 = vworld.mat_ids["slate"]
	b.aim = _bx_aim(o.x + 2.0, o.z - 2.0)
	b._place_key = ""
	if _bx_ui == "kit":
		b.open_panel()
	elif _bx_ui.begins_with("panel"):
		b.set_active(false)
		panels.open_tab(int(_bx_ui.substr(5)))
	if _shot_path == "":
		get_tree().quit()

## a few finished buildings in the meadow west of the river (for screenshots)
func _bx_show() -> void:
	var b := builder
	b.test_mode = true
	b.set_active(true)
	Game.creative = true
	b.mat = vworld.mat_ids["cobble"]
	b.mat2 = vworld.mat_ids["slate"]
	b.pattern_sel = 0
	_bx_place("haus", "haus", 0, Vector3i(48, 22, 40), -27.0, 29.0)
	b.mat = vworld.mat_ids["plaster"]
	b.mat2 = vworld.mat_ids["brick_red"]
	_bx_place("haus pult", "haus", 1, Vector3i(40, 20, 32), -27.0, 37.5)
	b.mat = vworld.mat_ids["bricks"]
	_bx_place("turm", "turm", 2, Vector3i(28, 52, 28), -21.0, 24.0)
	b.mat = vworld.mat_ids["cobble_mossy"]
	_bx_place("mauer", "wand", 1, Vector3i(32, 14, 3), -22.0, 29.0, 0, Vector2(-22.0, 35.0))
	b.mat = vworld.mat_ids["planks"]
	_bx_place("boden", "boden", 0, Vector3i(24, 2, 24), -19.5, 33.0)
	b.shape_i = 0
	b.aim = {}
	b.place = {}
	b._hide_visuals()
	b.set_active(false)
