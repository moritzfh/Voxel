extends Node
## Mining & chopping: aim with the camera centre, hold the left mouse button. The fitting tool is picked
## automatically (shovel for soil, axe for wood, pickaxe for stone). Every swing breaks an irregular chunk out of
## the 12.5 cm voxel world; crumbs fly to the player, loose overhangs fall, trees topple once the notch is deep.

const VOXEL_BODY := preload("res://scripts/voxel/voxel_body.gd")
const PROP_OBJECT := preload("res://scripts/voxel/prop_object.gd")
const LOG_PICKUP := preload("res://scripts/voxel/log_pickup.gd")
const REACH := 6.5
const TREASURE_LOOT := {"gold": 30, "kristall": 25, "eisen": 80}

var main: Node
var player: CharacterBody3D
var cam_rig: Node3D
var vworld: Node3D
var debris: Node3D
var hud: CanvasLayer
var vmat: Material
var target := {}
var enabled := true           # false while building
var props := {}               # "tree:chunk:index" -> prop object node
var gone := {}                # key -> [kind, meta] of rocks that crumbled away completely
var models := {}
var _models_file: FileAccess
var _cd := 0.0
var _swing_n := 0
var _preload_t := 0.0
var _local_carve := false
var highlight: MeshInstance3D
var tool_mesh: MeshInstance3D
var _tool_kind := ""
var _tool_tier := 0
var _tool_meshes := {}
var _treasures: Array = []
var test_tool := ""           # screenshots: tool to show while the mouse is not captured

func setup(p_main: Node) -> void:
	main = p_main
	player = main.player
	cam_rig = main.cam_rig
	vworld = main.vworld
	hud = main.hud
	vmat = vworld.vmat
	models = main.world_data.get("models_vox", {})
	_models_file = FileAccess.open("res://generated/models_vox.bin", FileAccess.READ)
	_treasures = main.world_data.get("markers", {}).get("treasures", [])
	debris = Node3D.new()
	debris.name = "Debris"
	debris.set_script(load("res://scripts/voxel/debris.gd"))
	main.add_child(debris)
	debris.target = player
	debris.palette = (vmat as ShaderMaterial).get_shader_parameter("palette")
	debris.collected.connect(func(n): Sfx.play("pickup", null, -14.0, 0.15, 0.05))
	vworld.island_detached.connect(_on_island)
	# aim highlight: a thin outlined box around the voxel under the crosshair
	highlight = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.13
	var hm := StandardMaterial3D.new()
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(1, 1, 1, 0.22)
	hm.no_depth_test = false
	bm.material = hm
	highlight.mesh = bm
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.visible = false
	main.add_child(highlight)
	# tool in the right hand
	tool_mesh = MeshInstance3D.new()
	tool_mesh.visible = false
	var arm: Node3D = player.model.get_node_or_null("arm_r")
	if arm:
		arm.add_child(tool_mesh)
		tool_mesh.position = Vector3(0.02, -0.6, -0.02)

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	_cd -= delta
	_preload_t -= delta
	if _preload_t <= 0.0 and vworld:
		_preload_t = 0.6
		vworld.preload_near(player.global_position)
	var active: bool = enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.input_blocked
	if not active:
		target = {}
		highlight.visible = false
		if not (main.builder and main.builder.active):
			hud.set_target_info("", Color.WHITE, false)
		_show_tool("hammer" if main.builder and main.builder.active else test_tool)
		if _ore_mmi:
			_ore_mmi.visible = false
		return
	target = _pick()
	if target.get("kind", "") == "voxel":
		vworld.prewarm(vworld.chunk_of(target["voxel"]))
	_update_aim()
	_ore_tick(delta)
	if not target.is_empty() and Input.is_action_pressed("attack") and _cd <= 0.0:
		_use()

func _ray() -> Array:
	var cam := get_viewport().get_camera_3d()
	var c := get_viewport().get_visible_rect().size * 0.5
	return [cam.project_ray_origin(c), cam.project_ray_normal(c)]

