extends CharacterBody3D
const FOES := preload("res://scripts/enemies/enemy_types.gd")
const MODELS := preload("res://scripts/wildlife/models.gd")
const NAMES := {"bird":"Vogel", "bee":"Biene", "bear":"Bär", "wolf":"Wolf", "rabbit":"Hase", "turtle":"Schildkröte", "chicken":"Huhn","goblin":"Goblin","witch":"Hexe","bandit":"Räuber","cyclops":"Großer Zyklop","dragon":"Drache","sandworm":"Riesen-Sandwurm"}
const HEALTH := {"bird":15.0,"bee":32.0,"bear":120.0,"wolf":65.0,"rabbit":20.0,"turtle":40.0,"chicken":24.0,"goblin":55.0,"witch":75.0,"bandit":90.0,"cyclops":650.0,"dragon":1000.0,"sandworm":850.0}
const SPEED := {"bird":3.4,"bee":0.65,"bear":1.05,"wolf":1.5,"rabbit":0.9,"turtle":0.22,"chicken":.7,"goblin":3.0,"witch":2.3,"bandit":3.3,"cyclops":2.0,"dragon":2.4,"sandworm":1.7}
var manager: Node3D
var species := "rabbit"
var animal_id := 0
var home := Vector3.ZERO
var pen_rect := Rect2()
var pen_id := ""
var target := Vector3.ZERO
var level := 1
var level_tag: Label3D
var _knock := Vector3.ZERO
var _lift := 0.0
var _geometry: Array = []
var hp := 20.0
var state := "idle"
var model: Node3D
var voice: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()
var _time := 0.0
var _decision := 0.0
var _attack_cd := 0.0
var _voice_timer := 0.0
var _respawn := 0.0
var _hurt := 0.0
var _flee := 0.0
var _network_position := Vector3.ZERO
var _network_yaw := 0.0
var _travel := 0.0
var _stuck := 0.0
var _last_pos := Vector3.ZERO
var _parts := {}
var _height := 0.65
var _radius := 0.24
var _head_rest_z := 0.0
var target_player := 0
var young := false
var parent_id := -1
var pack_id := -1
var flock_id := -1
var group_slot := 0
var size_factor := 1.0
var aggro_player := 0
var aggro_animal := -1
var anger_time := 0.0
var _think_clock := 0.0
var _intent := {}
var _wander_state := "idle"
var feeding_time := 0.0
var meal_point := Vector3.ZERO
var _progress_time := 0.0
var _progress_origin := Vector3.ZERO

func setup(owner_node: Node3D, kind: String, id: int, location: Vector3, config: Dictionary = {}) -> void:
	manager = owner_node
	species = kind
	young = bool(config.get("young",false))
	parent_id = int(config.get("parent",-1))
	pack_id = int(config.get("pack",-1))
	flock_id = int(config.get("flock",-1))
	group_slot = int(config.get("slot",0))
	size_factor = (.76 if species == "wolf" else 1.25 if species == "bird" else 1.0)*(.55 if young else 1.0)
	animal_id = id
	name = "%s_%02d" % [species, animal_id]
	rng.seed = 8713 + id * 137
	home = location
	global_position = home
	_network_position = home
	target = home
	level = level_at(home)
	hp = max_health()
	_height = float({"bear":1.5,"wolf":1.1,"rabbit":0.6,"turtle":0.3,"bird":0.26,"bee":0.12,"chicken":.65}.get(species,FOES.TYPES.get(species,{}).get("height",1.8)))*size_factor
	_radius = float({"bear":0.55,"wolf":0.35,"rabbit":0.2,"turtle":0.24,"bird":0.15,"bee":0.08,"chicken":.18}.get(species,FOES.TYPES.get(species,{}).get("radius",.4)))*size_factor
	collision_layer = 8
	collision_mask = 1
	floor_snap_length = 0.7
	floor_max_angle = deg_to_rad(48.0)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = _radius
	capsule.height = maxf(_height, _radius * 2)
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)
	set_meta("wildlife", true)
	model = MODELS.create("chick" if species == "chicken" and young else species)
	model.scale = Vector3.ONE*size_factor
	add_child(model)
	_geometry = model.find_children("*","GeometryInstance3D",true,false)
	level_tag = Label3D.new()
	level_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	level_tag.font_size = 32
	level_tag.pixel_size = .003
	level_tag.position.y = _height+.3
	level_tag.visibility_range_end = 14
	level_tag.modulate = Color("eed797")
	add_child(level_tag)
	level_tag.text = display_name()
	for part in model.get_children():
		_parts[part.name] = part
	if _parts.has("head"):
		_head_rest_z = _parts["head"].position.z
		if young: _parts["head"].scale = Vector3.ONE*1.15
	voice = AudioStreamPlayer3D.new()
	voice.bus = "Wildlife"
	voice.unit_size = 5.0
	voice.max_distance = {"bird":40.0,"bee":7.0,"bear":32.0,"wolf":65.0,"rabbit":6.0,"turtle":5.0,"chicken":18.0}.get(species,45.0)
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	voice.attenuation_filter_cutoff_hz = 6500.0
	voice.volume_db = -12.0
	add_child(voice)
	if species == "bee":
		var buzz: AudioStreamWAV = load("res://assets/audio/wildlife/bee.wav").duplicate()
		buzz.loop_mode = AudioStreamWAV.LOOP_FORWARD
		buzz.loop_end = int(buzz.get_length() * buzz.mix_rate)
		voice.stream = buzz
		voice.volume_db = -25.0
	_time = rng.randf() * 20.0
	_decision = rng.randf_range(0.1, 2.0)
	_voice_timer = rng.randf_range(2.0, 12.0)
	_last_pos = global_position
	_progress_origin = global_position
	_think_clock = rng.randf_range(0.0,.22)

