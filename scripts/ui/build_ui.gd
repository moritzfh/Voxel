extends Control
## HUD of the build mode: shape bar (replaces the hotbar), material + mode chips, info under the crosshair,
## key hints, and the construction kit panel (Tab) with every option.

const K := preload("res://scripts/ui/ui_kit.gd")

var b: Node                     # builder
var palette: Array = []         # linear colours per voxel value
var bar: Control
var slots: Array = []
var mode_chip: Control
var mode_icon: TextureRect
var mode_label: Label
var mat_chip: Control
var mat_swatch: Control
var mat_label: Label
var mat_sub: Label
var shape_title: Label
var info_title: Label
var info_dims: Label
var info_cost: Label
var hints: Control
var hint_label: Label
var kit: Control
var kit_body: Control
var _hotbar: Control
var _icons := {}

func setup(builder: Node) -> void:
	b = builder
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pal = (b.vworld.vmat as ShaderMaterial).get_shader_parameter("palette")
	for v in pal:
		palette.append(Color(v.x, v.y, v.z).linear_to_srgb())
	for s in b.SHAPES:
		_icons[s["id"]] = load("res://assets/ui/shape_%s.png" % s["id"])
	for n in ["bauplan", "faerben", "kopieren"]:
		_icons[n] = load("res://assets/ui/shape_%s.png" % n)
	_icons["bauen"] = load("res://assets/ui/icon_hammer.png")
	if b.hud.slot_panels.size() > 0:
		_hotbar = b.hud.slot_panels[0].get_parent()
	_build_bar()
	_build_info()
	_build_hints()
	_build_kit()
	visible = false
	b.changed.connect(refresh)
	b.mode_toggled.connect(func(on: bool):
		visible = on
		if _hotbar:
			_hotbar.visible = not on
		refresh())
	Game.inventory_changed.connect(func():
		if visible:
			_refresh_chips()
			if kit.visible:
				_rebuild_kit())
	Game.talents_changed.connect(refresh)

# ---------------------------------------------------------------- colours / patterns
func mat_color(id: int, variant := 0) -> Color:
	var v := (id << 2) | variant
	if v < palette.size():
		return palette[v]
	return Color(0.5, 0.5, 0.5)

