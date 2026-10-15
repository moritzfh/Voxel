extends Node
## Predict local poses; the host owns timing, melee geometry, damage and mana spending.
const SKILLS := preload("res://scripts/game/warrior_skills.gd")
var main: Node
var player: CharacterBody3D
var fx: Node3D
var sword_equipped := true
var combo := 0
var combo_until := 0.0
var busy := 0.0
var cooldowns := {}
var queued := 0.0
var kind := ""
var action_time := 0.0
var action_duration := 0.0
var direction := Vector3.FORWARD
var guard_time := 0.0
var rage_time := 0.0
var server_peers := {}
var jobs: Array = []

func setup(game: Node) -> void:
	main = game
	player = main.player
	player.combat = self
	fx = Node3D.new()
	fx.name = "CombatPixels"
	fx.set_script(load("res://scripts/game/combat_fx.gd"))
	main.add_child(fx)
	main.tools._show_tool("sword")
	if player.model.has_node("sword"): player.model.get_node("sword").hide()
	player.defeated.connect(func(_source: String):
		busy = 0
		queued = 0
		player.anim.combat_duration = 0
		jobs = jobs.filter(func(job: Dictionary): return int(job.peer)!=Net.my_id()))

func _unhandled_input(event: InputEvent) -> void:
	if player.input_blocked or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED or (main.builder and main.builder.active): return
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("equip_sword"):
		toggle_sword()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dodge"):
		request("dodge")
	else:
		for id in SKILLS.ABILITIES:
			if event.is_action_pressed(SKILLS.ABILITIES[id].action): request(id); get_viewport().set_input_as_handled(); break

func toggle_sword() -> bool:
	if busy>0: return false
	sword_equipped = not sword_equipped
	main.tools._show_tool("sword" if sword_equipped else "")
	main.hud.show_toast("Slot 1 · Schwert gezogen" if sword_equipped else "Slot 1 · Fäuste / Werkzeuge",1.5)
	return true

func request_attack() -> void:
	if main.builder and main.builder.active: return
	if not sword_equipped and main.world_features_enabled() and main.tools.target.get("kind","") not in ["","animal"]: return
	if busy>.12: queued = .24; return
	if busy>0: queued = .24; return
	request("attack")

func request(action: String) -> bool:
	if busy>0 or player.input_blocked or player.swimming or cooldowns.get(action,0.0)>0: return false
	if action!="dodge" and action!="attack" and not sword_equipped:
		main.hud.show_toast("Ziehe zuerst dein Schwert ["+Settings.key_name("equip_sword")+"]",1.5); return false
	if not SKILLS.allowed(action,Game.level,Game.talents):
		main.hud.show_toast("Diese Fähigkeit kannst du im Kriegerbaum [T] lernen.",2); return false
	if action in ["dodge","slam","dash"] and not player.is_on_floor(): return false
	var cost := SKILLS.cost(action,Game.talents)
	if player.mana<cost: main.hud.show_toast("Nicht genug Mana",1.2); return false
	if action=="dodge" and player.stamina<25-5*Game.rank("dodge"): return false
	player.mana -= cost
	if action=="dodge": player.stamina -= 25-5*Game.rank("dodge")
	var now := Time.get_ticks_msec()/1000.0
	if action=="attack": combo = (combo%3)+1 if now<combo_until else 1; combo_until = now+1.3
	var duration := (.44 if combo<3 else .68) if action=="attack" else .52 if action=="dodge" else float(SKILLS.ABILITIES[action].duration)
	if action=="spin": duration += .3*Game.rank("whirlwind")
	busy = duration
	action_time = 0
	action_duration = duration
	kind = action
	var yaw: float = main.cam_rig.yaw
	if action=="dodge":
		var input := Input.get_vector("move_left","move_right","move_forward","move_back")
		if input.length()>.1: yaw = atan2(-input.x,-input.y)+main.cam_rig.yaw
	direction = Vector3.FORWARD.rotated(Vector3.UP,yaw)
	player._facing = yaw
	if action=="slam": player.velocity.y = 7.2
	if action=="guard": guard_time = 3.0
	if action=="heal": player.hp = minf(player.hp_max,player.hp+35)
	if action=="berserk": rage_time = 6
	if action=="dodge": player.hurt_cooldown = maxf(player.hurt_cooldown,.4)
	var cd := float(SKILLS.ABILITIES.get(action,{}).get("cd",0))*(1-.1*Game.rank("recovery"))
	if action=="dodge": cd = 1.2-.2*Game.rank("dodge")
	cooldowns[action] = cd
	player.anim.combat_pose(action,combo,duration)
	player.anim.sword_held = sword_equipped
	player.attack_count += 1
	player.item_used.emit(0 if action=="attack" else 2)
	player.stats_changed.emit()
	main.cam_rig.swing()
	Sfx.play("whoosh",player.global_position,-9 if action in ["spin","slam"] else -16)
	var op := {"op":"combat_request","kind":action,"yaw":yaw,"sword":sword_equipped,"level":Game.level,"ranks":Game.talents.duplicate()}
	if main.wildlife.authority(): _accept(Net.my_id(),op)
	else: Net.send_op_to(1,op)
	return true

