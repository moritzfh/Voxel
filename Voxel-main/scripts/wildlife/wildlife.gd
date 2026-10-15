extends Node3D
## The host simulates wildlife; clients receive interpolated snapshots and request melee hits.
const ENEMY := preload("res://scripts/enemies/enemy.gd")
const ANIMAL := preload("res://scripts/wildlife/animal.gd")
const BEHAVIOR := preload("res://scripts/wildlife/behavior.gd")
const SPAWNS := {
	"bird":[Vector2(-6,2),Vector2(-20,-16),Vector2(20,-8),Vector2(30,-38),Vector2(-12,-52),Vector2(18,-70),Vector2(48,-100),Vector2(-35,-89)],
	"bee":[Vector2(-4,5),Vector2(-6,7),Vector2(-10,10),Vector2(26,-7),Vector2(29,-8),Vector2(35,3),Vector2(-8,-42),Vector2(-11,-45)],
	"bear":[Vector2(44,-106),Vector2(67,-125),Vector2(-52,-106)],
	"wolf":[Vector2(24,-82),Vector2(34,-96),Vector2(10,-119),Vector2(46,-121)],
	"rabbit":[Vector2(-5,11),Vector2(-10,18),Vector2(28,-5),Vector2(40,6),Vector2(-10,-57),Vector2(-40,10),Vector2(15,-71)],
	"turtle":[Vector2(3,7),Vector2(17,-13),Vector2(23,-35),Vector2(43,-70)],
	"chicken":[Vector2(-8,20),Vector2(-12,22),Vector2(-16,20),Vector2(-38,-32),Vector2(-40,-36),Vector2(-42,-31)],
}
var main: Node
var animals: Array = []
var foes: Array = []

func all_actors() -> Array:
	return animals+foes

var by_id := {}
var _sync_time := 0.0
var _hit_cooldowns := {}
var packs := {}
var flocks := {}
var by_species := {}
var children := {}
var world_time := 0.0
var navigation := AStar3D.new()
var _world_features_cache := false
var external_states := {}
const VILLAGE_BUFFER := 48.0
var _fixed_village_zones: Array = []

func village_zones(point: Vector2) -> Array:
	if main.world_data.get("streamed",false):
		var result := []
		var region: Vector2i = main.generator.land.region_of(point)
		for x in range(-1,2):
			for z in range(-1,2):
				for village in main.generator.land.region(region+Vector2i(x,z)).villages:
					result.append([village.p,VILLAGE_BUFFER])
		return result
	return _fixed_village_zones

func village_clear(point: Vector3, margin := 0.0) -> bool:
	var flat := Vector2(point.x,point.z)
	for zone in village_zones(flat):
		if flat.distance_to(zone[0])<float(zone[1])+margin: return false
	return true

func safe_wild_home(point: Vector3, id := 0) -> Vector3:
	if village_clear(point,3): return point
	var origin := Vector2(point.x,point.z)
	var altitude := 0.0
	if main.world_data.get("streamed",false): altitude = maxf(0,point.y-main.generator.land.height(origin))
	# Deterministic search, independent of loaded chunks and peer frame timing.
	for ring in range(1,16):
		for step in 24:
			var angle := TAU*float(step)/24+float(posmod(id,13))*.13
			var p := origin+Vector2(cos(angle),sin(angle))*float(ring)*10
			var location := Vector3(p.x,point.y,p.y)
			if not village_clear(location,4): continue
			if main.world_data.get("streamed",false):
				if main.generator.land.water_level(p)>-50: continue
				location.y = main.generator.land.height(p)+maxf(.15,altitude)
			else:
				if not main.player.world_bounds.grow(-2).has_point(p): continue
				var ground := ground_at(location,70)
				if ground.is_empty() or underwater(ground.position): continue
				location.y = ground.position.y+.08
			return location
	return point