static func _h(x: int, y: int, s: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff

static func pattern_variant(p: int, x: int, y: int) -> int:
	match p:
		1:
			return 0
		2:
			var row := y / 2
			var along := x + (row & 1) * 2
			if y % 2 == 0 and along % 3 == 0:
				return 3
			return _h(row, along / 3, 51) % 3
		3:
			return 1 if (y / 2) & 1 else 0
		4:
			return 2 if (x + y) & 1 else 0
		5:
			return _h(x, y, 77) % 4
	var v := _h(x / 2, y / 2, 61) % 3
	return 3 if _h(x, y, 62) % 50 == 0 else v

## draws a little wall of voxels in the material and pattern
func draw_swatch(c: Control, r: Rect2, id: int, p: int, cells := 8) -> void:
	var cs := r.size.x / cells
	var rows := int(r.size.y / cs)
	for y in rows:
		for x in cells:
			var col := mat_color(id, pattern_variant(p, x, rows - 1 - y))
			c.draw_rect(Rect2(r.position + Vector2(x * cs, y * cs), Vector2(cs, cs)), col)
			c.draw_rect(Rect2(r.position + Vector2(x * cs, y * cs), Vector2(cs, cs)), Color(0, 0, 0, 0.12), false, 1.0)
	c.draw_rect(r, Color(0, 0, 0, 0.6), false, 1.5)

# ---------------------------------------------------------------- bottom bar
func _build_bar() -> void:
	var n: int = b.SHAPES.size() + 1
	var sw := 72.0
	var gap := 7.0
	var slots_w := n * sw + (n - 1) * gap
	var total := 168.0 + 18.0 + slots_w + 18.0 + 268.0
	bar = Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -total * 0.5
	bar.offset_top = -64 - 112
	bar.size = Vector2(total, 112)
	# mode chip
	mode_chip = K.panel(bar, Rect2(0, 0, 168, 76))
	mode_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_icon = TextureRect.new()
	mode_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mode_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	K.put(mode_chip, mode_icon, Vector2(8, 8), Vector2(58, 58))
	mode_label = K.label("Bauen", K.F_HEAD, 21)
	K.put(mode_chip, mode_label, Vector2(72, 12))
	var ml := K.label("Modus", K.F_BODY, 16, K.CREAM_DIM)
	K.put(mode_chip, ml, Vector2(73, 40))
	K.key_cap(bar, "X", Vector2(84 - 13, 82))
	# shape slots
	var x0 := 168.0 + 18.0
	for i in n:
		var x := x0 + i * (sw + gap)
		var p := K.panel(bar, Rect2(x, 0, sw, 76))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.corner_size = 4.0
		var ic := TextureRect.new()
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.texture = _icons["bauplan"] if i == n - 1 else _icons[b.SHAPES[i]["id"]]
		K.put(p, ic, Vector2(7, 6), Vector2(58, 58))
		var lock := Control.new()
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.size = Vector2(sw, 76)
		lock.draw.connect(func():
			lock.draw_rect(Rect2(Vector2.ZERO, lock.size), Color(0.02, 0.03, 0.03, 0.55))
			var c := Vector2(sw - 16, 16)
			lock.draw_arc(c + Vector2(0, -3), 5.0, PI, TAU, 12, K.GOLD, 2.0)
			lock.draw_rect(Rect2(c + Vector2(-7, -2), Vector2(14, 11)), K.GOLD))
		p.add_child(lock)
		var key := "P" if i == n - 1 else str((i + 1) % 10)
		K.key_cap(bar, key, Vector2(x + sw * 0.5 - 13, 82))
		slots.append({"panel": p, "lock": lock})
	# material chip
	var mx := x0 + slots_w + 18.0
	mat_chip = K.panel(bar, Rect2(mx, 0, 268, 76))
	mat_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat_swatch = Control.new()
	mat_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat_swatch.draw.connect(func(): draw_swatch(mat_swatch, Rect2(Vector2.ZERO, mat_swatch.size), b.mat, b.pattern(), 6))
	K.put(mat_chip, mat_swatch, Vector2(10, 10), Vector2(56, 56))
	mat_label = K.label("Bruchstein", K.F_HEAD, 20)
	K.put(mat_chip, mat_label, Vector2(76, 8))
	mat_sub = K.label("", K.F_BODY, 16, K.CREAM_DIM)
	K.put(mat_chip, mat_sub, Vector2(77, 36))
	K.key_cap(bar, "Tab", Vector2(mx + 134 - 22, 82))
	# title of the selected shape above the bar
	shape_title = K.label("", K.F_HEAD, 21)
	shape_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shape_title.size = Vector2(600, 30)
	shape_title.position = Vector2(total * 0.5 - 300, -38)
	shape_title.add_theme_constant_override("outline_size", 6)
	shape_title.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.05, 0.8))
	bar.add_child(shape_title)

func _refresh_chips() -> void:
	var m: int = b.mode
	mode_icon.texture = _icons[["bauen", "faerben", "kopieren"][m]]
	mode_label.text = b.MODES[m]
	mat_label.text = b.mat_name(b.mat)
	var res: String = b.vworld.res_of(b.mat << 2)
	var per: float = b.per_voxel(b.mat)
	var have := Game.count(res)
	var ratio := "1 je Voxel" if per >= 1.0 else "1 je %d Voxel" % roundi(1.0 / per)
	mat_sub.text = "%s · %s %d" % [b.PATTERNS[b.pattern_sel] if b.pattern_sel > 0 else "Auto", b.res_name(res), have] if not Game.creative else "%s · Kreativ" % b.PATTERNS[b.pattern_sel]
	mat_chip.tooltip_text = ratio
	mat_swatch.queue_redraw()