func level_at(point: Vector3) -> int:
	var origin: Vector3 = manager.main.player.spawn_point
	return 1+mini(199,floori(Vector2(point.x-origin.x,point.z-origin.z).length()/180))

func max_health() -> float:
	return float(HEALTH[species])*(.5 if young else 1.0)*(1+.18*(level-1))

func experience_reward() -> int:
	return (6 if young else int(FOES.TYPES.get(species,{}).get("xp",{"bear":100,"wolf":60,"rabbit":12,"chicken":12,"turtle":10,"bird":8,"bee":5}.get(species,20))))*level

func food_reward() -> int:
	return 0 if FOES.TYPES.has(species) or young or species in ["bird","bee"] else 2 if species=="bear" else 1

func melee_distance(point: Vector3) -> float:
	return maxf(0,Vector2(point.x-global_position.x,point.z-global_position.z).length()-_radius)

func display_name() -> String:
	var label: String = ("Küken" if species == "chicken" else NAMES[species]+"-Jungtier") if young else NAMES[species]
	return label+" · Lv. %d" % level

func growth_speed() -> float:
	return (.9 if young else 1.0)*(1+minf(.5,.012*(level-1)))

func melee_reach() -> float:
	return {"bear":1.8,"wolf":1.25,"bee":1.1}.get(species,1.0)*(.7 if young else 1.0)

func predator() -> bool:
	return species in ["bear", "wolf"]

func flying() -> bool:
	return species in ["bird", "bee"]

func _physics_process(delta: float) -> void:
	if manager.main.world_data.get("streamed",false) and not manager.main.generator.chunks.has(manager.main.generator.chunk_of(global_position)):
		voice.stop()
		return
	_time += delta
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_hurt = maxf(0.0, _hurt - delta)
	_flee = maxf(0.0, _flee - delta)
	anger_time = maxf(0.0,anger_time-delta)
	feeding_time = maxf(0.0,feeding_time-delta)
	_think_clock -= delta
	_decision -= delta
	if manager.authority():
		_simulate(delta)
		if pen_rect.has_area():
			var point := Vector2(global_position.x,global_position.z).clamp(pen_rect.position+Vector2.ONE*.6,pen_rect.end-Vector2.ONE*.6)
			global_position.x = point.x; global_position.z = point.y
	else:
		global_position = global_position.lerp(_network_position, 1.0 - exp(-12.0 * delta))
		rotation.y = lerp_angle(rotation.y, _network_yaw, 1.0 - exp(-12.0 * delta))
	_audio_tick(delta)

