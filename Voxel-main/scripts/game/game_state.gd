extends Node
## Progression state (autoload "Game"): resources, tools, XP / level, talents, unlocked shapes, blueprints, quests,
## discovered runes and treasures. Pure state + signals; the HUD and the gameplay nodes read and change it.

signal inventory_changed
signal xp_changed
signal leveled_up(level: int)
signal talents_changed
signal quests_changed
signal notify(text: String, color: Color)

# ---------------------------------------------------------------- resources
const RESOURCES := {
	"erde": {"name": "Erde", "color": Color("8a5c36")},
	"sand": {"name": "Sand", "color": Color("d6c48f")},
	"stein": {"name": "Stein", "color": Color("8c8a85")},
	"holz": {"name": "Holz", "color": Color("9d6c3f")},
	"laub": {"name": "Laub", "color": Color("4f9134")},
	"kupfer": {"name": "Kupfer", "color": Color("d0803f")},
	"eisen": {"name": "Eisen", "color": Color("c08a70")},
	"kristall": {"name": "Kristall", "color": Color("5fe3d6")},
	"gold": {"name": "Gold", "color": Color("e6ba50")},
	"glas": {"name": "Glas", "color": Color("a9d4e8")},
	"ziegel": {"name": "Ziegel", "color": Color("a5462f")},
	"stoff": {"name": "Stoff", "color": Color("ece9e0")},
	"lehm": {"name": "Lehm", "color": Color("b88a63")},
}
const RES_ORDER := ["erde", "sand", "lehm", "stein", "holz", "laub", "kupfer", "eisen", "kristall", "gold", "glas", "ziegel", "stoff"]

# tool tiers: 1 Stein, 2 Kupfer, 3 Eisen, 4 Kristall
const TIER_NAMES := ["", "Stein", "Kupfer", "Eisen", "Kristall"]
const TIER_COLORS := [Color.WHITE, Color("9a978f"), Color("d0803f"), Color("c9cdd3"), Color("5fe3d6")]

var inv := {}
var tool_tier := 1
var xp := 0
var level := 1
var talent_points := 0
var talents := {}            # id -> rank
var blueprints: Array = []   # [{name, size: [x,y,z], data: PackedByteArray}]
var runes_found: Array = []  # indices into markers.runes
var treasures_found: Array = []
var trees_felled := 0
var stats := {"mined": 0, "built": 0}
var quests := {}             # id -> {state: "active"/"done", ...}
var creative := false        # unlimited resources (debug / sandbox)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()

func reset() -> void:
	world_features = bool(Settings.get_value("world_features"))
	creative = false
	build_quest_progress = 0.0
	inv = {}
	for r in RES_ORDER:
		inv[r] = 0
	# a starting stash so building can be tried right away
	inv["holz"] = 600
	inv["stein"] = 800
	inv["erde"] = 400
	tool_tier = 1
	xp = 0
	level = 1
	talent_points = 0
	talents = {}
	blueprints = []
	runes_found = []
	treasures_found = []
	trees_felled = 0
	stats = {"mined": 0, "built": 0}
	quests = {}
	start_quest("erste_schritte")

# ---------------------------------------------------------------- inventory
func count(res: String) -> int:
	return int(inv.get(res, 0))

func add(res: String, n: int, silent := false) -> void:
	if res == "" or n == 0:
		return
	inv[res] = maxi(0, count(res) + n)
	inventory_changed.emit()
	if not silent and n > 0:
		notify.emit("+%d %s" % [n, RESOURCES.get(res, {}).get("name", res)], RESOURCES.get(res, {}).get("color", Color.WHITE))
	_check_quests()

func add_many(d: Dictionary) -> void:
	for r in d:
		inv[r] = maxi(0, count(r) + int(d[r]))
	inventory_changed.emit()
	_check_quests()

func can_afford(cost: Dictionary) -> bool:
	if creative:
		return true
	for r in cost:
		if count(r) < int(cost[r]):
			return false
	return true

