extends Camera3D
## Caméra isométrique orthographique façon MMO RPG : angle fixe (orientation
## + plongée), suit la cible, zoom à la molette par paliers.
##
## Stabilité des glyphes : en projection orthographique, un déplacement de la
## caméra parallèle à l'écran décale l'image d'une quantité fixe de pixels. Si
## l'on cale ce déplacement sur un multiple exact de la taille d'une cellule,
## le décor glisse d'une case entière à la fois : chaque morceau de décor garde
## le même glyphe d'une frame à l'autre, au lieu de scintiller.

@export var target_path: NodePath
## Quad ASCII : on lit sa taille de cellule pour caler la caméra sur la grille.
@export var post_process_path: NodePath
## Orientation autour de l'axe vertical (45° = vue diagonale isométrique).
@export_range(0.0, 360.0) var yaw_degrees := 45.0
## Angle de plongée au-dessus de l'horizon (35° ≈ isométrique « vraie »,
## plus haut = plus vu du dessus).
@export_range(10.0, 89.0) var pitch_degrees := 50.0
## Hauteur du point visé au-dessus des pieds de la cible.
@export var look_height := 1.0
## Plus la valeur est grande, plus la caméra rattrape vite la cible.
@export var follow_smoothing := 6.0
## Recul de la caméra le long de son axe (orthographique : n'influence que le
## découpage near/far, pas la taille à l'écran).
@export var camera_distance := 40.0
## Cale la position de la caméra sur la grille de cellules (anti-scintillement).
@export var snap_to_cells := true

## Secousse maximale (en cellules) quand l'intensité vaut 1.
@export var shake_max_cells := 2.0
## Vitesse à laquelle la secousse s'éteint (par seconde).
@export var shake_decay := 3.0

@export_group("Zoom")
## Paliers de zoom : hauteur visible à l'écran, en mètres.
@export var zoom_levels: Array[float] = [7.0, 9.0, 12.0, 15.0, 19.0, 24.0]
## Palier initial (index dans zoom_levels).
@export var zoom_index := 2
@export var zoom_smoothing := 12.0

var _target: Node3D
var _post: Node
var _focus := Vector3.ZERO   # point suivi (lissé)
var _size := 12.0            # hauteur visible actuelle (lissée)
var _trauma := 0.0           # intensité de la secousse (0..1)


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	_target = get_node_or_null(target_path) as Node3D
	_post = get_node_or_null(post_process_path)
	zoom_index = clampi(zoom_index, 0, zoom_levels.size() - 1)
	_size = zoom_levels[zoom_index]
	if _target:
		_focus = _target.global_position
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_index = maxi(zoom_index - 1, 0)
	elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_index = mini(zoom_index + 1, zoom_levels.size() - 1)
	else:
		return
	get_viewport().set_input_as_handled()


# En _physics_process pour rester synchronisée avec le CharacterBody3D (pas de saccades).
## Secousse (coups reçus, impacts). Les intensités s'additionnent, plafonnées à 1.
func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	_trauma = move_toward(_trauma, 0.0, shake_decay * delta)
	if _target:
		_focus = _focus.lerp(_target.global_position, 1.0 - exp(-follow_smoothing * delta))
	var wanted := zoom_levels[zoom_index]
	_size = lerpf(_size, wanted, 1.0 - exp(-zoom_smoothing * delta))
	if absf(_size - wanted) < 0.01:
		_size = wanted # palier atteint : taille exacte, la grille redevient stable
	_update_transform()


## Direction (normalisée) du point visé vers la caméra, d'après l'angle fixe.
func get_view_direction() -> Vector3:
	var pitch := deg_to_rad(pitch_degrees)
	var yaw := deg_to_rad(yaw_degrees)
	return Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw)


func _update_transform() -> void:
	size = _size
	# Base de la caméra construite à partir de l'angle fixe (et non de la
	# transformation courante) : pas d'accumulation d'erreurs d'arrondi.
	var back := get_view_direction()                 # +Z caméra (elle regarde vers -Z)
	var right := Vector3.UP.cross(back).normalized() # +X caméra
	var up := back.cross(right)                      # +Y caméra

	var look_point := _focus + Vector3.UP * look_height
	if snap_to_cells:
		look_point = _snap_to_grid(look_point, right, up)
	# Secousse par cellules entières : l'image saute d'une case à l'autre au
	# lieu de glisser, donc les glyphes du décor ne scintillent pas.
	if _trauma > 0.0:
		var amp := _trauma * _trauma * shake_max_cells
		var cell := _cell_world()
		look_point += right * roundf(randf_range(-amp, amp)) * cell + up * roundf(randf_range(-amp, amp)) * cell

	global_transform = Transform3D(Basis(right, up, back), look_point + back * camera_distance)


## Arrondit la position du point visé, dans le plan de l'écran, au multiple le
## plus proche de la taille d'une cellule exprimée en mètres.
func _snap_to_grid(point: Vector3, right: Vector3, up: Vector3) -> Vector3:
	var cell_world := _cell_world()
	if cell_world <= 0.0:
		return point
	var a := point.dot(right)
	var b := point.dot(up)
	var snapped_a := roundf(a / cell_world) * cell_world
	var snapped_b := roundf(b / cell_world) * cell_world
	return point + right * (snapped_a - a) + up * (snapped_b - b)


## Taille d'une cellule, en mètres, dans le plan de l'écran.
func _cell_world() -> float:
	var viewport_height := get_viewport().get_visible_rect().size.y
	if viewport_height <= 0.0:
		return 0.0
	var cell_pixels := 5
	if _post and "cell_size" in _post:
		cell_pixels = _post.cell_size
	return _size * float(cell_pixels) / viewport_height
