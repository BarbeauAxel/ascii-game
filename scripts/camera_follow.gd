extends Camera3D
## Caméra isométrique orthographique façon MMO RPG : angle fixe (orientation
## + plongée), suit la cible, zoom à la molette par paliers.
##
## Stabilité des glyphes, défilement fluide : en projection orthographique, un
## déplacement de la caméra parallèle à l'écran décale l'image d'une quantité
## fixe de pixels. On cale la caméra sur le pixel entier (l'image se décale
## d'un nombre entier de pixels, sans rééchantillonnage), et on décale la
## grille de cellules du shader ASCII d'autant (`grid_offset`) : la grille
## reste accrochée au monde. Chaque morceau de décor garde sa cellule et son
## glyphe (pas de scintillement), et l'image défile pixel par pixel au lieu de
## sauter d'une cellule entière (5 px) à la fois.

@export var target_path: NodePath
## Quad ASCII : on lui transmet le décalage de grille (et on lit sa taille de cellule).
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
## Cale la caméra sur le pixel et accroche la grille ASCII au monde
## (anti-scintillement). Désactivé : grille fixe à l'écran, le décor scintille.
@export var snap_to_pixels := true

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
	# Secousse, en pixels entiers (la grille suit, donc pas de scintillement).
	var pixel := _pixel_world()
	if _trauma > 0.0 and pixel > 0.0:
		var amp := _trauma * _trauma * shake_max_cells * float(_cell_pixels())
		look_point += right * roundf(randf_range(-amp, amp)) * pixel + up * roundf(randf_range(-amp, amp)) * pixel

	var offset := Vector2.ZERO
	if snap_to_pixels and pixel > 0.0:
		# Position de la caméra dans le plan de l'écran, en pixels entiers.
		var a := roundf(look_point.dot(right) / pixel)
		var b := roundf(look_point.dot(up) / pixel)
		look_point += right * (a * pixel - look_point.dot(right)) + up * (b * pixel - look_point.dot(up))
		# Caméra vers la droite de n px : l'image part à gauche de n px, la
		# grille aussi. Vers le haut : l'image descend (y écran vers le bas).
		offset = Vector2(fposmod(a, 2520.0), fposmod(-b, 2520.0))
	if _post and _post.has_method("set_grid_offset"):
		_post.set_grid_offset(offset)

	global_transform = Transform3D(Basis(right, up, back), look_point + back * camera_distance)


## Taille d'un pixel, en mètres, dans le plan de l'écran.
func _pixel_world() -> float:
	var viewport_height := get_viewport().get_visible_rect().size.y
	if viewport_height <= 0.0:
		return 0.0
	return _size / viewport_height


func _cell_pixels() -> int:
	if _post and "cell_size" in _post:
		return _post.cell_size
	return 5
