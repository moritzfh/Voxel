## Headless bake step: converts the generator output (tools/out) into Godot resources.
## Run: godot --headless --path . --script res://bake/bake.gd
extends SceneTree

const OUT_DIR := "res://generated/"
var src_dir := ""
var data: PackedByteArray
var manifest: Dictionary
var tile_names: Array = []

func _init() -> void:
	src_dir = ProjectSettings.globalize_path("res://tools/out/")
	var t0 := Time.get_ticks_msec()
	manifest = JSON.parse_string(FileAccess.get_file_as_string(src_dir + "world.json"))
	data = FileAccess.get_file_as_bytes(src_dir + "world.bin")
	print("bake: loaded ", data.size() / 1048576, " MB")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var vmat := make_voxel_material("res://shaders/voxel.gdshader", "voxel_mat.tres")
	var wmat := make_water_material()
	var pmat := make_voxel_material("res://shaders/voxel_plant.gdshader", "plant_mat.tres")
	var lmat := make_voxel_material("res://shaders/voxel_plant.gdshader", "lily_mat.tres")
	lmat.set_shader_parameter("sway", 0.0)
	ResourceSaver.save(lmat, OUT_DIR + "lily_mat.tres")
	var cmat := make_voxel_material("res://shaders/voxel_cloud.gdshader", "cloud_mat.tres")
	var root := Node3D.new()
	root.name = "World"
	for lod in ["far", "back", "mid", "near"]:
		if manifest.has(lod):
			build_lod(root, lod, vmat, wmat)
	if manifest.has("trees"):
		build_trees(root, vmat)
	if manifest.has("plants_inst"):
		build_plants(root, pmat, lmat)
	if manifest.has("props_inst"):
		build_props(root, vmat)
	if manifest.has("rocks_inst"):
		build_rocks(root, vmat)
	if manifest.has("clouds"):
		build_clouds(root, cmat)
	build_lights(root)
	build_colliders(root)
	if manifest.has("characters"):
		build_characters()
	if manifest.has("water_map"):
		var wm: Dictionary = manifest["water_map"]
		for fn in ["near_vox.bin", "models_vox.bin"]:
			if FileAccess.file_exists(src_dir + fn):
				DirAccess.copy_absolute(src_dir + fn, ProjectSettings.globalize_path(OUT_DIR + fn))
		var img := Image.create_from_data(int(wm["w"]), int(wm["h"]), false, Image.FORMAT_RF, slice(wm["buf"]))
		ResourceSaver.save(img, OUT_DIR + "water_level.res", ResourceSaver.FLAG_COMPRESS)
	# split the world into several sub-scenes (each < 24 MB, so files stay easy to move around)
	var gdir := DirAccess.open(OUT_DIR)
	for fn in gdir.get_files():
		if fn.begins_with("world_") and fn.ends_with(".scn"):
			gdir.remove(fn)
	for holder in root.get_children():
		var kids: Array = holder.get_children()
		save_parts(String(holder.name), kids)
	var world := Node3D.new()
	world.name = "World"
	for p in part_paths:
		var inst: Node = load(p).instantiate()
		world.add_child(inst)
		inst.owner = world
	var ps := PackedScene.new()
	var err := ps.pack(world)
	if err != OK:
		push_error("pack failed %d" % err)
	err = ResourceSaver.save(ps, OUT_DIR + "world.scn", ResourceSaver.FLAG_COMPRESS)
	print("bake: world parts ", part_paths.size())
	print("bake: saved world.scn err=", err, " in ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	var extra := {}
	if manifest.has("water_map"):
		var wmeta: Dictionary = manifest["water_map"].duplicate()
		wmeta.erase("buf")
		manifest["water_meta"] = wmeta
	for k in ["markers", "bounds", "minimap", "water_meta", "near_vox", "models_vox", "materials"]:
		if manifest.has(k):
			extra[k] = manifest[k]
	var f := FileAccess.open(OUT_DIR + "world_data.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(extra))
	f.close()
	quit()

func slice(e: Array) -> PackedByteArray:
	var off: int = int(e[0])
	var n: int = int(e[1])
	return data.slice(off, off + n)

func make_voxel_material(shader_path: String, save_name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	apply_palette(m)
	ResourceSaver.save(m, OUT_DIR + save_name)
	return load(OUT_DIR + save_name)

func apply_palette(m: ShaderMaterial) -> void:
	var p: Dictionary = manifest["palette"]
	var pal := PackedVector3Array()
	var flat: Array = p["pal"]
	for i in 256:
		pal.append(Vector3(float(flat[i * 3]), float(flat[i * 3 + 1]), float(flat[i * 3 + 2])))
	m.set_shader_parameter("palette", pal)
	m.set_shader_parameter("emission_tab", PackedFloat32Array(p["em"]))
	m.set_shader_parameter("roughness_tab", PackedFloat32Array(p["rough"]))
	m.set_shader_parameter("jitter_tab", PackedFloat32Array(p["jit"]))

func make_water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	ResourceSaver.save(m, OUT_DIR + "water_mat.tres")
	return load(OUT_DIR + "water_mat.tres")

func mesh_from(ent: Dictionary, with_uv2: bool = true) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = slice(ent["pos"]).to_vector3_array()
	arrays[Mesh.ARRAY_NORMAL] = slice(ent["nrm"]).to_vector3_array()
	var flags := 0
	if ent.has("cus"):
		arrays[Mesh.ARRAY_CUSTOM0] = slice(ent["cus"])
		flags = Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	if ent.has("uv"):
		arrays[Mesh.ARRAY_TEX_UV] = slice(ent["uv"]).to_vector2_array()
	if with_uv2 and ent.has("uv2"):
		arrays[Mesh.ARRAY_TEX_UV2] = slice(ent["uv2"]).to_vector2_array()
	arrays[Mesh.ARRAY_INDEX] = slice(ent["idx"]).to_int32_array()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return am

func build_lod(root: Node3D, lod: String, vmat: Material, wmat: Material) -> void:
	var info: Dictionary = manifest[lod]
	var holder := Node3D.new()
	holder.name = "Terrain" + lod.capitalize()
	root.add_child(holder)
	var shadows := lod == "mid" or lod == "near"
	var nchunks := 0
	if info.get("fine", false):
		build_fine(holder, info, vmat, wmat)
		return
	for ent in info["chunks"]:
		var cname := "%s_%d_%d" % [lod, int(ent["cx"]), int(ent["cz"])]
		if ent.has("vis"):
			var mi := MeshInstance3D.new()
			mi.name = cname
			var am := mesh_from(ent["vis"])
			am.surface_set_material(0, vmat)
			mi.mesh = am
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if lod == "far" or lod == "back":
				mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			holder.add_child(mi)
			nchunks += 1
		if ent.has("water"):
			var wi := MeshInstance3D.new()
			wi.name = cname + "_water"
			var wm := mesh_from(ent["water"])
			wm.surface_set_material(0, wmat)
			wi.mesh = wm
			wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			holder.add_child(wi)
		if ent.has("col"):
			var sb := StaticBody3D.new()
			sb.name = cname + "_col"
			var cs := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(slice(ent["col"]).to_vector3_array())
			cs.shape = shape
			sb.add_child(cs)
			holder.add_child(sb)
	print("bake: ", lod, " chunks ", nchunks)

func build_fine(holder: Node3D, info: Dictionary, vmat: Material, wmat: Material) -> void:
	var n := 0
	var lod_names := ["f", "m", "c"]
	for ent in info["chunks"]:
		var c: Array = ent["center"]
		var base := Vector3(float(c[0]), 0.0, float(c[1]))
		var cname := "%s_%d_%d" % [String(holder.name).to_lower(), int(ent["cx"]), int(ent["cz"])]
		var lods: Array = ent["lods"]
		for li in lods.size():
			var e: Dictionary = lods[li]
			var r: Array = e["range"]
			for kind in ["vis", "water"]:
				if not e.has(kind):
					continue
				var mi := MeshInstance3D.new()
				mi.name = "%s_%s%s" % [cname, lod_names[li], "" if kind == "vis" else "_w"]
				var am := mesh_from(e[kind])
				am.surface_set_material(0, vmat if kind == "vis" else wmat)
				mi.mesh = am
				mi.position = base
				mi.visibility_range_begin = float(r[0])
				mi.visibility_range_end = float(r[1])
				if kind == "water":
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				elif float(r[0]) >= 150.0:
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				elif li == 2:
					mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				holder.add_child(mi)
				n += 1
		if ent.has("scol"):
			var sbs := StaticBody3D.new()
			sbs.name = cname + "_sc"
			sbs.set_meta("terrain", true)
			var css := CollisionShape3D.new()
			var shs := ConcavePolygonShape3D.new()
			shs.set_faces(slice(ent["scol"]).to_vector3_array())
			css.shape = shs
			sbs.add_child(css)
			holder.add_child(sbs)
		if not ent.has("hm"):
			continue
		# ground collision: height map in fine voxel units
		var sb := StaticBody3D.new()
		sb.name = cname + "_hm"
		sb.set_meta("terrain", true)
		var hs := HeightMapShape3D.new()
		var sz := int(ent["hm_size"])
		hs.map_width = sz
		hs.map_depth = sz
		var hd := slice(ent["hm"]).to_float32_array()
		hs.map_data = hd
		var cs := CollisionShape3D.new()
		cs.shape = hs
		var hc: Array = ent["hm_center"]
		var vs := float(info["vs"])
		cs.position = Vector3(float(hc[0]), float(hc[1]), float(hc[2]))
		cs.scale = Vector3(vs, vs, vs)
		sb.add_child(cs)
		holder.add_child(sb)
	var k := 0
	for sc in info["struct_col"]:
		var sb2 := StaticBody3D.new()
		sb2.name = "near_struct_col_%d" % k
		var cs2 := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(slice(sc["col"]).to_vector3_array())
		cs2.shape = shape
		sb2.add_child(cs2)
		holder.add_child(sb2)
		k += 1
	print("bake: ", holder.name, " fine meshes ", n, " struct colliders ", k)

func build_trees(root: Node3D, vmat: Material) -> void:
	var info: Dictionary = manifest["trees"]
	var holder := Node3D.new()
	holder.name = "Trees"
	root.add_child(holder)
	var meshes := {}
	for name in info["meshes"]:
		var lods := []
		var i := 0
		for ent in info["meshes"][name]:
			var am := mesh_from(ent)
			am.surface_set_material(0, vmat)
			ResourceSaver.save(am, OUT_DIR + "tree_%s_lod%d.res" % [name, i], ResourceSaver.FLAG_COMPRESS)
			lods.append(load(OUT_DIR + "tree_%s_lod%d.res" % [name, i]))
			i += 1
		meshes[name] = lods
	var ranges: Array = info["ranges"]
	var nl := ranges.size()
	var n := 0
	for ch in info["chunks"]:
		var tier: int = int(ch["tier"])
		var buf := slice(ch["buf"]).to_float32_array()
		for lod in nl:
			if tier == 2 and lod < nl - 1:
				continue
			if tier == 1 and lod == 0:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[ch["mesh"]][lod]
			mm.instance_count = int(ch["n"])
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d_l%d" % [ch["mesh"], int(ch["center"][0]), int(ch["center"][1]), lod]
			mmi.multimesh = mm
			if tier < 2:
				var r: Array = ranges[lod]
				mmi.visibility_range_begin = float(r[0])
				mmi.visibility_range_end = float(r[1])
				if tier == 1 and lod == 1:
					mmi.visibility_range_begin = 0.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if lod >= 3:
				mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			holder.add_child(mmi)
			n += 1
			if (lod == 1 or lod == 2) and tier < 2:
				# cheap shadow caster: the next coarser LOD, shadows only, same distance band
				var sh := MultiMeshInstance3D.new()
				var smm := MultiMesh.new()
				smm.transform_format = MultiMesh.TRANSFORM_3D
				smm.mesh = meshes[ch["mesh"]][lod + 1]
				smm.instance_count = int(ch["n"])
				smm.buffer = buf
				sh.multimesh = smm
				sh.name = mmi.name + "_sh"
				sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				sh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				sh.visibility_range_begin = mmi.visibility_range_begin
				sh.visibility_range_end = mmi.visibility_range_end
				holder.add_child(sh)
				n += 1
	var cb := StaticBody3D.new()
	cb.name = "TreeColliders"
	holder.add_child(cb)
	var ti := 0
	for c in info["colliders"]:
		var cs := CollisionShape3D.new()
		cs.name = "tree_%d" % ti
		ti += 1
		var sh := CylinderShape3D.new()
		sh.radius = float(c[3])
		sh.height = 6.0
		cs.shape = sh
		cs.position = Vector3(float(c[0]), float(c[1]) + 3.0, float(c[2]))
		if c.size() > 4:
			cs.set_meta("tree", {"mesh": c[4], "chunk": c[5], "index": int(c[6]), "pos": [float(c[0]), float(c[1]), float(c[2])],
				"yaw": float(c[7]), "scale": float(c[8])})
		cb.add_child(cs)
	print("bake: tree multimeshes ", n)

func build_plants(root: Node3D, pmat: Material, lmat: Material) -> void:
	var info: Dictionary = manifest["plants_inst"]
	var holder := Node3D.new()
	holder.name = "Plants"
	root.add_child(holder)
	var meshes := {}
	for name in info["meshes"]:
		var lods := []
		var i := 0
		for ent in info["meshes"][name]:
			var am := mesh_from(ent)
			am.surface_set_material(0, lmat if name == "lily" else pmat)
			ResourceSaver.save(am, OUT_DIR + "plant_%s_lod%d.res" % [name, i], ResourceSaver.FLAG_COMPRESS)
			lods.append(load(OUT_DIR + "plant_%s_lod%d.res" % [name, i]))
			i += 1
		meshes[name] = lods
	var ranges: Array = info["ranges"]
	var n := 0
	for ch in info["chunks"]:
		var buf := slice(ch["buf"]).to_float32_array()
		for lod in ranges.size():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = meshes[ch["mesh"]][lod]
			mm.instance_count = int(ch["n"])
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "pl_%s_%d_%d_%d" % [ch["mesh"], int(ch["center"][0]), int(ch["center"][1]), lod]
			mmi.multimesh = mm
			var r: Array = ranges[lod]
			mmi.visibility_range_begin = float(r[0])
			mmi.visibility_range_end = float(r[1])
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			holder.add_child(mmi)
			n += 1
	print("bake: plant multimeshes ", n)

func build_props(root: Node3D, vmat: Material) -> void:
	var info: Dictionary = manifest["props_inst"]
	var holder := Node3D.new()
	holder.name = "Props"
	root.add_child(holder)
	var meshes := {}
	for name in info["meshes"]:
		var am := mesh_from(info["meshes"][name])
		am.surface_set_material(0, vmat)
		ResourceSaver.save(am, OUT_DIR + "prop_%s.res" % name, ResourceSaver.FLAG_COMPRESS)
		meshes[name] = load(OUT_DIR + "prop_%s.res" % name)
	for grp in info["groups"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[grp["mesh"]]
		mm.instance_count = int(grp["n"])
		mm.buffer = slice(grp["buf"]).to_float32_array()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "props_" + str(grp["mesh"])
		mmi.multimesh = mm
		holder.add_child(mmi)

func build_rocks(root: Node3D, vmat: Material) -> void:
	var info: Dictionary = manifest["rocks_inst"]
	var holder := Node3D.new()
	holder.name = "Rocks"
	root.add_child(holder)
	var meshes := {}
	for name in info["meshes"]:
		var lods := []
		var i := 0
		for ent in info["meshes"][name]:
			var am := mesh_from(ent)
			am.surface_set_material(0, vmat)
			ResourceSaver.save(am, OUT_DIR + "rock_%s_lod%d.res" % [name, i], ResourceSaver.FLAG_COMPRESS)
			lods.append(load(OUT_DIR + "rock_%s_lod%d.res" % [name, i]))
			i += 1
		meshes[name] = lods
	var n := 0
	for ch in info["chunks"]:
		var pebble := str(ch["mesh"]).begins_with("pebble")
		var ranges: Array = info["ranges"]["pebble" if pebble else "rock"]
		var buf := slice(ch["buf"]).to_float32_array()
		for lod in ranges.size():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[ch["mesh"]][lod]
			mm.instance_count = int(ch["n"])
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "rocks_%s_%d_%d_l%d" % [ch["mesh"], int(ch["center"][0]), int(ch["center"][1]), lod]
			mmi.multimesh = mm
			var r: Array = ranges[lod]
			mmi.visibility_range_begin = float(r[0])
			mmi.visibility_range_end = float(r[1])
			if pebble or lod == 2:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			holder.add_child(mmi)
			n += 1
	var block := StaticBody3D.new()
	block.name = "RockColliders"
	holder.add_child(block)
	var picks := StaticBody3D.new()
	picks.name = "RockPicks"
	picks.collision_layer = 2
	picks.collision_mask = 0
	holder.add_child(picks)
	var ri := 0
	for it in info.get("items", []):
		var cs := CollisionShape3D.new()
		cs.name = "rock_%d" % ri
		ri += 1
		var bs := BoxShape3D.new()
		var big: bool = it[11]
		bs.size = Vector3(float(it[8]) * (0.85 if big else 0.9), float(it[9]) * (1.0 if big else 0.9), float(it[10]) * (0.85 if big else 0.9))
		cs.shape = bs
		cs.position = Vector3(float(it[0]), float(it[1]) + float(it[9]) * 0.5, float(it[2]))
		cs.rotation.y = float(it[3])
		cs.set_meta("rock", {"mesh": it[5], "chunk": it[6], "index": int(it[7]), "pos": [float(it[0]), float(it[1]), float(it[2])],
			"yaw": float(it[3]), "scale": float(it[4])})
		(block if big else picks).add_child(cs)
	print("bake: rock multimeshes ", n, " rock colliders ", ri)

func build_clouds(root: Node3D, cmat: Material) -> void:
	var info: Dictionary = manifest["clouds"]
	var holder := Node3D.new()
	holder.name = "Clouds"
	root.add_child(holder)
	for grp in info["groups"]:
		var am := mesh_from(info["meshes"][grp["mesh"]])
		am.surface_set_material(0, cmat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = am
		mm.instance_count = int(grp["n"])
		mm.buffer = slice(grp["buf"]).to_float32_array()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "clouds_" + str(grp["mesh"])
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# the shader moves clouds along x (wind + wrap), so cull against the whole sky box
		mmi.custom_aabb = AABB(Vector3(-2200, 150, -2400), Vector3(4400, 300, 4200))
		holder.add_child(mmi)

func build_lights(root: Node3D) -> void:
	if not manifest.has("lights"):
		return
	var holder := Node3D.new()
	holder.name = "Lights"
	root.add_child(holder)
	var i := 0
	for l in manifest["lights"]:
		var o := OmniLight3D.new()
		o.name = "Lantern%d" % i
		o.position = Vector3(float(l["pos"][0]), float(l["pos"][1]), float(l["pos"][2]))
		o.light_color = Color(float(l["color"][0]), float(l["color"][1]), float(l["color"][2]))
		o.light_energy = float(l["energy"])
		o.omni_range = float(l["range"])
		o.omni_attenuation = 1.6
		o.shadow_enabled = false
		o.light_bake_mode = Light3D.BAKE_DYNAMIC
		o.distance_fade_enabled = true
		o.distance_fade_begin = 60.0
		o.distance_fade_length = 20.0
		o.set_script(load("res://scripts/lantern_flicker.gd"))
		holder.add_child(o)
		i += 1

func build_colliders(root: Node3D) -> void:
	if not manifest.has("colliders"):
		return
	var sb := StaticBody3D.new()
	sb.name = "PropColliders"
	root.add_child(sb)
	for c in manifest["colliders"]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(c[3]), float(c[4]), float(c[5]))
		cs.shape = bs
		cs.position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		cs.rotation.y = float(c[6])
		sb.add_child(cs)

func build_characters() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/character.gdshader")
	ResourceSaver.save(mat, OUT_DIR + "char_mat.tres")
	mat = load(OUT_DIR + "char_mat.tres")
	for cname in manifest["characters"]:
		var parts: Dictionary = manifest["characters"][cname]
		var root := Node3D.new()
		root.name = cname.capitalize()
		for pname in parts:
			var ent: Dictionary = parts[pname]["mesh"]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = slice(ent["pos"]).to_vector3_array()
			arrays[Mesh.ARRAY_NORMAL] = slice(ent["nrm"]).to_vector3_array()
			arrays[Mesh.ARRAY_COLOR] = slice(ent["col"]).to_color_array()
			if ent.has("uv"):
				arrays[Mesh.ARRAY_TEX_UV] = slice(ent["uv"]).to_vector2_array()
			arrays[Mesh.ARRAY_INDEX] = slice(ent["idx"]).to_int32_array()
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			am.surface_set_material(0, mat)
			var mi := MeshInstance3D.new()
			mi.name = pname
			mi.mesh = am
			var pv: Array = parts[pname]["pivot"]
			mi.position = Vector3(float(pv[0]), float(pv[1]), float(pv[2]))
			root.add_child(mi)
		set_owner_recursive(root, root)
		var ps := PackedScene.new()
		ps.pack(root)
		ResourceSaver.save(ps, OUT_DIR + "char_%s.scn" % cname, ResourceSaver.FLAG_COMPRESS)
	print("bake: characters ", manifest["characters"].keys())

const PART_LIMIT := 24 * 1024 * 1024
var part_paths: Array = []

func save_parts(pname: String, nodes: Array) -> void:
	var holder := Node3D.new()
	holder.name = pname
	for n in nodes:
		if n.get_parent():
			n.get_parent().remove_child(n)
		holder.add_child(n)
	set_owner_recursive(holder, holder)
	var ps := PackedScene.new()
	ps.pack(holder)
	var path: String = OUT_DIR + "world_%s.scn" % pname.to_lower()
	ResourceSaver.save(ps, path, ResourceSaver.FLAG_COMPRESS)
	var f := FileAccess.open(path, FileAccess.READ)
	var size := f.get_length()
	f.close()
	for n in nodes:
		holder.remove_child(n)
	holder.free()
	if size > PART_LIMIT and nodes.size() > 1:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var half := nodes.size() / 2
		save_parts(pname + "a", nodes.slice(0, half))
		save_parts(pname + "b", nodes.slice(half))
		return
	print("bake: part ", path, " ", size / 1048576.0, " MB")
	part_paths.append(path)

func set_owner_recursive(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		set_owner_recursive(c, owner_node)