func spawn_external(id: int, spec: Dictionary, position: Vector3) -> Node:
	if by_id.has(id): return by_id[id]
	if not spec.has("pen"): position = safe_wild_home(position,id)
	var animal := CharacterBody3D.new()
	animal.set_script(ENEMY if ANIMAL.FOES.TYPES.has(str(spec.species)) else ANIMAL)
	add_child(animal)
	animal.setup(self,str(spec.species),id,position,spec)
	animal.pen_rect = spec.get("pen",Rect2())
	animal.pen_id = str(spec.get("pen_id",""))
	if animal.has_meta("enemy"): foes.append(animal)
	else: animals.append(animal)
	by_id[id] = animal
	if not by_species.has(animal.species): by_species[animal.species] = []
	by_species[animal.species].append(animal)
	if animal.pack_id>=0 and packs.has(animal.pack_id): packs[animal.pack_id].members.append(animal)
	if animal.parent_id>=0:
		if not children.has(animal.parent_id): children[animal.parent_id] = []
		children[animal.parent_id].append(animal)
	if external_states.has(id): animal.restore(external_states[id],true)
	return animal

func remove_external(id: int) -> void:
	if not by_id.has(id): return
	var animal: Node = by_id[id]
	external_states[id] = animal.snapshot()
	animals.erase(animal)
	foes.erase(animal)
	by_species[animal.species].erase(animal)
	by_id.erase(id)
	for list in children.values(): list.erase(animal)
	children.erase(id)
	if packs.has(animal.pack_id):
		packs[animal.pack_id].members.erase(animal)
		if packs[animal.pack_id].members.is_empty(): packs.erase(animal.pack_id)
	if animal.flock_id>=3:
		var alive := false
		for bird in by_species.get("bird",[]):
			if bird.flock_id==animal.flock_id: alive = true
		if not alive: flocks.erase(animal.flock_id)
	animal.queue_free()