func refresh() -> void:
	if not b:
		return
	_refresh_chips()
	var n := slots.size()
	for i in n:
		var p: Control = slots[i]["panel"]
		var sel := false
		var locked := false
		if i == n - 1:
			sel = b.bp_i >= 0 and b.mode == 0
			locked = Game.blueprints.is_empty()
		else:
			sel = b.shape_i == i and b.bp_i < 0 and b.mode != 2
			locked = not b.shape_unlocked(i)
		p.bg_color = Color(0.24, 0.30, 0.17, 0.95) if sel else Color(0.05, 0.09, 0.08, 0.9)
		p.bg_color_top = Color(0.36, 0.42, 0.22, 0.95) if sel else Color(0.09, 0.14, 0.12, 0.9)
		p.gold = Color(1.0, 0.86, 0.5) if sel else K.GOLD
		p.modulate = Color(1.15, 1.1, 1.0) if sel else Color.WHITE
		p.queue_redraw()
		slots[i]["lock"].visible = locked
	if b.mode == 2:
		shape_title.text = "Kopieren · Bereich ziehen → Bauplan"
	elif b.bp_i >= 0 and b.bp_i < Game.blueprints.size():
		shape_title.text = "Bauplan · %s  (P: nächster)" % Game.blueprints[b.bp_i]["name"]
	else:
		var s: Dictionary = b.shape()
		var vl: Array = s["variants"]
		shape_title.text = s["name"] + ("  ·  %s  (V)" % b.variant()["name"] if vl.size() > 1 else "")
	_refresh_hints()
	if kit.visible:
		_rebuild_kit()

# ---------------------------------------------------------------- info under the crosshair
func _build_info() -> void:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -320
	box.offset_top = 30
	box.size = Vector2(640, 90)
	info_title = K.label("", K.F_HEAD, 19)
	info_dims = K.label("", K.F_BODY, 18, K.CREAM_DIM)
	info_cost = K.label("", K.F_HEAD, 19)
	var y := 0.0
	for l in [info_title, info_cost, info_dims]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(640, 26)
		l.position = Vector2(0, y)
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.05, 0.75))
		box.add_child(l)
		y += 25.0

func set_info(place: Variant) -> void:
	if place == null or (place as Dictionary).is_empty():
		info_title.text = ""
		info_cost.text = ""
		info_dims.text = ""
		b.hud.set_target_info("", Color.WHITE, visible and not b._panel_open)
		return
	b.hud.set_target_info("", Color.WHITE, true)
	var p: Dictionary = place
	var op: int = p["op"]
	var col: Color = b.state_color()
	match op:
		0:
			info_title.text = "%d Voxel bauen" % int(p["count"]) if p["valid"] else str(p["reason"])
		1:
			info_title.text = "Abziehen: %d Voxel" % int(p["count"]) if p["valid"] else str(p["reason"])
		2:
			info_title.text = "Färben: %d Voxel" % int(p["count"]) if p["valid"] else str(p["reason"])
		3:
			info_title.text = "Bereich als Bauplan speichern (loslassen)" if b.dragging != 0 else "Ziehen, um einen Bereich zu markieren"
	info_title.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.35))
	var cost: Dictionary = p.get("cost", {})
	if op == 1:
		info_cost.text = "gibt verbaute Baustoffe zurück"
		info_cost.add_theme_color_override("font_color", K.CREAM_DIM)
	elif not cost.is_empty() and not Game.creative:
		var parts := []
		var ok := true
		for r in cost:
			var have := Game.count(r)
			parts.append("%d %s (%d)" % [int(cost[r]), b.res_name(r), have])
			if have < int(cost[r]):
				ok = false
		info_cost.text = ("bis " if p.get("upper", false) else "") + "Kosten: " + ", ".join(parts)
		info_cost.add_theme_color_override("font_color", K.GREEN if ok else K.RED)
	else:
		info_cost.text = ""
	var hint := ""
	if p.has("found"):
		hint = "  ·  Fundament %s m" % b._m(int(p["found"]) * 0.125)
	info_dims.text = ("R drehen · Mausrad Höhe" if b.dragging == 0 else "loslassen = fertig · andere Maustaste = abbrechen") + hint

