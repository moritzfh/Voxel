extends Node3D
const DOOR := preload("res://scripts/worlds/door.gd")
const RESIDENT := preload("res://scripts/worlds/resident.gd")
var main: Node
var stream: Node
var clock := 0.0
var doors := {}
var door_states := {}
var residents := {}
var resident_states := {}
var chunk_entities := {}
var feeding := {}
var pens := {}
var _sync := 0.0
var spawn_queue: Array = []

func setup(game: Node, terrain: Node) -> void:
	main = game; stream = terrain

func load_chunk(key: Vector2i, deferred := false) -> void:
	if chunk_entities.has(key): return
	var entities := {"doors":[],"residents":[],"animals":[]}
	chunk_entities[key] = entities
	var rect := Rect2(Vector2(key)*16,Vector2.ONE*16)
	var region: Dictionary = stream.land.region(stream.land.region_of(rect.get_center()))
	_spawn_wildlife(key,entities,deferred)
	if main.enemies: main.enemies.load_chunk(key,deferred)
	for house in region.houses:
		var point := Vector2(house.p.x+float(house.side)*3.5,house.p.y-.65)
		if rect.has_point(point):
			var door := Node3D.new()
			door.set_script(DOOR)
			add_child(door)
			door.setup(self,"house_"+str(house.id),Vector3(point.x,float(house.h)+.125,point.y),-PI*.5,false,float(house.side))
			doors[door.door_id] = door
			entities.doors.append(door.door_id)
	for village in region.villages:
		for yard in ["pen","field"]:
			var fence: Rect2 = village[yard]
			var point := Vector2(fence.get_center().x-1,fence.position.y)
			if rect.has_point(point):
				var door := Node3D.new()
				door.set_script(DOOR)
				add_child(door)
				door.setup(self,yard+"_"+str(village.id),Vector3(point.x,float(village.h)+.125,point.y),0,true)
				doors[door.door_id] = door
				entities.doors.append(door.door_id)
		if rect.has_point(village.p):
			pens[village.id] = village.pen
			for role in ["farmer","merchant","walker","guard"]:
				if deferred: spawn_queue.append({"key":key,"resident":true,"village":village,"role":role})
				else: _spawn_resident(key,village,role)
			var pen: Rect2 = village.pen
			var base_id := 100000+int((str(village.id)+"hens").hash()&0x3fffffff)*10
			for i in 8:
				var spot := pen.get_center()+Vector2((i%3-1)*1.3,(i/3-1)*1.3)
				var spec := {"species":"chicken","spot":spot,"young":i>=4,"parent":base_id+i%4 if i>=4 else -1,"pen":pen,"pen_id":village.id}
				if deferred: queue_spawn(key,base_id+i,spec,Vector3(spot.x,float(village.h)+.2,spot.y))
				else:
					var animal: Node = main.wildlife.spawn_external(base_id+i,spec,Vector3(spot.x,float(village.h)+.2,spot.y))
					entities.animals.append(animal.animal_id)

func unload_chunk(key: Vector2i) -> void:
	if not chunk_entities.has(key): return
	var entities: Dictionary = chunk_entities[key]
	for id in entities.doors:
		if doors.has(id): doors[id].queue_free(); doors.erase(id)
	for id in entities.residents:
		if residents.has(id):
			resident_states[id] = residents[id].snapshot()
			residents[id].queue_free(); residents.erase(id)
	for id in entities.animals: main.wildlife.remove_external(id)
	if main.enemies: main.enemies.unload_chunk(key)
	chunk_entities.erase(key)
	spawn_queue = spawn_queue.filter(func(job: Dictionary): return job.key!=key)
	main.interactables = main.interactables.filter(func(entry: Dictionary): return is_instance_valid(entry.node) and not entry.node.is_queued_for_deletion())

func toggle_door(id: String) -> void:
	if not doors.has(id): return
	var value := not bool(door_states.get(id,false))
	door_states[id] = value
	doors[id].set_open(value)
	if Net.is_host(): Net.send_op({"op":"door_state","id":id,"open":value})

