extends OmniLight3D
## Gentle candle flicker for lantern lights.

var _base := 2.0
var _seed := 0.0

func _ready() -> void:
	_base = light_energy
	_seed = randf() * 100.0

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0 + _seed
	light_energy = _base * (0.9 + 0.06 * sin(t * 7.3) + 0.04 * sin(t * 13.1 + 1.7))