func motion() -> void:
	if busy<=0: return
	if kind in ["dodge","dash","slam"]:
		var speed := 10.5 if kind=="dodge" else 14.0 if kind=="dash" else 7.0
		if kind=="slam" and action_time>.52: speed = 1.0; player.velocity.y = minf(player.velocity.y,-8.0)
		player.velocity.x = direction.x*speed
		player.velocity.z = direction.z*speed
		player._facing = atan2(-direction.x,-direction.z)
	elif kind=="attack" or kind in ["cleave","execution"]:
		player.velocity.x *= .75
		player.velocity.z *= .75

func _physics_process(dt: float) -> void:
	if not main or not main.wildlife: return
	busy = maxf(0,busy-dt)
	action_time += dt
	guard_time = maxf(0,guard_time-dt)
	rage_time = maxf(0,rage_time-dt)
	queued = maxf(0,queued-dt)
	player.mana_max = 50+10*Game.rank("capacity")
	for id in cooldowns: cooldowns[id] = maxf(0,cooldowns[id]-dt)
	if busy<=0 and queued>0: queued = 0; request_attack()
	if busy<=0 and not player.input_blocked and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("attack"): request_attack()
	if not main.wildlife.authority(): return
	for id in server_peers:
		var peer: Dictionary = server_peers[id]
		peer.mana = minf(50+10*int(peer.ranks.get("capacity",0)),peer.mana+dt)
		peer.rage = maxf(0,peer.rage-dt)
	for i in range(jobs.size()-1,-1,-1):
		jobs[i].time -= dt
		if jobs[i].time<=0:
			var job: Dictionary = jobs[i]
			jobs.remove_at(i)
			_impact(job)

func handle_op(from_id: int, op: Dictionary) -> void:
	match str(op.get("op","")):
		"combat_request":
			if main.wildlife.authority() and main.remotes.has(from_id): _accept(from_id,op)
		"combat_pose":
			if from_id==1 and main.remotes.has(int(op.get("peer",0))):
				main.remotes[int(op.peer)].play_combat(str(op.kind),int(op.stage),float(op.duration))
		"combat_effect":
			if from_id!=1 or main.wildlife.authority(): return
			if op.get("wave",false): fx.wave(op.point,float(op.radius),Color("b7ebed") if op.get("crit",false) else Color("91cde3"),float(op.get("arc",TAU)),float(op.get("yaw",0)))
			for hit in op.get("hits",[]):
				if main.wildlife.by_id.has(int(hit[0])):
					var animal: Node3D = main.wildlife.by_id[int(hit[0])]
					animal.visual_hit(float(hit[1]),bool(hit[2]))
					if hit.size()>3: animal.restore({"hp":hit[3],"p":hit[4],"y":animal.rotation.y,"level":animal.level})
		"combat_mana":
			if from_id==1 and not main.wildlife.authority(): player.mana = clampf(float(op.mana),0,player.mana_max); player.stats_changed.emit()
		"combat_potion":
			if main.wildlife.authority() and main.remotes.has(from_id) and not server_peers.has(from_id):
				var profile: Dictionary = main.guest_progress.get(str(Net.players.get(from_id,{}).get("name","")),{})
				var saved_game: Dictionary = profile.get("game",{})
				var ranks := SKILLS.clean_ranks(int(saved_game.get("level",1)),saved_game.get("talents",{}))
				server_peers[from_id] = {"mana":float(profile.get("mana",50)),"potions":int(profile.get("potions",3)),"ranks":ranks,"next":0.0,"cd":{},"combo":0,"until":0.0,"rage":0.0}
			if main.wildlife.authority() and server_peers.has(from_id) and int(server_peers[from_id].potions)>0:
				server_peers[from_id].potions -= 1
				server_peers[from_id].mana = 50+10*int(server_peers[from_id].ranks.get("capacity",0))
				_mana(from_id)
		"combat_heal":
			if from_id==1 and not main.wildlife.authority(): player.hp = minf(player.hp_max,player.hp+clampf(float(op.get("amount",0)),0,12))

