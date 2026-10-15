extends Node3D
## Procedural animation for the voxel characters (parts are child MeshInstance3D nodes rotating around their pivots).

var parts := {}
var rest := {}
var _phase := 0.0
var _t := 0.0
var _speed := 0.0
var _air := 0.0
var _glide := 0.0
var _attack := -1.0
var combat_kind := ""
var combat_stage := 0
var combat_time := 0.0
var combat_duration := 0.0
var sword_held := true
var _was_roll := false
var _talk := 0.0
var _scarf_swing := 0.0

func _ready() -> void:
	for c in get_children():
		if c is Node3D:
			parts[c.name] = c
			rest[c.name] = c.position

signal swung

func attack() -> void:
	_attack = 0.0
	swung.emit()

func combat_pose(kind: String, stage: int, duration: float) -> void:
	combat_kind = kind
	combat_stage = stage
	combat_time = 0
	combat_duration = duration
	_attack = -1
	swung.emit()

func talk(seconds: float = 2.0) -> void:
	_talk = seconds

func _set_rot(name: String, r: Vector3) -> void:
	if parts.has(name):
		parts[name].rotation = r

func _set_off(name: String, off: Vector3) -> void:
	if parts.has(name):
		parts[name].position = rest[name] + off

## speed: 0..1 (relative to sprint speed), vy: vertical velocity
func update_pose(delta: float, speed: float, on_floor: bool, vy: float, gliding: bool) -> void:
	_t += delta
	_speed = lerp(_speed, speed, 1.0 - exp(-10.0 * delta))
	_air = lerp(_air, 0.0 if on_floor else 1.0, 1.0 - exp(-12.0 * delta))
	_glide = lerp(_glide, 1.0 if gliding else 0.0, 1.0 - exp(-8.0 * delta))
	var s := _speed
	_phase += delta * (2.0 + s * 11.0)
	var swing := sin(_phase) * clampf(s * 1.6, 0.0, 1.0) * (1.0 - _air)
	var bob: float = abs(cos(_phase)) * 0.06 * clamp(s * 1.5, 0.0, 1.0) * (1.0 - _air)
	var breathe := sin(_t * 1.8) * 0.012 * (1.0 - clampf(s * 3.0, 0.0, 1.0))
	var lean := s * 0.18
	# legs
	var leg_amp := 0.75
	_set_rot("leg_l", Vector3(swing * leg_amp - _air * 0.5, 0, 0))
	_set_rot("leg_r", Vector3(-swing * leg_amp + _air * 0.3, 0, 0))
	# body
	var up := Vector3(0, bob + breathe, 0)
	for n in ["torso", "head", "arm_l", "arm_r", "scarf", "sword"]:
		_set_off(n, up)
	_set_rot("torso", Vector3(-lean * 0.5, 0, 0))
	_set_rot("sword", Vector3(-lean * 0.5, 0, 0))
	_set_rot("head", Vector3(lean * 0.3 + sin(_t * 0.7) * 0.02, sin(_t * 0.4) * 0.06 * (1.0 - s), 0))
	# arms
	var arm_amp := 0.65
	var ar := Vector3(-swing * arm_amp - _air * 0.6, 0, 0.06 + _air * 0.25)
	var al := Vector3(swing * arm_amp - _air * 0.6, 0, -0.06 - _air * 0.25)
	if _glide > 0.01:
		ar = ar.lerp(Vector3(-0.2, 0, 1.35), _glide)
		al = al.lerp(Vector3(-0.2, 0, -1.35), _glide)
	if _attack >= 0.0:
		_attack += delta
		var a: float = clamp(_attack / 0.45, 0.0, 1.0)
		var wind := sin(a * PI)
		ar = Vector3(-2.6 * wind + 1.2 * a * a, 0.3 * wind, 0.2)
		if _attack > 0.5:
			_attack = -1.0
	if _talk > 0.0:
		_talk -= delta
		ar = ar.lerp(Vector3(-0.6 + sin(_t * 5.0) * 0.15, 0, 0.25), 0.8)
	rotation.x = 0
	rotation.z = 0
	if _was_roll:
		position.y = 0
		position.z = 0
		_was_roll = false
	if sword_held and parts.has("CombatSword"):
		ar = Vector3(-.65-swing*.25,-.15,.45)
	if combat_time<combat_duration:
		combat_time += delta
		var p := clampf(combat_time/combat_duration,0,1)
		var swing_t := smoothstep(.12,.8,p)
		var envelope := sin(p*PI)
		match combat_kind:
			"attack":
				var side := -1.0 if combat_stage==1 else 1.0
				ar = Vector3(-1.35,side*lerpf(-1.4,1.5,swing_t),side*.55)
				_set_rot("torso",Vector3(0,side*lerpf(-.45,.45,swing_t),0))
				if combat_stage==3: rotation.y += TAU*swing_t; ar = Vector3(-1.4,-.5,1.15)
			"spin": rotation.y += TAU*combat_time/ .3; ar = Vector3(-1.35,0,1.2); al = Vector3(-.2,0,-.8)
			"dodge":
				rotation.x = -TAU*p
				position.y = .9-cos(rotation.x)*.9
				position.z = -sin(rotation.x)*.9
				_was_roll = true
				_set_rot("leg_l",Vector3(-1.5,0,0)); _set_rot("leg_r",Vector3(-1.5,0,0)); ar = Vector3(-1,0,.25); al = Vector3(-1,0,-.25)
			"slam": ar = Vector3(-2.8 if p<.6 else lerpf(-2.8,.3,smoothstep(.6,.9,p)),0,.12); al = ar+Vector3(0,0,-.3); _set_rot("torso",Vector3(.5*envelope,0,0))
			"cleave": ar = Vector3(lerpf(-2.9,.6,swing_t),0,.1); al = Vector3(-1.5*envelope,0,-.3)
			"dash", "execution": ar = Vector3(-1.65,0,.2); _set_rot("torso",Vector3(-.4,0,0)); _set_off("arm_r",up+Vector3(0,0,-envelope*.35))
			"guard": ar = Vector3(-1.35,-.8,.8); al = Vector3(-1.2,.3,-.6)
			"heal": ar = Vector3(-2.5*envelope,0,.4); al = Vector3(-2.5*envelope,0,-.4)
			"berserk": ar = Vector3(-2.8*envelope,0,.2); al = Vector3(-1.5*envelope,0,-.8)
	_set_rot("arm_r", ar)
	_set_rot("arm_l", al)
	# scarf trails behind, flaps with speed and wind
	var target_swing := 0.25 + s * 0.9 + _air * 0.6 + _glide * 0.5
	_scarf_swing = lerp(_scarf_swing, target_swing, 1.0 - exp(-4.0 * delta))
	var flap := sin(_t * (5.0 + s * 9.0)) * (0.05 + s * 0.12)
	_set_rot("scarf", Vector3(-(_scarf_swing * 0.55 + flap) + lean * 0.5, 0, sin(_t * 2.3) * 0.05))
