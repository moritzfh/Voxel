extends "res://scripts/wildlife/animal.gd"
const TYPES := preload("res://scripts/enemies/enemy_types.gd")
var definition := {}
var is_boss := false
var encounter_id := 0
var dungeon_id := ""
var leash := 35.0
var _windup := 0.0
var _pending := ""
var _aim := Vector3.ZERO
var _victim_id := 0
var _visual_attack := 0.0
var _visual_total := 1.0
var _visual_windup := .7
var _visual_kind := ""
var _attack_index := 0
var _body_boxes: Array = []

func setup(owner_node: Node3D, kind: String, id: int, location: Vector3, config: Dictionary = {}) -> void:
	definition = TYPES.TYPES[kind]
	is_boss = bool(definition.boss)
	encounter_id = int(config.get("encounter",id))
	dungeon_id = str(config.get("dungeon",""))
	leash = 19 if is_boss else 35
	super.setup(owner_node,kind,id,location,config)
	collision_layer = 16
	collision_mask = 1|16|32
	set_meta("enemy",true)
	level_tag.modulate = Color("eda68b") if is_boss else Color("e3b19a")
	level_tag.visibility_range_end = 40 if is_boss else 22
	# The main capsule follows the torso. Dragon head and tails also have physical bodies.
	if species=="dragon":
		for child in get_children():
			if child is CollisionShape3D and child.shape is CapsuleShape3D:
				var torso := BoxShape3D.new()
				torso.size = Vector3(2.8,3.2,4.1)
				child.shape = torso; child.position = Vector3(0,1.6,.2)
				_body_boxes.append(AABB(child.position-torso.size*.5,torso.size))
				break
		add_box(Vector3(0,2.5,-2.5),Vector3(1.5,1.6,2.0))
		add_box(Vector3(0,.9,3.3),Vector3(.9,1.2,2.4))
		add_box(Vector3(.3,.6,5.0),Vector3(.6,.6,1.2))
	elif species=="sandworm":
		add_box(Vector3(0,.6,2.8),Vector3(1.6,1.2,3.2))
		add_box(Vector3(-.2,.35,4.7),Vector3(.7,.7,1.2))
	voice.max_distance = 65 if is_boss else 28
	voice.bus = "Effects"
	voice.unit_size = 8 if is_boss else 4