func _simulate(delta: float) -> void:
	if hp <= 0.0:
		_respawn -= delta
		if _respawn <= 0.0:
			if not pen_rect.has_area(): home = manager.safe_wild_home(home,animal_id)
			_knock = Vector3.ZERO
			_lift = 0
			velocity = Vector3.ZERO
			hp = max_health()
			global_position = home + Vector3.UP * 0.3
			state = "idle"
			show()
			collision_layer = 8
		return
	if _knock.length()>.1 or _lift>0:
		velocity.x = _knock.x
		velocity.z = _knock.z
		velocity.y = _lift if _lift>0 else velocity.y-delta*18
		_lift = 0
		_knock = _knock.move_toward(Vector3.ZERO,delta*8)
		move_and_slide()
		return
	if _think_clock <= 0.0 or _intent.is_empty():
		_think_clock = .20
		_intent = manager.plan_for(self)
	target = _intent.get("goal",global_position)
	state = _intent.get("state","idle")
	var speed: float = float(_intent.get("speed",0.0))*growth_speed()
	target_player = int(_intent.get("player",0))
	var victim: Node = _intent.get("victim")
	if victim != null and is_instance_valid(victim) and victim.hp > 0.0:
		target = victim.global_position
	elif victim != null:
		_intent = {}
		_think_clock = 0.0
		state = "idle"
		speed = 0.0
	if target_player != 0:
		var current: Variant = manager.player_position(target_player)
		if current is Vector3:
			target = current+Vector3.UP*1.3 if species == "bee" else current
	var horizontal := Vector2(target.x-global_position.x,target.z-global_position.z).length()
	if (target_player != 0 or (victim != null and is_instance_valid(victim) and victim.hp > 0.0)) and horizontal < melee_reach() and absf(target.y-global_position.y) < 2.0 and manager.can_see(self,target):
		state = "attack"
		speed = 0.0
		if _attack_cd <= 0.0:
			_attack_cd = 1.7 if species == "bear" else 1.1
			var damage := (23.0 if species == "bear" else 11.0 if species == "wolf" else 2.0)*(.5 if young else 1.0)*(1+.12*(level-1))
			if target_player != 0:
				manager.damage_player(target_player,damage,animal_id)
			else:
				manager.attack_animal(self,victim,damage)
			call_sound(true)
	if species == "bird" and state == "flock":
		target = manager.flock_target(flock_id,group_slot)
		velocity = (manager.flock_velocity(flock_id,group_slot)+(target-global_position)*3.0).limit_length(10.0)
		if Vector2(velocity.x,velocity.z).length() > .1:
			rotation.y = lerp_angle(rotation.y,atan2(-velocity.x,-velocity.z),1.0-exp(-8.0*delta))
		move_and_slide()
		return
	var to := target - global_position
	var flat := Vector3(to.x, 0, to.z)
	if flat.length() < (0.24 if state == "patrol" else 0.45) and state in ["roam", "return", "follow", "patrol"]:
		state = "idle"
		speed = 0.0
	if _hurt > 0.0:
		speed *= 0.25
	var direction := flat.normalized()
	if direction.length_squared() > 0.1 and speed > 0.0:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0-exp(-7.0*delta))
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 9.0)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 9.0)
	if flying():
		velocity.y = clampf((target.y - global_position.y) * 1.5, -2.0, 3.5)
		var ahead := global_position + direction * 1.3
		var query := PhysicsRayQueryParameters3D.create(global_position, ahead, 1)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			velocity.y = 3.0
			target.y = maxf(target.y, global_position.y + 2.0)
		move_and_slide()
	else:
		var level: float = manager.main.player.water_level_at(global_position)
		if species == "turtle" and level > -50 and global_position.y < level + 0.15:
			velocity.y = clampf((level - 0.02 - global_position.y)*5.0, -2.0, 2.0)
		else:
			velocity.y = -1.0 if is_on_floor() else maxf(-20.0, velocity.y - delta * 18.0)
			if species == "rabbit" and speed > 0.1 and is_on_floor():
				velocity.y = 2.7
		# Stop at cliffs and water instead of charging blindly over an edge.
		if speed > 0.0:
			var ground: Dictionary = manager.ground_at(global_position + direction * maxf(0.8, _radius*2.0), global_position.y + 2.0)
			if ground.is_empty() or global_position.y-ground["position"].y > 1.8 or (species != "turtle" and manager.underwater(ground["position"])):
				velocity.x = 0
				velocity.z = 0
				_decision = 0.0
				state = "idle"
			else:
				_step_up(direction, delta)
		move_and_slide()
	if global_position.y < -15.0:
		global_position = home+Vector3.UP
		velocity = Vector3.ZERO
		target = home
		state = "idle"
	elif pack_id < 0 and flock_id < 0 and global_position.distance_to(home) > 45.0 and target_player == 0 and victim == null:
		target = home
		state = "return"
	if speed > 0.2 and global_position.distance_to(_last_pos) < 0.002:
		_stuck += delta
		if _stuck > 1.4:
			_choose_target()
			_decision = 3.0
			_stuck = 0.0
	else:
		_stuck = 0.0
	_last_pos = global_position
	_progress_time += delta
	if _progress_time > 1.8:
		var distance := Vector2(global_position.x-_progress_origin.x,global_position.z-_progress_origin.z).length()
		if speed > .2 and distance < .6 and state in ["patrol","idle"]:
			manager.reroute_pack(self)
		_progress_origin = global_position
		_progress_time = 0.0