func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	if not creative:
		for r in cost:
			inv[r] = count(r) - int(cost[r])
		inventory_changed.emit()
	return true

# ---------------------------------------------------------------- XP, level, talents
func xp_needed(l: int) -> int:
	return int(120.0 * pow(float(l), 1.4))

func add_xp(n: int) -> void:
	if n <= 0:
		return
	xp += n
	while xp >= xp_needed(level):
		xp -= xp_needed(level)
		level += 1
		talent_points += 1
		leveled_up.emit(level)
		notify.emit("Stufe %d! +1 Talentpunkt (T)" % level, Color(1.0, 0.85, 0.4))
	xp_changed.emit()

const WARRIOR := preload("res://scripts/game/warrior_skills.gd")
var TALENTS: Dictionary = BASE_TALENTS.merged(WARRIOR.NODES)
const BASE_TALENTS := {
	"schlag": {"tree": "Bergbau", "name": "Kräftiger Schlag", "max": 3, "desc": "+25 % größere Brocken pro Stufe"},
	"gespuer": {"tree": "Bergbau", "name": "Erz-Gespür", "max": 1, "desc": "Erze leuchten durch den Stein, wenn du sie anvisierst"},
	"sprengung": {"tree": "Bergbau", "name": "Sprengkraft", "max": 2, "desc": "Jeder 5. Schlag bricht einen riesigen Brocken heraus"},
	"axt": {"tree": "Holzfäller", "name": "Scharfe Axt", "max": 3, "desc": "+30 % tiefere Kerben"},
	"ertrag": {"tree": "Holzfäller", "name": "Holzertrag", "max": 2, "desc": "+25 % Holz und Laub"},
	"formen1": {"tree": "Baumeister", "name": "Runde Formen", "max": 1, "desc": "Kugel, Kuppel, Turm und Rundturm"},
	"formen2": {"tree": "Baumeister", "name": "Bögen & Treppen", "max": 1, "desc": "Torbogen, Treppe, Freitreppe und Rampe", "needs": "formen1"},
	"formen3": {"tree": "Baumeister", "name": "Dächer & Zinnen", "max": 1, "desc": "Sattel- und Pultdach, Säule, Zinnen", "needs": "formen2"},
	"pinsel": {"tree": "Baumeister", "name": "Großer Pinsel", "max": 2, "desc": "Maximale Formgröße 10 m / 16 m (statt 6 m)"},
	"sparsam": {"tree": "Baumeister", "name": "Sparsam", "max": 3, "desc": "-15 % Materialkosten pro Stufe"},
	"plaene": {"tree": "Baumeister", "name": "Baupläne", "max": 2, "desc": "3 / 8 Bauplan-Speicher"},
	"fuesse": {"tree": "Entdecker", "name": "Flinke Füße", "max": 2, "desc": "+10 % Laufgeschwindigkeit pro Stufe"},
	"schatz": {"tree": "Entdecker", "name": "Schatzsucher", "max": 1, "desc": "Vergrabene Schätze erscheinen auf der Karte"},
	"runen": {"tree": "Entdecker", "name": "Runenkunde", "max": 1, "desc": "Unentdeckte Runensteine erscheinen auf der Karte"},
}

func rank(id: String) -> int:
	return int(talents.get(id, 0))

func can_learn(id: String) -> bool:
	if not TALENTS.has(id): return false
	var t: Dictionary = TALENTS[id]
	if level<int(t.get("level",1)): return false
	if talent_points <= 0 or rank(id) >= int(t["max"]):
		return false
	if t.has("needs") and rank(t["needs"]) <= 0:
		return false
	return true

func learn(id: String) -> bool:
	if not can_learn(id):
		return false
	talents[id] = rank(id) + 1
	talent_points -= 1
	talents_changed.emit()
	notify.emit("Talent gelernt: %s" % TALENTS[id]["name"], Color(0.7, 0.95, 0.6))
	return true

func max_shape_voxels() -> int:
	return [48, 80, 128][rank("pinsel")]

func blueprint_slots() -> int:
	return [1, 3, 8][rank("plaene")]