func setup(game: Node) -> void:
	main = game
	if not main.world_data.get("streamed",false):
		for village in main.world_data.get("villages",[]): _fixed_village_zones.append([village.p,VILLAGE_BUFFER])
		if _fixed_village_zones.is_empty():
			for house in main._house_markers(): _fixed_village_zones.append([Vector2(house[0],house[1]),23.0])
	_build_routes()
	var specs: Array = []
	for species: String in SPAWNS:
		for spot: Vector2 in SPAWNS[species]:
			specs.append({"species":species,"spot":spot})
	# Preserve the first 34 IDs so existing wildlife saves still map to the same adults.
	for i in 22:
		specs.append({"species":"bird","spot":Vector2.ZERO})
	for i in 4:
		specs.append({"species":"wolf","spot":Vector2.ZERO})
	var adult_birds: Array = range(8)
	adult_birds.append_array(range(40,62))
	for i in adult_birds.size():
		specs[adult_birds[i]].merge({"flock":i/10,"slot":i%10},true)
	var pack_members := [[19,20,62,63],[21,22,64,65]]
	for group in 2:
		for slot in 4:
			specs[pack_members[group][slot]].merge({"pack":group,"slot":slot},true)
	for parent in [16,17,19,19,21,21,23,24,25,26,27,30,31,32,8,10,12,14]:
		var spec: Dictionary = specs[parent].duplicate()
		spec.merge({"young":true,"parent":parent,"spot":spec["spot"]+Vector2(1.0,0.7)},true)
		if spec["species"] == "wolf":
			spec["slot"] = 4+int(children.get(parent,[]).size())
			var known: Array = children.get(parent,[])
			known.append(specs.size())
			children[parent] = known
		specs.append(spec)
	children.clear()
	for i in 12:
		var group: int = i%3
		var parent: int = adult_birds[group*10+i/3]
		specs.append({"species":"bird","spot":Vector2.ZERO,"young":true,"parent":parent,"flock":group,"slot":10+i/3})
	for parent in range(34,40):
		specs.append({"species":"chicken","spot":specs[parent]["spot"]+Vector2(.5,.5),"young":true,"parent":parent})
	if main.world_data.get("procedural",false):
		var seeded := RandomNumberGenerator.new()
		seeded.seed = int(Worlds.config.seed)^71314
		var village: Vector2 = main.world_data.villages[0].p
		for spec: Dictionary in specs:
			if spec.has("pack") or spec.has("flock"): continue
			var anchor: Vector2 = village
			if spec.species in ["bear","rabbit"]:
				var tree: Vector3 = main.world_data.forests[seeded.randi_range(0,main.world_data.forests.size()-1)]
				anchor = Vector2(tree.x,tree.z)
			elif spec.species == "turtle" and not main.world_data.river.is_empty():
				anchor = main.world_data.river[seeded.randi_range(12,main.world_data.river.size()-13)]+Vector2(7,0)
			spec.spot = anchor+Vector2(seeded.randf_range(-5,5),seeded.randf_range(-5,5))
		for spec: Dictionary in specs:
			if spec.get("parent",-1) >= 0 and not spec.has("pack") and not spec.has("flock"):
				spec.spot = specs[spec.parent].spot+Vector2(1,.7)
		if main.world_data.get("streamed",false):
			var village_data: Dictionary = main.generator.land.region(Vector2i.ZERO).villages[0]
			for spec: Dictionary in specs:
				if spec.species=="chicken": spec.spot = village_data.pen.get_center()
	for id in specs.size():
		var spec: Dictionary = specs[id]
		var location := _spawn_position(spec)
		var farm: bool = main.world_data.get("streamed",false) and spec.species=="chicken"
		if not farm and int(spec.get("parent",-1))>=0 and by_id.has(int(spec.parent)):
			location = by_id[int(spec.parent)].home+Vector3(1,0,.7)
		if not farm: location = safe_wild_home(location,id)
		var animal := CharacterBody3D.new()
		animal.set_script(ANIMAL)
		add_child(animal)
		animal.setup(self,spec["species"],id,location+Vector3.UP*.08,spec)
		if main.world_data.get("streamed",false) and spec.species=="chicken":
			var home_village: Dictionary = main.generator.land.region(Vector2i.ZERO).villages[0]
			animal.pen_rect = home_village.pen
			animal.pen_id = home_village.id
		animals.append(animal)
		by_id[id] = animal
		var list: Array = by_species.get(animal.species,[])
		list.append(animal)
		by_species[animal.species] = list
		if animal.parent_id >= 0:
			var offspring: Array = children.get(animal.parent_id,[])
			offspring.append(animal)
			children[animal.parent_id] = offspring
		if animal.pack_id >= 0:
			packs[animal.pack_id]["members"].append(animal)

func _spawn_position(spec: Dictionary) -> Vector3:
	if spec.has("flock"):
		return flock_target(int(spec["flock"]),int(spec["slot"]))
	if spec.has("pack"):
		return trail_point(int(spec["pack"]),float(spec["slot"])*1.45)
	var spot: Vector2 = spec["spot"]
	var location := Vector3(spot.x,0,spot.y)
	var ground := ground_at(location,70.0)
	if not ground.is_empty():
		location = ground["position"]
	if spec["species"] == "bee":
		location.y += 1.2
	elif spec["species"] == "turtle":
		var water: float = main.player.water_level_at(location)
		if water > -50:
			location.y = maxf(location.y,water+.1)
	else:
		for attempt in 12:
			if not underwater(location):
				break
			var offset := Vector3(cos(attempt*2.4),0,sin(attempt*2.4))*(3.0+attempt*.7)
			ground = ground_at(Vector3(spot.x,0,spot.y)+offset,70.0)
			if not ground.is_empty():
				location = ground["position"]
	return location

func authority() -> bool:
	if Worlds.remote: return false
	return not Net.active() or Net.is_host()

func nearest_player(point: Vector3) -> Dictionary:
	var result := {"id":Net.my_id(),"position":main.player.global_position,"distance":point.distance_to(main.player.global_position)}
	for id in main.remotes:
		var player: Node3D = main.remotes[id]
		if not player.visible:
			continue
		var distance := point.distance_to(player.global_position)
		if distance < float(result["distance"]):
			result = {"id":id,"position":player.global_position,"distance":distance}
	return result

