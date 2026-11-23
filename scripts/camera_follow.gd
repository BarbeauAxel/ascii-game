extends Camera3D
## Caméra isométrique façon MMO RPG : angle fixe (orientation + plongée),
## suit la cible, zoom à la molette.
##
## L'angle ne change jamais : seul le point visé suit la cible (avec lissage)
## et la distance varie avec le zoom. La position de la caméra est recalculée
## à chaque frame à partir de ces trois éléments.

@export var target_path: NodePath
## Orientation autour de l'axe vertical (45° = vue diagonale isométrique).
@export_range(0.0, 360.0) var yaw_degrees := 45.0
## Angle de plongée au-dessus de l'horizon (35° ≈ isométrique « vraie »,
## plus haut = plus vu du dessus).
@export_range(10.0, 89.0) var pitch_degrees := 50.0
## Hauteur du point visé au-dessus des pieds de la cible.
@export var look_height := 1.0
## Plus la valeur est grande, plus la caméra rattrape vite la cible.
@export var follow_smoothing := 6.0

@export_group("Zoom")
## Distance initiale entre la caméra et le point visé.
@export var distance := 16.0
@export var min_distance := 8.0
@export var max_distance := 28.0
## Variation de distance par cran de molette.
@export var zoom_step := 2.0
@export var zoom_smoothing := 10.0

var _target: Node3D
var _focus := Vector3.ZERO        # point suivi (lissé)
var _distance := 16.0             # distance actuelle (lissée)
var _target_distance := 16.0      # distance visée par le zoom


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_target_distance = clampf(distance, min_distance, max_distance)
	_distance = _target_distance
	if _target:
		_focus = _target.global_position
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	# Certains pavés tactiles envoient un « facteur » pour un défilement fin.
	var amount := zoom_step * (mouse.factor if mouse.factor > 0.0 else 1.0)
	if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
		_target_distance = clampf(_target_distance - amount, min_distance, max_distance)
	elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_target_distance = clampf(_target_distance + amount, min_distance, max_distance)
	else:
		return
	get_viewport().set_input_as_handled()


# En _physics_process pour rester synchronisée avec le CharacterBody3D (pas de saccades).
func _physics_process(delta: float) -> void:
	if _target:
		_focus = _focus.lerp(_target.global_position, 1.0 - exp(-follow_smoothing * delta))
	_distance = lerpf(_distance, _target_distance, 1.0 - exp(-zoom_smoothing * delta))
	_update_transform()


## Direction (normalisée) du point visé vers la caméra, d'après l'angle fixe.
func get_view_direction() -> Vector3:
	var pitch := deg_to_rad(pitch_degrees)
	var yaw := deg_to_rad(yaw_degrees)
	return Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw)


func _update_transform() -> void:
	var look_point := _focus + Vector3.UP * look_height
	global_position = look_point + get_view_direction() * _distance
	look_at(look_point, Vector3.UP)