func _choose_target() -> void:
	var radius: float = {"bird":10.0,"bee":2.4,"bear":10.0,"wolf":12.0,"rabbit":6.0,"turtle":4.0,"chicken":4.0}[species]
	for attempt in 8:
		var angle := rng.randf() * TAU
		var location := home + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(0.5, radius)
		if flying():
			location.y = home.y + rng.randf_range(-0.5, 1.7)
			target = location
			return
		var ground: Dictionary = manager.ground_at(location, maxf(home.y, global_position.y) + 3.0)
		if ground.is_empty() or ground["normal"].y < 0.7:
			continue
		location = ground["position"]
		if absf(location.y-home.y) > 3.0:
			continue
		if species != "turtle" and manager.underwater(location):
			continue
		target = location
		return
	target = home

func _step_up(direction: Vector3, delta: float) -> void:
	if not is_on_floor() or species == "rabbit":
		return
	var probe := direction * maxf(0.12, delta * SPEED[species])
	if not test_move(global_transform, probe):
		return
	var raised := global_transform.translated(Vector3.UP * 0.52)
	if not test_move(global_transform, Vector3.UP*0.52) and not test_move(raised, probe):
		var contact := KinematicCollision3D.new()
		if test_move(raised.translated(probe), Vector3.DOWN * 0.6, contact):
			var rise := 0.52 + contact.get_travel().y
			if rise > 0.05:
				global_position.y += rise
	elif species == "wolf" and not test_move(global_transform,Vector3.UP*1.1) and not test_move(global_transform.translated(Vector3.UP*1.1),probe):
		velocity.y = 6.2

func _process(delta: float) -> void:
	for mesh in _geometry: mesh.set_instance_shader_parameter("hit_flash",1.0 if _hurt>0 and fmod(_hurt,.14)>.055 else 0.0)
	if hp <= 0.0 or manager.main.player.global_position.distance_squared_to(global_position) > 10000:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_travel += speed * delta * 6.0
	model.position.y = sin(_time*3.0)*0.07 if flying() else sin(_travel*2.0)*minf(speed,1.0)*0.025
	model.rotation.z = sin(_time*4.0)*0.03 if flying() else 0.0
	if _parts.has("head"):
		_parts["head"].rotation.x = maxf(0.0,sin(_time*3.2))*.65 if species == "chicken" and state == "idle" else sin(_time*1.3)*0.06 if state == "idle" else 0.0
		if state == "feeding": _parts["head"].rotation.x = .65+sin(_time*7.0)*.12
		if species == "turtle":
			_parts["head"].position.z = lerpf(_parts["head"].position.z, _head_rest_z+0.16 if state == "hide" else _head_rest_z, 1.0-exp(-5.0*delta))
	for i in 4:
		var part: Node3D = _parts.get("leg%d" % i)
		if part:
			part.rotation.x = sin(_travel + (PI if i in [1,2] else 0.0)) * minf(speed,1.0) * (0.45 if species != "turtle" else 0.25)
	if _parts.has("wing_l"):
		var flap := (0.15 if species == "chicken" else 1.0)*sin(_time * (85.0 if species == "bee" else 19.0 if species == "bird" else 8.0)) * (0.8 if species == "bird" else 0.5)
		_parts["wing_l"].rotation.z = flap
		_parts["wing_r"].rotation.z = -flap
	if _parts.has("tail"):
		_parts["tail"].rotation.y = sin(_time*4.0)*0.12
	for i in 2:
		if _parts.has("ear%d" % i):
			_parts["ear%d" % i].rotation.x = sin(_time*2.0+i)*0.12
	if state == "attack":
		model.rotation.x = -sin((1.7-_attack_cd)*8.0)*0.12
	else:
		model.rotation.x = 0.0