# ---------------------------------------------------------------- key hints
func _build_hints() -> void:
	hints = Control.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hints)
	hints.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hints.position = Vector2(28, 206)
	hints.size = Vector2(330, 360)
	var p := K.panel(hints, Rect2(Vector2.ZERO, hints.size))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.bg_color.a = 0.72
	p.bg_color_top.a = 0.72
	var t := K.label("Bauen", K.F_TITLE, 22)
	K.put(p, t, Vector2(18, 10))
	hint_label = K.label("", K.F_BODY, 17, K.CREAM)
	hint_label.add_theme_constant_override("line_spacing", 1)
	K.put(p, hint_label, Vector2(18, 46), Vector2(300, 300))

func _refresh_hints() -> void:
	var lines := []
	var stroke: bool = b._drag_kind() == "stroke"
	match int(b.mode):
		0:
			if stroke:
				lines.append("Linke Maus halten:  malen")
				lines.append("Rechte Maus halten:  wegformen")
				lines.append("Mausrad:  Pinselgröße")
			else:
				lines.append("Linke Maus:  bauen (ziehen = Fläche)")
				lines.append("Rechte Maus:  ausschneiden")
				lines.append("Mausrad:  Höhe   ·   Shift: Stärke")
		1:
			lines.append("Linke Maus:  einfärben (ziehen)")
			lines.append("Mausrad:  Höhe der Form")
		2:
			lines.append("Linke Maus ziehen:  Bereich wählen")
			lines.append("Mausrad:  Höhe des Bereichs")
	lines.append("R:  drehen   ·   Shift+R:  spiegeln")
	lines.append("1–0:  Formen   ·   V:  Variante")
	lines.append("X:  Modus   ·   P:  Baupläne")
	lines.append("G:  Raster (%s)" % b.GRID_NAMES[b.grid_i])
	lines.append("Mittlere Maus:  Material aufnehmen")
	lines.append("Alt+Rad:  letzte Materialien")
	lines.append("Strg+Z / Strg+Y:  zurück / vor")
	lines.append("Tab:  Baukasten   ·   B:  fertig")
	hint_label.text = "\n".join(lines)
	hints.size.y = 60 + lines.size() * 25
	(hints.get_child(0) as Control).size.y = hints.size.y

# ---------------------------------------------------------------- construction kit (Tab)
func _build_kit() -> void:
	kit = Control.new()
	kit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	kit.mouse_filter = Control.MOUSE_FILTER_STOP
	kit.visible = false
	add_child(kit)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	kit.add_child(dim)
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -780
	box.offset_top = -430
	box.size = Vector2(1560, 860)
	kit.add_child(box)
	var p := K.panel(box, Rect2(Vector2.ZERO, box.size))
	var t := K.label("Baukasten", K.F_TITLE, 32)
	K.put(p, t, Vector2(30, 16))
	var sub := K.label("Alles was du hier einstellst, siehst du sofort in der Vorschau.  Tab / Esc schließt.", K.F_BODY, 18, K.CREAM_DIM)
	K.put(p, sub, Vector2(250, 28))
	K.button(p, "Schließen", Rect2(1400, 18, 136, 40), func(): b.close_panel())
	kit_body = Control.new()
	kit_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.put(p, kit_body, Vector2(0, 70), Vector2(1560, 790))

func show_panel(on: bool) -> void:
	kit.visible = on
	if on:
		_rebuild_kit()
		Sfx.play("click", null, -6.0)

func _section(x: float, y: float, w: float, title: String) -> float:
	var l := K.label(title, K.F_SC, 22, K.GOLD)
	K.put(kit_body, l, Vector2(x, y))
	K.separator(kit_body, Vector2(x, y + 32), w)
	return y + 44

func _rebuild_kit() -> void:
	for c in kit_body.get_children():
		c.queue_free()
	_kit_shapes(30, 0, 470)
	_kit_materials(530, 0, 560)
	_kit_options(1120, 0, 410)