func potion_used() -> void:
	if main.wildlife.authority():
		if server_peers.has(Net.my_id()): server_peers[Net.my_id()].mana = player.mana
	else: Net.send_op_to(1,{"op":"combat_potion"})

func _accept(id: int, op: Dictionary) -> bool:
	var action := str(op.get("kind",""))
	if action not in ["attack","dodge"] and not SKILLS.ABILITIES.has(action): return false
	var yaw := float(op.get("yaw",0))
	if not is_finite(yaw): return false
	var level := clampi(int(op.get("level",1)),1,100)
	var ranks := SKILLS.clean_ranks(level,op.get("ranks",{}))
	if not SKILLS.allowed(action,level,ranks): return false
	if not server_peers.has(id):
		var profile: Dictionary = main.guest_progress.get(str(Net.players.get(id,{}).get("name","")),{})
		server_peers[id] = {"mana":player.mana if id==Net.my_id() else float(profile.get("mana",50)),"potions":player.potions if id==Net.my_id() else int(profile.get("potions",3)),"ranks":ranks,"next":0.0,"cd":{},"combo":0,"until":0.0,"rage":0.0}
	var peer: Dictionary = server_peers[id]
	peer.ranks = ranks
	var now := Time.get_ticks_msec()/1000.0
	if now+.05<float(peer.next) or now<float(peer.cd.get(action,0)): return false
	var sword := bool(op.get("sword",true))
	if action not in ["attack","dodge"] and not sword: return false
	var cost := SKILLS.cost(action,ranks)
	if id==Net.my_id(): peer.mana = player.mana+cost
	if peer.mana+.1<cost: _mana(id); return false
	peer.mana = maxf(0,peer.mana-cost)
	var stage := 0
	if action=="attack": stage = int(peer.combo)%3+1 if now<float(peer.until) else 1; peer.combo = stage; peer.until = now+1.3
	var duration := (.44 if stage<3 else .68) if action=="attack" else .52 if action=="dodge" else float(SKILLS.ABILITIES[action].duration)
	if action=="spin": duration += .3*int(ranks.get("whirlwind",0))
	peer.next = now+duration
	peer.cd[action] = now+float(SKILLS.ABILITIES.get(action,{}).get("cd",0))*(1-.1*int(ranks.get("recovery",0)))
	if action=="dodge": peer.cd[action] = now+1.2-.2*int(ranks.get("dodge",0))
	if action=="berserk": peer.rage = 6
	Net.send_op({"op":"combat_pose","peer":id,"kind":action,"stage":stage,"duration":duration})
	if id!=Net.my_id() and main.remotes.has(id): main.remotes[id].play_combat(action,stage,duration)
	if id!=Net.my_id(): _mana(id)
	if action in ["dodge","guard","heal","berserk"]: return true
	var impact := (.2 if stage<3 else .36) if action=="attack" else float(SKILLS.ABILITIES[action].impact)
	var count := 3+int(ranks.get("whirlwind",0)) if action=="spin" else 1
	for i in count: jobs.append({"peer":id,"kind":action,"stage":stage,"sword":sword,"yaw":yaw,"ranks":ranks,"time":impact+i*.3,"rage":peer.rage>0})
	if action=="slam" and int(ranks.get("aftershock",0))>0: jobs.append({"peer":id,"kind":"aftershock","stage":0,"sword":true,"yaw":yaw,"ranks":ranks,"time":impact+.45,"rage":peer.rage>0})
	return true

func _mana(id: int) -> void:
	if not server_peers.has(id): return
	if id==Net.my_id(): player.mana = clampf(float(server_peers[id].mana),0,player.mana_max); player.stats_changed.emit()
	else: Net.send_op_to(id,{"op":"combat_mana","mana":server_peers[id].mana})

