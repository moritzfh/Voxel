extends Node3D
## Another player's hero: interpolates the received network state, animates and shows a name tag.

const INTERP_DELAY := 0.12   # seconds behind the newest packet (smooths jitter)

var peer_id := 0
var model: Node3D
var tag: Label3D
var _buf: Array = []         # [{t, pos, yaw, vel, flags}]
var _clock := 0.0
var _last_attack := -1
var _yaw := 0.0
var _vy := 0.0
var weapon: MeshInstance3D

func setup(id: int, display_name: String, color: Color) -> void:
	peer_id = id
	name = "Remote_%d" % id
	model = load("res://generated/char_hero.scn").instantiate()
	model.set_script(load("res://scripts/character_anim.gd"))
	add_child(model)
	weapon = MeshInstance3D.new()
	model.parts["CombatSword"] = weapon
	var game := get_parent()
	if game.get("tools"): weapon.mesh = game.tools._build_tool("sword",1)
	model.get_node("arm_r").add_child(weapon)
	weapon.position = Vector3(.02,-.6,-.02)
	if model.has_node("sword"): model.get_node("sword").hide()
	tag = Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = false
	tag.fixed_size = false
	tag.pixel_size = 0.0045
	tag.font_size = 48
	tag.outline_size = 12
	tag.position = Vector3(0, 2.25, 0)
	tag.modulate = Color(1, 1, 1)
	tag.outline_modulate = Color(0.05, 0.07, 0.06, 0.85)
	add_child(tag)
	apply_identity(display_name, color)
	visible = false

func apply_identity(display_name: String, color: Color) -> void:
	tag.text = display_name
	tag.modulate = color.lightened(0.35)
	for part in ["scarf", "head"]:
		var gi := model.get_node_or_null(part)
		if gi is GeometryInstance3D:
			var a := 0.0 if color == Net.COLORS[0] else 1.0
			(gi as GeometryInstance3D).set_instance_shader_parameter("recolor", Color(color.r, color.g, color.b, a))

func push_state(s: Dictionary) -> void:
	_buf.append({"t": _clock, "pos": s["pos"], "yaw": s["yaw"], "vel": s["vel"], "flags": s["flags"]})
	if _buf.size() > 30:
		_buf.pop_front()
	if not visible:
		visible = true
		global_position = s["pos"]
		_yaw = s["yaw"]
	var a: int = int(s["attack"])
	if _last_attack >= 0 and a != _last_attack and model and (int(s["flags"])&16)==0:
		model.attack()
	_last_attack = a
	if weapon:
		weapon.visible = (int(s["flags"])&8)!=0
		model.sword_held = weapon.visible

func play_combat(kind: String, stage: int, duration: float) -> void:
	if model: model.combat_pose(kind,stage,duration)

func _process(delta: float) -> void:
	_clock += delta
	if _buf.is_empty() or model == null:
		return
	var t := _clock - INTERP_DELAY
	var a: Dictionary = _buf[0]
	var b: Dictionary = _buf[0]
	for i in range(_buf.size() - 1):
		if _buf[i]["t"] <= t and _buf[i + 1]["t"] >= t:
			a = _buf[i]
			b = _buf[i + 1]
			break
		if _buf[i + 1]["t"] < t:
			a = _buf[i + 1]
			b = _buf[i + 1]
	var pos: Vector3
	if a == b:
		# no newer packet yet: extrapolate a little along the last velocity
		var dt := clampf(t - float(a["t"]), 0.0, 0.25)
		pos = a["pos"] + a["vel"] * dt
	else:
		var f := clampf((t - float(a["t"])) / maxf(0.001, float(b["t"]) - float(a["t"])), 0.0, 1.0)
		pos = (a["pos"] as Vector3).lerp(b["pos"], f)
	if global_position.distance_to(pos) > 6.0:
		global_position = pos
	else:
		global_position = global_position.lerp(pos, 1.0 - exp(-20.0 * delta))
	var target_yaw: float = b["yaw"]
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-14.0 * delta))
	model.rotation.y = _yaw
	var vel: Vector3 = b["vel"]
	var flags: int = int(b["flags"])
	var on_floor := (flags & 1) != 0
	var gliding := (flags & 2) != 0
	var hv := Vector2(vel.x, vel.z).length()
	model.update_pose(delta, hv / 7.4, on_floor, vel.y, gliding)
	# drop very old samples
	while _buf.size() > 2 and float(_buf[1]["t"]) < t - 0.5:
		_buf.pop_front()
