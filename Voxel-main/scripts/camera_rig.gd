extends Node3D
## Over-the-shoulder orbit camera with collision (SpringArm3D), mouse + gamepad.
## H (or zooming all the way in) switches to first person: eye height, hero hidden (shadow stays),
## the current tool is shown bottom right and swings with every hit.

@export var pivot_height := 2.03
@export var distance := 4.6
@export var min_distance := 2.2
@export var max_distance := 9.0
@export var mouse_sensitivity := 0.0032
@export var stick_sensitivity := 2.6
@export var follow_sharpness := 16.0
@export var start_yaw_deg := 5.0

var target: Node3D
var yaw := 0.0
var pitch := deg_to_rad(-4.0)
var _dist := 4.6
var shake := 0.0
var first_person := false
@export var eye_height := 1.62
var viewmodel: MeshInstance3D
var _vm_mesh: MeshInstance3D
var _vm_swing := 1.0
var _vm_bob := 0.0
var _hidden_geo: Array = []
@onready var arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

## Field of view: vertical 62° on 16:9. On wider screens (21:9, 32:9) the horizontal FOV
## is capped so the image doesn't get stretched at the edges.
@export var base_vfov := 62.0
var hfov_cap := 110.0

func _ready() -> void:
	top_level = true
	yaw = deg_to_rad(start_yaw_deg)
	_dist = distance
	get_viewport().size_changed.connect(update_fov)
	update_fov()

func set_hfov_cap(c: float) -> void:
	hfov_cap = c
	update_fov()

func update_fov() -> void:
	var s := get_viewport().get_visible_rect().size
	var aspect := s.x / maxf(1.0, s.y)
	var natural_h := rad_to_deg(2.0 * atan(tan(deg_to_rad(base_vfov) * 0.5) * aspect))
	if natural_h > hfov_cap:
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = hfov_cap
	else:
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = base_vfov

func set_target(t: Node3D) -> void:
	target = t
	global_position = target.global_position + Vector3(0, pivot_height, 0)
	if target is CollisionObject3D:
		arm.add_excluded_object((target as CollisionObject3D).get_rid())

func _pitch_min() -> float:
	return deg_to_rad(-86) if first_person else deg_to_rad(-70)

