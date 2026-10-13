extends Control
## The adventurer's book: Inventar (I), Herstellen, Talente (T), Journal (J) and Karte (M) in one tabbed panel.

const K := preload("res://scripts/ui/ui_kit.gd")
const TABS := ["Inventar", "Herstellen", "Talente", "Journal", "Karte"]
const TAB_KEYS := ["I", "", "T", "J", "M"]

var main: Node
var cur := 0
var body: Control
var tab_buttons: Array = []
var map_view: Control

func setup(p_main: Node) -> void:
	main = p_main
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -680
	box.offset_top = -430
	box.size = Vector2(1360, 860)
	add_child(box)
	var p := K.panel(box, Rect2(Vector2.ZERO, box.size))
	var x := 30.0
	for i in TABS.size():
		var w := 40.0 + K.F_HEAD.get_string_size(TABS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + (34.0 if TAB_KEYS[i] != "" else 0.0)
		var tb := K.button(p, TABS[i] + ("  [%s]" % TAB_KEYS[i] if TAB_KEYS[i] != "" else ""), Rect2(x, 20, w, 46), func(): open_tab(i), 22, false)
		tab_buttons.append(tb)
		x += w + 10
	K.button(p, "Schließen", Rect2(1200, 20, 130, 46), close, 20)
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.put(p, body, Vector2(30, 84), Vector2(1300, 756))
	for sig in [Game.inventory_changed, Game.talents_changed, Game.quests_changed, Game.xp_changed]:
		sig.connect(func():
			if visible and cur != 4:
				_rebuild())

func toggle(tab: int) -> void:
	if visible and cur == tab:
		close()
	else:
		open_tab(tab)

func open_tab(i: int) -> void:
	cur = i
	if not visible:
		visible = true
		if main.builder and main.builder._panel_open:
			main.builder.close_panel()
		main.player.input_blocked = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Sfx.play("click", null, -6.0)
	for k in tab_buttons.size():
		K.style(tab_buttons[k], 22, k == cur)
	_rebuild()

func close() -> void:
	visible = false
	main.player.input_blocked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if visible and (k.keycode == KEY_ESCAPE or k.keycode == KEY_TAB):
		close()
		get_viewport().set_input_as_handled()
		return
	if main.hud.chat_open or main.hud.menu.visible or (main.builder and main.builder._panel_open):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var tab := -1
	match k.keycode:
		KEY_I:
			tab = 0
		KEY_T:
			tab = 2
		KEY_J:
			tab = 3
		KEY_M:
			tab = 4
	if tab >= 0:
		toggle(tab)
		get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if visible and cur == 4 and map_view:
		map_view.queue_redraw()

func _rebuild() -> void:
	for c in body.get_children():
		c.queue_free()
	map_view = null
	match cur:
		0:
			_inventory()
		1:
			_crafting()
		2:
			_talents()
		3:
			_journal()
		4:
			_map()

func _title(text: String, pos: Vector2, w: float) -> float:
	var l := K.label(text, K.F_SC, 23, K.GOLD)
	K.put(body, l, pos)
	K.separator(body, pos + Vector2(0, 34), w)
	return pos.y + 48

# ---------------------------------------------------------------- inventory
func _inventory() -> void:
	var y := _title("Rohstoffe", Vector2(0, 0), 820)
	var i := 0
	for r in Game.RES_ORDER:
		var info: Dictionary = Game.RESOURCES[r]
		var cx := (i % 4) * 206.0
		var cy := y + (i / 4) * 92.0
		var card := K.panel(body, Rect2(cx, cy, 196, 82), false)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sw := Control.new()
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col: Color = info["color"]
		sw.draw.connect(func():
			for gx in 4:
				for gy in 4:
					var f := 0.85 + 0.3 * float((gx * 7 + gy * 3) % 5) / 5.0
					sw.draw_rect(Rect2(gx * 12, gy * 12, 12, 12), Color(col.r * f, col.g * f, col.b * f))
			sw.draw_rect(Rect2(0, 0, 48, 48), Color(0, 0, 0, 0.6), false, 1.5))
		K.put(card, sw, Vector2(14, 17), Vector2(48, 48))
		var nl := K.label(info["name"], K.F_HEAD, 20)
		K.put(card, nl, Vector2(74, 10))
		var cl := K.label(str(Game.count(r)) if not Game.creative else "∞", K.F_TITLE, 24, K.CREAM if Game.count(r) > 0 else K.CREAM_DIM)
		K.put(card, cl, Vector2(74, 38))
		i += 1
	var y2 := _title("Werkzeug", Vector2(860, 0), 440)
	var tier := Game.tool_tier
	var tl := K.label("%s-Werkzeug" % Game.TIER_NAMES[tier], K.F_HEAD, 24, Game.TIER_COLORS[tier])
	K.put(body, tl, Vector2(860, y2))
	var icons := ["icon_pickaxe", "icon_axe", "icon_hammer"]
	for k in 3:
		var ic := TextureRect.new()
		ic.texture = load("res://assets/ui/%s.png" % icons[k])
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = Game.TIER_COLORS[tier].lerp(Color.WHITE, 0.5)
		K.put(body, ic, Vector2(860 + k * 76, y2 + 40), Vector2(64, 64))
	var nxt := ""
	match tier:
		1:
			nxt = "Kupfer schaltet Eisenerz und Bergfels frei."
		2:
			nxt = "Eisen schaltet Kristall und Gold frei."
		3:
			nxt = "Kristall: die größten, schnellsten Schläge."
		_:
			nxt = "Das beste Werkzeug, das es gibt."
	var nl2 := K.label(nxt, K.F_BODY, 18, K.CREAM_DIM)
	K.put(body, nl2, Vector2(860, y2 + 114))
	var y3 := _title("Statistik", Vector2(860, y2 + 170), 440)
	var lines := [
		"Abgebaut:  %d Voxel" % int(Game.stats.get("mined", 0)),
		"Gebaut:  %d Voxel" % int(Game.stats.get("built", 0)),
		"Bäume gefällt:  %d" % Game.trees_felled,
		"Runensteine:  %d / 8" % Game.runes_found.size(),
		"Schätze:  %d / 6" % Game.treasures_found.size(),
		"Baupläne:  %d / %d" % [Game.blueprints.size(), Game.blueprint_slots()],
	]
	var sl := K.label("\n".join(lines), K.F_BODY, 19, K.CREAM)
	K.put(body, sl, Vector2(860, y3))
	var hint := K.label("Abbauen: Linke Maus auf Erde, Stein, Bäume und Felsen.\nVerbaute Baustoffe (Bruchstein, Bretter, Ziegel …) geben 1 Rohstoff je 4 Voxel – genau so viel, wie sie beim Bauen kosten.", K.F_BODY, 17, K.CREAM_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	K.put(body, hint, Vector2(0, 690), Vector2(820, 60))

# ---------------------------------------------------------------- crafting
func _crafting() -> void:
	var y := _title("Herstellen", Vector2(0, 0), 1300)
	var i := 0
	for rec in Game.RECIPES:
		var cx := (i % 2) * 650.0
		var cy := y + (i / 2) * 140.0
		var card := K.panel(body, Rect2(cx, cy, 630, 128), false)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var is_tool: bool = rec.has("tier")
		var owned: bool = is_tool and Game.tool_tier >= int(rec["tier"])
		var nl := K.label(rec["name"], K.F_HEAD, 22, Game.TIER_COLORS[int(rec["tier"])] if is_tool else K.CREAM)
		K.put(card, nl, Vector2(18, 10))
		var dl := K.label(rec["desc"], K.F_BODY, 17, K.CREAM_DIM)
		K.put(card, dl, Vector2(18, 40))
		var parts := []
		var ok := true
		for r in rec["cost"]:
			var need := int(rec["cost"][r])
			parts.append("%d %s" % [need, Game.RESOURCES[r]["name"]])
			if Game.count(r) < need and not Game.creative:
				ok = false
		var cl := K.label("Kosten: " + ", ".join(parts), K.F_HEAD, 18, K.GREEN if ok else K.RED)
		K.put(card, cl, Vector2(18, 72))
		if rec.has("out"):
			var outs := []
			for r in rec["out"]:
				outs.append("%d %s" % [int(rec["out"][r]), Game.RESOURCES[r]["name"]])
			var ol := K.label("Ergibt: " + ", ".join(outs), K.F_BODY, 17, K.CREAM)
			K.put(card, ol, Vector2(18, 98))
		var bt := K.button(card, "Hergestellt" if owned else "Herstellen", Rect2(470, 42, 140, 44), func():
			if Game.craft(rec):
				Sfx.play("levelup" if rec.has("tier") else "place", null, -4.0), 19)
		bt.disabled = owned or not ok or (is_tool and Game.tool_tier < int(rec["tier"]) - 1)
		i += 1

# ---------------------------------------------------------------- talents
func _talents() -> void:
	var head := K.label("Stufe %d   ·   %d / %d EP   ·   Talentpunkte: %d" % [Game.level, Game.xp, Game.xp_needed(Game.level), Game.talent_points], K.F_HEAD, 22, K.GOLD if Game.talent_points > 0 else K.CREAM)
	K.put(body, head, Vector2(0, 0))
	var trees := ["Bergbau", "Holzfäller", "Baumeister", "Entdecker"]
	for ti in trees.size():
		var x := ti * 326.0
		var y := _title(trees[ti], Vector2(x, 40), 310)
		for id in Game.TALENTS:
			var t: Dictionary = Game.TALENTS[id]
			if t["tree"] != trees[ti]:
				continue
			var r := Game.rank(id)
			var card := K.panel(body, Rect2(x, y, 310, 98), false)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if r > 0:
				card.bg_color = Color(0.12, 0.2, 0.12, 0.9)
			var nl := K.label(t["name"], K.F_HEAD, 19, K.GREEN if r >= int(t["max"]) else K.CREAM)
			K.put(card, nl, Vector2(14, 8))
			var rl := K.label("%d / %d" % [r, int(t["max"])], K.F_HEAD, 17, K.GOLD)
			rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			K.put(card, rl, Vector2(220, 9), Vector2(76, 24))
			var dl := K.label(t["desc"], K.F_BODY, 16, K.CREAM_DIM)
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			K.put(card, dl, Vector2(14, 34), Vector2(200, 60))
			var bt := K.button(card, "Lernen", Rect2(214, 50, 84, 38), func():
				if Game.learn(id):
					Sfx.play("levelup", null, -6.0), 16)
			bt.disabled = not Game.can_learn(id)
			if t.has("needs") and Game.rank(t["needs"]) <= 0:
				bt.tooltip_text = "Braucht zuerst: " + Game.TALENTS[t["needs"]]["name"]
			y += 106
	var hint := K.label("Talentpunkte gibt es mit jeder Stufe. Erfahrung bekommst du fürs Abbauen, Bauen, Fällen, Entdecken und für Aufträge.", K.F_BODY, 17, K.CREAM_DIM)
	K.put(body, hint, Vector2(0, 722))

# ---------------------------------------------------------------- journal
func _journal() -> void:
	var y := _title("Aufträge", Vector2(0, 0), 820)
	for id in Game.quests:
		var q: Dictionary = Game.QUESTS.get(id, {})
		if q.is_empty():
			continue
		var done: bool = Game.quests[id]["state"] == "done"
		var card := K.panel(body, Rect2(0, y, 820, 96 if not done else 62), false)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tl := K.label(q["title"], K.F_HEAD, 21, K.GREEN if done else K.CREAM)
		K.put(card, tl, Vector2(16, 8))
		var st := K.label("erledigt" if done else Game.quest_progress(id), K.F_HEAD, 17, K.GREEN if done else K.GOLD)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		K.put(card, st, Vector2(400, 10), Vector2(404, 24))
		if not done:
			var dl := K.label(q["desc"], K.F_BODY, 18, K.CREAM_DIM)
			K.put(card, dl, Vector2(16, 40))
			var rl := K.label("Belohnung: %d EP" % int(q["xp"]) + ("  ·  40 Gold, 60 Kristall" if id == "wachturm" else ""), K.F_BODY, 16, K.CREAM_DIM)
			K.put(card, rl, Vector2(16, 66))
		y += (106 if not done else 72)
	var y2 := _title("Dorf", Vector2(860, 0), 440)
	for v in main.hud.village_quests:
		var vl := K.label(v[0], K.F_HEAD, 19, K.GREEN if v[2] else K.CREAM)
		K.put(body, vl, Vector2(860, y2))
		var vs := K.label(v[1], K.F_BODY, 17, K.CREAM_DIM)
		K.put(body, vs, Vector2(860, y2 + 26))
		y2 += 64
	var y3 := _title("Wegweiser", Vector2(860, y2 + 10), 440)
	var tips := K.label("• Runensteine leuchten blau – berühre sie mit E.\n• Schätze liegen unter einem X aus Kieseln.\n• Kupfer findest du tief im Stein,\n   Eisen noch tiefer, Kristall ganz unten.\n• B öffnet den Baumodus, Tab den Baukasten.", K.F_BODY, 18, K.CREAM_DIM)
	K.put(body, tips, Vector2(860, y3))

# ---------------------------------------------------------------- map
var _tex := {}
var _area := Rect2()
var _wr := Rect2()
var _s := 1.0

func _map() -> void:
	map_view = Control.new()
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.put(body, map_view, Vector2(0, 0), Vector2(1300, 740))
	if _tex.is_empty():
		for n in ["minimap", "icon_arrow", "icon_house", "icon_rune", "icon_chest"]:
			_tex[n] = load("res://assets/ui/%s.png" % n)
	map_view.draw.connect(_draw_map)

func _to_map(x: float, z: float) -> Vector2:
	return _area.position + Vector2((x - _wr.position.x) * _s, (z - _wr.position.y) * _s)

func _draw_map() -> void:
	var mm: Control = main.hud.minimap
	var markers: Dictionary = main.world_data.get("markers", {})
	_wr = mm.world_rect
	var side := minf(map_view.size.x - 380, map_view.size.y)
	_area = Rect2(Vector2(0, 0), Vector2(side, side))
	_s = side / _wr.size.x
	map_view.draw_rect(_area, Color(0.25, 0.42, 0.2))
	map_view.draw_texture_rect(_tex["minimap"], _area, false)
	map_view.draw_rect(_area, K.GOLD, false, 2.0)
	for h in mm.houses:
		var hp := _to_map(h[0], h[1])
		map_view.draw_texture_rect(_tex["icon_house"], Rect2(hp - Vector2(13, 13), Vector2(26, 26)), false)
	var runes: Array = markers.get("runes", [])
	for i in runes.size():
		var found: bool = i in Game.runes_found
		if found or Game.rank("runen") > 0:
			var rp := _to_map(runes[i][0], runes[i][2])
			map_view.draw_texture_rect(_tex["icon_rune"], Rect2(rp - Vector2(15, 15), Vector2(30, 30)), false, Color.WHITE if found else Color(0.6, 0.7, 1.0, 0.7))
	var tr: Array = markers.get("treasures", [])
	if Game.rank("schatz") > 0:
		for i in tr.size():
			if i in Game.treasures_found:
				continue
			var tp := _to_map(tr[i][0], tr[i][2])
			map_view.draw_line(tp - Vector2(9, 9), tp + Vector2(9, 9), Color(0.85, 0.15, 0.1), 4.0)
			map_view.draw_line(tp + Vector2(-9, 9), tp + Vector2(9, -9), Color(0.85, 0.15, 0.1), 4.0)
	if main.build_site.size() > 0 and Game.quests.has("wachturm") and Game.quests["wachturm"]["state"] == "active":
		var bp := _to_map(main.build_site[0], main.build_site[2])
		map_view.draw_arc(bp, 14.0, 0, TAU, 24, Color(1.0, 0.85, 0.3), 3.0)
		map_view.draw_string(K.F_HEAD, bp + Vector2(18, 6), "Wachturm", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.9, 0.5))
	for o in mm.others:
		var op := _to_map(o[0].x, o[0].y)
		map_view.draw_circle(op, 8.0, Color(0.05, 0.07, 0.06))
		map_view.draw_circle(op, 6.0, o[1])
	var pp := _to_map(main.player.global_position.x, main.player.global_position.z)
	map_view.draw_set_transform(pp, mm.facing, Vector2.ONE)
	map_view.draw_texture_rect(_tex["icon_arrow"], Rect2(-Vector2(15, 15), Vector2(30, 30)), false)
	map_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# legend
	var lx := side + 40
	var ly := 10.0
	map_view.draw_string(K.F_SC, Vector2(lx, ly + 22), "Legende", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, K.GOLD)
	ly += 50
	var rows := [["icon_arrow", "Du"], ["icon_house", "Häuser im Dorf"], ["icon_rune", "Runenstein (%d / 8 berührt)" % Game.runes_found.size()]]
	for r in rows:
		map_view.draw_texture_rect(_tex[r[0]], Rect2(Vector2(lx, ly), Vector2(28, 28)), false)
		map_view.draw_string(K.F_BODY, Vector2(lx + 40, ly + 21), r[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, K.CREAM)
		ly += 40
	map_view.draw_line(Vector2(lx + 5, ly + 5), Vector2(lx + 23, ly + 23), Color(0.85, 0.15, 0.1), 4.0)
	map_view.draw_line(Vector2(lx + 5, ly + 23), Vector2(lx + 23, ly + 5), Color(0.85, 0.15, 0.1), 4.0)
	map_view.draw_string(K.F_BODY, Vector2(lx + 40, ly + 21), "Schatz (Talent Schatzsucher)", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, K.CREAM)
	ly += 52
	map_view.draw_arc(Vector2(lx + 14, ly + 14), 11.0, 0, TAU, 24, Color(1.0, 0.85, 0.3), 3.0)
	map_view.draw_string(K.F_BODY, Vector2(lx + 40, ly + 21), "Bauauftrag", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, K.CREAM)
	ly += 56
	var hint := "Unentdeckte Runensteine zeigt das\nTalent „Runenkunde“." if Game.rank("runen") == 0 else "Blasse Runen: noch nicht berührt."
	for t in hint.split("\n"):
		map_view.draw_string(K.F_BODY, Vector2(lx, ly + 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, K.CREAM_DIM)
		ly += 24