func _pick() -> Dictionary:
	var r := _ray()
	var from: Vector3 = r[0]
	var dir: Vector3 = r[1]
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 40.0, 1 | 2)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var p: Vector3 = hit["position"]
	if p.distance_to(player.global_position + Vector3(0, 1.0, 0)) > REACH:
		return {}
	var col: Object = hit["collider"]
	var shape_node: Node = null
	if col is CollisionObject3D:
		var owner_id: int = (col as CollisionObject3D).shape_find_owner(hit["shape"])
		shape_node = (col as CollisionObject3D).shape_owner_get_owner(owner_id)
	if col.has_meta("prop_object"):
		var po: Node = col.get_meta("prop_object")
		return {"kind": po.kind, "prop": po, "point": p, "normal": hit["normal"], "from": from}
	if shape_node and shape_node.has_meta("tree"):
		return {"kind": "tree", "meta": shape_node.get_meta("tree"), "shape": shape_node, "point": p, "normal": hit["normal"], "from": from}
	if shape_node and shape_node.has_meta("rock"):
		return {"kind": "rock", "meta": shape_node.get_meta("rock"), "shape": shape_node, "point": p, "normal": hit["normal"], "from": from}
	if col.has_meta("terrain"):
		var vr: Dictionary = vworld.voxel_ray(p - dir * 0.7, dir, 1.6)
		if vr.get("hit", false):
			return {"kind": "voxel", "voxel": vr["voxel"], "normal": vr["normal"], "value": int(vr["value"]), "point": vr["point"], "from": from}
	return {}

# ---------------------------------------------------------------- tool rules
func _tool_for_value(v: int) -> Dictionary:
	var h: int = vworld.hard[v]
	var tier: int = Game.tool_tier
	var need := 1
	if h >= 5:
		need = 3
	elif h >= 4:
		need = 2
	var power := 1.0 + 0.4 * (tier - 1)
	var schlag := 1.0 + 0.25 * Game.rank("schlag")
	var d := {"ok": tier >= need, "need": need, "max_hard": h}
	if h <= 1:
		d.merge({"tool": "schaufel", "count": int(170 * power * schlag), "jitter": 0.3, "sound": "dig", "cd": 0.38})
	elif h == 2:
		d.merge({"tool": "axt", "count": int(90 * power * schlag), "jitter": 0.55, "sound": "chop", "cd": 0.42})
	else:
		d.merge({"tool": "spitzhacke", "count": int((70 if h == 3 else 55) * power * schlag), "jitter": 1.15, "sound": "chip", "cd": 0.45})
	if h == 0:
		d["count"] = int(d["count"] * 1.4)
	if tier >= 3:
		d["cd"] = float(d["cd"]) * 0.85
	return d

func _update_aim() -> void:
	if target.is_empty():
		highlight.visible = false
		hud.set_target_info("", Color.WHITE, false)
		_show_tool("")
		return
	var k: String = target["kind"]
	if k == "voxel":
		var v: int = target["value"]
		var t := _tool_for_value(v)
		var m: int = v >> 2
		var mat: Dictionary = vworld.materials.get(m, {})
		var res: String = mat.get("res", "")
		var label := "%s" % Game.RESOURCES.get(res, {}).get("name", mat.get("name", "?"))
		if not t["ok"]:
			label += "  ·  braucht %s-Werkzeug" % Game.TIER_NAMES[t["need"]]
		hud.set_target_info(label, Color(1, 0.6, 0.5) if not t["ok"] else Color(0.95, 0.92, 0.84), true)
		highlight.visible = true
		var vox: Vector3i = target["voxel"]
		highlight.global_position = vworld.to_world(vox) + Vector3.ONE * 0.0625
		highlight.scale = Vector3.ONE * (1.0 + 0.05 * sin(Time.get_ticks_msec() / 120.0))
		_show_tool(t["tool"])
	else:
		highlight.visible = false
		hud.set_target_info("Baum fällen" if k == "tree" else "Fels abbauen", Color(0.95, 0.92, 0.84), true)
		_show_tool("axt" if k == "tree" else "spitzhacke")

# ---------------------------------------------------------------- actions
func _use() -> void:
	match target["kind"]:
		"voxel":
			_mine_voxel(target)
		"tree", "rock":
			_hit_prop(target)

func _swing_fx(t: Dictionary) -> void:
	if player.anim:
		player.anim.attack()
	# face the target
	var to: Vector3 = t["point"] - player.global_position
	player._facing = atan2(-to.x, -to.z)