func _impact(job: Dictionary) -> void:
	var location: Variant = main.wildlife.player_position(int(job.peer))
	if not location is Vector3: return
	var ranks: Dictionary = job.ranks
	var action: String = job.kind
	if action in ["slam","aftershock"]:
		Sfx.play("crash",location,-15)
		if int(job.peer)==Net.my_id(): main.cam_rig.add_shake(.22)
	var area: bool = action in ["spin","slam","aftershock"] or (action=="attack" and int(job.stage)==3 and bool(job.sword))
	var radius := 3.0 if job.sword else 1.65
	var damage := 23.0 if job.sword else 8.0
	var lift := 0.0
	var knock := 2.4
	var critical: bool = action=="attack" and int(job.stage)==3 and bool(job.sword)
	if critical: damage *= 2.0; radius = 3.3
	match action:
		"spin": radius = 3.1+.6*int(ranks.get("radius",0)); damage = 14; knock = 1.7
		"slam": radius = 4.2+.6*int(ranks.get("radius",0)); damage = 38*(1+.2*int(ranks.get("quake",0))); lift = 7; knock = 3.5
		"aftershock": radius = 4.2+.6*int(ranks.get("radius",0)); damage = 19; lift = 3; knock = 2
		"cleave": damage = 45; radius = 3.8; knock = 4
		"dash": damage = 31; radius = 3.0; knock = 5
		"execution": damage = 36; radius = 2.8; knock = 3
	if job.sword: damage *= 1+.1*int(ranks.get("edge",0))
	if job.rage: damage *= 1.4
	var forward := Vector3.FORWARD.rotated(Vector3.UP,float(job.yaw))
	var hits := []
	for animal in main.wildlife.living_near(location,radius+8):
		var offset: Vector3 = animal.global_position-location
		if animal.melee_distance(location)>radius or absf(offset.y)>3: continue
		if not area and Vector3(offset.x,0,offset.z).normalized().dot(forward)<.3: continue
		if not main.wildlife.can_see(animal,location): continue
		var amount: float = damage
		var crit := critical
		if action=="execution" and animal.hp<animal.max_health()*.3: amount *= 3; crit = true
		main.wildlife.provoke(animal,int(job.peer))
		var died: bool = animal.receive_hit(amount,location,knock,lift,crit)
		hits.append([animal.animal_id,amount,crit,animal.hp,animal.global_position])
		if died:
			var xp: int = animal.experience_reward()
			var food: int = animal.food_reward()
			server_peers[job.peer].mana += 6+2*int(ranks.get("predator",0))
			if int(job.peer)==Net.my_id(): main.wildlife._reward(xp,food)
			else: Net.send_op_to(int(job.peer),{"op":"wild_reward","xp":xp,"food":food})
		if int(job.peer)==Net.my_id() and job.sword: player.hp = minf(player.hp_max,player.hp+int(ranks.get("lifesteal",0)))
	if int(job.peer)!=Net.my_id() and job.sword and not hits.is_empty() and int(ranks.get("lifesteal",0))>0:
		Net.send_op_to(int(job.peer),{"op":"combat_heal","amount":hits.size()*int(ranks.get("lifesteal",0))})
	if critical and not hits.is_empty(): server_peers[job.peer].mana += 4+2*int(ranks.get("flow",0))
	if not hits.is_empty():
		_mana(int(job.peer))
		Sfx.play("hit",location,-9)
		if int(job.peer)==Net.my_id(): main.cam_rig.add_shake(.14 if critical else .06)
	var arc := TAU if area else PI*.7
	fx.wave(location,radius,Color("f9da84") if critical else Color("9edce8"),arc,float(job.yaw))
	Net.send_op({"op":"combat_effect","point":location,"radius":radius,"crit":critical,"wave":true,"arc":arc,"yaw":job.yaw,"hits":hits})

func status_text() -> String:
	var lines := ["%s [%s] · Linke Maus: 3er-Kombo · %s: Sprint · %s: Rolle" % ["Schwert" if sword_equipped else "Fäuste",Settings.key_name("equip_sword"),Settings.key_name("sprint"),Settings.key_name("dodge")]]
	var parts := []
	for id in SKILLS.ABILITIES:
		if not SKILLS.allowed(id,Game.level,Game.talents): continue
		var ability: Dictionary = SKILLS.ABILITIES[id]
		var cd := float(cooldowns.get(id,0))
		parts.append("%s %s (%s)" % [Settings.key_name(ability.action),ability.name,"%.1fs" % cd if cd>.05 else "%d M" % roundi(SKILLS.cost(id,Game.talents))])
	for i in range(0,parts.size(),4): lines.append(" · ".join(parts.slice(i,mini(i+4,parts.size()))))
	return "\n".join(lines)
