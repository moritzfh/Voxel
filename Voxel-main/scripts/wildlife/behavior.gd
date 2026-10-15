extends RefCounted
## Decisions are separate from movement: families, patrols, hunting and retaliation share one locomotion system.

static func plan(point: Vector3, speed: float, state: String, victim: Node = null, player_id := 0) -> Dictionary:
	return {"goal":point,"speed":speed,"state":state,"victim":victim,"player":player_id}

static func decide(manager: Node, animal: Node) -> Dictionary:
	if animal.pen_rect.has_area():
		var pen: Rect2 = animal.pen_rect
		var life: Node = manager.main.generator.life if manager.main.world_data.get("streamed",false) else null
		if life and float(life.feeding.get(animal.pen_id,-1))>life.clock:
			var goal := Vector3(pen.get_center().x+sin(animal.animal_id)*.7,animal.home.y,pen.position.y+2)
			return plan(goal,0.0 if animal.global_position.distance_to(goal)<.7 else 1.8,"feeding")
		if animal._flee>0:
			var threat: Dictionary = manager.nearest_player(animal.global_position)
			var away: Vector3 = animal.global_position-threat.position
			var point := Vector2(animal.global_position.x+away.x,animal.global_position.z+away.z).clamp(pen.position+Vector2.ONE*.7,pen.end-Vector2.ONE*.7)
			return plan(Vector3(point.x,animal.home.y,point.y),2.2,"flee")
		var result := roam(animal)
		var goal: Vector3 = result.goal
		var point := Vector2(goal.x,goal.z).clamp(pen.position+Vector2.ONE*.8,pen.end-Vector2.ONE*.8)
		result.goal = Vector3(point.x,animal.home.y,point.y)
		return result
	if animal.feeding_time > 0.0:
		return plan(animal.meal_point,0.0,"feeding")
	if animal.species == "bird" and animal.flock_id >= 0 and animal._flee <= 0.0:
		return plan(manager.flock_target(animal.flock_id,animal.group_slot),5.6*animal.growth_speed(),"flock")
	var nearby: Dictionary = manager.nearest_player(animal.global_position)
	var player: Vector3 = nearby["position"]
	var distance: float = nearby["distance"]
	if animal.species == "bee" and animal.anger_time > 0.0 and animal.aggro_player != 0:
		var attacker: Variant = manager.player_position(animal.aggro_player)
		if attacker is Vector3 and animal.global_position.distance_to(attacker) < 24.0:
			return plan(attacker+Vector3.UP*1.3,3.4,"chase",null,animal.aggro_player)
	if animal.young:
		if animal._flee > 0.0:
			return flee(manager,animal,player)
		if animal.species == "wolf" and animal.pack_id >= 0:
			return plan(manager.patrol_target(animal),2.4,"patrol")
		var parent: Node = manager.by_id.get(animal.parent_id)
		if parent != null and parent.hp > 0.0:
			var behind: Vector3 = parent.global_position+parent.global_transform.basis.z*.9+parent.global_transform.basis.x*(.6 if animal.animal_id%2 == 0 else -.6)
			if animal.flying(): behind.y = parent.global_position.y-.1
			if animal.global_position.distance_to(behind) > 1.4:
				return plan(behind,1.9 if animal.species != "turtle" else .42,"follow")
			return plan(animal.global_position,0.0,"idle")
	if animal.species == "bear":
		return bear(manager,animal,nearby)
	if animal.species == "wolf":
		return wolf(manager,animal,nearby)
	if animal._flee > 0.0 or (animal.species in ["rabbit","chicken"] and distance < (5.5 if animal.species == "rabbit" else 2.8)):
		return flee(manager,animal,player)
	if animal.species == "turtle" and distance < 2.2:
		return plan(animal.global_position,0.0,"hide")
	return roam(animal)

