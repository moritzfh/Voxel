extends Node3D
## Deterministic encounter placement, transient projectiles and host-owned attack resolution.
const TYPES := preload("res://scripts/enemies/enemy_types.gd")
var main: Node
var chunks := {}
var projectiles: Array = []
var sequence := 0

func setup(game: Node) -> void:
	main = game
	if not main.world_data.get("streamed",false): spawn_test_encounters()

func standard_plan(key: Vector2i) -> Dictionary:
	var land: RefCounted = main.generator.land
	var cell := Vector2i(floori(key.x/4.0),floori(key.y/4.0))
	var value: int = land.coordinate_seed(cell,485173)
	var chosen := cell*4+Vector2i(value%4,(value/4)%4)
	if key!=chosen or value%5==0: return {}
	var point := Vector2(key)*16+Vector2(8,8)
	var location := Vector3(point.x,land.height(point)+.2,point.y)
	if not main.wildlife.village_clear(location,9) or land.river_distance(point)<13 or land.water_level(point)>-50: return {}
	for dungeon in land.region(land.region_of(point)).get("dungeons",[]):
		if point.distance_to(dungeon.p)<float(dungeon.radius)+12: return {}
	var level := TYPES.level_at(location,main.player.spawn_point)
	return {"id":40000000000000+value*16,"species":TYPES.STANDARD[(value/16)%3],"point":location,"count":TYPES.group_size(level),"level":level}

func dungeon_plans(key: Vector2i) -> Array:
	var land: RefCounted = main.generator.land
	var rect := Rect2(Vector2(key)*16,Vector2.ONE*16)
	var region: Dictionary = land.region(land.region_of(rect.get_center()))
	var plans := []
	for dungeon in region.get("dungeons",[]):
		if not rect.has_point(dungeon.p): continue
		var point := Vector3(dungeon.p.x,float(dungeon.h)+.3,dungeon.p.y)
		if not main.wildlife.village_clear(point,float(dungeon.radius)): continue
		plans.append({"id":60000000000000+int(str(dungeon.id).hash()&0x7fffffff)*16,"species":dungeon.species,"point":point,"count":1,"dungeon":dungeon.id})
	# Previous world descriptions keep their original terrain. Existing remote ruins get one guardian.
	if int(Worlds.config.get("encounter_version",0))==0:
		for ruin in region.ruins:
			var p: Vector2 = ruin.p+Vector2(12,0)
			if not rect.has_point(p): continue
			var point := Vector3(p.x,land.height(p)+.3,p.y)
			if not main.wildlife.village_clear(point,10): continue
			var value: int = str(ruin.id).hash()&0x7fffffff
			plans.append({"id":60000000000000+value*16,"species":TYPES.BOSSES[value%3],"point":point,"count":1,"dungeon":ruin.id})
	return plans

func load_chunk(key: Vector2i, deferred := false) -> void:
	if chunks.has(key): return
	chunks[key] = []
	var standard := standard_plan(key)
	if not standard.is_empty(): spawn_plan(standard,key,deferred)
	for plan in dungeon_plans(key): spawn_plan(plan,key,deferred)

func spawn_plan(plan: Dictionary, key: Vector2i, deferred := false) -> void:
	for i in int(plan.count):
		var point: Vector3 = plan.point
		if int(plan.count)>1:
			point += Vector3((i%3-1)*1.8,0,(i/3)*1.8)
		if main.world_data.get("streamed",false): point.y = main.generator.land.height(Vector2(point.x,point.z))+.2
		if not main.wildlife.village_clear(point,2): continue
		var id := int(plan.id)+i
		var spec := {"species":plan.species,"encounter":int(plan.id),"dungeon":plan.get("dungeon","")}
		if deferred:
			main.generator.life.queue_spawn(key,id,spec,point,true)
		else: main.wildlife.spawn_external(id,spec,point)
		if not chunks[key].has(id): chunks[key].append(id)

func unload_chunk(key: Vector2i) -> void:
	if not chunks.has(key): return
	for id in chunks[key]: main.wildlife.remove_external(id)
	chunks.erase(key)

func spawn_test_encounters() -> void:
	var spots := [Vector3(-65,0,-92),Vector3(56,0,-80),Vector3(72,0,-125),Vector3(-65,0,-125),Vector3(52,0,-121),Vector3(65,0,24)]
	for i in 6:
		var point: Vector3 = spots[i]
		if main.world_data.get("procedural",false):
			var b: Rect2 = main.player.world_bounds
			point = Vector3(b.get_center().x+cos(i*TAU/6)*b.size.x*.35,0,b.get_center().y+sin(i*TAU/6)*b.size.y*.35)
		var ground: Dictionary = main.wildlife.ground_at(point,80)
		if ground.is_empty(): continue
		point = main.wildlife.safe_wild_home(ground.position+.1*Vector3.UP,913+i)
		var species: String = (TYPES.STANDARD+TYPES.BOSSES)[i]
		var id := 10000000000000+i*16
		var key := Vector2i(i,-999)
		chunks[key] = []
		spawn_plan({"id":id,"species":species,"point":point,"count":1 if i>=3 else TYPES.group_size(TYPES.level_at(point,main.player.spawn_point)),"dungeon":"test_arena_"+str(i) if i>=3 else ""},key)