func add_box(center: Vector3, dimensions: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	shape.position = center
	add_child(shape)
	_body_boxes.append(AABB(center-dimensions*.5,dimensions))

func predator() -> bool: return true
func flying() -> bool: return false
func melee_reach() -> float: return float(definition.get("reach",1.5))

func melee_distance(point: Vector3) -> float:
	var best := super.melee_distance(point)
	var local := to_local(point+Vector3.UP*.8)
	for box: AABB in _body_boxes:
		best = minf(best,local.distance_to(local.clamp(box.position,box.end)))
	return best

func call_sound(aggressive: bool) -> void:
	if not voice or (voice.playing and not aggressive): return
	voice.stream = load("res://assets/audio/enemies/%s.wav" % species)
	voice.pitch_scale = rng.randf_range(.92,1.08)
	voice.volume_db = -10 if is_boss else -17
	voice.play()

func _simulate(dt: float) -> void:
	if hp<=0:
		if is_boss: return
		_respawn -= dt
		if _respawn<=0 and manager.nearest_player(home).distance>18:
			hp = max_health(); global_position = home+Vector3.UP*.1
			collision_layer = 16; state = "idle"; show()
			_knock = Vector3.ZERO; velocity = Vector3.ZERO
		return
	if _knock.length()>.1 or _lift>0:
		velocity.x = _knock.x; velocity.z = _knock.z
		velocity.y = _lift if _lift>0 else velocity.y-dt*18
		_lift = 0; _knock = _knock.move_toward(Vector3.ZERO,dt*(12 if is_boss else 8))
		move_and_slide(); return
	if _windup>0:
		_windup -= dt
		velocity.x = 0; velocity.z = 0
		velocity.y = -1 if is_on_floor() else velocity.y-dt*18
		move_and_slide()
		if _windup<=0: _finish_attack()
		return
	var nearest: Dictionary = manager.nearest_player(global_position)
	var enemy_player := int(nearest.id)
	var goal: Vector3 = nearest.position
	var rival: Node = manager.by_id.get(aggro_animal)
	var retaliating: bool = rival!=null and rival.hp>0 and anger_time>0 and global_position.distance_to(rival.position)<22
	if retaliating: goal = rival.position; enemy_player = 0
	var distance := Vector2(goal.x-global_position.x,goal.z-global_position.z).length()
	var permitted: bool = (Worlds.damage_multiplier()>0 or anger_time>0) and manager.village_clear(goal,1)
	var engaged: bool = permitted and distance<(22 if is_boss else 16) and goal.distance_to(home)<leash+5 and manager.can_see(self,goal)
	var speed := float(definition.speed)*growth_speed()
	if engaged:
		state = "chase"
		var range_limit := 11.0 if species in ["witch","dragon"] and not retaliating else melee_reach()
		if distance<range_limit and _attack_cd<=0:
			start_attack(enemy_player,goal,rival if retaliating else null)
			speed = 0
		elif species=="witch" and distance<4:
			goal = global_position+(global_position-goal).normalized()*3
		elif distance<range_limit*.8: speed = 0
	else:
		state = "return" if global_position.distance_to(home)>3 else "idle"
		goal = home
		speed *= .6
		if state=="idle": speed = 0
	var direction := goal-global_position; direction.y = 0
	direction = direction.normalized()
	if speed>0:
		rotation.y = lerp_angle(rotation.y,atan2(-direction.x,-direction.z),1-exp(-7*dt))
	var separation := Vector3.ZERO
	for friend in manager.foes:
		if friend==self or friend.hp<=0: continue
		var apart: Vector3 = global_position-friend.global_position; apart.y = 0
		var minimum: float = _radius+friend._radius+.15
		if apart.length()<minimum and apart.length()>.01: separation += apart.normalized()*(minimum-apart.length())*2
	velocity.x = move_toward(velocity.x,direction.x*speed+separation.x,dt*10)
	velocity.z = move_toward(velocity.z,direction.z*speed+separation.z,dt*10)
	velocity.y = -1 if is_on_floor() else maxf(-22,velocity.y-dt*18)
	var before := global_position
	if speed>0:
		var ground: Dictionary = manager.ground_at(global_position+direction*maxf(.8,_radius),global_position.y+3)
		if ground.is_empty() or ground.normal.y<.55 or manager.underwater(ground.position) or absf(global_position.y-ground.position.y)>2.0:
			velocity.x = 0; velocity.z = 0
		else: _step_up(direction,dt)
	move_and_slide()
	if not manager.village_clear(global_position,_radius) or global_position.distance_to(home)>leash+8:
		global_position = before; velocity = Vector3.ZERO
	if global_position.y< -15: global_position = home; velocity = Vector3.ZERO

func start_attack(player_id: int, goal: Vector3, rival: Node = null) -> void:
	_victim_id = player_id
	_aim = goal
	_pending = "melee"
	if rival: aggro_animal = rival.animal_id
	if species=="witch" and player_id!=0: _pending = "bolt"
	if species=="cyclops": _pending = "smash"
	if species=="dragon": _pending = "breath" if global_position.distance_to(goal)>4 or _attack_index%2==0 else "smash"
	if species=="sandworm": _pending = "eruption"
	if rival: _pending = "melee"
	_attack_index += 1
	_windup = .35 if not is_boss else .9 if species!="sandworm" else 1.05
	_attack_cd = 1.6 if not is_boss else 3.2
	state = "windup"
	var offset := goal-global_position
	rotation.y = atan2(-offset.x,-offset.z)
	manager.main.enemies.cue(self,_pending,_aim,_windup)
	call_sound(true)

func _finish_attack() -> void:
	state = "attack"
	var damage := float(definition.damage)*(1+.12*(level-1))
	if _pending in ["bolt","breath"]:
		var origin := global_position+Vector3.UP*(2.6 if is_boss else 1.2)
		var forward := (_aim+Vector3.UP*.8-origin).normalized()
		for turn in ([-.18,0.0,.18] if _pending=="breath" else [0.0]):
			manager.main.enemies.shoot(self,origin,forward.rotated(Vector3.UP,float(turn)),damage,_pending=="breath")
		return
	var point := _aim if _pending=="eruption" else global_position
	var radius := 3.0 if _pending=="eruption" else 4.3 if _pending=="smash" else melee_reach()
	manager.main.enemies.strike(self,point,radius,damage,_pending,_victim_id)

func _process(dt: float) -> void:
	super._process(dt)
	if hp<=0: return
	_visual_attack = maxf(0,_visual_attack-dt)
	var attack := _visual_attack>0
	var elapsed := _visual_total-_visual_attack
	var arm_angle := (-2.3*smoothstep(0,_visual_windup*.65,elapsed)+2.8*smoothstep(_visual_windup*.65,_visual_windup+.08,elapsed))*(1-smoothstep(_visual_windup+.08,_visual_total,elapsed))
	for arm in ["arm_l","arm_r"]:
		if _parts.has(arm): _parts[arm].rotation.x = -.2 if not attack else arm_angle
	if species=="dragon":
		if _parts.has("head") and attack: _parts.head.rotation.x = -.2*sin(clampf(elapsed/_visual_total,0,1)*PI)
		for wing in ["wing_l","wing_r"]:
			if _parts.has(wing): _parts[wing].rotation.z = sin(_time*2.4)*.12*(1 if wing=="wing_l" else -1)
	if species=="sandworm": model.rotation.z = sin(_time*2)*.06; model.position.y = sin(_time*3)*.12

func receive_hit(damage: float, attacker: Vector3, knock := 2.4, lift := 0.0, crit := false) -> bool:
	var died := super.receive_hit(damage,attacker,knock*(.3 if is_boss else 1),lift*(.35 if is_boss else 1),crit)
	if died: _respawn = 180; _windup = 0
	return died

func snapshot() -> Dictionary:
	var value := super.snapshot()
	value.merge({"enemy":true,"species":species,"encounter":encounter_id,"dungeon":dungeon_id},true)
	return value

func restore(data: Dictionary, snap := false) -> void:
	super.restore(data,snap)
	collision_layer = 16 if hp>0 else 0
	if snap: _windup = 0; _pending = ""
