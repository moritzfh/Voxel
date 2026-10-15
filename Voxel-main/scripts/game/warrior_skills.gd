extends RefCounted
## Shared definitions for progression, host validation and the skill book.
const NODES := {
	"edge": {"tree":"Klinge","name":"Schwertkunst","max":3,"level":2,"desc":"+10 % Schwertschaden pro Rang."},
	"flow": {"tree":"Klinge","name":"Kampffluss","max":2,"level":3,"needs":"edge","desc":"Kombofinale: +2 Mana pro Rang bei einem Treffer."},
	"cleave": {"tree":"Klinge","name":"Spaltender Hieb [C]","max":1,"level":3,"needs":"edge","desc":"18 Mana · schwerer Überkopfhieb mit weitem Trefferbogen."},
	"lifesteal": {"tree":"Klinge","name":"Lebensklinge","max":2,"level":6,"needs":"cleave","desc":"Schwerttreffer heilen 1 Leben pro Rang."},
	"execution": {"tree":"Klinge","name":"Hinrichtung [K]","max":1,"level":12,"needs":"lifesteal","desc":"25 Mana · Stoß: dreifacher Schaden unter 30 % Gegnerleben."},
	"whirlwind": {"tree":"Sturm","name":"Wirbelmeister","max":2,"level":2,"desc":"Wirbel [Q]: +1 Umdrehung und Treffer pro Rang."},
	"radius": {"tree":"Sturm","name":"Sturmreichweite","max":2,"level":4,"needs":"whirlwind","desc":"Wirbel und Druckwellen reichen je Rang 0,6 m weiter."},
	"quake": {"tree":"Sturm","name":"Erdspalter","max":3,"level":3,"desc":"Sprungschlag [R]: +20 % Schaden pro Rang."},
	"aftershock": {"tree":"Sturm","name":"Nachbeben","max":1,"level":8,"needs":"quake","desc":"Der Sprungschlag löst eine zweite, schwächere Welle aus."},
	"dash": {"tree":"Sturm","name":"Klingensturm [V]","max":1,"level":5,"needs":"radius","desc":"16 Mana · schneller Vorstoß mit ausgestreckter Klinge."},
	"iron": {"tree":"Wacht","name":"Eiserne Haut","max":3,"level":2,"desc":"8 % weniger erlittener Schaden pro Rang."},
	"dodge": {"tree":"Wacht","name":"Flinke Rolle","max":2,"level":3,"desc":"Rolle [Strg]: weniger Ausdauer und kürzere Erholung."},
	"guard": {"tree":"Wacht","name":"Klingenwacht [X]","max":1,"level":4,"needs":"iron","desc":"12 Mana · 3 Sekunden lang 65 % weniger Schaden."},
	"heal": {"tree":"Wacht","name":"Zweiter Atem [Z]","max":1,"level":6,"needs":"guard","desc":"22 Mana · heilt 35 Leben mit einer aufrichtenden Geste."},
	"berserk": {"tree":"Wacht","name":"Kriegsrausch [U]","max":1,"level":10,"needs":"heal","desc":"30 Mana · 6 Sekunden lang 40 % mehr Schaden."},
	"capacity": {"tree":"Geist","name":"Manavorrat","max":3,"level":2,"desc":"+10 maximales Mana pro Rang."},
	"predator": {"tree":"Geist","name":"Siegesfunke","max":3,"level":3,"needs":"capacity","desc":"Besiegte Tiere geben +2 Mana pro Rang."},
	"economy": {"tree":"Geist","name":"Fokus","max":2,"level":5,"needs":"capacity","desc":"Fähigkeiten kosten 10 % weniger Mana pro Rang."},
	"recovery": {"tree":"Geist","name":"Bereitschaft","max":2,"level":7,"needs":"economy","desc":"Fähigkeiten erholen sich 10 % schneller pro Rang."},
}
const ABILITIES := {
	"spin": {"action":"skill_spin","name":"Wirbelklinge","cost":16.0,"cd":5.0,"duration":1.05,"impact":0.18},
	"slam": {"action":"skill_slam","name":"Sprungschlag","cost":24.0,"cd":7.0,"duration":0.85,"impact":0.72},
	"cleave": {"action":"skill_cleave","name":"Spaltender Hieb","cost":18.0,"cd":4.0,"duration":0.65,"impact":0.32},
	"dash": {"action":"skill_dash","name":"Klingensturm","cost":16.0,"cd":5.0,"duration":0.42,"impact":0.28},
	"guard": {"action":"skill_guard","name":"Klingenwacht","cost":12.0,"cd":10.0,"duration":0.5,"impact":0.0},
	"heal": {"action":"skill_heal","name":"Zweiter Atem","cost":22.0,"cd":14.0,"duration":0.8,"impact":0.0},
	"berserk": {"action":"skill_berserk","name":"Kriegsrausch","cost":30.0,"cd":18.0,"duration":0.7,"impact":0.0},
	"execution": {"action":"skill_execution","name":"Hinrichtung","cost":25.0,"cd":8.0,"duration":0.65,"impact":0.3},
}

static func allowed(kind: String, level: int, ranks: Dictionary) -> bool:
	if kind in ["spin","slam","attack","dodge"]: return true
	return NODES.has(kind) and level>=int(NODES[kind].level) and int(ranks.get(kind,0))>0

static func cost(kind: String, ranks: Dictionary) -> float:
	return float(ABILITIES.get(kind,{}).get("cost",0.0))*(1.0-.1*int(ranks.get("economy",0)))

static func clean_ranks(level: int, input: Dictionary) -> Dictionary:
	var result := {}
	var budget := maxi(0,level-1)
	for id in NODES:
		var n: Dictionary = NODES[id]
		if level<int(n.level) or (n.has("needs") and not result.has(n.needs)): continue
		var value := clampi(int(input.get(id,0)),0,mini(int(n.max),budget))
		if value>0: result[id] = value; budget -= value
	return result
