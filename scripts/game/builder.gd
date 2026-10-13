extends Node
## Build mode (B). Instead of placing single blocks you draw parametric voxel shapes:
##   left mouse: hold and drag over the ground = footprint, release = build. A click alone uses the last size.
##   right mouse: the same shape is cut out (doors, windows, cellars, tunnels).
##   wheel: height (or depth on walls) · Shift+wheel: wall thickness · R: rotate · Shift+R: mirror
##   1-0: shapes · V: variant · X: mode (Bauen / Färben / Kopieren) · P: blueprints · G: grid · MMB: pipette
##   Tab: the full construction kit (materials, patterns, all options) · Ctrl+Z / Ctrl+Y: undo / redo
## The preview ("ghost") shows the real colours and patterns, its cost and whether it fits.

const GHOST_SHADER := preload("res://shaders/voxel_ghost.gdshader")
const XRAY_SHADER := preload("res://shaders/voxel_xray.gdshader")
const RANGE := 26.0
const UNDO_MAX := 40

signal changed            # selection / options changed (UI refresh)
signal mode_toggled(on: bool)

## drag: "rect" = footprint, "line" = wall along the drag, "stroke" = continuous brush, "none" = click only.
## thick_axis: what Shift+wheel changes ("z" = depth of the wall, "y" = height, "p" = shell thickness).
const SHAPES := [
	{"id": "quader", "name": "Quader", "kind": 0, "drag": "rect", "size": Vector3i(16, 16, 16), "thick": 2, "thick_axis": "p",
		"desc": "Massiver oder hohler Block. Ziehen = Grundfläche, Mausrad = Höhe.",
		"variants": [{"name": "Voll"}, {"name": "Hohl", "hollow": true}]},
	{"id": "wand", "name": "Wand", "kind": 0, "drag": "line", "size": Vector3i(32, 24, 2), "thick_axis": "z",
		"desc": "Zieh eine Linie – die Wand folgt. Shift+Mausrad = Wandstärke.",
		"variants": [{"name": "Glatt"}, {"name": "Zinnen", "crenel": 4, "talent": "formen3"},
			{"name": "Torbogen", "kind": 3, "talent": "formen2", "arch": true}]},
	{"id": "boden", "name": "Boden", "kind": 0, "drag": "rect", "size": Vector3i(32, 2, 32), "thick_axis": "y", "nofound": false,
		"desc": "Flache Platte für Böden, Wege und Decken. Mausrad = Stärke.",
		"variants": [{"name": "Boden"}]},
	{"id": "raum", "name": "Raum", "kind": 0, "drag": "rect", "size": Vector3i(40, 24, 32), "thick": 2, "thick_axis": "p",
		"desc": "Zieh ein Rechteck – vier Wände entstehen auf einmal.",
		"variants": [{"name": "Offen", "hollow": true, "open_top": true, "open_bottom": true},
			{"name": "Mit Boden", "hollow": true, "open_top": true},
			{"name": "Geschlossen", "hollow": true}]},
	{"id": "haus", "name": "Haus", "kind": -2, "drag": "rect", "size": Vector3i(48, 22, 40), "thick": 2, "thick_axis": "p",
		"desc": "Ein ganzes Haus: Wände, Dach (Zweitmaterial), Tür, Fenster und Dielenboden.",
		"variants": [{"name": "Satteldach"}, {"name": "Pultdach", "half": true}, {"name": "Flachdach", "flat": true}]},
	{"id": "pinsel", "name": "Pinsel", "kind": 7, "drag": "stroke", "size": Vector3i(8, 8, 8), "thick_axis": "", "nofound": true,
		"desc": "Freihand modellieren: gedrückt halten und malen. Rechts = wegformen.",
		"variants": [{"name": "Rund"}, {"name": "Eckig", "kind": 0}]},
	{"id": "kugel", "name": "Kugel", "kind": 1, "drag": "rect", "size": Vector3i(24, 24, 24), "thick": 2, "thick_axis": "p", "talent": "formen1", "nofound": true,
		"desc": "Kugeln, Kuppeln und Gewölbe.",
		"variants": [{"name": "Kugel"}, {"name": "Kuppel", "half": true}, {"name": "Hohlkugel", "hollow": true},
			{"name": "Hohlkuppel", "half": true, "hollow": true}]},
	{"id": "turm", "name": "Turm", "kind": 2, "drag": "rect", "size": Vector3i(32, 48, 32), "thick": 2, "thick_axis": "p", "talent": "formen1",
		"desc": "Zylinder, Rundtürme mit Zinnen und Säulen.",
		"variants": [{"name": "Zylinder"}, {"name": "Rundturm", "hollow": true, "open_top": true},
			{"name": "Wehrturm", "hollow": true, "open_top": true, "crenel": 4},
			{"name": "Säule", "kind": 6, "talent": "formen3"}]},
	{"id": "treppe", "name": "Treppe", "kind": 4, "drag": "rect", "size": Vector3i(12, 16, 24), "thick_axis": "", "talent": "formen2",
		"desc": "Treppen und Rampen – sie steigen von dir weg an.",
		"variants": [{"name": "Treppe", "fill_under": true}, {"name": "Freitreppe", "fill_under": false},
			{"name": "Rampe", "kind": 8}]},
	{"id": "dach", "name": "Dach", "kind": 5, "drag": "rect", "size": Vector3i(40, 16, 32), "thick": 2, "thick_axis": "p", "talent": "formen3", "nofound": true,
		"desc": "Sattel- und Pultdächer. Am besten auf die Wandkronen ziehen.",
		"variants": [{"name": "Satteldach", "hollow": true}, {"name": "Pultdach", "half": true, "hollow": true},
			{"name": "Massiv"}]},
]
const PATTERNS := ["Auto", "Natürlich", "Einfarbig", "Mauerwerk", "Streifen", "Schachbrett", "Gemischt"]
const AUTO_PATTERN := {"bricks": 2, "bricks_dark": 2, "brick_red": 2, "slate": 3, "planks": 3, "planks_dark": 3,
	"timber": 1, "plaster": 1, "glass": 1, "window": 1, "cloth_w": 1, "cloth_r": 1, "cloth_b": 1, "cloth_g": 1,
	"cloth_y": 1, "iron": 1, "gold": 5, "crystal": 5, "lantern": 1, "crate": 3, "hay": 5}
