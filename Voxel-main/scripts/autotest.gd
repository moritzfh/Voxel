extends Node
## Automated walk-through used for testing (run with: godot --headless --path . -- --autotest)
## Steers the player through waypoints by faking input, logs progress and reports stuck spots.

var main: Node
var player: CharacterBody3D
var rig: Node3D
var route := [
	["walk", Vector2(-0.8, -16.0)],
	["walk", Vector2(-4.2, -20.0)],
	["talk"],
	["walk", Vector2(-2.0, -27.0)],
	["walk", Vector2(-1.5, -23.2)],
	["walk", Vector2(10.0, -23.0)],
	["walk", Vector2(22.0, -23.0)],
	["walk", Vector2(30.5, -21.5)],
	["walk", Vector2(37.0, -18.5)],
	["walk", Vector2(38.4, -17.2)],
	["talk"],
	["walk", Vector2(33.0, -21.0)],
	["walk", Vector2(22.0, -23.0)],
	["walk", Vector2(-1.5, -23.2)],
	["walk", Vector2(-1.0, -8.0)],
	["walk", Vector2(-2.6, -7.0)],
	["walk", Vector2(-11.0, -11.4)],
	["walk", Vector2(-14.0, -13.6)],
	["walk", Vector2(-15.2, -16.8)],
	["walk", Vector2(-19.4, -16.8)],
	["talk"],
	["walk", Vector2(-15.2, -22.0)],
	["walk", Vector2(-16.0, -29.0)],
	["walk", Vector2(-19.5, -31.5)],
	["walk", Vector2(-23.0, -32.0)],
	["walk", Vector2(-28.0, -42.0)],
	["walk", Vector2(-30.0, -52.0)],
	["walk", Vector2(-28.6, -59.0)],
	["walk", Vector2(-28.2, -64.0)],
	["walk", Vector2(-21.5, -63.5)],
	["talk"],
	["walk", Vector2(-28.2, -64.0)],
	["walk", Vector2(-29.5, -52.0)],
	["walk", Vector2(-28.0, -42.0)],
	["walk", Vector2(-23.0, -32.5)],
	["walk", Vector2(-16.0, -29.0)],
	["walk", Vector2(-17.6, -38.0)],
	["walk", Vector2(-17.4, -44.0)],
	["walk", Vector2(-6.0, -40.0)],
	["walk", Vector2(2.6, -37.0)],
	["walk", Vector2(2.6, -29.5)],
	["walk", Vector2(-1.5, -27.0)],
	["walk", Vector2(-1.0, -14.0)],
	["walk", Vector2(10.0, -12.0)],
	["walk", Vector2(9.0, -4.0)],
	["walk", Vector2(3.0, -3.0)],
	["walk", Vector2(0.0, 0.0)],
]
var step := 0
var t := 0.0
var last_progress_pos := Vector3.ZERO
var stuck_t := 0.0
var log_t := 0.0
var issues: Array = []
var started := false

func _physics_process(delta: float) -> void:
	if not started:
		t += delta
		if t > 1.0:
			started = true
			t = 0.0
			last_progress_pos = player.global_position
		return
	if step >= route.size():
		_finish()
		return
	var cmd: Array = route[step]
	t += delta
	log_t += delta
	if log_t > 1.0:
		log_t = 0.0
		print("pos ", player.global_position.snapped(Vector3(0.01, 0.01, 0.01)), " floor=", player.is_on_floor(), " step=", step)
	match cmd[0]:
		"walk":
			var goal: Vector2 = cmd[1]
			var p := Vector2(player.global_position.x, player.global_position.z)
			var d := goal - p
			if d.length() < 0.6:
				_release()
				print("reached ", goal, " at y=", snappedf(player.global_position.y, 0.01), " in ", snappedf(t, 0.1), "s")
				_next()
				return
			# face the goal: camera yaw so that 'forward' points at the goal
			rig.yaw = atan2(-d.x, -d.y)
			Input.action_press("move_forward")
			if player.global_position.distance_to(last_progress_pos) > 0.5:
				last_progress_pos = player.global_position
				stuck_t = 0.0
			else:
				stuck_t += delta
			if stuck_t > 1.2 and stuck_t < 1.25:
				Input.action_press("jump")
			elif stuck_t > 1.3:
				Input.action_release("jump")
			if stuck_t > 4.0 or t > 40.0:
				issues.append("stuck at %s heading to %s" % [str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1))), str(goal)])
				print("STUCK at ", player.global_position, " -> ", goal)
				player.global_position = Vector3(goal.x, player.global_position.y + 3.0, goal.y)
				_next()
		"talk":
			if t < 0.05:
				var ev := InputEventAction.new()
				ev.action = "interact"
				ev.pressed = true
				Input.parse_input_event(ev)
			if t > 0.5:
				var nm = "none"
				if main._current != null:
					nm = str(main._current["node"].name)
				var best := 999.0
				for it in main.interactables:
					if it["kind"] == "npc":
						best = min(best, it["node"].global_position.distance_to(player.global_position))
				print("interact done, current=", nm, " nearest npc=", snappedf(best, 0.1), " at ", player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))
				_next()
		"jump":
			Input.action_press("jump")
			if t > 0.2:
				Input.action_release("jump")
			if t > 1.2:
				_next()
	if player.global_position.y < -6.0:
		issues.append("fell below world at %s" % str(player.global_position))

func _release() -> void:
	Input.action_release("move_forward")
	Input.action_release("jump")

func _next() -> void:
	_release()
	step += 1
	t = 0.0
	stuck_t = 0.0
	last_progress_pos = player.global_position

func _finish() -> void:
	print("AUTOTEST DONE. elder_talked=", main.elder_talked, " crates=", main.crates_found)
	print("issues: ", issues)
	get_tree().quit()