func cost_factor() -> float:
	return 1.0 - 0.15 * rank("sparsam")

# ---------------------------------------------------------------- crafting
const RECIPES := [
	{"id": "glas", "name": "Glas", "out": {"glas": 100}, "cost": {"sand": 150}, "desc": "Für Fenster und Glaswände"},
	{"id": "ziegel", "name": "Ziegel", "out": {"ziegel": 100}, "cost": {"lehm": 60, "sand": 40}, "desc": "Backstein aus Lehm brennen"},
	{"id": "ziegel2", "name": "Ziegel (aus Erde)", "out": {"ziegel": 100}, "cost": {"erde": 160, "sand": 60}, "desc": "Geht auch ohne Lehm – nur teurer"},
	{"id": "stoff", "name": "Stoff", "out": {"stoff": 100}, "cost": {"laub": 400}, "desc": "Fasern zu Stoff weben"},
	{"id": "tool2", "name": "Kupferwerkzeug", "tier": 2, "cost": {"kupfer": 300, "holz": 200}, "desc": "Baut Eisenerz und Bergfels ab, größere Brocken"},
	{"id": "tool3", "name": "Eisenwerkzeug", "tier": 3, "cost": {"eisen": 400, "holz": 200, "kupfer": 100}, "desc": "Baut Kristall und Gold ab, noch größere Brocken"},
	{"id": "tool4", "name": "Kristallwerkzeug", "tier": 4, "cost": {"kristall": 250, "eisen": 200, "gold": 60}, "desc": "Die schnellsten, größten Schläge"},
]

func craft(recipe: Dictionary) -> bool:
	if recipe.has("tier") and tool_tier >= int(recipe["tier"]):
		return false
	if recipe.has("tier") and tool_tier < int(recipe["tier"]) - 1:
		notify.emit("Erst die Stufe davor herstellen", Color(1, 0.6, 0.5))
		return false
	if not spend(recipe["cost"]):
		notify.emit("Nicht genug Rohstoffe", Color(1, 0.6, 0.5))
		return false
	if recipe.has("tier"):
		tool_tier = int(recipe["tier"])
		notify.emit("%s hergestellt!" % recipe["name"], TIER_COLORS[tool_tier])
		add_xp(80 * tool_tier)
	else:
		add_many(recipe["out"])
		notify.emit("%s hergestellt" % recipe["name"], Color(0.9, 0.9, 0.8))
	_check_quests()
	return true

# ---------------------------------------------------------------- quests
const QUESTS := {
	"erste_schritte": {"title": "Erste Schritte", "desc": "Grabe 400 Erde aus und fälle einen Baum.", "next": "kupfer", "xp": 150},
	"kupfer": {"title": "Unter der Erde", "desc": "Grabe dich zum Stein durch und finde 100 Kupfer.", "next": "werkzeug", "xp": 200},
	"werkzeug": {"title": "Neues Werkzeug", "desc": "Stelle Kupferwerkzeug her (I → Herstellen).", "next": "wachturm", "xp": 250},
	"wachturm": {"title": "Der Wachturm", "desc": "Fülle den leuchtenden Umriss am Flussufer mit beliebigen Voxeln.", "next": "runen", "xp": 400},
	"runen": {"title": "Runensucher", "desc": "Finde 4 der 8 Runensteine.", "next": "schaetze", "xp": 400},
	"schaetze": {"title": "Schatzjäger", "desc": "Grabe 3 vergrabene Schätze aus (X aus Kieseln).", "next": "", "xp": 600},
}
var build_quest_progress := 0.0
var world_features := false
const WORLD_QUESTS := ["erste_schritte","kupfer","werkzeug","wachturm","schaetze"]

func quest_visible(id: String) -> bool:
	return world_features or not id in WORLD_QUESTS

func start_quest(id: String) -> void:
	if id == "" or quests.has(id):
		return
	quests[id] = {"state": "active"}
	quests_changed.emit()