func _mine_voxel(t: Dictionary) -> void:
	var v: int = t["value"]
	var tool := _tool_for_value(v)
	_swing_fx(t)
	if not tool["ok"]:
		_cd = 0.5
		Sfx.play("clink", t["point"], -4.0)
		hud.show_toast("Zu hart – %s-Werkzeug nötig (I → Herstellen)" % Game.TIER_NAMES[tool["need"]], 1.5)
		debris.spawn(t["point"], v, Vector3(t["normal"]), false, 0.6, 0.4)
		return
	_cd = tool["cd"]
	_swing_n += 1
	var count: int = tool["count"]
	if Game.rank("sprengung") > 0 and _swing_n % 5 == 0:
		count = int(count * (2.2 + 0.8 * Game.rank("sprengung")))
		cam_rig.add_shake(0.35)
	var seed := randi()
	_local_carve = true
	var r: Dictionary = vworld.carve(t["voxel"], t["normal"], count, tool["max_hard"], seed, tool["jitter"])
	_local_carve = false
	var removed: PackedInt32Array = r.get("removed", PackedInt32Array())
	if removed.is_empty():
		return
	main.net_op({"op": "carve", "at": t["voxel"], "n": t["normal"], "c": count, "h": tool["max_hard"], "s": seed, "j": tool["jitter"]})
	_book_values(removed, 3)
	debris.burst_voxels(removed, vworld, Vector3(t["normal"]), true, 26)
	Sfx.play(tool["sound"], t["point"], -2.0)
	cam_rig.add_shake(0.06)
	_check_treasure(t["point"])

## count removed voxels per resource and book them (list stride 4 or 5 with value at offset 3)
var _carry := {}   # fractional resources (crafted materials give 1 per 4 voxels)

func _book_values(list: PackedInt32Array, voff: int, stride := 4, mult := 1.0) -> Dictionary:
	var counts := {}
	var amount := {}
	for i in range(0, list.size(), stride):
		var v := list[i + voff]
		var res: String = vworld.res_of(v)
		if res == "":
			continue
		counts[res] = int(counts.get(res, 0)) + 1
		amount[res] = float(amount.get(res, 0.0)) + vworld.yield_tab[v]
	var total := 0
	for res in amount:
		var f: float = float(amount[res]) * mult
		if res in ["holz", "laub"]:
			f *= 1.0 + 0.25 * Game.rank("ertrag")
		f += float(_carry.get(res, 0.0))
		var n := floori(f)
		_carry[res] = f - n
		if n > 0:
			Game.add(res, n)
		total += n
	Game.record_mined(counts)
	Game.stats["mined"] = int(Game.stats.get("mined", 0))
	Game.add_xp(maxi(1, total / 25))
	return counts

func _check_treasure(p: Vector3) -> void:
	for i in _treasures.size():
		if i in Game.treasures_found:
			continue
		var tp: Array = _treasures[i]
		if p.distance_to(Vector3(tp[0], tp[1], tp[2])) < 1.3:
			Game.treasures_found.append(i)
			Game.add_many(TREASURE_LOOT)
			Game.add_xp(200)
			Game.notify.emit("Schatz gefunden! +30 Gold, +25 Kristall, +80 Eisen", Color(1.0, 0.85, 0.35))
			Sfx.play("treasure", null, -3.0)
			for k in 30:
				debris.spawn(Vector3(tp[0], tp[1] + 0.3, tp[2]), (54 << 2) | (k % 3), Vector3.UP, true, 1.3)
			Game._check_quests()

# ---------------------------------------------------------------- trees and rocks
func _model_data(name: String) -> PackedByteArray:
	var m: Dictionary = models[name]
	_models_file.seek(int(m["off"]))
	return _models_file.get_buffer(int(m["size"])).decompress(int(m["raw"]), FileAccess.COMPRESSION_DEFLATE)

func get_prop(kind: String, meta: Dictionary, shape_node: Node) -> Node:
	var key := "%s:%s:%d" % [kind, meta["chunk"], int(meta["index"])]
	if props.has(key) and is_instance_valid(props[key]):
		return props[key]
	var model_name: String = ("tree_" if kind == "tree" else "rock_") + str(meta["mesh"])
	if not models.has(model_name):
		return null
	var po := Node3D.new()
	po.set_script(PROP_OBJECT)
	po.name = "prop_" + key.replace(":", "_")
	main.add_child(po)
	po.setup(kind, meta, models[model_name], _model_data(model_name), vmat, vworld)
	po.set_meta("key", key)
	vworld.hide_instance(meta["chunk"], int(meta["index"]))
	if shape_node:
		(shape_node as CollisionShape3D).disabled = true
	else:
		_disable_original_collider(kind, meta)
	props[key] = po
	return po