static func roam(animal: Node) -> Dictionary:
	if animal._decision <= 0.0 or animal.state not in ["idle","roam"]:
		animal._decision = animal.rng.randf_range(3.0,7.0)
		animal._wander_state = "roam" if animal.rng.randf() > .25 or animal.flying() else "idle"
		if animal._wander_state == "roam": animal._choose_target()
	return plan(animal.target,animal.SPEED[animal.species] if animal._wander_state == "roam" else 0.0,animal._wander_state)

static func flee(manager: Node, animal: Node, fallback: Vector3) -> Dictionary:
	var threat := fallback
	var attacker: Node = manager.by_id.get(animal.aggro_animal)
	if attacker != null and attacker.hp > 0.0: threat = attacker.global_position
	var away: Vector3 = animal.global_position-threat
	away.y = 0
	if away.length_squared() < .01: away = Vector3.RIGHT
	var target: Vector3 = animal.global_position+away.normalized()*5.0
	if animal.flying(): target.y = animal.global_position.y+1.7
	return plan(target,float(animal.SPEED[animal.species])*3.5,"flee")

static func retaliation(manager: Node, animal: Node, speed: float) -> Dictionary:
	if animal.anger_time <= 0.0: return {}
	var target: Variant = manager.player_position(animal.aggro_player)
	if animal.aggro_player != 0 and target is Vector3 and animal.global_position.distance_to(target) < 27.0 and manager.can_see(animal,target):
		return plan(target,speed,"chase",null,animal.aggro_player)
	var rival: Node = manager.by_id.get(animal.aggro_animal)
	if rival != null and rival.hp > 0.0 and rival.global_position.distance_to(animal.global_position) < 20.0:
		return plan(rival.global_position,speed,"hunt",rival)
	return {}

static func bear(manager: Node, animal: Node, nearby: Dictionary) -> Dictionary:
	var angry := retaliation(manager,animal,4.1)
	if not angry.is_empty(): return angry
	var protective: bool = manager.has_cub(animal)
	var player: Vector3 = nearby["position"]
	var detection := 10.0 if protective else 3.3
	if Worlds.damage_multiplier() == 0.0: detection = 0.0
	if float(nearby["distance"]) < detection and manager.can_see(animal,player):
		return plan(player,4.1,"guard" if protective else "chase",null,nearby["id"])
	if protective:
		var closest: Node = null
		var distance := 11.0
		for threat in manager.living_near(animal.global_position,11.0):
			if threat == animal or threat.parent_id == animal.animal_id or threat.animal_id == animal.parent_id:
				continue
			var d: float = threat.global_position.distance_to(animal.global_position)
			if d < distance and manager.can_see(animal,threat.global_position):
				distance = d
				closest = threat
		if closest != null: return plan(closest.global_position,4.1,"guard",closest)
	return roam(animal)

static func wolf(manager: Node, animal: Node, nearby: Dictionary) -> Dictionary:
	var angry := retaliation(manager,animal,4.9)
	if not angry.is_empty(): return angry
	var player: Vector3 = nearby["position"]
	if Worlds.damage_multiplier() > 0.0 and float(nearby["distance"]) < 12.0 and manager.can_see(animal,player):
		return plan(player,4.9,"chase",null,nearby["id"])
	var pack_size: int = manager.pack_strength(animal)
	if pack_size >= 3:
		for rival in manager.living_near(animal.global_position,12.0,"bear"):
			if not rival.young and manager.can_see(animal,rival.global_position):
				return plan(rival.global_position,4.9,"hunt",rival)
	var prey: Node = null
	var distance := 18.0
	for rabbit in manager.living_near(animal.global_position,18.0,"rabbit"):
		var d: float = rabbit.global_position.distance_to(animal.global_position)
		if d < distance and manager.can_see(animal,rabbit.global_position):
			distance = d
			prey = rabbit
	if prey != null: return plan(prey.global_position,4.9,"hunt",prey)
	if animal.pack_id >= 0:
		return plan(manager.patrol_target(animal),1.8,"patrol")
	return roam(animal)