const GRIDS := [1, 2, 4, 8]
const GRID_NAMES := ["12,5 cm", "25 cm", "50 cm", "1 m"]
const MODES := ["Bauen", "Färben", "Kopieren"]
## build palette: [group, [material names]]
const PALETTE := [
	["Natur", ["grass", "dirt", "path", "sand", "gravel", "clay", "stone", "cliff", "mountain", "moss", "snow", "oak", "log"]],
	["Stein", ["cobble", "cobble_mossy", "bricks", "bricks_dark", "slate", "plaster", "brick_red"]],
	["Holz", ["planks", "planks_dark", "timber", "crate", "hay"]],
	["Glas & Stoff", ["glass", "window", "cloth_w", "cloth_r", "cloth_b", "cloth_g", "cloth_y"]],
	["Edel", ["iron", "lantern", "gold", "crystal"]],
]
const MAT_NAMES := {"grass": "Gras", "dirt": "Erde", "path": "Weg", "sand": "Sand", "gravel": "Kies", "clay": "Lehm",
	"stone": "Stein", "cliff": "Fels", "mountain": "Bergfels", "moss": "Moos", "snow": "Schnee", "oak": "Laub",
	"log": "Holzstamm", "cobble": "Bruchstein", "cobble_mossy": "Moosstein", "bricks": "Steinziegel",
	"bricks_dark": "Dunkler Stein", "slate": "Schiefer", "plaster": "Putz", "brick_red": "Backstein", "planks": "Bretter",
	"planks_dark": "Dunkle Bretter", "timber": "Fachwerk", "crate": "Kistenholz", "hay": "Heu", "glass": "Glas",
	"window": "Leuchtfenster", "cloth_w": "Stoff weiß", "cloth_r": "Stoff rot", "cloth_b": "Stoff blau",
	"cloth_g": "Stoff grün", "cloth_y": "Stoff gelb", "iron": "Eisen", "lantern": "Leuchtstein", "gold": "Gold",
	"crystal": "Kristall", "pine": "Nadeln", "bricks_m": "Ziegel"}

var main: Node
var player: CharacterBody3D
var cam_rig: Node3D
var vworld: Node3D
var hud: CanvasLayer
var tools: Node
var ui: Control

# ---------------------------------------------------------------- options
var active := false
var mode := 0
var shape_i := 0
var bp_i := -1                 # >= 0: placing blueprint bp_i instead of a shape
var variants := {}             # shape id -> variant index
var sizes := {}                # shape id -> Vector3i local size (x = width, y = height, z = depth)
var thicks := {}               # shape id -> shell thickness
var rot_off := 0
var mirror := false
var mat := 0                   # material id
var mat2 := 0                  # second material (roofs)
var pattern_sel := 0           # index into PATTERNS (0 = auto)
var grid_i := 2
var foundation := true
var only_built := true
var glass_windows := false
var recent: Array = []         # recently used material ids

# ---------------------------------------------------------------- state
var aim := {}
var dragging := 0              # 0 none, 1 left (build / paint / select), 2 right (subtract)
var drag := {}                 # {base: Vector3i, n: Vector3i, cur: Vector3i}
var place := {}                # current placement (see _compute)
var _place_key := ""
var _compute_t := 0.0
var _dab_t := 0.0
var _last_dab := Vector3i(-999999, 0, 0)
var _stroke := {}              # merged undo entry of a brush stroke
var undo_stack: Array = []
var redo_stack: Array = []
var _panel_open := false
var test_mode := false         # scripted tests: aim / drag end are set from outside
var test_cur := Vector3i(-999999, 0, 0)

# ---------------------------------------------------------------- visuals
var ghost: MeshInstance3D
var ghost_mat: ShaderMaterial
var xray_mat: ShaderMaterial
var wire: MeshInstance3D
var wire_mesh: ImmediateMesh
var wire_mat: StandardMaterial3D
var dim_label: Label3D
var marker: MeshInstance3D

func setup(p_main: Node) -> void:
	main = p_main
	player = main.player
	cam_rig = main.cam_rig
	vworld = main.vworld
	hud = main.hud
	tools = main.tools
	mat = int(vworld.mat_ids.get("cobble", 8))
	mat2 = int(vworld.mat_ids.get("slate", 14))
	recent = [mat, int(vworld.mat_ids.get("planks", 12)), int(vworld.mat_ids.get("bricks", 6)), mat2,
		int(vworld.mat_ids.get("plaster", 10)), int(vworld.mat_ids.get("dirt", 2))]
	sizes["_sel"] = Vector3i(48, 48, 48)
	for s in SHAPES:
		sizes[s["id"]] = s["size"]
		thicks[s["id"]] = int(s.get("thick", 2))
		variants[s["id"]] = 0
	_build_visuals()
	ui = Control.new()
	ui.set_script(load("res://scripts/ui/build_ui.gd"))
	hud.root.add_child(ui)
	ui.setup(self)

func _build_visuals() -> void:
	var vm := vworld.vmat as ShaderMaterial
	ghost_mat = ShaderMaterial.new()
	ghost_mat.shader = GHOST_SHADER
	for p in ["palette", "emission_tab", "roughness_tab", "jitter_tab", "bevel_strength", "ao_strength", "saturation"]:
		ghost_mat.set_shader_parameter(p, vm.get_shader_parameter(p))
	ghost_mat.render_priority = 1
	xray_mat = ShaderMaterial.new()
	xray_mat.shader = XRAY_SHADER
	ghost_mat.next_pass = xray_mat
	ghost = MeshInstance3D.new()
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ghost.visible = false
	main.add_child(ghost)
	wire_mesh = ImmediateMesh.new()
	wire_mat = StandardMaterial3D.new()
	wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire_mat.no_depth_test = true
	wire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wire_mat.vertex_color_use_as_albedo = true
	wire = MeshInstance3D.new()
	wire.mesh = wire_mesh
	wire.material_override = wire_mat
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wire.visible = false
	main.add_child(wire)
	dim_label = Label3D.new()
	dim_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dim_label.no_depth_test = true
	dim_label.fixed_size = true
	dim_label.pixel_size = 0.0011
	dim_label.font_size = 30
	dim_label.outline_size = 10
	dim_label.font = load("res://assets/fonts/alegreya-latin-700-normal.woff2")
	dim_label.modulate = Color(1, 0.97, 0.88)
	dim_label.outline_modulate = Color(0.04, 0.06, 0.05, 0.85)
	dim_label.visible = false
	main.add_child(dim_label)
	marker = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.16
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.9, 0.5)
	mm.no_depth_test = true
	bm.material = mm
	marker.mesh = bm
	marker.visible = false
	main.add_child(marker)

# ---------------------------------------------------------------- helpers
func shape() -> Dictionary:
	return SHAPES[shape_i]

func shape_id() -> String:
	if mode == 2:
		return "_sel"
	return "bauplan" if bp_i >= 0 else str(shape()["id"])

func variant() -> Dictionary:
	var s := shape()
	var vl: Array = s["variants"]
	return vl[clampi(int(variants[s["id"]]), 0, vl.size() - 1)]

func shape_unlocked(i: int) -> bool:
	var s: Dictionary = SHAPES[i]
	return not s.has("talent") or Game.rank(s["talent"]) > 0 or Game.creative

func variant_unlocked(v: Dictionary) -> bool:
	return not v.has("talent") or Game.rank(v["talent"]) > 0 or Game.creative

func max_size() -> int:
	return Game.max_shape_voxels()

func grid() -> int:
	return GRIDS[grid_i]

func mat_name(id: int) -> String:
	var n: String = str(vworld.materials.get(id, {}).get("name", "?"))
	return MAT_NAMES.get(n, n.capitalize())

func mat_value(id: int) -> int:
	return id << 2

func pattern() -> int:
	if pattern_sel == 0:
		var n: String = str(vworld.materials.get(mat, {}).get("name", ""))
		return int(AUTO_PATTERN.get(n, 0))
	return pattern_sel - 1

func per_voxel(id: int) -> float:
	return vworld.yield_tab[id << 2]

func res_name(r: String) -> String:
	return str(Game.RESOURCES.get(r, {}).get("name", r))