func _disable_original_collider(kind: String, meta: Dictionary) -> void:
	var holder: Node = main.get_node("World").find_child("TreeColliders" if kind == "tree" else "Rock*", true, false)
	if holder == null:
		return
	for body in ([holder] if kind == "tree" else holder.get_parent().get_children()):
		for cs in body.get_children():
			if cs is CollisionShape3D and cs.has_meta(kind):
				var m: Dictionary = cs.get_meta(kind)
				if m["chunk"] == meta["chunk"] and int(m["index"]) == int(meta["index"]):
					cs.disabled = true
					return

func _hit_prop(t: Dictionary) -> void:
	var po: Node = t.get("prop")
	if po == null:
		po = get_prop(t["kind"], t["meta"], t.get("shape"))
	if po == null:
		return
	var kind: String = po.kind
	var tier: int = Game.tool_tier
	_swing_fx(t)
	var seed := randi()
	var power: int
	var max_hard: int
	if kind == "tree":
		power = int(24 * (1.0 + 0.3 * Game.rank("axt")) * (1.0 + 0.35 * (tier - 1)))
		max_hard = 2
		_cd = 0.45
	else:
		power = int(60 * (1.0 + 0.4 * (tier - 1)) * (1.0 + 0.25 * Game.rank("schlag")))
		max_hard = 3 + mini(2, tier - 1)
		_cd = 0.45
	main.net_op({"op": "prop", "k": kind, "key": po.get_meta("key"), "meta": po.meta, "p": t["point"], "f": t["from"], "pw": power, "h": max_hard, "s": seed})
	apply_prop_hit(po, t["point"], t["from"], power, seed, max_hard, true)

## shared by local hits and network ops
func apply_prop_hit(po: Node, point: Vector3, from: Vector3, power: int, seed: int, max_hard: int, local: bool) -> void:
	var kind: String = po.kind
	var r: Dictionary = po.hit(point, from, power, seed, max_hard)
	var removed: PackedInt32Array = r["removed"]
	if not removed.is_empty():
		var step := maxi(1, (removed.size() / 4) / 22)
		var i := 0
		while i < removed.size() / 4:
			var wp: Vector3 = po.voxel_world_pos(removed[i * 4], removed[i * 4 + 1], removed[i * 4 + 2])
			debris.spawn(wp, removed[i * 4 + 3], (from - point).normalized(), local)
			i += step
		if local:
			_book_values(removed, 3)
		Sfx.play("chop" if kind == "tree" else "chip", point, -2.0)
		if local:
			cam_rig.add_shake(0.05)
	var parts: Array = r["parts"]
	if not parts.is_empty() and kind == "tree":
		# the biggest part is the falling tree; tiny leaf clumps just drop
		parts.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
		Sfx.play("crack", po.global_position + Vector3(0, 2, 0), 2.0)
		if local:
			Game.trees_felled += 1
			Game.add_xp(30)
			Game._check_quests()
	for i in parts.size():
		_spawn_part(po, parts[i], kind, local, i == 0)
	if r.get("gone", false):
		Sfx.play("crumble", point, 0.0)
		gone[po.get_meta("key")] = [kind, po.meta]
		props.erase(po.get_meta("key"))
		po.queue_free()

func _spawn_part(po: Node, part: Dictionary, kind: String, local: bool, main_part := true) -> void:
	var obj: VoxelObject = part["object"]
	if obj.solid_count() < 6:
		return
	var body := RigidBody3D.new()
	body.set_script(VOXEL_BODY)
	main.add_child(body)
	var rot: Basis = po.global_transform.basis.orthonormalized()
	body.setup(obj, po.part_origin_world(part["origin"]), rot, po.scale_f, vmat, "tree" if kind == "tree" else "chunk")
	body.set_meta("local", local)
	body.shattered.connect(_on_body_shattered)
	if kind == "tree" and main_part:
		var away: Vector3 = po.global_position - player.global_position
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3(randf() - 0.5, 0, randf() - 0.5)
		away = away.normalized()
		var axis := Vector3.UP.cross(away).normalized()
		body.apply_torque_impulse(axis * body.mass * 1.6)
		body.apply_central_impulse(away * body.mass * 0.4)
	elif kind == "tree":
		body.kind = "chunk"