func _audio_tick(delta: float) -> void:
	if hp <= 0.0:
		voice.stop()
		return
	var near: bool = manager.main.player.global_position.distance_to(global_position) < voice.max_distance
	if species == "bee":
		voice.pitch_scale = (1.25 if anger_time > 0.0 else 1.0)*(1.15 if young else 1.0)
		voice.volume_db = -18.0 if anger_time > 0.0 else -25.0
		if near and not voice.playing:
			voice.play()
		elif not near and voice.playing:
			voice.stop()
		return
	_voice_timer -= delta
	if _voice_timer <= 0.0:
		_voice_timer = rng.randf_range(6.0, 16.0) if species == "bird" else rng.randf_range(12.0, 32.0)
		if near:
			call_sound(state in ["chase","attack"])

func call_sound(aggressive: bool) -> void:
	if species == "bee":
		voice.pitch_scale = 1.25 if anger_time > 0.0 else 1.0
		voice.volume_db = -18.0 if anger_time > 0.0 else -25.0
		if not voice.playing: voice.play()
		return
	if voice.playing and not aggressive:
		return
	var sound: String = {"bird":"bird%d" % rng.randi_range(0,2),"wolf":"wolf_growl" if aggressive else "wolf_howl","bear":"bear","rabbit":"rabbit","turtle":"turtle","bee":"bee","chicken":"chick" if young else "chicken"}[species]
	voice.stream = load("res://assets/audio/wildlife/%s.wav" % sound)
	voice.pitch_scale = rng.randf_range(0.93, 1.07)*(1.2 if young else 1.0)
	voice.volume_db = -12.0 if predator() else -18.0
	voice.play()

func receive_hit(damage: float, attacker: Vector3, knock := 2.4, lift := 0.0, crit := false) -> bool:
	if hp <= 0.0:
		return false
	if not predator():
		_flee = 3.0
	hp = maxf(0.0, hp - damage)
	var away := global_position-attacker
	away.y = 0
	_knock = away.normalized()*knock
	_lift = lift
	visual_hit(damage,crit)
	state = "chase"
	target = attacker
	call_sound(true)
	if hp <= 0.0:
		_respawn = 100.0
		state = "dead"
		collision_layer = 0
		if manager.main.combat: manager.main.combat.fx.death(self)
		hide()
		voice.stop()
		return true
	return false

func visual_hit(damage: float, critical := false) -> void:
	_hurt = .4
	var text := Label3D.new()
	text.text = ("KRIT! " if critical else "")+str(roundi(damage))
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.font_size = 44 if critical else 34
	text.pixel_size = .004
	text.modulate = Color("ffe071") if critical else Color.WHITE
	manager.main.add_child(text)
	text.global_position = global_position+Vector3.UP*(_height+.5)
	var tween := text.create_tween().set_parallel(true)
	tween.tween_property(text,"position:y",text.position.y+.8,.65)
	tween.tween_property(text,"modulate:a",0.0,.65)
	tween.chain().tween_callback(text.queue_free)

func snapshot() -> Dictionary:
	return {"level":level,"id":animal_id,"p":global_position,"home":home,"y":rotation.y,"hp":hp,"s":state,"t":target,"r":_respawn,"v":velocity,"anger":anger_time,"ap":aggro_player,"aa":aggro_animal,"feed":feeding_time,"meal":meal_point}

func _exit_tree() -> void:
	if is_instance_valid(voice):
		voice.stop()
		voice.stream = null

func restore(data: Dictionary, snap := false) -> void:
	var was_alive := hp>0
	home = data.get("home",home)
	if snap and not pen_rect.has_area(): home = manager.safe_wild_home(home,animal_id)
	level = clampi(int(data.get("level",level_at(home))),1,200)
	if level_tag: level_tag.text = display_name()
	_network_position = data.get("p", home)
	if snap and not pen_rect.has_area() and not manager.village_clear(_network_position): _network_position = home
	_network_yaw = data.get("y", 0.0)
	hp = clampf(float(data.get("hp", max_health())),0.0,max_health())
	state = data.get("s", "idle")
	target = data.get("t", home)
	_respawn = maxf(0.0,float(data.get("r",0.0)))
	velocity = data.get("v", Vector3.ZERO)
	anger_time = float(data.get("anger",0.0))
	aggro_player = int(data.get("ap",0))
	aggro_animal = int(data.get("aa",-1))
	feeding_time = float(data.get("feed",0.0))
	meal_point = data.get("meal",global_position)
	_intent = {}
	_think_clock = 0.0
	if was_alive and hp<=0 and not snap and manager.main.combat: manager.main.combat.fx.death(self)
	visible = hp > 0.0
	collision_layer = 8 if visible else 0
	if snap:
		global_position = _network_position
		rotation.y = _network_yaw