## resource cost of a value histogram (256 counts)
func cost_of_counts(counts: PackedInt32Array) -> Dictionary:
	var acc := {}
	for v in 256:
		var c := counts[v]
		if c <= 0:
			continue
		var r: String = vworld.res_of(v)
		if r == "":
			continue
		acc[r] = float(acc.get(r, 0.0)) + c * vworld.yield_tab[v]
	var out := {}
	for r in acc:
		out[r] = maxi(1, ceili(float(acc[r]) * Game.cost_factor()))
	return out

## what cutting out gives back: only crafted building materials (natural ground has to be mined)
func refund_of_counts(counts: PackedInt32Array) -> Dictionary:
	var acc := {}
	for v in 256:
		var c := counts[v]
		if c <= 0 or vworld.processed[v] == 0:
			continue
		var r: String = vworld.res_of(v)
		if r != "":
			acc[r] = float(acc.get(r, 0.0)) + c * vworld.yield_tab[v]
	var out := {}
	for r in acc:
		var n := floori(float(acc[r]))
		if n > 0:
			out[r] = n
	return out

func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return ""
	var parts := []
	for r in cost:
		parts.append("%d %s" % [int(cost[r]), res_name(r)])
	return ", ".join(parts)

func _note_recent(id: int) -> void:
	recent.erase(id)
	recent.push_front(id)
	if recent.size() > 8:
		recent.resize(8)

# ---------------------------------------------------------------- mode on / off
func toggle() -> void:
	set_active(not active)

func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	tools.enabled = not on
	dragging = 0
	drag = {}
	_place_key = ""
	place = {}
	_hide_visuals()
	if not on and _panel_open:
		close_panel()
	if on:
		tools._show_tool("hammer")
		Sfx.play("whoosh", null, -10.0)
	mode_toggled.emit(on)
	changed.emit()

func _hide_visuals() -> void:
	ghost.visible = false
	wire.visible = false
	dim_label.visible = false
	marker.visible = false

func open_panel() -> void:
	_panel_open = true
	dragging = 0
	ui.show_panel(true)
	player.input_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_panel() -> void:
	_panel_open = false
	ui.show_panel(false)
	player.input_blocked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ---------------------------------------------------------------- selection API (keys + UI)
func select_shape(i: int) -> void:
	if i < 0 or i >= SHAPES.size():
		return
	if not shape_unlocked(i):
		var t: String = SHAPES[i]["talent"]
		hud.show_toast("%s – lerne das Talent „%s“ (T)" % [SHAPES[i]["name"], Game.TALENTS[t]["name"]], 2.2)
		Sfx.play("clink", null, -8.0)
		return
	if mode == 2:
		mode = 0
	if shape_i == i and bp_i < 0:
		cycle_variant()
		return
	shape_i = i
	bp_i = -1
	_after_change()
	Sfx.play("click", null, -10.0)

func cycle_variant() -> void:
	var s := shape()
	var vl: Array = s["variants"]
	var cur := int(variants[s["id"]])
	for k in vl.size():
		cur = (cur + 1) % vl.size()
		if variant_unlocked(vl[cur]):
			break
	variants[s["id"]] = cur
	_after_change()
	Sfx.play("click", null, -10.0)

func set_variant(i: int) -> void:
	var vl: Array = shape()["variants"]
	if i >= 0 and i < vl.size() and variant_unlocked(vl[i]):
		variants[shape()["id"]] = i
		_after_change()

func cycle_mode() -> void:
	set_mode((mode + 1) % MODES.size())

func set_mode(m: int) -> void:
	mode = m
	if mode == 2:
		bp_i = -1
	_after_change()
	Sfx.play("click", null, -10.0)

func set_material(id: int, second := false) -> void:
	if second:
		mat2 = id
	else:
		mat = id
		_note_recent(id)
	_after_change()

func set_pattern(i: int) -> void:
	pattern_sel = clampi(i, 0, PATTERNS.size() - 1)
	_after_change()

func cycle_grid() -> void:
	grid_i = (grid_i + 1) % GRIDS.size()
	hud.show_toast("Raster: %s" % GRID_NAMES[grid_i], 1.0)
	_after_change()

func rotate(steps := 1) -> void:
	rot_off = (rot_off + steps) % 4
	_after_change()
	Sfx.play("click", null, -12.0)

func toggle_mirror() -> void:
	mirror = not mirror
	hud.show_toast("Gespiegelt" if mirror else "Nicht gespiegelt", 0.8)
	_after_change()

func select_blueprint(i: int) -> void:
	if i < 0 or i >= Game.blueprints.size():
		return
	bp_i = i
	if mode != 0:
		mode = 0
	_after_change()

func cycle_blueprint() -> void:
	if Game.blueprints.is_empty():
		hud.show_toast("Noch keine Baupläne – X bis „Kopieren“, dann ein Gebäude markieren", 2.5)
		return
	select_blueprint((bp_i + 1) % Game.blueprints.size() if bp_i >= 0 else 0)
	hud.show_toast("Bauplan: %s" % Game.blueprints[bp_i]["name"], 1.2)

func adjust_height(d: int) -> void:
	var id := shape_id()
	if id == "bauplan":
		return
	var s: Vector3i = sizes[id]
	var g := maxi(1, grid()) if id != "pinsel" else 1
	if id == "pinsel":
		s = Vector3i.ONE * clampi(s.x + d, 2, mini(max_size(), 32))
	else:
		var y := clampi(s.y + d * g, 1, max_size())
		s.y = y
	sizes[id] = s
	_after_change()

func adjust_thick(d: int) -> void:
	var id := shape_id()
	if id == "bauplan" or id == "pinsel":
		return
	var ax: String = shape()["thick_axis"]
	var s: Vector3i = sizes[id]
	match ax:
		"z":
			s.z = clampi(s.z + d, 1, max_size())
			sizes[id] = s
		"y":
			s.y = clampi(s.y + d, 1, max_size())
			sizes[id] = s
		"p":
			thicks[id] = clampi(int(thicks[id]) + d, 1, 12)
		_:
			return
	_after_change()

func set_size(v: Vector3i) -> void:
	var id := shape_id()
	if id == "bauplan":
		return
	var m := max_size()
	sizes[id] = Vector3i(clampi(v.x, 1, m), clampi(v.y, 1, m), clampi(v.z, 1, m))
	_after_change()

func _after_change() -> void:
	_place_key = ""
	changed.emit()

# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not active:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B and _can_input():
			set_active(true)
			get_viewport().set_input_as_handled()
		return
	if _panel_open:
		if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_TAB or event.keycode == KEY_ESCAPE):
			close_panel()
			get_viewport().set_input_as_handled()
		return
	if not _can_input():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.ctrl_pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			return  # camera zoom
		get_viewport().set_input_as_handled()
		if not mb.pressed:
			if (mb.button_index == MOUSE_BUTTON_LEFT and dragging == 1) or (mb.button_index == MOUSE_BUTTON_RIGHT and dragging == 2):
				_release()
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if dragging == 2:
					_cancel_drag()
				else:
					_press(1)
			MOUSE_BUTTON_RIGHT:
				if dragging == 1:
					_cancel_drag()
				elif mode == 0:
					_press(2)
			MOUSE_BUTTON_MIDDLE:
				pipette()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var d := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
				if mb.alt_pressed:
					_cycle_recent(d)
				elif mb.shift_pressed:
					adjust_thick(d)
				else:
					adjust_height(d)
		return
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		var handled := true
		if k.ctrl_pressed and k.keycode == KEY_Z:
			if k.shift_pressed:
				redo()
			else:
				undo()
		elif k.ctrl_pressed and k.keycode == KEY_Y:
			redo()
		elif k.echo:
			handled = false
		elif k.keycode == KEY_B:
			set_active(false)
		elif k.keycode == KEY_TAB:
			open_panel()
		elif k.keycode >= KEY_1 and k.keycode <= KEY_9:
			select_shape(k.keycode - KEY_1)
		elif k.keycode == KEY_0:
			select_shape(9)
		elif k.keycode == KEY_R:
			if k.shift_pressed:
				toggle_mirror()
			else:
				rotate(1)
		elif k.keycode == KEY_V:
			if bp_i < 0:
				cycle_variant()
		elif k.keycode == KEY_X:
			cycle_mode()
		elif k.keycode == KEY_G:
			cycle_grid()
		elif k.keycode == KEY_P:
			cycle_blueprint()
		elif k.keycode == KEY_ESCAPE and dragging != 0:
			_cancel_drag()
		else:
			handled = false
		if handled:
			get_viewport().set_input_as_handled()

func _can_input() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.input_blocked and not hud.menu.visible and not hud.chat_open

func _cycle_recent(d: int) -> void:
	if recent.size() < 2:
		return
	var i: int = recent.find(mat)
	i = (i + d + recent.size()) % recent.size()
	mat = recent[i]
	hud.show_toast(mat_name(mat), 0.8)
	_after_change()

func _press(button: int) -> void:
	if aim.is_empty():
		return
	dragging = button
	var op := _op_for(button)
	var n: Vector3i = aim["normal"]
	var base: Vector3i = aim["voxel"] + n if op == 0 else aim["voxel"]
	if op == 3:
		base = aim["voxel"]
	drag = {"base": base, "n": n, "cur": base, "op": op}
	_place_key = ""
	if _drag_kind() == "stroke":
		_stroke = {"changes": PackedInt32Array(), "spent": {}, "refund": {}}
		_dab_t = 0.0
		_last_dab = Vector3i(-999999, 0, 0)

func _cancel_drag() -> void:
	if _drag_kind() == "stroke":
		_finish_stroke()
	dragging = 0
	drag = {}
	_place_key = ""
	marker.visible = false

func _release() -> void:
	if _drag_kind() == "stroke":
		_finish_stroke()
		dragging = 0
		drag = {}
		_place_key = ""
		return
	_compute(true)
	_commit()
	dragging = 0
	drag = {}
	_place_key = ""
	marker.visible = false

## 0 build, 1 subtract, 2 paint, 3 select (copy)
func _op_for(button: int) -> int:
	if mode == 1:
		return 2
	if mode == 2:
		return 3
	return 1 if button == 2 else 0

func _drag_kind() -> String:
	if bp_i >= 0:
		return "none"
	if mode == 2:
		return "rect"
	return str(shape()["drag"])

func pipette() -> void:
	if aim.is_empty():
		return
	var v: int = aim["value"]
	if v <= 0 or v >= 255:
		return
	var id := v >> 2
	var nm: String = str(vworld.materials.get(id, {}).get("name", ""))
	var ok := false
	for grp in PALETTE:
		if nm in grp[1]:
			ok = true
	if not ok:
		hud.show_toast("%s kann man nicht verbauen" % mat_name(id), 1.2)
		return
	set_material(id)
	hud.show_toast("Pipette: %s" % mat_name(id), 1.0)
	Sfx.play("click", null, -8.0)

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if not active:
		return
	_compute_t -= delta
	if test_mode:
		_compute(false)
		_update_visuals()
		ui.set_info(place)
		return
	if _panel_open or not _can_input():
		_hide_visuals()
		if not _panel_open and ui:
			ui.set_info(null)
		return
	aim = _aim()
	if not aim.is_empty():
		# start converting the aimed chunk to editable voxels in the background, so placing never hitches
		vworld.prewarm(vworld.chunk_of(aim["voxel"]))
	if dragging != 0 and _drag_kind() == "stroke":
		_dab_t -= delta
		if _dab_t <= 0.0 and not aim.is_empty():
			_dab()
	_compute(false)
	_update_visuals()
	ui.set_info(place)

func _ray() -> Array:
	var cam := get_viewport().get_camera_3d()
	var c := get_viewport().get_visible_rect().size * 0.5
	return [cam.project_ray_origin(c), cam.project_ray_normal(c)]

func _aim() -> Dictionary:
	var r := _ray()
	var from: Vector3 = r[0]
	var dir: Vector3 = r[1]
	# start the voxel ray at the player's distance (third-person camera behind the player)
	var skip := maxf(0.0, (player.global_position + Vector3(0, 1.2, 0) - from).dot(dir) - 1.2)
	from += dir * skip
	for t in [0.0, 8.0, 16.0, 24.0]:
		vworld.preload_near(from + dir * t)
	var h: Dictionary = vworld.vol.raycast(from, dir, RANGE, false)
	if not h.get("hit", false):
		return {}
	return {"voxel": h["voxel"], "normal": h["normal"], "point": h["point"], "value": int(h["value"]), "from": from, "dir": dir}

## camera direction quantised: quarter turns so that local +z points away from the camera
func _cam_q() -> int:
	var f: Vector3 = -cam_rig.global_transform.basis.z
	if absf(f.x) > absf(f.z):
		return 3 if f.x > 0.0 else 1
	return 0 if f.z > 0.0 else 2

static func _axis_of(n: Vector3i) -> int:
	if n.x != 0:
		return 0
	if n.y != 0:
		return 1
	return 2

static func _comp(v: Vector3i, a: int) -> int:
	return v.x if a == 0 else (v.y if a == 1 else v.z)

static func _with(v: Vector3i, a: int, val: int) -> Vector3i:
	if a == 0:
		v.x = val
	elif a == 1:
		v.y = val
	else:
		v.z = val
	return v

func _snap_lo(x: int) -> int:
	var g := grid()
	return floori(float(x) / g) * g if g > 1 else x

## ray of the camera intersected with the drag plane (voxel coords), or the last value
func _drag_cell() -> Vector3i:
	if test_mode and test_cur.x > -999999:
		drag["cur"] = test_cur
		return test_cur
	var base: Vector3i = drag["base"]
	var n: Vector3i = drag["n"]
	var ax := _axis_of(n)
	var r := _ray()
	var from: Vector3 = r[0]
	var dir: Vector3 = r[1]
	var plane_w: float = vworld.origin[ax] + (_comp(base, ax) + 0.5) * vworld.vs
	var dc: float = dir[ax]
	if absf(dc) < 0.02:
		return drag["cur"]
	var t := (plane_w - from[ax]) / dc
	if t <= 0.0 or t > 60.0:
		return drag["cur"]
	var p := from + dir * t
	var c: Vector3i = vworld.to_voxel(p)
	c = _with(c, ax, _comp(base, ax))
	# limit the footprint to the maximum shape size
	var m := max_size() - 1
	c = Vector3i(clampi(c.x, base.x - m, base.x + m), clampi(c.y, base.y - m, base.y + m), clampi(c.z, base.z - m, base.z + m))
	drag["cur"] = c
	return c