func players() -> Array:
	var result := [{"id":Net.my_id(),"point":main.player.global_position}]
	for id in main.remotes:
		if main.remotes[id].visible: result.append({"id":id,"point":main.remotes[id].global_position})
	return result

func cue(enemy: Node, kind: String, point: Vector3, duration: float) -> void:
	enemy._visual_attack = duration+.3
	enemy._visual_total = duration+.3
	enemy._visual_windup = duration
	enemy._visual_kind = kind
	var marker: Vector3 = point if kind=="eruption" else enemy.global_position
	var radius := 3.0 if kind=="eruption" else 4.3 if kind=="smash" else 1.7
	main.combat.fx.wave(marker,radius,Color(1,.3,.15,.8))
	Net.send_op({"op":"enemy_cue","id":enemy.animal_id,"kind":kind,"point":marker,"duration":duration,"radius":radius})

func strike(enemy: Node, point: Vector3, radius: float, damage: float, kind: String, victim_id: int) -> void:
	if not main.wildlife.authority() or enemy.hp<=0: return
	main.combat.fx.wave(point,radius,Color("ddaf6b") if kind=="eruption" else Color("e28861"))
	Net.send_op({"op":"enemy_impact","point":point,"radius":radius,"kind":kind})
	if kind=="melee" and victim_id==0:
		var rival: Node = main.wildlife.by_id.get(enemy.aggro_animal)
		if rival and rival.hp>0: main.wildlife.attack_animal(enemy,rival,damage)
		return
	for player in players():
		if kind=="melee" and int(player.id)!=victim_id: continue
		if not main.wildlife.village_clear(player.point): continue
		if Vector2(player.point.x-point.x,player.point.z-point.z).length()>radius+.32 or absf(player.point.y-point.y)>3: continue
		if not main.wildlife.can_see(enemy,player.point): continue
		main.wildlife.damage_player(int(player.id),damage,enemy.animal_id)
	Sfx.play("crash" if enemy.is_boss else "hit",point,-14)

func shoot(enemy: Node, origin: Vector3, direction: Vector3, damage: float, fire: bool) -> void:
	sequence += 1
	var op := {"op":"enemy_projectile","shot":sequence,"owner":enemy.animal_id,"origin":origin,"direction":direction,"damage":damage,"fire":fire}
	spawn_projectile(op)
	Net.send_op(op)

func spawn_projectile(op: Dictionary) -> void:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = .25 if op.fire else .16
	mesh.height = mesh.radius*2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ed9549") if op.fire else Color("b787e7")
	mat.emission_enabled = true; mat.emission = mat.albedo_color; mat.emission_energy_multiplier = 2
	mesh.material = mat; node.mesh = mesh
	add_child(node); node.global_position = op.origin
	projectiles.append({"node":node,"id":int(op.shot),"owner":int(op.owner),"v":Vector3(op.direction)*11,"damage":float(op.damage),"fire":bool(op.fire),"life":3.0})

func _physics_process(dt: float) -> void:
	if not main or not main.wildlife: return
	for i in range(projectiles.size()-1,-1,-1):
		var shot: Dictionary = projectiles[i]
		shot.life -= dt
		var from: Vector3 = shot.node.global_position
		var to: Vector3 = from+shot.v*dt
		var query := PhysicsRayQueryParameters3D.create(from,to,1)
		query.exclude = [main.player.get_rid()]
		var wall := get_world_3d().direct_space_state.intersect_ray(query)
		if not wall.is_empty(): to = wall.position
		var hit := false
		if main.wildlife.authority():
			for player in players():
				if not main.wildlife.village_clear(player.point): continue
				var center: Vector3 = player.point+Vector3.UP*.9
				if center.distance_to(Geometry3D.get_closest_point_to_segment(center,from,to))<(.65 if shot.fire else .5):
					main.wildlife.damage_player(int(player.id),float(shot.damage),int(shot.owner)); hit = true; break
		shot.node.global_position = to
		if hit or not wall.is_empty() or shot.life<=0:
			if main.wildlife.authority(): Net.send_op({"op":"enemy_projectile_end","shot":shot.id,"point":to,"fire":shot.fire})
			main.combat.fx.wave(to,.9,Color("eda05d") if shot.fire else Color("b18cda"))
			shot.node.queue_free(); projectiles.remove_at(i)

func handle_op(from_id: int, op: Dictionary) -> void:
	if from_id!=1 or main.wildlife.authority(): return
	match str(op.get("op","")):
		"enemy_cue":
			var enemy: Node = main.wildlife.by_id.get(int(op.id))
			if enemy and enemy.has_meta("enemy"):
				enemy._visual_attack = float(op.duration)+.3
				enemy._visual_total = enemy._visual_attack
				enemy._visual_windup = float(op.duration)
				enemy._visual_kind = str(op.kind)
				enemy.call_sound(true)
			main.combat.fx.wave(op.point,float(op.radius),Color(1,.3,.15,.8))
		"enemy_impact": main.combat.fx.wave(op.point,float(op.radius),Color("e2a76c"))
		"enemy_projectile": spawn_projectile(op)
		"enemy_projectile_end":
			for i in range(projectiles.size()-1,-1,-1):
				if int(projectiles[i].id)==int(op.shot): projectiles[i].node.queue_free(); projectiles.remove_at(i)