func _on_island(obj: VoxelObject, origin: Vector3i) -> void:
	if obj.solid_count() < 3:
		return
	var body := RigidBody3D.new()
	body.set_script(VOXEL_BODY)
	main.add_child(body)
	body.setup(obj, vworld.to_world(origin), Basis(), 1.0, vmat, "chunk")
	body.set_meta("local", _local_carve)
	body.shattered.connect(_on_body_shattered)
	body.angular_velocity = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	Sfx.play("crack", body.global_position, -6.0, 0.2)

func _on_body_shattered(body: Node, counts: PackedInt32Array, at: Vector3) -> void:
	var local: bool = body.get_meta("local", false)
	var near := at.distance_to(player.global_position) < 40.0
	Sfx.play("crash" if body.kind == "tree" else "crumble", at, 0.0 if body.kind == "tree" else -3.0)
	if near:
		cam_rig.add_shake(clampf(0.5 - at.distance_to(player.global_position) * 0.02, 0.05, 0.4))
	for s in body.sample_voxels(60 if body.kind == "tree" else 30):
		debris.spawn(s[0], s[1], Vector3.UP, local and body.kind != "tree", 1.2)
	if body.kind == "tree":
		# leaves burst, the trunk becomes logs to pick up
		var wood := 0
		var leaves := 0
		for v in 256:
			var c := counts[v]
			if c == 0:
				continue
			var res: String = vworld.res_of(v)
			if res == "holz":
				wood += c
			elif res == "laub":
				leaves += c
		if local:
			Game.add("laub", int(leaves * 0.012 * (1.0 + 0.25 * Game.rank("ertrag"))))
		var n_logs := clampi(wood / 350, 1, 7)
		var axis: Vector3 = body.global_transform.basis.y.normalized()
		var base: Vector3 = body.global_position - axis * float(body.obj.get_size().y) * body.vs * body.vis_scale * 0.3
		for i in n_logs:
			var lg := RigidBody3D.new()
			lg.set_script(LOG_PICKUP)
			main.add_child(lg)
			lg.setup(vworld, base + axis * (i * 1.1) + Vector3(0, 0.4, 0), axis, int(wood * (1.0 + 0.25 * Game.rank("ertrag")) / n_logs) if local else 0, player)
		return
	if local:
		# loose crown pieces count like leaves of a felled tree (a whole crown would be thousands)
		var v_list := PackedInt32Array()
		for v in 256:
			var c := counts[v]
			if c > 0 and vworld.res_of(v) == "laub":
				c = roundi(c * 0.012)
			for k in c:
				v_list.append_array([0, 0, 0, v])
		_book_values(v_list, 3)

# ---------------------------------------------------------------- tool model in the hand
func _show_tool(kind: String) -> void:
	if kind == _tool_kind and Game.tool_tier == _tool_tier:
		return
	_tool_kind = kind
	_tool_tier = Game.tool_tier
	if kind == "":
		tool_mesh.visible = false
		cam_rig.set_viewmodel(null)
		return
	var key := "%s_%d" % [kind, _tool_tier]
	if not _tool_meshes.has(key):
		_tool_meshes[key] = _build_tool(kind, _tool_tier)
	tool_mesh.mesh = _tool_meshes[key]
	tool_mesh.visible = true
	cam_rig.set_viewmodel(tool_mesh.mesh)

func _build_tool(kind: String, tier: int) -> Mesh:
	var o: VoxelObject = vworld.new_object()
	o.set_voxel_size(0.03125)
	o.create(Vector3i(11, 24, 3))
	var handle := (15 << 2) | 1                  # log
	var head_v: int = [0, (4 << 2), (57 << 2) | 2, (27 << 2), (59 << 2) | 2][tier]
	for y in range(2, 23):
		o.set_voxel(Vector3i(5, y, 1), handle)
	match kind:
		"spitzhacke":
			for x in range(0, 11):
				var dy: int = 1 if absi(x - 5) >= 4 else 0
				o.set_voxel(Vector3i(x, 1 + dy, 1), head_v)
				if absi(x - 5) < 3:
					o.set_voxel(Vector3i(x, 2, 1), head_v)
		"axt":
			for y in range(1, 9):
				for x in range(6, 10):
					if (x - 6) <= (y - 1) and (x - 6) <= (9 - y):
						o.set_voxel(Vector3i(x, y, 1), head_v)
		"schaufel":
			for y in range(0, 7):
				for x in range(3, 8):
					o.set_voxel(Vector3i(x, y, 1), head_v)
		"hammer":
			var iron := (27 << 2)
			for y in range(0, 5):
				for x in range(1, 10):
					for z in range(0, 3):
						o.set_voxel(Vector3i(x, y, z), iron if (x == 1 or x == 9 or head_v == 0) else head_v)
	var d := o.mesh(0, true, Vector3(-5.5, -23.0, -1.5) * 0.03125)
	var m: ArrayMesh = vworld.array_mesh(d, vmat)
	return m