# ---------------------------------------------------------------- placement
## builds `place` = {op, lo, ext, obj, q, valid, reason, cost, count, refund_hint, key}
func _compute(force: bool) -> void:
	var kind := _drag_kind()
	if aim.is_empty() and (dragging == 0 or kind == "stroke"):
		place = {}
		_place_key = ""
		return
	var op: int = drag["op"] if dragging != 0 else _op_for(1)
	var n: Vector3i = drag["n"] if dragging != 0 else aim["normal"]
	var ax := _axis_of(n)
	var sgn := _comp(n, ax)
	var base: Vector3i
	if dragging != 0 and kind != "stroke":
		base = drag["base"]
	else:
		base = aim["voxel"] + n if op == 0 else aim["voxel"]
		if op == 3:
			base = aim["voxel"]
	var id := shape_id()
	var L: Vector3i = Vector3i(16, 16, 16) if id == "bauplan" else sizes.get(id, Vector3i(16, 16, 16))
	var m := max_size()
	L = Vector3i(mini(L.x, m), mini(L.y, m), mini(L.z, m))
	var q := (_cam_q() + rot_off) % 4
	var ext := Vector3i.ZERO
	var lo := Vector3i.ZERO
	var bp_obj: VoxelObject = null
	if id == "bauplan" and op != 3:
		bp_obj = _blueprint_object(q)
		if bp_obj == null:
			place = {}
			return
		ext = bp_obj.get_size()
	var cur: Vector3i = _drag_cell() if dragging != 0 and kind != "stroke" else base
	var dragged := dragging != 0 and kind != "stroke" and kind != "none" and cur != base
	var depth := L.y if ax == 1 else L.z
	if bp_obj != null:
		depth = _comp(ext, ax)
	if dragged and kind == "line" and ax == 1:
		# wall along the dominant drag direction, thickness centred on the start
		var dx := cur.x - base.x
		var dz := cur.z - base.z
		var along := 0 if absi(dx) >= absi(dz) else 2
		var a0 := mini(_comp(base, along), _comp(cur, along))
		var a1 := maxi(_comp(base, along), _comp(cur, along))
		if grid() > 1:
			a0 = _snap_lo(a0)
			a1 = _snap_lo(a1 + grid()) - 1
		var other := 2 if along == 0 else 0
		var t := L.z
		var o0 := _snap_lo(_comp(base, other) - t / 2) if grid() > 1 else _comp(base, other) - t / 2
		lo = _with(_with(lo, along, a0), other, o0)
		ext = _with(_with(ext, along, a1 - a0 + 1), other, t)
		ext.y = L.y
		lo.y = base.y
		q = 0 if along == 0 else 1
		if (q == 0 and _cam_q() == 2) or (q == 1 and _cam_q() == 3):
			q += 2
	elif dragged:
		for a in 3:
			if a == ax:
				continue
			var a0 := mini(_comp(base, a), _comp(cur, a))
			var a1 := maxi(_comp(base, a), _comp(cur, a))
			if grid() > 1 and not (a == 1 and ax != 1):
				a0 = _snap_lo(a0)
				a1 = _snap_lo(a1 + grid()) - 1
			lo = _with(lo, a, a0)
			ext = _with(ext, a, a1 - a0 + 1)
		ext = _with(ext, ax, depth)
		if ax != 1:
			# rectangle on a wall: local depth runs into / out of the wall
			var need_odd := ax == 0
			if (q % 2 == 1) != need_odd:
				q = (q + 1) % 4
	else:
		if bp_obj == null:
			ext = Vector3i(L.z, L.y, L.x) if q % 2 == 1 else L
			if ax != 1 and kind != "stroke":
				var need_odd2 := ax == 0
				if (q % 2 == 1) != need_odd2:
					q = (q + 1) % 4
					ext = Vector3i(L.z, L.y, L.x) if q % 2 == 1 else L
		for a in 3:
			if a == ax and kind != "stroke":
				continue
			var e := _comp(ext, a)
			var l0 := _comp(base, a) - e / 2
			if grid() > 1 and kind != "stroke" and not (a == 1) and a != ax:
				l0 = _snap_lo(l0 + grid() / 2)
			lo = _with(lo, a, l0)
	if kind == "stroke":
		# brush dabs are centred on the surface so they blend into it
		for a in 3:
			lo = _with(lo, a, _comp(base, a) - _comp(ext, a) / 2)
	else:
		var e_ax := _comp(ext, ax)
		if op == 0 or op == 3:
			lo = _with(lo, ax, _comp(base, ax) if sgn > 0 else _comp(base, ax) - e_ax + 1)
		else:
			lo = _with(lo, ax, _comp(base, ax) - e_ax + 1 if sgn > 0 else _comp(base, ax))
	var key := "%d|%s|%s|%s|%s|%d|%d|%d|%d|%d|%d|%s|%s|%d|%d|%s|%d" % [op, id, str(variants.get(id, 0)), str(lo), str(ext), q, int(mirror),
		mat, mat2, pattern(), int(foundation), str(sizes.get(id)), str(thicks.get(id)), bp_i, Game.blueprints.size(), str(n), int(glass_windows)]
	if key == _place_key and not force:
		return
	var vol_n := ext.x * ext.y * ext.z
	if not force and vol_n > 250000 and _compute_t > 0.0:
		return
	_compute_t = 0.12
	_place_key = key
	place = {"op": op, "lo": lo, "ext": ext, "q": q, "n": n, "valid": true, "reason": "", "cost": {}, "count": 0, "id": id}
	if op == 3:
		place["count"] = 0
		return
	# the object in local orientation, then rotated into the world
	var obj: VoxelObject
	if bp_obj != null:
		obj = bp_obj
	else:
		var Ls := Vector3i(ext.z, ext.y, ext.x) if q % 2 == 1 else ext
		obj = _make_shape(Ls, lo)
		if mirror:
			obj.mirror_x()
		obj.rotate_y(q)
	if op == 0 and ax == 1 and sgn > 0 and foundation and not shape().get("nofound", false) and bp_i < 0 and kind != "stroke":
		var fr: Dictionary = vworld.vol.foundation(obj, lo, 64)
		if int(fr.get("shift", 0)) > 0:
			obj = fr["object"]
			lo.y -= int(fr["shift"])
			place["lo"] = lo
			place["found"] = int(fr["shift"])
	if id != "haus" and bp_obj == null:
		obj.paint_all(mat_value(mat), pattern(), lo)
	place["obj"] = obj
	ext = obj.get_size()
	place["ext"] = ext
	if not vworld.in_area(lo) or not vworld.in_area(lo + ext - Vector3i.ONE):
		place["valid"] = false
		place["reason"] = "Hier kann nicht gebaut werden"
		return
	var total := obj.solid_count()
	var overlap: int = vworld.vol.count_overlap(obj, lo)
	match op:
		0:
			var placed := total - overlap
			place["count"] = placed
			if placed <= 0:
				place["valid"] = false
				place["reason"] = "Alles schon belegt"
				return
			if id == "haus" or bp_obj != null:
				place["cost"] = cost_of_counts(obj.value_counts())
				place["upper"] = true
			else:
				var c := PackedInt32Array()
				c.resize(256)
				c[mat_value(mat)] = placed
				place["cost"] = cost_of_counts(c)
			if not Game.can_afford(place["cost"]):
				place["valid"] = false
				place["reason"] = "Zu wenig Material"
			elif _hits_player(obj, lo):
				place["valid"] = false
				place["reason"] = "Du stehst im Weg"
		1:
			place["count"] = overlap
			if overlap <= 0:
				place["valid"] = false
				place["reason"] = "Hier ist nichts zum Abziehen"
		2:
			place["count"] = overlap
			var c2 := PackedInt32Array()
			c2.resize(256)
			c2[mat_value(mat)] = overlap
			place["cost"] = cost_of_counts(c2)
			if overlap <= 0:
				place["valid"] = false
				place["reason"] = "Nichts zum Färben"
			elif not Game.can_afford(place["cost"]):
				place["valid"] = false
				place["reason"] = "Zu wenig Material"