func _pitch_max() -> float:
	return deg_to_rad(86) if first_person else deg_to_rad(35)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clamp(pitch - event.relative.y * mouse_sensitivity * (-1.0 if Settings.get_value("invert_y") else 1.0), _pitch_min(), _pitch_max())
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if not first_person and distance <= min_distance + 0.01:
				set_first_person(true)
			distance = clamp(distance - 0.4, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if first_person:
				set_first_person(false)
				distance = min_distance
			else:
				distance = clamp(distance + 0.4, min_distance, max_distance)
	elif event.is_action_pressed("first_person") \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		set_first_person(not first_person)
		get_viewport().set_input_as_handled()

func set_first_person(on: bool) -> void:
	if on == first_person:
		return
	first_person = on
	pitch = clamp(pitch, _pitch_min(), _pitch_max())
	# hide the hero's body (its shadow stays) while looking through its eyes
	var model: Node = target.get("model") if target else null
	if on and model:
		_hidden_geo.clear()
		for g in model.find_children("*", "GeometryInstance3D", true, false):
			_hidden_geo.append([g, (g as GeometryInstance3D).cast_shadow])
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	elif not on:
		for e in _hidden_geo:
			if is_instance_valid(e[0]):
				e[0].cast_shadow = e[1]
		_hidden_geo.clear()
	if viewmodel:
		viewmodel.visible = on and _vm_mesh.mesh != null
	if on and model and model.has_signal("swung") and not model.is_connected("swung", swing):
		model.connect("swung", swing)

## tool mesh shown bottom right in first person (null = empty hands)
func set_viewmodel(mesh: Mesh) -> void:
	if viewmodel == null:
		viewmodel = MeshInstance3D.new()   # holder: the hand
		camera.add_child(viewmodel)
		_vm_mesh = MeshInstance3D.new()
		_vm_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vm_mesh.rotation_degrees = Vector3(0, 0, 180)   # tool meshes hang down from the hand; hold it upright
		_vm_mesh.scale = Vector3.ONE * 0.55
		viewmodel.add_child(_vm_mesh)
	_vm_mesh.mesh = mesh
	viewmodel.visible = first_person and mesh != null

func swing() -> void:
	_vm_swing = 0.0

func _process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.12:
		yaw -= look.x * stick_sensitivity * delta
		pitch = clamp(pitch - look.y * stick_sensitivity * 0.7 * delta, deg_to_rad(-70), deg_to_rad(35))
	if target:
		if first_person:
			global_position = global_position.lerp(target.global_position + Vector3(0, eye_height, 0), 1.0 - exp(-40.0 * delta))
		else:
			var goal := target.global_position + Vector3(0, pivot_height, 0)
			global_position = global_position.lerp(goal, 1.0 - exp(-follow_sharpness * delta))
	rotation = Vector3(pitch, yaw, 0.0)
	_dist = lerp(_dist, 0.0 if first_person else distance, 1.0 - exp(-(30.0 if first_person else 8.0) * delta))
	arm.spring_length = _dist
	_update_viewmodel(delta)
	if shake > 0.001:
		shake = maxf(0.0, shake - delta * 2.5)
		camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.08
		camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.08
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

func add_shake(a: float) -> void:
	shake = minf(1.0, shake + a)

func heading_degrees() -> float:
	# 0 = north (-Z), 90 = east (+X)
	return fposmod(-rad_to_deg(yaw), 360.0)

func _update_viewmodel(delta: float) -> void:
	if viewmodel == null or not viewmodel.visible:
		return
	var speed := 0.0
	if target is CharacterBody3D:
		var v: Vector3 = (target as CharacterBody3D).velocity
		speed = Vector2(v.x, v.z).length()
	_vm_bob += delta * (2.0 + speed * 1.6)
	var bob := Vector3(sin(_vm_bob) * 0.012, absf(cos(_vm_bob)) * 0.014, 0.0) * minf(1.0, speed / 4.0)
	_vm_swing = minf(1.0, _vm_swing + delta / 0.3)
	# swing: wind up quickly, strike down, settle back
	var s := sin(_vm_swing * PI) * (1.0 - _vm_swing * 0.3)
	viewmodel.position = Vector3(0.30, -0.40, -0.52) + bob + Vector3(-0.08, -0.06, -0.12) * s
	viewmodel.rotation = Vector3(deg_to_rad(-28.0) - s * 1.25, deg_to_rad(-22.0), deg_to_rad(-16.0) + s * 0.25)
	if target and target.get("combat") and target.combat.busy>0:
		var combat: Node = target.combat
		var p := clampf(combat.action_time/maxf(.01,combat.action_duration),0,1)
		var envelope := sin(p*PI)
		match combat.kind:
			"attack":
				var side := -1.0 if combat.combo==1 else 1.0
				viewmodel.position.x += side*sin(p*TAU)*.16
				viewmodel.rotation.y += side*lerpf(-.8,.8,smoothstep(.1,.8,p))
				if combat.combo==3: viewmodel.rotation.z += TAU*p
			"spin": viewmodel.position.x += sin(combat.action_time*TAU/.3)*.22; viewmodel.rotation.y += sin(combat.action_time*TAU/.3)*.7
			"slam", "cleave": viewmodel.position.y += envelope*.32; viewmodel.rotation.x -= envelope
			"dash", "execution": viewmodel.position.z -= envelope*.23; viewmodel.rotation.x -= .8
			"guard": viewmodel.position.x -= .2; viewmodel.rotation.z -= 1.1
			"heal", "berserk": viewmodel.position.y += envelope*.3
