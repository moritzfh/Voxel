extends RefCounted
const TYPES := {
	"goblin":{"name":"Goblin","hp":55.0,"speed":3.0,"height":1.4,"radius":.35,"damage":10.0,"reach":1.3,"xp":35,"boss":false},
	"witch":{"name":"Hexe","hp":75.0,"speed":2.3,"height":2.15,"radius":.38,"damage":18.0,"reach":1.4,"xp":55,"boss":false},
	"bandit":{"name":"Räuber","hp":90.0,"speed":3.3,"height":1.95,"radius":.4,"damage":15.0,"reach":1.7,"xp":50,"boss":false},
	"cyclops":{"name":"Großer Zyklop","hp":650.0,"speed":2.0,"height":4.75,"radius":1.25,"damage":38.0,"reach":4.1,"xp":450,"boss":true},
	"dragon":{"name":"Drache","hp":1000.0,"speed":2.4,"height":4.3,"radius":1.8,"damage":44.0,"reach":4.2,"xp":700,"boss":true},
	"sandworm":{"name":"Riesen-Sandwurm","hp":850.0,"speed":1.7,"height":5.0,"radius":1.5,"damage":40.0,"reach":3.8,"xp":600,"boss":true},
}
const STANDARD := ["goblin","witch","bandit"]
const BOSSES := ["cyclops","dragon","sandworm"]

static func group_size(level: int) -> int:
	return clampi(1+(level-1)/2,1,5)

static func level_at(point: Vector3, spawn: Vector3) -> int:
	return 1+mini(199,floori(Vector2(point.x-spawn.x,point.z-spawn.z).length()/180))