func _kit_shapes(x: float, y: float, w: float) -> void:
	y = _section(x, y, w, "Formen")
	var n: int = b.SHAPES.size()
	for i in n:
		var s: Dictionary = b.SHAPES[i]
		var cx := x + (i % 5) * 94
		var cy := y + (i / 5) * 112
		var sel: bool = b.shape_i == i and b.bp_i < 0 and b.mode != 2
		var unlocked: bool = b.shape_unlocked(i)
		var btn := K.button(kit_body, "", Rect2(cx, cy, 86, 104), func(): b.select_shape(i), 16, sel)
		btn.tooltip_text = s["desc"] + ("" if unlocked else "\nTalent: " + Game.TALENTS[s["talent"]]["name"])
		var ic := TextureRect.new()
		ic.texture = _icons[s["id"]]
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.modulate = Color.WHITE if unlocked else Color(0.45, 0.45, 0.45)
		K.put(btn, ic, Vector2(13, 6), Vector2(60, 60))
		var nl := K.label(s["name"], K.F_HEAD, 17, K.CREAM if unlocked else K.CREAM_DIM)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		K.put(btn, nl, Vector2(0, 66), Vector2(86, 24))
		var kl := K.label(str((i + 1) % 10), K.F_HEAD, 14, K.GOLD)
		K.put(btn, kl, Vector2(6, 2))
	y += 236
	# variants of the current shape
	var s2: Dictionary = b.shape()
	var vl: Array = s2["variants"]
	var lv := K.label("Variante  (V)", K.F_HEAD, 19)
	K.put(kit_body, lv, Vector2(x, y))
	y += 30
	var vx := x
	for vi in vl.size():
		var v: Dictionary = vl[vi]
		var vw := 24.0 + K.F_HEAD.get_string_size(v["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		if vx + vw > x + w:
			vx = x
			y += 44
		var vb := K.button(kit_body, v["name"], Rect2(vx, y, vw, 38), func(): b.set_variant(vi), 18, int(b.variants[s2["id"]]) == vi and b.bp_i < 0)
		vb.disabled = not b.variant_unlocked(v)
		if vb.disabled:
			vb.tooltip_text = "Talent: " + Game.TALENTS[v["talent"]]["name"]
		vx += vw + 8
	y += 50
	var desc := K.label(s2["desc"], K.F_BODY, 18, K.CREAM_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	K.put(kit_body, desc, Vector2(x, y), Vector2(w, 52))
	y += 62
	# size in metres
	var ls := K.label("Größe (Meter)", K.F_HEAD, 19)
	K.put(kit_body, ls, Vector2(x, y))
	y += 32
	var id: String = b.shape_id()
	var sz: Vector3i = b.sizes.get(id, Vector3i(16, 16, 16))
	var names := ["Breite", "Höhe", "Tiefe"]
	for a in 3:
		var l := K.label(names[a], K.F_BODY, 17, K.CREAM_DIM)
		K.put(kit_body, l, Vector2(x + a * 156, y))
		var sp := SpinBox.new()
		sp.min_value = 0.125
		sp.max_value = Game.max_shape_voxels() * 0.125
		sp.step = 0.125
		sp.value = [sz.x, sz.y, sz.z][a] * 0.125
		sp.suffix = "m"
		sp.custom_arrow_step = 0.5
		sp.select_all_on_focus = true
		_style_spin(sp)
		K.put(kit_body, sp, Vector2(x + a * 156, y + 24), Vector2(140, 36))
		sp.value_changed.connect(func(val: float):
			var cur: Vector3i = b.sizes.get(b.shape_id(), Vector3i(16, 16, 16))
			var vv := maxi(1, roundi(val / 0.125))
			if a == 0:
				cur.x = vv
			elif a == 1:
				cur.y = vv
			else:
				cur.z = vv
			b.set_size(cur))
	y += 74
	if str(s2.get("thick_axis", "")) == "p":
		var lt := K.label("Wandstärke", K.F_BODY, 17, K.CREAM_DIM)
		K.put(kit_body, lt, Vector2(x, y))
		var spt := SpinBox.new()
		spt.min_value = 1
		spt.max_value = 12
		spt.value = int(b.thicks.get(id, 2))
		spt.suffix = "× 12,5 cm"
		_style_spin(spt)
		K.put(kit_body, spt, Vector2(x, y + 24), Vector2(180, 36))
		spt.value_changed.connect(func(val: float):
			b.thicks[b.shape_id()] = int(val)
			b._after_change())
	var lr := K.label("Drehung", K.F_BODY, 17, K.CREAM_DIM)
	K.put(kit_body, lr, Vector2(x + 212, y))
	K.button(kit_body, "⟲  R", Rect2(x + 212, y + 24, 120, 36), func(): b.rotate(1), 18)
	K.check(kit_body, "Spiegeln", Vector2(x + 344, y + 25), b.mirror, func(v: bool):
		b.mirror = v
		b._after_change(), 130)

func _style_spin(sp: SpinBox) -> void:
	var le := sp.get_line_edit()
	le.add_theme_font_override("font", K.F_BODY)
	le.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.05, 0.95)
	sb.border_color = Color(K.GOLD, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	le.add_theme_stylebox_override("normal", sb)
	le.add_theme_stylebox_override("focus", sb)
	le.add_theme_color_override("font_color", K.CREAM)

func _kit_materials(x: float, y: float, w: float) -> void:
	y = _section(x, y, w, "Material")
	for grp in b.PALETTE:
		var gl := K.label(grp[0], K.F_HEAD, 17, K.CREAM_DIM)
		K.put(kit_body, gl, Vector2(x, y))
		var mx := x + 116
		for nm in grp[1]:
			if not b.vworld.mat_ids.has(nm):
				continue
			var id: int = b.vworld.mat_ids[nm]
			if mx + 50 > x + w:
				mx = x + 116
				y += 54
			_mat_button(Vector2(mx, y - 4), id, b.mat == id, func(): b.set_material(id))
			mx += 54
		y += 56
	# selected material details
	var res: String = b.vworld.res_of(b.mat << 2)
	var per: float = b.per_voxel(b.mat)
	var det := K.label("%s  ·  %s" % [b.mat_name(b.mat), ("1 %s je Voxel (Natur)" % b.res_name(res)) if per >= 1.0 else ("1 %s reicht für %d Voxel" % [b.res_name(res), roundi(1.0 / per)])], K.F_HEAD, 19)
	K.put(kit_body, det, Vector2(x, y + 2))
	var have := K.label("Vorrat: %d %s" % [Game.count(res), b.res_name(res)], K.F_BODY, 18, K.CREAM_DIM)
	K.put(kit_body, have, Vector2(x, y + 28))
	y += 66
	y = _section(x, y, w, "Muster")
	for pi: int in b.PATTERNS.size():
		var px: float = x + pi * 80
		var btn := K.button(kit_body, "", Rect2(px, y, 74, 98), func(): b.set_pattern(pi), 14, b.pattern_sel == pi)
		var sw := Control.new()
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pat: int = b.pattern() if pi == 0 else pi - 1
		sw.draw.connect(func(): draw_swatch(sw, Rect2(Vector2.ZERO, sw.size), b.mat, pat, 8))
		K.put(btn, sw, Vector2(9, 8), Vector2(56, 56))
		var pl := K.label(b.PATTERNS[pi], K.F_BODY, 15, K.CREAM)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		K.put(btn, pl, Vector2(0, 68), Vector2(74, 22))
	y += 112
	y = _section(x, y, w, "Zweitmaterial  (Dach vom Haus)")
	var mx2 := x
	for nm in ["slate", "brick_red", "planks_dark", "planks", "hay", "cobble", "bricks_dark", "plaster", "cloth_r", "cloth_b", "gold"]:
		if b.vworld.mat_ids.has(nm):
			var id2: int = b.vworld.mat_ids[nm]
			_mat_button(Vector2(mx2, y), id2, b.mat2 == id2, func(): b.set_material(id2, true))
			mx2 += 50

func _mat_button(pos: Vector2, id: int, sel: bool, cb: Callable) -> void:
	var btn := Button.new()
	btn.position = pos
	btn.size = Vector2(46, 46)
	K.style(btn, 14, sel)
	btn.tooltip_text = "%s\n%s" % [b.mat_name(id), "Natur: 1 Rohstoff je Voxel" if b.per_voxel(id) >= 1.0 else "Baustoff: 1 Rohstoff je 4 Voxel"]
	btn.pressed.connect(cb)
	var sw := Control.new()
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var auto: int = int(b.AUTO_PATTERN.get(str(b.vworld.materials.get(id, {}).get("name", "")), 0))
	sw.draw.connect(func(): draw_swatch(sw, Rect2(Vector2.ZERO, sw.size), id, auto, 5))
	K.put(btn, sw, Vector2(6, 6), Vector2(34, 34))
	kit_body.add_child(btn)

func _kit_options(x: float, y: float, w: float) -> void:
	y = _section(x, y, w, "Modus")
	var modes := [["Bauen", "bauen"], ["Färben", "faerben"], ["Kopieren", "kopieren"]]
	for i in 3:
		var btn := K.button(kit_body, "", Rect2(x + i * 136, y, 128, 92), func(): b.set_mode(i), 17, b.mode == i)
		var ic := TextureRect.new()
		ic.texture = _icons[modes[i][1]]
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		K.put(btn, ic, Vector2(39, 4), Vector2(50, 50))
		var l := K.label(modes[i][0], K.F_HEAD, 18)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		K.put(btn, l, Vector2(0, 58), Vector2(128, 26))
	y += 104
	y = _section(x, y, w, "Optionen")
	var lg := K.label("Raster", K.F_BODY, 18, K.CREAM_DIM)
	K.put(kit_body, lg, Vector2(x, y + 6))
	for gi in b.GRIDS.size():
		K.button(kit_body, b.GRID_NAMES[gi], Rect2(x + 70 + gi * 84, y, 78, 36), func():
			b.grid_i = gi
			b._after_change(), 16, b.grid_i == gi)
	y += 46
	K.check(kit_body, "Fundament bis zum Boden", Vector2(x, y), b.foundation, func(v: bool):
		b.foundation = v
		b._after_change(), w)
	y += 36
	K.check(kit_body, "Haus: Fenster verglasen (Glas)", Vector2(x, y), b.glass_windows, func(v: bool):
		b.glass_windows = v
		b._after_change(), w)
	y += 36
	K.check(kit_body, "Kopieren: nur Gebautes (kein Boden)", Vector2(x, y), b.only_built, func(v: bool):
		b.only_built = v, w)
	y += 36
	K.check(kit_body, "Kreativmodus (unendlich Material)", Vector2(x, y), Game.creative, func(v: bool):
		Game.creative = v
		b._after_change(), w)
	y += 48
	y = _section(x, y, w, "Baupläne  (%d / %d)" % [Game.blueprints.size(), Game.blueprint_slots()])
	if Game.blueprints.is_empty():
		var e := K.label("Modus „Kopieren“: Bereich ziehen –\nschon ist er als Bauplan gespeichert.", K.F_BODY, 17, K.CREAM_DIM)
		K.put(kit_body, e, Vector2(x, y))
		y += 56
	for i in Game.blueprints.size():
		var bp: Dictionary = Game.blueprints[i]
		var ed := K.line_edit(kit_body, Rect2(x, y, 200, 36), bp["name"])
		ed.text_submitted.connect(func(t: String): b.rename_blueprint(i, t))
		ed.focus_exited.connect(func(): b.rename_blueprint(i, ed.text))
		var sz: Array = bp["size"]
		var dl := K.label("%s×%s×%s m" % [b._m(sz[0] * 0.125), b._m(sz[1] * 0.125), b._m(sz[2] * 0.125)], K.F_BODY, 15, K.CREAM_DIM)
		K.put(kit_body, dl, Vector2(x + 2, y + 36))
		K.button(kit_body, "Setzen", Rect2(x + 208, y, 110, 36), func():
			b.select_blueprint(i)
			b.close_panel(), 17, b.bp_i == i)
		K.button(kit_body, "Löschen", Rect2(x + 324, y, 86, 36), func(): b.delete_blueprint(i), 15)
		y += 62
	y += 4
	y = _section(x, y, w, "Tipp")
	var tip := K.label("Rechte Maus schneidet mit derselben Form aus –\nso entstehen Türen, Fenster, Keller und Tunnel.\nAusgeschnittene Baustoffe bekommst du zurück.", K.F_BODY, 17, K.CREAM_DIM)
	K.put(kit_body, tip, Vector2(x, y))