func _hits_player(obj: VoxelObject, lo: Vector3i) -> bool:
	var p: Vector3i = vworld.to_voxel(player.global_position)
	var sz := obj.get_size()
	for dy in range(1, 14, 2):
		for dx in [-2, 0, 2]:
			for dz in [-2, 0, 2]:
				var c := p + Vector3i(dx, dy, dz) - lo
				if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= sz.x or c.y >= sz.y or c.z >= sz.z:
					continue
				if obj.get_voxel(c) != 0:
					return true
	return false

func _params() -> Dictionary:
	var v := variant()
	var id: String = shape()["id"]
	var p := {"hollow": v.get("hollow", false), "thick": int(thicks.get(id, 2)), "open_top": v.get("open_top", false),
		"open_bottom": v.get("open_bottom", false), "half": v.get("half", false), "step": 2,
		"fill_under": v.get("fill_under", true), "crenel": int(v.get("crenel", 0))}
	return p

## local-space shape (x = width, y = height, z = depth); `lo` only matters for world-aligned patterns
func _make_shape(L: Vector3i, lo: Vector3i) -> VoxelObject:
	var o: VoxelObject = vworld.new_object()
	var s := shape()
	var v := variant()
	var kind: int = int(v.get("kind", s["kind"]))
	var p := _params()
	if str(s["id"]) == "haus":
		return _make_house(L, lo)
	if v.get("arch", false):
		# wall with a round gate in the middle
		var gw := clampi(int(L.x / 3.0), 8, 24)
		p["thick"] = maxi(1, (L.x - gw) / 2)
		p["top"] = clampi(L.y / 4, 2, 8)
	o.fill_shape(kind, L, p, mat_value(mat))
	return o

func _make_house(L: Vector3i, lo: Vector3i) -> VoxelObject:
	var v := variant()
	var t: int = int(thicks.get("haus", 2))
	var W := maxi(L.x, 12)
	var D := maxi(L.z, 12)
	var H := maxi(L.y, 10)
	var ov := 2 if mini(W, D) >= 20 else 1
	var flat: bool = v.get("flat", false)
	var half: bool = v.get("half", false)
	var RH := 2 if flat else clampi(int(round(D * (0.55 if half else 0.42))), 4, 48)
	var o: VoxelObject = vworld.new_object()
	o.create(Vector3i(W, H + RH, D))
	var wall_v := mat_value(mat)
	var roof_v := mat_value(mat2)
	var planks := mat_value(int(vworld.mat_ids.get("planks", 12)))
	# walls (with floor) in the main material and pattern
	var walls: VoxelObject = vworld.new_object()
	walls.fill_shape(0, Vector3i(W - 2 * ov, H, D - 2 * ov), {"hollow": true, "thick": t, "open_top": true}, wall_v)
	walls.paint_all(wall_v, pattern(), lo + Vector3i(ov, 0, ov))
	o.blit(walls, Vector3i(ov, 0, ov), 0)
	var floor_o: VoxelObject = vworld.new_object()
	floor_o.fill_shape(0, Vector3i(W - 2 * ov - 2 * t, 1, D - 2 * ov - 2 * t), {}, planks)
	floor_o.paint_all(planks, 3, lo + Vector3i(ov + t, 0, ov + t))
	o.blit(floor_o, Vector3i(ov + t, 0, ov + t), 0)
	# gable ends under the roof
	if not flat:
		var gable: VoxelObject = vworld.new_object()
		var gh := int(RH * (D - 2 * ov) / float(D)) if half else RH
		gable.fill_shape(5, Vector3i(W - 2 * ov, gh, D - 2 * ov), {"half": half}, wall_v)
		var cut: VoxelObject = vworld.new_object()
		cut.fill_shape(0, Vector3i(maxi(1, W - 2 * ov - 2 * t), gh, D - 2 * ov), {}, wall_v)
		gable.blit(cut, Vector3i(t, 0, 0), 2)
		gable.paint_all(wall_v, pattern(), lo + Vector3i(ov, H, ov))
		o.blit(gable, Vector3i(ov, H, ov), 0)
	# roof
	var roof: VoxelObject = vworld.new_object()
	if flat:
		roof.fill_shape(0, Vector3i(W, 2, D), {}, roof_v)
	else:
		roof.fill_shape(5, Vector3i(W, RH, D), {"hollow": true, "thick": 2, "half": half}, roof_v)
	roof.paint_all(roof_v, 3 if not flat else 1, lo + Vector3i(0, H, 0))
	o.blit(roof, Vector3i(0, H, 0), 0)
	# door in the wall facing the camera (local z = ov), windows on the other walls
	var dw := 8 if W >= 24 else 6
	var dh := clampi(H - 4, 6, 17)
	var door: VoxelObject = vworld.new_object()
	door.fill_shape(0, Vector3i(dw, dh, t), {}, 1)
	o.blit(door, Vector3i(W / 2 - dw / 2, 1, ov), 2)
	if H >= 14:
		var wy := clampi(H / 2 - 2, 4, H - 7)
		var wsz := 6
		var win: VoxelObject = vworld.new_object()
		win.fill_shape(0, Vector3i(wsz, wsz, t), {}, mat_value(int(vworld.mat_ids.get("glass", 60))))
		var win_x: VoxelObject = vworld.new_object()
		win_x.fill_shape(0, Vector3i(t, wsz, wsz), {}, mat_value(int(vworld.mat_ids.get("glass", 60))))
		var mode_w := 0 if glass_windows else 2
		# front wall: left and right of the door
		for xw in [ov + t + 4, W - ov - t - 4 - wsz]:
			if absi(xw + wsz / 2 - W / 2) > dw / 2 + wsz:
				o.blit(win, Vector3i(xw, wy, ov), mode_w)
		# back wall
		var step := 22
		var x0 := ov + t + 6
		while x0 + wsz <= W - ov - t - 4:
			o.blit(win, Vector3i(x0, wy, D - ov - t), mode_w)
			x0 += step
		# side walls
		var z0 := ov + t + 6
		while z0 + wsz <= D - ov - t - 4:
			o.blit(win_x, Vector3i(ov, wy, z0), mode_w)
			o.blit(win_x, Vector3i(W - ov - t, wy, z0), mode_w)
			z0 += step
	return o