func ground_at(point: Vector3, from_y: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x,from_y,point.z),Vector3(point.x,-18,point.z),1)
	query.exclude = [main.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

func underwater(point: Vector3) -> bool:
	var level: float = main.player.water_level_at(point)
	return level > -50.0 and point.y < level - 0.1

func can_see(animal: Node3D, point: Vector3) -> bool:
	var origin: Vector3 = animal.global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(origin,point+Vector3.UP,1)
	query.exclude = [main.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _physics_process(delta: float) -> void:
	if not authority():
		return
	world_time += delta
	_update_packs()
	if not Net.active() or not Net.is_host():
		return
	_sync_time -= delta
	if _sync_time <= 0.0:
		_sync_time = 0.25
		var compact := []
		for animal in all_actors():
			compact.append([animal.animal_id,animal.global_position,animal.rotation.y,animal.hp,animal.state,animal.velocity,animal.level])
		Net.send_op({"op":"wild_state","animals":compact,"clock":world_time,"world_features":main.world_features_enabled()})

func hit(animal_id: int) -> void:
	if authority():
		_apply_hit(Net.my_id(),animal_id,Game.tool_tier)
	else:
		Net.send_op_to(1,{"op":"wild_hit","id":animal_id,"tier":Game.tool_tier})

func melee_target(origin: Vector3, direction: Vector3) -> Node3D:
	var closest: Node3D = null
	var best := INF
	for animal in all_actors():
		if animal.hp <= 0.0 or animal.melee_distance(main.player.global_position) > 3.3:
			continue
		var center: Vector3 = animal.global_position+Vector3.UP*(animal._height*0.55)
		var along := (center-origin).dot(direction)
		if along <= 0.0:
			continue
		var off_axis := center.distance_to(origin+direction*along)
		if off_axis > 0.65+animal._radius or along > best:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin,center,1)
		query.exclude = [main.player.get_rid()]
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty() and can_see(animal,main.player.global_position):
			best = along
			closest = animal
	return closest

func _apply_hit(player_id: int, animal_id: int, tier: int) -> void:
	if not by_id.has(animal_id):
		return
	var now := Time.get_ticks_msec()
	if now - int(_hit_cooldowns.get(player_id,-1000)) < 420:
		return
	var location: Vector3
	if player_id == Net.my_id():
		location = main.player.global_position
	elif main.remotes.has(player_id):
		location = main.remotes[player_id].global_position
	else:
		return
	var animal: Node3D = by_id[animal_id]
	if animal.hp <= 0.0 or location.distance_to(animal.global_position) > 3.5 or not can_see(animal,location):
		return
	_hit_cooldowns[player_id] = now
	provoke(animal,player_id)
	var died: bool = animal.receive_hit(23.0+float(clampi(tier,1,4)-1)*7.0,location)
	Sfx.play("hit",animal.global_position+Vector3.UP*0.5,-11.0)
	if died:
		var xp: int = animal.experience_reward()
		var food: int = animal.food_reward()
		if player_id == Net.my_id():
			_reward(xp,food)
		else:
			Net.send_op_to(player_id,{"op":"wild_reward","xp":xp,"food":food})

func damage_player(player_id: int, amount: float, animal_id: int) -> void:
	if not authority() or not by_id.has(animal_id):
		return
	var animal: Node3D = by_id[animal_id]
	amount *= Worlds.damage_multiplier()
	if player_id == Net.my_id():
		main.player.take_damage(amount,animal.NAMES[animal.species])
	else:
		Net.send_op_to(player_id,{"op":"wild_damage","amount":amount,"id":animal_id})

func _reward(xp: int, food: int) -> void:
	Game.add_xp(xp)
	main.player.food += food
	main.player.stats_changed.emit()
	main.hud.show_toast("Besiegt · +%d Erfahrung" % xp + (" · +%d Essen" % food if food>0 else ""))

func apply_remote(from_id: int, op: Dictionary) -> void:
	match str(op.get("op","")):
		"wild_state":
			if from_id != 1 or authority():
				return
			world_time = float(op.get("clock",world_time))
			main.accept_world_rule(bool(op.get("world_features",false)))
			for entry in op.get("animals",[]):
				if entry is Array and entry.size() >= 6 and by_id.has(int(entry[0])):
					by_id[int(entry[0])].restore({"p":entry[1],"y":entry[2],"hp":entry[3],"s":entry[4],"v":entry[5],"level":entry[6] if entry.size()>6 else 1})
				elif entry is Array and entry.size()>=6 and int(entry[0])>=100000:
					external_states[int(entry[0])] = {"id":entry[0],"p":entry[1],"y":entry[2],"hp":entry[3],"s":entry[4],"v":entry[5],"level":entry[6] if entry.size()>6 else 1}
		"wild_hit":
			if authority():
				_apply_hit(from_id,int(op.get("id",-1)),int(op.get("tier",1)))
		"wild_damage":
			if from_id == 1 and not authority() and by_id.has(int(op.get("id",-1))):
				var animal: Node3D = by_id[int(op["id"])]
				main.player.take_damage(clampf(float(op.get("amount",0.0)),0.0,maxf(23.0,float(ANIMAL.FOES.TYPES.get(animal.species,{}).get("damage",23.0)))*(1+.12*(animal.level-1))*Worlds.damage_multiplier()),animal.NAMES[animal.species])
		"wild_reward":
			if from_id == 1 and not authority():
				_reward(clampi(int(op.get("xp",0)),0,140000),clampi(int(op.get("food",0)),0,2))

func save_state() -> Array:
	var state: Array = external_states.values().duplicate(true)
	for animal in all_actors():
		state.append(animal.snapshot())
	var groups := {}
	for group in packs:
		groups[group] = {"points":packs[group]["points"],"waypoint":packs[group]["waypoint"],"trail":packs[group]["trail"].duplicate()}
	state.append({"id":-1,"groups":groups,"clock":world_time})
	var flock_data := {}
	for group in flocks:
		var curve: Curve3D = flocks[group].curve
		var points := []
		for i in curve.point_count: points.append([curve.get_point_position(i),curve.get_point_in(i),curve.get_point_out(i)])
		flock_data[group] = {"points":points,"offset":flocks[group].offset}
	state.append({"id":-2,"flocks":flock_data})
	return state

func load_state(state: Array) -> void:
	for entry in state:
		if entry is Dictionary and entry.has("flocks"):
			for group in entry.flocks:
				var description: Dictionary = entry.flocks[group]
				var curve := Curve3D.new()
				curve.up_vector_enabled = false
				for point in description.points: curve.add_point(point[0],point[1],point[2])
				flocks[int(group)] = {"curve":curve,"offset":float(description.offset)}
		if entry is Dictionary and entry.has("groups"):
			world_time = float(entry.get("clock",world_time))
			for group in entry["groups"]:
				var key := int(group)
				if packs.has(key):
					var saved: Dictionary = entry["groups"][group]
					packs[key]["points"] = saved.get("points",packs[key]["points"])
					packs[key]["waypoint"] = clampi(int(saved.get("waypoint",1)),0,packs[key]["points"].size()-1)
					packs[key]["trail"] = saved.get("trail",packs[key]["trail"]).duplicate()
		if entry is Dictionary and by_id.has(int(entry.get("id",-1))):
			by_id[int(entry["id"])].restore(entry,true)
		elif entry is Dictionary and int(entry.get("id",-1))>=100000:
			external_states[int(entry.id)] = entry.duplicate(true)

func plan_for(animal: Node) -> Dictionary:
	return BEHAVIOR.decide(self,animal)

func player_position(id: int) -> Variant:
	if id == Net.my_id():
		return main.player.global_position
	if main.remotes.has(id) and main.remotes[id].visible:
		return main.remotes[id].global_position
	return null

func living_near(point: Vector3, radius: float, species := "") -> Array:
	var result := []
	for animal in (all_actors() if species == "" else by_species.get(species,[])):
		if animal.hp > 0.0 and animal.global_position.distance_squared_to(point) < radius*radius:
			result.append(animal)
	return result

func has_cub(bear: Node) -> bool:
	for cub in children.get(bear.animal_id,[]):
		if cub.hp > 0 and cub.global_position.distance_to(bear.global_position) < 15.0:
			return true
	return false

func provoke(animal: Node, player_id: int) -> void:
	animal.feeding_time = 0.0
	animal.aggro_player = player_id
	animal.anger_time = 24.0
	animal._think_clock = 0.0
	for parent in [by_id.get(animal.parent_id)]:
		if parent != null and parent.hp > 0:
			parent.aggro_player = player_id
			parent.anger_time = 30.0
			parent._think_clock = 0.0
	if animal.has_meta("enemy"):
		for friend in foes:
			if friend.encounter_id==animal.encounter_id and friend.hp>0:
				friend.aggro_player = player_id; friend.anger_time = 24
	if animal.species in ["bee","wolf"]:
		for friend in living_near(animal.global_position,14.0,animal.species):
			if animal.species == "bee" or friend.pack_id == animal.pack_id:
				friend.aggro_player = player_id
				friend.anger_time = 24.0
				friend._think_clock = 0.0

func attack_animal(attacker: Node, victim: Node, amount: float) -> void:
	if not authority() or attacker.hp <= 0 or victim.hp <= 0:
		return
	if attacker.global_position.distance_to(victim.global_position) > attacker.melee_reach()+1.0:
		return
	victim.aggro_animal = attacker.animal_id
	victim.anger_time = 18.0
	victim._think_clock = 0.0
	var killed: bool = victim.receive_hit(amount,attacker.global_position)
	if killed and attacker.species in ["wolf","bear"]:
		attacker.feeding_time = 4.0
		attacker.meal_point = victim.global_position
		attacker.hp = minf(attacker.max_health(),attacker.hp+8.0)
		attacker._think_clock = 0.0
	Sfx.play("hit",victim.global_position+Vector3.UP*.3,-20.0)

func pack_strength(animal: Node, radius := 12.0) -> int:
	var count := 0
	for friend in packs.get(animal.pack_id,{}).get("members",[]):
		if friend.hp > 0 and not friend.young and friend.global_position.distance_to(animal.global_position) < radius:
			count += 1
	return count

func patrol_target(animal: Node) -> Vector3:
	var pack: Dictionary = packs[animal.pack_id]
	var leader: Node = pack.get("leader")
	if leader == null or leader == animal:
		return pack["points"][int(pack["waypoint"])]
	return trail_point(animal.pack_id,float(animal.group_slot)*1.45)

func trail_point(group: int, distance: float) -> Vector3:
	var trail: Array = packs[group]["trail"]
	for i in trail.size()-1:
		var length: float = trail[i].distance_to(trail[i+1])
		if distance <= length:
			return trail[i].lerp(trail[i+1],distance/maxf(length,.001))
		distance -= length
	return trail.back()

func flock_target(group: int, slot: int, at_time := -1.0) -> Vector3:
	var flock: Dictionary = flocks[group]
	var curve: Curve3D = flock["curve"]
	var clock := world_time if at_time < 0 else at_time
	var progress := fposmod(clock*4.5+float(flock["offset"]),curve.get_baked_length())
	var point := curve.sample_baked(progress)
	var ahead := curve.sample_baked(fposmod(progress+1.0,curve.get_baked_length()))
	var forward := (ahead-point).normalized()
	var right := Vector3(-forward.z,0,forward.x)
	var rank := float((slot+1)/2)
	var side := -1.0 if slot%2 == 1 else 1.0
	var offset := right*side*rank*1.0-forward*rank*1.35
	if group == 1:
		offset = right*float(slot%4-2)*1.2-forward*float(slot/4)*1.3
	elif group == 2:
		offset = right*float(slot)*.65-forward*float(slot)*1.1
	if slot == 0:
		offset = Vector3.ZERO
	return point+offset+Vector3.UP*sin(clock*1.4+slot)*.12

func flock_velocity(group: int, slot: int) -> Vector3:
	return (flock_target(group,slot,world_time+.08)-flock_target(group,slot,world_time))/.08

func _update_packs() -> void:
	for group in packs:
		var pack: Dictionary = packs[group]
		var leader: Node = null
		for member in pack["members"]:
			if member.hp > 0 and not member.young:
				leader = member
				break
		pack["leader"] = leader
		if leader == null:
			continue
		var trail: Array = pack["trail"]
		if Vector2(leader.global_position.x-trail[0].x,leader.global_position.z-trail[0].z).length() > .25:
			trail.push_front(leader.global_position)
			if trail.size() > 180:
				trail.resize(180)
		var points: PackedVector3Array = pack["points"]
		if leader.global_position.distance_to(points[int(pack["waypoint"])]) < 1.3:
			pack["waypoint"] = (int(pack["waypoint"])+1)%points.size()

func reroute_pack(animal: Node) -> void:
	if animal.pack_id < 0: return
	var pack: Dictionary = packs[animal.pack_id]
	if pack.get("leader") != animal: return
	if animal.pack_id>=3:
		pack.waypoint = (int(pack.waypoint)+1)%pack.points.size()
		return
	var points: PackedVector3Array = pack["points"]
	var waypoint: int = pack["waypoint"]
	var blocked := navigation.get_closest_point(points[waypoint])
	if blocked >= 0: navigation.set_point_disabled(blocked,true)
	var next_index := mini(waypoint+3,points.size()-1)
	var start := navigation.get_closest_point(animal.global_position)
	var finish := navigation.get_closest_point(points[next_index])
	var detour := navigation.get_point_path(start,finish)
	if detour.size() >= 2:
		var replacement := points.slice(0,waypoint)
		replacement.append_array(detour)
		replacement.append_array(points.slice(next_index+1))
		pack["points"] = replacement
		pack["waypoint"] = waypoint
	else:
		pack["waypoint"] = (waypoint+1)%points.size()

func _build_routes() -> void:
	# Build a small dry-ground navigation graph for river/forest patrols.
	var grid := {}
	var bounds := Rect2(-55,-143,138,182)
	var step := 3
	if main.world_data.get("procedural",false):
		bounds = main.player.world_bounds.grow(-6)
		step = 4
		if main.world_data.get("streamed",false):
			bounds = Rect2(Vector2(main.player.position.x-22,main.player.position.z-22),Vector2(44,44))
	for x in range(int(bounds.position.x),int(bounds.end.x),step):
		for z in range(int(bounds.position.y),int(bounds.end.y),step):
			var ground := ground_at(Vector3(x,0,z),70.0)
			if ground.is_empty() or ground["normal"].y < .7 or underwater(ground["position"]):
				continue
			var index := navigation.get_available_point_id()
			navigation.add_point(index,ground["position"]+Vector3.UP*.05)
			grid[Vector2i(x,z)] = index
	for cell: Vector2i in grid:
		for offset in [Vector2i(step,0),Vector2i(0,step),Vector2i(step,step),Vector2i(-step,step)]:
			if not grid.has(cell+offset):
				continue
			var a: Vector3 = navigation.get_point_position(grid[cell])
			var b: Vector3 = navigation.get_point_position(grid[cell+offset])
			if absf(a.y-b.y) > 1.1:
				continue
			var ray := PhysicsRayQueryParameters3D.create(a+Vector3.UP*.55,b+Vector3.UP*.55,1)
			ray.exclude = [main.player.get_rid()]
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				navigation.connect_points(grid[cell],grid[cell+offset])
	var anchors := [
		[Vector3(22,0,-32),Vector3(20,0,-23),Vector3(-1,0,-23),Vector3(0,0,-49),Vector3(12,0,-72),Vector3(20,0,-53),Vector3(14,0,-59),Vector3(0,0,-49),Vector3(-1,0,-23),Vector3(20,0,-23),Vector3(22,0,-32)],
		[Vector3(68,0,-137),Vector3(74,0,-121),Vector3(69,0,-108),Vector3(59,0,-97),Vector3(68,0,-118),Vector3(68,0,-137)],
	]
	if main.world_data.get("procedural",false):
		anchors.clear()
		var river_points: Array = main.world_data.river
		var centers: Array = main.world_data.forests
		for group in 2:
			var center: Vector3 = centers[mini(group*centers.size()/2,centers.size()-1)]
			var flat := Vector2(center.x,center.z)
			var nearest := flat+Vector2(10,10)
			var distance := INF
			for p: Vector2 in river_points:
				if p.distance_squared_to(flat) < distance: distance = p.distance_squared_to(flat); nearest = p
			nearest.x += -9.0 if flat.x<nearest.x else 9.0
			var other := nearest+Vector2(0,24)
			other = other.clamp(bounds.position,bounds.end)
			anchors.append([Vector3(nearest.x,0,nearest.y),center,Vector3(other.x,0,other.y),Vector3(nearest.x,0,nearest.y)])
	for group in 2:
		var points := PackedVector3Array()
		for i in anchors[group].size()-1:
			var start: Vector3 = anchors[group][i]
			var end: Vector3 = anchors[group][i+1]
			var sg := ground_at(start,70.0)
			var eg := ground_at(end,70.0)
			if not sg.is_empty(): start = sg["position"]
			if not eg.is_empty(): end = eg["position"]
			var path := navigation.get_point_path(navigation.get_closest_point(start),navigation.get_closest_point(end))
			for point in path:
				if points.is_empty() or point.distance_to(points[points.size()-1]) > .1:
					points.append(point)
		if points.size() < 3:
			var village: Vector3 = main.player.spawn_point
			var start := navigation.get_closest_point(village)
			var finish := navigation.get_closest_point(village+Vector3(0,0,20))
			points = navigation.get_point_path(start,finish)
			if points.size() < 2: points = PackedVector3Array([village,village+Vector3(0,0,2)])
			points.append_array(points.duplicate().slice(0,points.size()-1))
		var curve := Curve3D.new()
		curve.up_vector_enabled = false
		for point in points:
			curve.add_point(point)
		var trail := []
		for i in 60:
			trail.append(curve.sample_baked(fposmod(-float(i)*.35,curve.get_baked_length())))
		packs[group] = {"points":points,"waypoint":1,"trail":trail,"members":[],"leader":null}
	for group in 3:
		var curve := Curve3D.new()
		curve.up_vector_enabled = false
		var positions := [Vector3(-24,27,12),Vector3(30,27,6),Vector3(57,32,-56),Vector3(32,36,-119),Vector3(-33,33,-85),Vector3(-24,27,12)]
		if main.world_data.get("procedural",false):
			positions.clear()
			var radius := bounds.size.x*.36
			for i in 9:
				var angle := float(i%8)*TAU/8
				var center: Vector2 = bounds.get_center() if main.world_data.get("streamed",false) else Vector2.ZERO
				var altitude: float = main.player.position.y+22 if main.world_data.get("streamed",false) else 44
				positions.append(Vector3(center.x+cos(angle)*radius,altitude+group*3,center.y+sin(angle)*radius))
		for i in positions.size():
			var prev: Vector3 = positions[posmod(i-1,positions.size()-1)]
			var next: Vector3 = positions[(i+1)%(positions.size()-1)]
			var tangent := (next-prev)*.16
			curve.add_point(positions[i]+Vector3.UP*float(group*2),-tangent,tangent)
		flocks[group] = {"curve":curve,"offset":float(group)*curve.get_baked_length()/3.0}
