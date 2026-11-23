extends CharacterBody3D
## Contrôleur du personnage : déplacement ZQSD/WASD + flèches, Maj pour
## courir, saut, gravité, combat. L'apparence et l'animation sont gérées par
## soldier.gd (enfant Visual/Soldier), qui lit la vitesse de ce corps.
##
## Combat :
##   - attaque (clic gauche ou J) : coup d'épée devant soi ; l'impact tombe au
##     milieu de l'animation et touche les ennemis dans un arc frontal ;
##   - parade (clic droit ou K, maintenu) : bouclier levé, dégâts reçus de face
##     fortement réduits, déplacement ralenti ;
##   - à 0 PV : le soldat tombe, puis se relève au point de départ.
##
## Les actions sont déclarées avec des touches *physiques* : la touche en
## position "W" d'un clavier QWERTY est la touche "Z" d'un AZERTY, donc ZQSD
## et WASD fonctionnent sans configuration.

signal health_changed(health: float, max_health: float)

const SOLDIER := preload("res://scripts/soldier.gd")

## Vitesse de marche et de course (Maj maintenue), en m/s.
@export var walk_speed := 3.2
@export var run_speed := 6.5
@export var acceleration := 14.0
@export var jump_velocity := 4.5
@export var turn_speed := 10.0

@export_group("Combat")
@export var max_health := 100.0
@export var attack_damage := 12.0
## Portée et ouverture de l'arc frappé (cosinus minimal de l'angle).
@export var attack_reach := 1.9
@export var attack_arc := 0.25
## Part des dégâts encaissée en parant de face.
@export var block_factor := 0.15
@export var block_speed_factor := 0.4
@export var respawn_delay := 3.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var health := 0.0

var _soldier: Node3D
var _spawn := Vector3.ZERO
var _attack_timer := -1.0      # temps écoulé depuis le début de l'attaque
var _attack_hit_done := true
var _blocking := false
var _dead_timer := -1.0
var _knockback := Vector3.ZERO

@onready var visual: Node3D = $Visual


func _ready() -> void:
	add_to_group("player")
	add_to_group("characters")
	_setup_input_actions()
	_spawn = global_position
	health = max_health
	# Les allures de l'animation suivent les vitesses réglées ici.
	_soldier = get_node_or_null("Visual/Soldier")
	if _soldier:
		_soldier.walk_speed_ref = walk_speed
		_soldier.run_speed_ref = run_speed
	health_changed.emit.call_deferred(health, max_health)


func is_alive() -> bool:
	return _dead_timer < 0.0


## Appelé par les ennemis au moment de l'impact.
func take_damage(amount: float, from: Vector3) -> void:
	if not is_alive():
		return
	var to_attacker := from - global_position
	to_attacker.y = 0.0
	if _blocking and _forward().dot(to_attacker.normalized()) > 0.3:
		amount *= block_factor
	else:
		_knockback = -to_attacker.normalized() * 3.0
	health = maxf(health - amount, 0.0)
	if _soldier:
		_soldier.flash()
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()


func _die() -> void:
	_dead_timer = 0.0
	_blocking = false
	if _soldier:
		_soldier.set_blocking(false)
		_soldier.set_down(true)


func _respawn() -> void:
	_dead_timer = -1.0
	global_position = _spawn
	velocity = Vector3.ZERO
	health = max_health
	health_changed.emit(health, max_health)
	if _soldier:
		_soldier.set_down(false)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if not is_alive():
		_dead_timer += delta
		velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-6.0 * delta))
		velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-6.0 * delta))
		move_and_slide()
		if _dead_timer >= respawn_delay:
			_respawn()
		return

	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	_update_combat(delta)

	# Direction voulue, relative à la caméra : "avant" = vers le haut de
	# l'écran. Avec la vue isométrique (caméra tournée à 45°), c'est donc
	# une diagonale dans le monde.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _camera_relative(input)

	var speed := run_speed if Input.is_action_pressed("run") else walk_speed
	if _blocking:
		speed = walk_speed * block_speed_factor
	var target := direction * speed + _knockback
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	var blend := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, target.x, blend)
	velocity.z = lerpf(velocity.z, target.z, blend)

	move_and_slide()

	# Oriente la silhouette (son avant est -Z) vers la direction de marche.
	# Pendant la parade, on garde le bouclier tourné vers l'ennemi (pas de
	# demi-tour en reculant).
	if direction.length_squared() > 0.01 and not _blocking:
		var yaw := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


func _update_combat(delta: float) -> void:
	_blocking = Input.is_action_pressed("block") and _attack_timer < 0.0
	if _soldier:
		_soldier.set_blocking(_blocking)

	if _attack_timer < 0.0 and not _blocking and Input.is_action_just_pressed("attack"):
		_attack_timer = 0.0
		_attack_hit_done = false
		if _soldier:
			_soldier.play_attack()
	if _attack_timer >= 0.0:
		_attack_timer += delta
		var duration := SOLDIER.ATTACK_DURATION
		var hit_at := SOLDIER.ATTACK_HIT_AT
		if not _attack_hit_done and _attack_timer >= duration * hit_at:
			_attack_hit_done = true
			_strike()
		if _attack_timer >= duration:
			_attack_timer = -1.0


## Touche tous les ennemis vivants dans l'arc frontal.
func _strike() -> void:
	var forward := _forward()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var e := enemy as Node3D
		if e == null or not e.is_alive():
			continue
		var to := e.global_position - global_position
		to.y = 0.0
		if to.length() <= attack_reach and forward.dot(to.normalized()) >= attack_arc:
			e.take_damage(attack_damage, global_position)


func _forward() -> Vector3:
	var f := -visual.global_basis.z
	f.y = 0.0
	return f.normalized()


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
	_add_action("run", [KEY_SHIFT])
	_add_action("attack", [KEY_J], [MOUSE_BUTTON_LEFT])
	_add_action("block", [KEY_K], [MOUSE_BUTTON_RIGHT])


func _add_action(action: StringName, physical_keys: Array, mouse_buttons: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in physical_keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
	for button in mouse_buttons:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = button
		InputMap.action_add_event(action, mouse)
