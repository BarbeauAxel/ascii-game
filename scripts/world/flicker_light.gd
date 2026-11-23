extends OmniLight3D
## Lumière de flamme : l'intensité vacille (bruit lissé, deux fréquences) et
## la source tremble de quelques centimètres, ce qui fait bouger les ombres.

## Intensité moyenne.
@export var base_energy := 2.0
## Amplitude du vacillement (fraction de base_energy).
@export var flicker := 0.25
## Vitesse du vacillement.
@export var speed := 1.0
## Tremblement de la position (mètres).
@export var jitter := 0.03

var _noise := FastNoiseLite.new()
var _time := 0.0
var _origin := Vector3.ZERO


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 1.0
	_origin = position
	light_energy = base_energy


func _process(delta: float) -> void:
	_time += delta * speed
	# Bruit lent (respiration de la flamme) + rapide (crépitement).
	var n := _noise.get_noise_1d(_time * 2.0) * 0.7 + _noise.get_noise_1d(_time * 9.0 + 100.0) * 0.3
	light_energy = base_energy * (1.0 + flicker * n * 2.0)
	position = _origin + Vector3(
		_noise.get_noise_1d(_time * 3.0 + 200.0),
		_noise.get_noise_1d(_time * 3.0 + 300.0) * 0.5,
		_noise.get_noise_1d(_time * 3.0 + 400.0)) * jitter * 2.0
