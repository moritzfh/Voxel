extends Node3D
## Over-the-shoulder orbit camera with collision (SpringArm3D), mouse + gamepad.

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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clamp(pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-70), deg_to_rad(35))
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clamp(distance - 0.4, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clamp(distance + 0.4, min_distance, max_distance)

func _process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.12:
		yaw -= look.x * stick_sensitivity * delta
		pitch = clamp(pitch - look.y * stick_sensitivity * 0.7 * delta, deg_to_rad(-70), deg_to_rad(35))
	if target:
		var goal := target.global_position + Vector3(0, pivot_height, 0)
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_sharpness * delta))
	rotation = Vector3(pitch, yaw, 0.0)
	_dist = lerp(_dist, distance, 1.0 - exp(-8.0 * delta))
	arm.spring_length = _dist
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
