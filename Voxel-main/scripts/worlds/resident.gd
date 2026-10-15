extends "res://scripts/npc.gd"
var life: Node
var village := {}
var resident_id := ""
var role := "farmer"
var task := "idle"
var goal := Vector3.ZERO
var remote_position := Vector3.ZERO
var remote_yaw := 0.0
var route: Array[Vector2] = []
var route_phase := -1
var grain: MultiMeshInstance3D
var grain_material: StandardMaterial3D

func configure(owner_life: Node, descriptor: Dictionary, id: String, occupation: String) -> void:
	life = owner_life; village = descriptor; resident_id = id; role = occupation
	display_name = {"farmer":"Bäuerin Hanna","walker":"Dorfältester Emil","merchant":"Händlerin Frieda","guard":"Dorfwache Theo"}[role]
	model_scene = load("res://generated/char_%s.scn" % {"farmer":"farmer","walker":"elder","merchant":"merchant","guard":"guard"}[role])
	lines = PackedStringArray(["Willkommen in "+str(village.name)+"!","Unsere Höfe versorgen das Dorf. Die Hühner bleiben hinter dem Zaun.","Öffne Türen und Tore mit E. Die Wege führen zu den nächsten Orten."])
	position = Vector3(village.p.x,float(village.h),village.p.y)+Vector3(0,0,int(role.hash()%8)-4)
	player = life.main.player

func _ready() -> void:
	super._ready()
	remote_position = position
	goal = position
	grain = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE*.08
	grain_material = StandardMaterial3D.new()
	grain_material.albedo_color = Color("e5b959")
	cube.material = grain_material
	mm.mesh = cube; mm.instance_count = 16
	grain.multimesh = mm
	grain.visible = false
	grain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	life.add_child(grain)

func _process(delta: float) -> void:
	var speed := 0.0
	if not Worlds.remote and (not Net.active() or Net.is_host()):
		var phase := int(fposmod(life.clock+float(abs(resident_id.hash())%17),160)/40)
		if phase!=route_phase:
			route_phase = phase
			_choose_route(phase)
		if not route.is_empty():
			var destination: Vector2 = route[0]
			var flat := Vector2(global_position.x,global_position.z)
			var difference := destination-flat
			if difference.length()<.15: route.pop_front()
			else:
				flat += difference.normalized()*minf(difference.length(),1.35*delta)
				global_position = Vector3(flat.x,float(village.h)+.15,flat.y)
				_yaw = lerp_angle(_yaw,atan2(-difference.x,-difference.y),minf(delta*7,1))
				speed = 1.35/7.4
			task = "walking"
		else:
			task = "feeding" if role=="farmer" and phase==2 else "tending" if role=="farmer" and phase==1 else "idle"
	else:
		speed = minf(1,global_position.distance_to(remote_position)*.5)
		global_position = global_position.lerp(remote_position,minf(1,delta*9))
		_yaw = lerp_angle(_yaw,remote_yaw,minf(1,delta*9))
	model.rotation.y = _yaw
	anim.update_pose(delta,speed,true,0,false)
	if task in ["feeding","tending"]: anim.talk(.3)
	if task=="feeding":
		life.feeding[village.id] = life.clock+.6
		grain.visible = true
		var pen: Rect2 = village.pen
		var target := Vector3(pen.get_center().x,float(village.h)+.45,pen.position.y+2)
		for i in 16:
			var t := fposmod(life.clock*1.1+i*.071,1)
			var point := (global_position+Vector3(0,1.4,0)).lerp(target,t)+Vector3(sin(i*13.0)*t*.7,sin(t*PI)*.7,cos(i*7.0)*t*.3)
			grain.multimesh.set_instance_transform(i,Transform3D(Basis(),point))
	else: grain.visible = false
	if _bubble_t>0:
		_bubble_t -= delta
		if _bubble_t<=0: bubble.visible = false

func _choose_route(phase: int) -> void:
	route.clear()
	var p: Vector2 = village.p
	var flat := Vector2(global_position.x,global_position.z)
	if role=="farmer":
		var field: Rect2 = village.field
		var pen: Rect2 = village.pen
		if phase==1:
			route.assign([Vector2(p.x,flat.y),p+Vector2(0,-18),Vector2(field.get_center().x,p.y-18),Vector2(field.get_center().x,field.position.y-1)])
		elif phase==2:
			route.assign([Vector2(p.x+13,flat.y),Vector2(p.x+13,pen.position.y-1),Vector2(pen.get_center().x,pen.position.y-1)])
		elif phase==0: route.assign([Vector2(p.x,flat.y),p+Vector2(0,-4)])
		else: route.assign([Vector2(p.x+13,flat.y),Vector2(p.x+13,p.y+17),p+Vector2(0,17),p+Vector2(0,5)])
	else:
		var offset: float = float(abs(resident_id.hash())%7)-3
		route.assign([Vector2(p.x+offset,flat.y),p+Vector2(offset,-15 if phase%2==0 else 15)])

func snapshot() -> Dictionary:
	return {"id":resident_id,"p":global_position,"y":_yaw,"task":task,"phase":route_phase}

func restore(state: Dictionary) -> void:
	remote_position = state.get("p",position)
	remote_yaw = float(state.get("y",0))
	task = str(state.get("task","idle"))
	if not Worlds.remote and (not Net.active() or Net.is_host()): global_position = remote_position

func _exit_tree() -> void:
	if is_instance_valid(grain): grain.queue_free()