func _spawn_wildlife(key: Vector2i, entities: Dictionary, deferred := false) -> void:
	var value: int = stream.land.coordinate_seed(key,61391)
	var point := Vector2(key)*16+Vector2(8,8)
	var region: Dictionary = stream.land.region(stream.land.region_of(point))
	if not main.wildlife.village_clear(Vector3(point.x,0,point.y),12): return
	for dungeon in region.get("dungeons",[]):
		if point.distance_to(dungeon.p)<24: return
	if stream.land.river_distance(point)<10 or stream.land.water_level(point)>-50: return
	var species := ""
	if value%23==0: species = "bird"
	elif value%17==0: species = "wolf"
	elif value%19==0: species = "bear"
	elif value%13==0: species = "rabbit"
	elif value%11==0: species = "bee"
	elif stream.land.river_distance(point)<16 and value%5==0: species = "turtle"
	if species.is_empty(): return
	var base_id: int = 2000000000000+value*32
	var group := base_id
	var points := PackedVector3Array()
	for offset: Vector2 in [Vector2(-4,-4),Vector2(4,-4),Vector2(4,4),Vector2(-4,4),Vector2(-4,-4)]:
		var p := point+offset
		points.append(Vector3(p.x,stream.land.height(p)+.15,p.y))
	if species=="wolf":
		var trail := []
		for i in 60: trail.append(points[0].lerp(points[1],float(i)/60))
		main.wildlife.packs[group] = {"points":points,"waypoint":1,"trail":trail,"members":[],"leader":null}
	elif species=="bird":
		var curve := Curve3D.new()
		curve.up_vector_enabled = false
		for i in 9:
			var a := float(i%8)*TAU/8
			curve.add_point(Vector3(point.x+cos(a)*32,stream.land.height(point)+22,point.y+sin(a)*32))
		main.wildlife.flocks[group] = {"curve":curve,"offset":0.0}
	var count := 14 if species=="bird" else 5 if species=="wolf" else 2 if species in ["bear","rabbit","turtle"] else 4
	for i in count:
		var spec := {"species":species,"spot":point,"young":i>=3 if species=="wolf" else i==count-1,"parent":base_id if i==count-1 else -1}
		var position := Vector3(point.x+(i%3-1)*1.2,stream.land.height(point)+.15,point.y+(i/3)*1.1)
		if species=="wolf":
			spec.merge({"pack":group,"slot":i},true)
			position = points[0]+Vector3(i*1.4,0,0)
		elif species=="bird":
			spec.merge({"flock":group,"slot":i},true)
			position = main.wildlife.flock_target(group,i)
		elif species=="bee": position.y += 1.2
		if deferred: queue_spawn(key,base_id+i,spec,position)
		else:
			var animal: Node = main.wildlife.spawn_external(base_id+i,spec,position)
			entities.animals.append(animal.animal_id)

func handle_op(from_id: int, op: Dictionary) -> void:
	match str(op.get("op","")):
		"door_request":
			if not Net.is_host() or not Net.players.has(from_id): return
			var id := str(op.get("id",""))
			var point: Variant = main.wildlife.player_position(from_id)
			if doors.has(id) and point is Vector3 and doors[id].global_position.distance_to(point)<4: toggle_door(id)
		"door_state":
			if from_id!=1 or Net.is_host(): return
			var id := str(op.get("id",""))
			door_states[id] = bool(op.get("open",false))
			if doors.has(id): doors[id].set_open(door_states[id])
		"village_state":
			if from_id!=1 or Net.is_host(): return
			clock = float(op.get("clock",clock))
			for state in op.get("residents",[]):
				resident_states[str(state.id)] = state
				if residents.has(str(state.id)): residents[str(state.id)].restore(state)

func _physics_process(delta: float) -> void:
	clock += delta
	if not Net.is_host(): return
	_sync -= delta
	if _sync<=0:
		_sync = .3
		var states := []
		for resident in residents.values(): states.append(resident.snapshot())
		Net.send_op({"op":"village_state","clock":clock,"residents":states})

func save_state() -> Dictionary:
	var states := resident_states.duplicate(true)
	for id in residents: states[id] = residents[id].snapshot()
	return {"clock":clock,"doors":door_states.duplicate(),"residents":states}

func load_state(state: Dictionary) -> void:
	clock = float(state.get("clock",clock))
	door_states = state.get("doors",{}).duplicate()
	resident_states = state.get("residents",{}).duplicate(true)
	for id in doors: doors[id].set_open(bool(door_states.get(id,false)),true)
	for id in residents:
		if resident_states.has(id): residents[id].restore(resident_states[id])

func queue_spawn(key: Vector2i, id: int, spec: Dictionary, point: Vector3, enemy := false) -> void:
	spawn_queue.append({"key":key,"id":id,"spec":spec,"point":point,"enemy":enemy})

func _pump_spawns() -> void:
	var deadline := Time.get_ticks_usec()+1800
	var count := 0
	while not spawn_queue.is_empty() and count<2 and Time.get_ticks_usec()<deadline:
		var job: Dictionary = spawn_queue.pop_front()
		if not chunk_entities.has(job.key): continue
		if bool(job.get("resident",false)):
			_spawn_resident(job.key,job.village,job.role)
			count += 1
			continue
		var animal: Node = main.wildlife.spawn_external(job.id,job.spec,job.point)
		if not job.enemy: chunk_entities[job.key].animals.append(animal.animal_id)
		count += 1

func _process(_delta: float) -> void:
	_pump_spawns()

func _spawn_resident(key: Vector2i, village: Dictionary, role: String) -> void:
	var resident := StaticBody3D.new()
	resident.set_script(RESIDENT)
	var id := str(village.id)+"_"+role
	resident.configure(self,village,id,role)
	add_child(resident)
	resident.talked.connect(main._on_npc_talked)
	residents[id] = resident
	if resident_states.has(id): resident.restore(resident_states[id])
	main.interactables.append({"node":resident,"kind":"npc","label":"[E] Mit %s sprechen" % resident.display_name})
	chunk_entities[key].residents.append(id)