func _blueprint_object(q: int) -> VoxelObject:
	if bp_i < 0 or bp_i >= Game.blueprints.size():
		return null
	var b: Dictionary = Game.blueprints[bp_i]
	var o: VoxelObject = vworld.new_object()
	var sz: Array = b["size"]
	o.set_data(Vector3i(int(sz[0]), int(sz[1]), int(sz[2])), b["data"])
	if mirror:
		o.mirror_x()
	o.rotate_y((q - int(b.get("q", 0)) + 4) % 4)
	return o

# ---------------------------------------------------------------- visuals
const C_OK := Color(0.55, 1.0, 0.62)
const C_BAD := Color(1.0, 0.36, 0.3)
const C_SUB := Color(1.0, 0.58, 0.22)
const C_PAINT := Color(0.45, 0.72, 1.0)
const C_SEL := Color(0.4, 0.85, 1.0)

func state_color() -> Color:
	if place.is_empty():
		return C_OK
	match int(place["op"]):
		1:
			return C_SUB if place["valid"] else C_BAD
		2:
			return C_PAINT if place["valid"] else C_BAD
		3:
			return C_SEL
	return C_OK if place["valid"] else C_BAD

var _ghost_key := ""

func _update_visuals() -> void:
	if place.is_empty():
		_hide_visuals()
		return
	var lo: Vector3i = place["lo"]
	var ext: Vector3i = place["ext"]
	var col := state_color()
	var op: int = place["op"]
	# ghost mesh
	if place.has("obj"):
		if _ghost_key != _place_key:
			_ghost_key = _place_key
			var obj: VoxelObject = place["obj"]
			var d: Dictionary = obj.mesh(0, false, Vector3.ZERO)
			ghost.mesh = vworld.array_mesh(d, ghost_mat) if not d.is_empty() else null
		ghost.global_position = vworld.to_world(lo)
		ghost.visible = ghost.mesh != null
		ghost_mat.set_shader_parameter("tint", col)
		ghost_mat.set_shader_parameter("solid_colors", op == 0 or op == 2)
		ghost_mat.set_shader_parameter("tint_mix", 0.18 if (op == 0 and place["valid"]) else 0.55)
		ghost_mat.set_shader_parameter("alpha", 0.62 if op == 0 else 0.4)
		ghost_mat.set_shader_parameter("height", ext.y * vworld.vs)
		xray_mat.set_shader_parameter("tint", col)
		xray_mat.set_shader_parameter("strength", 0.22 if op == 1 else 0.12)
	else:
		ghost.visible = false
	# wire box + size label
	var a: Vector3 = vworld.to_world(lo)
	var b: Vector3 = vworld.to_world(lo + ext)
	_draw_box(a, b, col)
	wire.visible = true
	var e: Vector3 = Vector3(ext) * float(vworld.vs)
	dim_label.text = "%s × %s × %s m" % [_m(e.x), _m(e.y), _m(e.z)]
	dim_label.global_position = Vector3((a.x + b.x) * 0.5, b.y + 0.35, (a.z + b.z) * 0.5)
	dim_label.modulate = col.lerp(Color.WHITE, 0.55)
	dim_label.visible = true
	if dragging != 0 and drag.has("base") and _drag_kind() != "stroke":
		marker.visible = true
		marker.global_position = vworld.to_world(drag["base"]) + Vector3.ONE * vworld.vs * 0.5
	else:
		marker.visible = false

func _m(v: float) -> String:
	var s := "%.2f" % v
	if s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return s.replace(".", ",")

func _draw_box(a: Vector3, b: Vector3, col: Color) -> void:
	wire_mesh.clear_surfaces()
	wire_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var c := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	var cc := Color(col.r, col.g, col.b, 0.85)
	for e in edges:
		wire_mesh.surface_set_color(cc)
		wire_mesh.surface_add_vertex(c[e[0]])
		wire_mesh.surface_set_color(cc)
		wire_mesh.surface_add_vertex(c[e[1]])
	# ticks every metre on the bottom edges (helps judging sizes)
	var tick := Color(col.r, col.g, col.b, 0.55)
	for axis in [0, 2]:
		var len: float = (b - a)[axis]
		var steps := int(len)
		for i in range(1, steps + 1):
			if float(i) >= len - 0.01:
				break
			var p := a
			p[axis] += i
			var d := Vector3(0, 0.12, 0)
			wire_mesh.surface_set_color(tick)
			wire_mesh.surface_add_vertex(p)
			wire_mesh.surface_set_color(tick)
			wire_mesh.surface_add_vertex(p + d)
	wire_mesh.surface_end()

# ---------------------------------------------------------------- commit
func _commit() -> void:
	if place.is_empty():
		return
	var op: int = place["op"]
	if op == 3:
		_copy_blueprint()
		return
	if not place["valid"]:
		hud.show_toast(place["reason"], 1.4)
		Sfx.play("clink", null, -6.0)
		return
	var obj: VoxelObject = place["obj"]
	var lo: Vector3i = place["lo"]
	var entry := _apply(obj, lo, op, true)
	if entry.is_empty():
		return
	_push_undo(entry)
	_fx(entry, op)

## applies an object to the world, books resources, sends it to the other players
func _apply(obj: VoxelObject, lo: Vector3i, op: int, net: bool) -> Dictionary:
	var vmode := 0 if op == 0 else (1 if op == 1 else 2)
	var pat := -1 if op == 0 else pattern()
	var r: Dictionary = vworld.apply_object(obj, lo, vmode, pat, false)
	var changes: PackedInt32Array = r.get("changes", PackedInt32Array())
	if changes.is_empty():
		return {}
	var counts: PackedInt32Array = r["counts"]
	var spent := {}
	var refund := {}
	match op:
		0:
			spent = cost_of_counts(counts)
			Game.spend(spent)
			Game.stats["built"] = int(Game.stats.get("built", 0)) + changes.size() / 5
			Game.add_xp(maxi(1, (changes.size() / 5) / 250))
		1:
			refund = refund_of_counts(counts)
			for res in refund:
				Game.add(res, int(refund[res]))
		2:
			spent = cost_of_counts(counts)
			Game.spend(spent)
			if changes.size() / 5 < 300000:
				var old := PackedInt32Array()
				old.resize(256)
				for i in range(3, changes.size(), 5):
					old[changes[i]] += 1
				refund = refund_of_counts(old)
				for res in refund:
					Game.add(res, int(refund[res]), true)
	if net:
		var data := obj.get_data()
		main.net_op({"op": "obj", "d": data.compress(FileAccess.COMPRESSION_ZSTD), "raw": data.size(), "sz": obj.get_size(),
			"at": lo, "m": vmode, "pt": pat})
	Game.quests_changed.emit()
	return {"changes": changes, "spent": spent, "refund": refund}

func _fx(entry: Dictionary, op: int) -> void:
	var changes: PackedInt32Array = entry["changes"]
	var n := changes.size() / 5
	var step := maxi(1, n / 28)
	var center := Vector3.ZERO
	var k := 0
	var i := 0
	while i < n:
		var p: Vector3 = vworld.to_world(Vector3i(changes[i * 5], changes[i * 5 + 1], changes[i * 5 + 2])) + Vector3.ONE * 0.0625
		center += p
		k += 1
		var v: int = changes[i * 5 + (4 if op != 1 else 3)]
		if op == 1:
			tools.debris.spawn(p, v, Vector3.UP, vworld.processed[v] == 1, 0.8, 0.9)
		else:
			tools.debris.spawn(p, v, Vector3.UP, false, 0.35, 0.55)
		i += step
	if k > 0:
		center /= k
	Sfx.play("place" if op == 0 else ("remove" if op == 1 else "click"), center, -2.0)
	if player.anim:
		player.anim.attack()
	cam_rig.add_shake(0.04)
	if op == 1:
		tools._check_treasure(center)

