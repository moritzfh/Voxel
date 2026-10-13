extends CharacterBody3D
## Third-person adventurer: walking, sprinting, jumping, gliding, auto step-up on 0.5 m blocks.

signal stats_changed
signal item_used(slot: int)

@export var walk_speed := 4.4
@export var sprint_speed := 7.4
@export var accel := 14.0
@export var air_accel := 4.0
@export var jump_velocity := 6.4
@export var gravity := 19.0
@export var step_height := 0.56

var hp := 100.0
var hp_max := 100.0
var mana := 50.0
var mana_max := 50.0
var stamina := 100.0
var stamina_max := 100.0
var potions := 3
var food := 3

var cam_rig: Node3D
var model: Node3D
var anim: Node
var water_img: Image
var water_meta := {}
var swimming := false
var gliding := false
var sprinting := false
var _coyote := 0.0
var _jump_buffer := 0.0
var _visual_offset := 0.0
var _facing := 0.0
var _attack_cd := 0.0
var _regen_block := 0.0
var _last_stats := Vector3.ZERO
var input_blocked := false   # menu / chat open (multiplayer keeps running)
var attack_count := 0

func _ready() -> void:
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50)
	safe_margin = 0.02
	_facing = rotation.y + deg_to_rad(5.0)
	rotation.y = 0.0
	if model:
		model.rotation.y = _facing

func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_blocked:
		input = Vector2.ZERO
	var yaw: float = cam_rig.yaw if cam_rig else 0.0
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	var moving := dir.length() > 0.08
	if dir.length() > 1.0:
		dir = dir.normalized()
	var want_sprint := (Input.is_action_pressed("sprint") or Input.is_action_pressed("skill_sprint")) and moving and not input_blocked
	sprinting = want_sprint and stamina > 0.5 and is_on_floor()
	if want_sprint and moving and stamina > 0.5:
		sprinting = true
	var speed := (sprint_speed if sprinting else walk_speed) * (1.0 + 0.1 * Game.rank("fuesse"))
	var target := dir * speed
	var a := accel if is_on_floor() else air_accel
	velocity.x = move_toward(velocity.x, target.x, a * speed * delta)
	velocity.z = move_toward(velocity.z, target.z, a * speed * delta)

	# water: float near the surface, jump to climb out
	var wl := water_level_at(global_position)
	swimming = wl > -50.0 and global_position.y < wl - 0.55
	if swimming:
		speed *= 0.6
		var float_y := wl - 0.9
		velocity.y = lerp(velocity.y, clampf((float_y - global_position.y) * 4.0, -3.0, 3.0), 1.0 - exp(-6.0 * delta))
		_coyote = 0.12
	# gravity, coyote time, jump buffer, glider
	if is_on_floor():
		_coyote = 0.12
		gliding = false
	elif not swimming:
		_coyote -= delta
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump") and not input_blocked:
		_jump_buffer = 0.15
	_jump_buffer -= delta
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
	var glide_held := Input.is_action_pressed("glide") and not input_blocked
	if not is_on_floor() and glide_held and velocity.y < 0.0:
		gliding = true
		velocity.y = max(velocity.y, -2.0)
	elif not glide_held:
		gliding = false

	_try_step_up(delta)
	move_and_slide()
	_keep_in_bounds()

	# stamina
	if sprinting and moving:
		stamina = max(0.0, stamina - 16.0 * delta)
		_regen_block = 0.8
	else:
		_regen_block -= delta
		if _regen_block <= 0.0:
			stamina = min(stamina_max, stamina + 22.0 * delta)
	mana = min(mana_max, mana + 1.0 * delta)
	var s := Vector3(hp, mana, stamina)
	if s.distance_to(_last_stats) > 0.05:
		_last_stats = s
		stats_changed.emit()

	# face the movement direction
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 0.3:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		_facing = lerp_angle(_facing, target_yaw, 1.0 - exp(-12.0 * delta))
	if model:
		model.rotation.y = _facing
		_visual_offset = lerp(_visual_offset, 0.0, 1.0 - exp(-14.0 * delta))
		model.position.y = _visual_offset
	if anim:
		anim.update_pose(delta, hv.length() / sprint_speed, is_on_floor(), velocity.y, gliding)

	_attack_cd -= delta

func water_level_at(p: Vector3) -> float:
	if water_img == null:
		return -100.0
	var i := int(floor((p.x - float(water_meta["x0"])) / float(water_meta["res"])))
	var k := int(floor((p.z - float(water_meta["z0"])) / float(water_meta["res"])))
	if i < 0 or k < 0 or i >= water_img.get_width() or k >= water_img.get_height():
		return -100.0
	return water_img.get_pixel(i, k).r

func _try_step_up(delta: float) -> void:
	# on the ground: auto step onto 0.5 m blocks; in the air (after a jump / swimming): climb ledges
	var airborne := not is_on_floor()
	if airborne and not swimming and velocity.y < -3.5:
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.0005:
		return
	var probe := motion.normalized() * maxf(motion.length(), 0.12)
	if not test_move(global_transform, probe):
		return
	var up := Vector3(0.0, step_height if not airborne else step_height * 1.25, 0.0)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, probe):
		return
	# find how far down we can settle after the step
	var col := KinematicCollision3D.new()
	var moved := raised.translated(probe)
	if test_move(moved, Vector3(0.0, -up.y - 0.05, 0.0), col):
		var drop := col.get_travel().y
		var rise := up.y + drop
		if rise > 0.05:
			global_position.y += rise
			_visual_offset -= rise
			if airborne:
				velocity.y = maxf(velocity.y, 0.0)

func _keep_in_bounds() -> void:
	var b := Rect2(Vector2(-88, -148), Vector2(176, 188))
	var p := Vector2(global_position.x, global_position.z)
	if not b.has_point(p):
		p = p.clamp(b.position, b.end)
		global_position.x = p.x
		global_position.z = p.y
	if global_position.y < -20.0:
		global_position = Vector3(0, 2, 0)
		velocity = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if input_blocked:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not (event is InputEventJoypadButton):
		return
	if event.is_action_pressed("attack") and _attack_cd <= 0.0:
		_attack_cd = 0.6
		attack_count += 1
		if anim:
			anim.attack()
		item_used.emit(0)
	elif event.is_action_pressed("use_potion"):
		if potions > 0 and mana < mana_max:
			potions -= 1
			mana = mana_max
			stats_changed.emit()
		item_used.emit(1)
	elif event.is_action_pressed("use_food"):
		if food > 0 and hp < hp_max:
			food -= 1
			hp = min(hp_max, hp + 30)
		elif food > 0:
			food -= 1
			stamina = stamina_max
		stats_changed.emit()
		item_used.emit(4)
