extends CharacterBody3D
## Contrôleur du personnage : déplacement ZQSD/WASD + flèches, saut, gravité.
##
## Les actions sont déclarées avec des touches *physiques* : la touche en
## position "W" d'un clavier QWERTY est la touche "Z" d'un AZERTY, donc ZQSD
## et WASD fonctionnent sans configuration.

@export var speed := 5.0
@export var acceleration := 14.0
@export var jump_velocity := 4.5
@export var turn_speed := 10.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var visual: Node3D = $Visual


func _ready() -> void:
	_setup_input_actions()


func _physics_process(delta: float) -> void:
	# Gravité / saut
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# Direction voulue, relative à la caméra : "avant" = vers le haut de
	# l'écran. Avec la vue isométrique (caméra tournée à 45°), c'est donc
	# une diagonale dans le monde.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _camera_relative(input)

	var target := direction * speed
	var blend := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, target.x, blend)
	velocity.z = lerpf(velocity.z, target.z, blend)

	move_and_slide()

	# Oriente la silhouette (son avant est -Z) vers la direction de marche.
	if direction.length_squared() > 0.01:
		var yaw := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


## Convertit l'entrée 2D (x = droite, y = bas) en direction dans le plan XZ,
## selon les axes de la caméra projetés au sol.
func _camera_relative(input: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(input.x, 0.0, input.y)
	var right := camera.global_basis.x
	var back := camera.global_basis.z # la caméra regarde vers -Z
	right.y = 0.0
	back.y = 0.0
	var direction := right.normalized() * input.x + back.normalized() * input.y
	return direction.limit_length(1.0)


## Crée les actions d'entrée si elles n'existent pas encore.
func _setup_input_actions() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])


func _add_action(action: StringName, physical_keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in physical_keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