# ---------------------------------------------------------------- saving / late joiners
func save_props() -> Array:
	var out := []
	for key in props:
		var po: Node = props[key]
		if not is_instance_valid(po):
			continue
		var d: PackedByteArray = po.obj.get_data()
		out.append({"key": key, "kind": po.kind, "meta": po.meta, "size": po.obj.get_size(), "raw": d.size(),
			"d": d.compress(FileAccess.COMPRESSION_ZSTD), "felled": po.felled, "notch": po.notch_y, "s0": po.section0})
	for key in gone:
		out.append({"key": key, "kind": gone[key][0], "meta": gone[key][1], "gone": true})
	return out

func load_props(list: Array) -> void:
	for e in list:
		var kind: String = e["kind"]
		var meta: Dictionary = e["meta"]
		var po: Node = get_prop(kind, meta, null)
		if po == null:
			continue
		if e.get("gone", false):
			gone[po.get_meta("key")] = [kind, meta]
			props.erase(po.get_meta("key"))
			po.queue_free()
			continue
		var raw: PackedByteArray = (e["d"] as PackedByteArray).decompress(int(e["raw"]), FileAccess.COMPRESSION_ZSTD)
		po.obj.set_data(e["size"], raw)
		po.felled = bool(e.get("felled", false))
		po.notch_y = int(e.get("notch", -1))
		po.section0 = int(e.get("s0", 0))
		po._remesh_all()
		po._update_collider()

# ---------------------------------------------------------------- talent "Erz-Gespür": ores glow through the rock
var _ore_mmi: MultiMeshInstance3D
var _ore_mat: StandardMaterial3D
var _ore_mask := PackedByteArray()
var _ore_t := 0.0
const ORE_COLORS := {57: Color(1.0, 0.55, 0.2), 58: Color(0.95, 0.8, 0.7), 59: Color(0.35, 1.0, 0.95), 54: Color(1.0, 0.85, 0.3)}

func _ore_tick(delta: float) -> void:
	var on: bool = Game.rank("gespuer") > 0 and target.get("kind", "") == "voxel" and vworld.hard[int(target.get("value", 0))] >= 3
	if not on:
		if _ore_mmi:
			_ore_mmi.visible = false
		return
	if _ore_mmi == null:
		_ore_mask.resize(256)
		for m in ORE_COLORS:
			for k in 4:
				_ore_mask[(m << 2) | k] = 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.11
		_ore_mat = StandardMaterial3D.new()
		_ore_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ore_mat.vertex_color_use_as_albedo = true
		_ore_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ore_mat.no_depth_test = true
		_ore_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		box.material = _ore_mat
		mm.mesh = box
		mm.instance_count = 400
		mm.visible_instance_count = 0
		_ore_mmi = MultiMeshInstance3D.new()
		_ore_mmi.multimesh = mm
		_ore_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ore_mmi.custom_aabb = AABB(Vector3(-400, -100, -400), Vector3(800, 400, 800))
		main.add_child(_ore_mmi)
	_ore_mmi.visible = true
	_ore_mat.albedo_color = Color(1, 1, 1, 0.55 + 0.35 * sin(Time.get_ticks_msec() / 180.0))
	_ore_t -= delta
	if _ore_t > 0.0:
		return
	_ore_t = 0.25
	var list: PackedInt32Array = vworld.vol.find_values(target["voxel"], 26, _ore_mask, 400)
	var mm2 := _ore_mmi.multimesh
	var n := list.size() / 4
	for i in n:
		var p: Vector3 = vworld.to_world(Vector3i(list[i * 4], list[i * 4 + 1], list[i * 4 + 2])) + Vector3.ONE * 0.0625
		mm2.set_instance_transform(i, Transform3D(Basis(), p))
		mm2.set_instance_color(i, ORE_COLORS.get(list[i * 4 + 3] >> 2, Color.WHITE))
	mm2.visible_instance_count = n