func active_quests() -> Array:
	var out := []
	for id in quests:
		if quests[id]["state"] == "active" and quest_visible(id):
			out.append(id)
	return out

func quest_progress(id: String) -> String:
	match id:
		"erste_schritte":
			return "Erde %d / 400 · Bäume %d / 1" % [mini(stats.get("erde_mined", 0), 400), mini(trees_felled, 1)]
		"kupfer":
			return "Kupfer %d / 100" % mini(stats.get("kupfer_mined", 0), 100)
		"werkzeug":
			return "Werkzeug: %s" % TIER_NAMES[tool_tier]
		"wachturm":
			return "Umriss gefüllt: %d %%" % int(build_quest_progress * 100.0)
		"runen":
			return "Runensteine %d / 4" % runes_found.size()
		"schaetze":
			return "Schätze %d / 3" % treasures_found.size()
	return ""

func _check_quests() -> void:
	for id in active_quests():
		var done := false
		match id:
			"erste_schritte":
				done = stats.get("erde_mined", 0) >= 400 and trees_felled >= 1
			"kupfer":
				done = stats.get("kupfer_mined", 0) >= 100
			"werkzeug":
				done = tool_tier >= 2
			"wachturm":
				done = build_quest_progress >= 0.85
			"runen":
				done = runes_found.size() >= 4
			"schaetze":
				done = treasures_found.size() >= 3
		if done:
			complete_quest(id)
	quests_changed.emit()

func complete_quest(id: String) -> void:
	if not quests.has(id) or quests[id]["state"] == "done":
		return
	quests[id]["state"] = "done"
	var q: Dictionary = QUESTS[id]
	notify.emit("Auftrag erfüllt: %s" % q["title"], Color(0.75, 1.0, 0.6))
	add_xp(int(q["xp"]))
	if id == "wachturm":
		add_many({"gold": 40, "kristall": 60})
	start_quest(q["next"])
	quests_changed.emit()

func record_mined(counts: Dictionary) -> void:
	for r in counts:
		var k: String = r + "_mined"
		stats[k] = int(stats.get(k, 0)) + int(counts[r])
		stats["mined"] = int(stats["mined"]) + int(counts[r])
	_check_quests()

# ---------------------------------------------------------------- save
func to_dict() -> Dictionary:
	var bps := []
	for b in blueprints:
		bps.append({"name": b["name"], "size": b["size"], "data": Marshalls.raw_to_base64((b["data"] as PackedByteArray).compress(FileAccess.COMPRESSION_ZSTD)), "raw": (b["data"] as PackedByteArray).size()})
	return {"inv": inv, "tier": tool_tier, "xp": xp, "level": level, "tp": talent_points, "talents": talents, "bp": bps,
		"runes": runes_found, "treasures": treasures_found, "trees": trees_felled, "stats": stats, "quests": quests, "bq": build_quest_progress}

func from_dict(d: Dictionary) -> void:
	reset()
	for r in d.get("inv", {}):
		inv[r] = int(d["inv"][r])
	tool_tier = int(d.get("tier", 1))
	xp = int(d.get("xp", 0))
	level = int(d.get("level", 1))
	talent_points = int(d.get("tp", 0))
	talents = {}
	for k in d.get("talents", {}):
		talents[k] = int(d["talents"][k])
	blueprints = []
	for b in d.get("bp", []):
		var raw := Marshalls.base64_to_raw(b["data"]).decompress(int(b["raw"]), FileAccess.COMPRESSION_ZSTD)
		blueprints.append({"name": b["name"], "size": b["size"], "data": raw})
	runes_found = []
	for i in d.get("runes", []):
		runes_found.append(int(i))
	treasures_found = []
	for i in d.get("treasures", []):
		treasures_found.append(int(i))
	trees_felled = int(d.get("trees", 0))
	stats = d.get("stats", stats)
	quests = d.get("quests", quests)
	build_quest_progress = float(d.get("bq", 0.0))
	inventory_changed.emit()
	xp_changed.emit()
	talents_changed.emit()
	quests_changed.emit()