func _push_undo(entry: Dictionary) -> void:
	undo_stack.append(entry)
	redo_stack.clear()
	var total := 0
	for e in undo_stack:
		total += (e["changes"] as PackedInt32Array).size()
	while undo_stack.size() > UNDO_MAX or (total > 12000000 and undo_stack.size() > 1):
		total -= (undo_stack[0]["changes"] as PackedInt32Array).size()
		undo_stack.pop_front()

func undo() -> void:
	if undo_stack.is_empty():
		hud.show_toast("Nichts mehr rückgängig zu machen", 1.0)
		return
	var e: Dictionary = undo_stack.pop_back()
	vworld.apply_changes(e["changes"], 3)
	Game.add_many(e["spent"])
	_take_back(e["refund"])
	redo_stack.append(e)
	_send_changes(e["changes"], 3)
	Sfx.play("whoosh", null, -8.0)
	hud.show_toast("Rückgängig", 0.7)
	_place_key = ""

func redo() -> void:
	if redo_stack.is_empty():
		hud.show_toast("Nichts zum Wiederholen", 1.0)
		return
	var e: Dictionary = redo_stack.back()
	if not Game.can_afford(e["spent"]):
		hud.show_toast("Zu wenig Material zum Wiederholen", 1.4)
		return
	redo_stack.pop_back()
	vworld.apply_changes(e["changes"], 4)
	Game.spend(e["spent"])
	Game.add_many(e["refund"])
	undo_stack.append(e)
	_send_changes(e["changes"], 4)
	Sfx.play("place", null, -8.0)
	hud.show_toast("Wiederholt", 0.7)
	_place_key = ""

func _take_back(d: Dictionary) -> void:
	for r in d:
		Game.inv[r] = maxi(0, Game.count(r) - int(d[r]))
	Game.inventory_changed.emit()

func _send_changes(changes: PackedInt32Array, column: int) -> void:
	if not Net.active():
		return
	var b := changes.to_byte_array()
	main.net_op({"op": "chg", "d": b.compress(FileAccess.COMPRESSION_ZSTD), "raw": b.size(), "c": column})

# ---------------------------------------------------------------- brush strokes
func _dab() -> void:
	var c: Vector3i = aim["voxel"]
	var r := maxi(1, int(sizes["pinsel"].x) / 2)
	var moved := (c - _last_dab).length_squared() >= maxi(1, r * r / 4)
	if not moved and Time.get_ticks_msec() - int(_stroke.get("t", 0)) < 160:
		_dab_t = 0.03
		return
	_dab_t = 0.05
	_last_dab = c
	_place_key = ""
	_compute(true)
	if place.is_empty() or not place.has("obj"):
		return
	if not place["valid"]:
		if place["reason"] == "Zu wenig Material":
			hud.show_toast(place["reason"], 1.0)
		return
	var entry := _apply(place["obj"], place["lo"], place["op"], true)
	if entry.is_empty():
		return
	_stroke["changes"] = (_stroke["changes"] as PackedInt32Array) + (entry["changes"] as PackedInt32Array)
	for k in ["spent", "refund"]:
		var acc: Dictionary = _stroke[k]
		for res in entry[k]:
			acc[res] = int(acc.get(res, 0)) + int(entry[k][res])
	_stroke["n"] = int(_stroke.get("n", 0)) + 1
	_stroke["t"] = Time.get_ticks_msec()
	if int(_stroke["n"]) % 3 == 1:
		Sfx.play("dig" if place["op"] != 2 else "click", vworld.to_world(c), -8.0, 0.2)
	var ch: PackedInt32Array = entry["changes"]
	if ch.size() >= 5:
		var k2 := (randi() % (ch.size() / 5)) * 5
		tools.debris.spawn(vworld.to_world(Vector3i(ch[k2], ch[k2 + 1], ch[k2 + 2])), ch[k2 + 3 if place["op"] == 1 else k2 + 4], Vector3.UP, false, 0.4, 0.6)

func _finish_stroke() -> void:
	if not _stroke.is_empty() and not (_stroke["changes"] as PackedInt32Array).is_empty():
		_push_undo({"changes": _stroke["changes"], "spent": _stroke["spent"], "refund": _stroke["refund"]})
	_stroke = {}

# ---------------------------------------------------------------- blueprints
func _copy_blueprint() -> void:
	var lo: Vector3i = place["lo"]
	var ext: Vector3i = place["ext"]
	if Game.blueprints.size() >= Game.blueprint_slots():
		hud.show_toast("Bauplan-Speicher voll (%d) – im Baukasten (Tab) löschen oder Talent „Baupläne“" % Game.blueprint_slots(), 2.6)
		Sfx.play("clink", null, -6.0)
		return
	vworld.prepare(lo, lo + ext - Vector3i.ONE)
	var o: VoxelObject = vworld.vol.copy_region(lo, ext)
	if only_built:
		var keep := PackedByteArray()
		keep.resize(256)
		for v in 256:
			keep[v] = vworld.processed[v]
		o.filter_values(keep)
	o.trim()
	var n := o.solid_count()
	if n == 0:
		hud.show_toast("Da ist nichts Gebautes drin" if only_built else "Leere Auswahl", 1.6)
		return
	var sz := o.get_size()
	var name := "Bauplan %d" % (Game.blueprints.size() + 1)
	Game.blueprints.append({"name": name, "size": [sz.x, sz.y, sz.z], "data": o.get_data(), "q": (_cam_q() + rot_off) % 4})
	Game.notify.emit("%s gespeichert (%d Voxel)" % [name, n], Color(0.6, 0.85, 1.0))
	Sfx.play("pickup", null, -4.0)
	bp_i = Game.blueprints.size() - 1
	mode = 0
	_after_change()

func delete_blueprint(i: int) -> void:
	if i < 0 or i >= Game.blueprints.size():
		return
	Game.blueprints.remove_at(i)
	if bp_i >= Game.blueprints.size():
		bp_i = -1
	_after_change()

func rename_blueprint(i: int, name: String) -> void:
	if i >= 0 and i < Game.blueprints.size() and name.strip_edges() != "":
		Game.blueprints[i]["name"] = name.strip_edges()
		changed.emit()

# ---------------------------------------------------------------- network
## an op from another player: apply it exactly like they did (no resources booked here)
func apply_remote(op: Dictionary) -> void:
	match str(op.get("op", "")):
		"obj":
			var o: VoxelObject = vworld.new_object()
			var raw: PackedByteArray = (op["d"] as PackedByteArray).decompress(int(op["raw"]), FileAccess.COMPRESSION_ZSTD)
			o.set_data(op["sz"], raw)
			vworld.apply_object(o, op["at"], int(op["m"]), int(op["pt"]), false)
			_place_key = ""
		"chg":
			var b: PackedByteArray = (op["d"] as PackedByteArray).decompress(int(op["raw"]), FileAccess.COMPRESSION_ZSTD)
			vworld.apply_changes(b.to_int32_array(), int(op["c"]))
			_place_key = ""
