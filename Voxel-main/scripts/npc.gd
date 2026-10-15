extends StaticBody3D
## Villager: idles, turns towards the player when close, talks via a speech bubble.

@export var display_name := "Dorfbewohner"
@export var lines: PackedStringArray = []
@export var model_scene: PackedScene
@export var wander_radius := 0.0

var anim: Node
var model: Node3D
var bubble: Label3D
var _line := 0
var _bubble_t := 0.0
var _home := Vector3.ZERO
var _yaw := 0.0
var _target := Vector3.ZERO
var _wait := 0.0
var player: Node3D
signal talked(npc: Node)

func _ready() -> void:
	_home = global_position
	_target = _home
	_yaw = rotation.y
	rotation.y = 0.0
	model = model_scene.instantiate()
	model.set_script(load("res://scripts/character_anim.gd"))
	add_child(model)
	model.rotation.y = _yaw
	anim = model
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.position.y = 2.45
	bubble.font = load("res://assets/fonts/alegreya-latin-700-normal.woff2")
	bubble.font_size = 44
	bubble.pixel_size = 0.0045
	bubble.outline_size = 14
	bubble.outline_modulate = Color(0.05, 0.08, 0.07, 0.9)
	bubble.modulate = Color(1.0, 0.96, 0.86)
	bubble.width = 620
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.no_depth_test = false
	bubble.visible = false
	add_child(bubble)
	var tag := Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.12
	tag.text = display_name
	tag.font = load("res://assets/fonts/alegreya-sc-latin-700-normal.woff2")
	tag.font_size = 34
	tag.pixel_size = 0.004
	tag.outline_size = 10
	tag.outline_modulate = Color(0, 0, 0, 0.8)
	tag.modulate = Color(0.95, 0.85, 0.55)
	tag.visibility_range_end = 14.0
	add_child(tag)

func interact() -> void:
	if lines.is_empty():
		return
	bubble.text = lines[_line % lines.size()]
	_line += 1
	bubble.visible = true
	_bubble_t = 4.5
	anim.talk(2.0)
	talked.emit(self)

func _process(delta: float) -> void:
	var speed := 0.0
	var near := false
	if player:
		var d := player.global_position - global_position
		d.y = 0
		near = d.length() < 4.5
		if near:
			var ty := atan2(-d.x, -d.z)
			_yaw = lerp_angle(_yaw, ty, 1.0 - exp(-6.0 * delta))
	if wander_radius > 0.0 and not near:
		_wait -= delta
		var to := _target - global_position
		to.y = 0
		if to.length() < 0.2 or _wait > 0.0:
			if _wait <= -3.0 or (_wait <= 0.0 and to.length() < 0.2):
				_wait = randf_range(2.0, 6.0)
				var a := randf() * TAU
				_target = _home + Vector3(cos(a), 0, sin(a)) * randf() * wander_radius
		else:
			var step: Vector3 = to.normalized() * 1.2 * delta
			global_position += step
			_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), 1.0 - exp(-5.0 * delta))
			speed = 1.2 / 7.4
	model.rotation.y = _yaw
	anim.update_pose(delta, speed, true, 0.0, false)
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			bubble.visible = false
