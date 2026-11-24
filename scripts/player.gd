extends CharacterBody3D
## Contrôleur du personnage : déplacement ZQSD/WASD + flèches, Maj pour
## courir, saut, gravité, combat. L'apparence et l'animation sont gérées par
## soldier.gd (enfant Visual/Soldier), qui lit la vitesse de ce corps.
##
## Combat :
##   - attaque (clic gauche ou J) : un coup tiré au hasard parmi taille
##     horizontale, revers diagonal et coup vertical lourd (jamais deux fois
##     le même de suite) ; un clic pendant un coup enchaîne le suivant ;
##     en courant, estoc avec une fente en avant. Chaque coup a sa portée, son
##     arc et ses dégâts (HITS) ; l'impact tombe sur l'image clé de l'animation ;
##   - parade (clic droit ou K, maintenu) : bouclier levé, dégâts reçus de face
##     fortement réduits, déplacement ralenti ;
##   - esquive (Ctrl ou bouton du milieu) : roulade dans la direction des
##     touches (en arrière sans direction), invulnérable pendant l'essentiel
##     de la roulade, puis courte récupération ;
##   - à 0 PV : le soldat tombe, puis se relève au point de départ.
##
## Marches : un obstacle de moins de `max_step_height` (rocher, débris,
## marche) se franchit en marchant, sans sauter (voir _try_step_up).
##
## Retours d'impact : éclats d'os ou étincelles, micro-pause du jeu (« hit
## stop ») et secousse de caméra par cellules entières.
##
## Les actions sont déclarées avec des touches *physiques* : la touche en
## position "W" d'un clavier QWERTY est la touche "Z" d'un AZERTY, donc ZQSD
## et WASD fonctionnent sans configuration.

signal health_changed(health: float, max_health: float)

const SOLDIER := preload("res://scripts/soldier.gd")
const HIT_FX := preload("res://scripts/fx/hit_fx.gd")
const NATURE := preload("res://scripts/world/nature.gd")
## Enfoncement maximal dans la mare (m) et vitesse au plus profond (facteur).
const WADE_DEPTH := 0.55
const WADE_SPEED := 0.45

## Vitesse de marche et de course (Maj maintenue), en m/s.
@export var walk_speed := 3.2
@export var run_speed := 6.5
@export var acceleration := 14.0
@export var jump_velocity := 4.5
@export var turn_speed := 10.0
## Hauteur maximale franchie en marchant (rochers, débris, marches), en m.
@export var max_step_height := 0.45

@export_group("Combat")
@export var max_health := 100.0
## Part des dégâts encaissée en parant de face.
@export var block_factor := 0.15
@export var block_speed_factor := 0.4
@export var respawn_delay := 3.0
## Roulade : durée, vitesse, part de la durée sans dégâts, délai entre deux.
@export var roll_duration := 0.5
@export var roll_speed := 7.5
@export var roll_invulnerable := 0.75
@export var roll_cooldown := 0.35

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var health := 0.0

var _soldier: Node3D
var _spawn := Vector3.ZERO
## Effet de chaque coup (même ordre que soldier.gd MOVES) : portée (m), arc
## (cosinus minimal de l'angle avec l'avant : -0.15 = très large, 0.6 = étroit),
## dégâts, secousse, fente (élan vers l'avant, m/s).
const HITS := [
	{"reach": 2.0, "arc": -0.15, "damage": 10.0, "shake": 0.25, "lunge": 1.0},  # taille
	{"reach": 1.9, "arc": 0.0, "damage": 10.0, "shake": 0.25, "lunge": 1.0},    # revers
	{"reach": 1.9, "arc": 0.3, "damage": 18.0, "shake": 0.45, "lunge": 1.5},    # vertical
	{"reach": 2.5, "arc": 0.6, "damage": 16.0, "shake": 0.35, "lunge": 6.5},    # estoc
]
const ESTOC := 3

var _attack_timer := -1.0      # temps écoulé depuis le début de l'attaque
var _attack_kind := 0
var _last_kind := -1           # dernier coup donné (pour ne pas le répéter)
var _queued := false           # clic reçu pendant un coup : enchaîner
var _rng := RandomNumberGenerator.new()
var _lunge := Vector3.ZERO
var _roll_timer := -1.0        # temps écoulé dans la roulade, -1 = aucune
var _roll_cooldown_left := 0.0
var _roll_dir := Vector3.ZERO
var _wade := 0.0               # profondeur dans la mare (0 = au sec, 1 = au plus profond)
# Montée de marche : le corps est déjà en haut, le visuel part d'en bas
# (`_step_rise` m plus bas) et le rejoint pendant l'animation.
var _step_rise := 0.0
var _step_time := 0.0
var _step_duration := 0.3
var _attack_hit_done := true
var _blocking := false
var _dead_timer := -1.0
var _knockback := Vector3.ZERO

@onready var visual: Node3D = $Visual


func _ready() -> void:
	add_to_group("player")
	_rng.randomize()
	add_to_group("characters")
	_setup_input_actions()
	_spawn = global_position
	health = max_health
	# Les allures de l'animation suivent les vitesses réglées ici.
	_soldier = get_node_or_null("Visual/Soldier")
	if _soldier:
		_soldier.walk_speed_ref = walk_speed
		_soldier.run_speed_ref = run_speed
		_soldier.footstep.connect(_on_footstep)
	health_changed.emit.call_deferred(health, max_health)


func is_alive() -> bool:
	return _dead_timer < 0.0


## Appelé par les ennemis au moment de l'impact.
func take_damage(amount: float, from: Vector3) -> void:
	if not is_alive():
		return
	# Roulade : le coup passe à côté.
	if _roll_timer >= 0.0 and _roll_timer < roll_duration * roll_invulnerable:
		return
	var to_attacker := from - global_position
	to_attacker.y = 0.0
	if _blocking and _forward().dot(to_attacker.normalized()) > 0.3:
		amount *= block_factor
		# Étincelles sur le bouclier.
		HIT_FX.burst(self, global_position + Vector3.UP * 1.1 + _forward() * 0.35, Color(1.0, 0.6, 0.2), 16, 3.5, 0.035, 0.35)
		Sfx.play("block", global_position + Vector3.UP)
		if _soldier:
			_soldier.hit_react(from, 0.35)
		_shake(0.25)
	else:
		_knockback = -to_attacker.normalized() * 3.0
		Sfx.play("hurt", global_position + Vector3.UP)
		if _soldier:
			_soldier.hit_react(from, 1.0)
		_shake(0.55)
		_hit_stop(0.07)
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
	_update_wading(delta)
	if _update_roll(delta):
		return

	# Direction voulue, relative à la caméra : "avant" = vers le haut de
	# l'écran. Avec la vue isométrique (caméra tournée à 45°), c'est donc
	# une diagonale dans le monde.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _camera_relative(input)

	var speed := run_speed if Input.is_action_pressed("run") else walk_speed
	# Dans la mare : on s'enfonce et on avance plus lentement.
	speed *= lerpf(1.0, WADE_SPEED, _wade)
	if _blocking:
		speed = walk_speed * block_speed_factor
	elif _attack_timer >= 0.0:
		# Pendant un coup, le soldat est engagé : il avance à peine (sinon ses
		# pieds glisseraient sous la posture d'appui).
		speed = walk_speed * 0.25
	var target := direction * speed + _knockback + _lunge
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	_lunge = _lunge.lerp(Vector3.ZERO, 1.0 - exp(-7.0 * delta))
	var blend := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, target.x, blend)
	velocity.z = lerpf(velocity.z, target.z, blend)

	move_and_slide()
	# Bloqué par un obstacle bas en avançant : on tente de le franchir.
	if is_on_wall() and direction.length_squared() > 0.01:
		_try_step_up(direction, delta)

	# Oriente la silhouette (son avant est -Z) vers la direction de marche.
	# Pendant la parade, on garde le bouclier tourné vers l'ennemi (pas de
	# demi-tour en reculant).
	if direction.length_squared() > 0.01 and not _blocking:
		var yaw := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


func _update_combat(delta: float) -> void:
	# Souris sur un élément d'interface (réglage du volume) : ses clics ne
	# sont pas des coups d'épée.
	var on_ui := get_viewport().gui_get_hovered_control() != null
	_blocking = Input.is_action_pressed("block") and _attack_timer < 0.0 and not on_ui
	if _soldier:
		_soldier.set_blocking(_blocking)

	var pressed := not _blocking and not on_ui and Input.is_action_just_pressed("attack")
	if pressed and _attack_timer < 0.0:
		var running := Input.is_action_pressed("run") and Vector2(velocity.x, velocity.z).length() > walk_speed * 1.3
		_start_attack(ESTOC if running else _random_move())
	elif pressed:
		# Clic pendant un coup : le suivant s'enchaîne dès la fin de celui-ci.
		_queued = true

	if _attack_timer >= 0.0:
		_attack_timer += delta
		var move: Dictionary = SOLDIER.MOVES[_attack_kind]
		var duration: float = move["duration"]
		if not _attack_hit_done and _attack_timer >= duration * float(move["hit"]):
			_attack_hit_done = true
			_strike()
		if _attack_timer >= duration:
			_attack_timer = -1.0
			if _queued:
				_start_attack(_random_move())


## Coup au hasard parmi taille, revers, vertical, différent du précédent.
func _random_move() -> int:
	var choices: Array[int] = [0, 1, 2]
	choices.erase(_last_kind)
	return choices[_rng.randi() % choices.size()]


## Roulade d'esquive. Retourne vrai tant qu'elle dure (elle remplace alors
## le déplacement normal).
func _update_roll(delta: float) -> bool:
	_roll_cooldown_left -= delta
	if _roll_timer < 0.0:
		if Input.is_action_just_pressed("dodge") and _roll_cooldown_left <= 0.0 and is_on_floor() and _attack_timer < 0.0:
			var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			_roll_dir = _camera_relative(input).normalized()
			if _roll_dir == Vector3.ZERO:
				_roll_dir = -_forward() # sans direction : roulade en arrière
				visual.rotation.y = atan2(_roll_dir.x, _roll_dir.z) # dos tourné à la roulade
			else:
				visual.rotation.y = atan2(-_roll_dir.x, -_roll_dir.z)
			_roll_timer = 0.0
			_blocking = false
			if _soldier:
				_soldier.set_blocking(false)
				_soldier.play_roll(roll_duration, input == Vector2.ZERO)
			Sfx.play("swing", global_position + Vector3.UP * 0.5, -6.0, 0.05, 0.6)
		else:
			return false
	_roll_timer += delta
	# Élan fort au début, qui retombe en fin de roulade.
	var speed := roll_speed * (1.0 - smoothstep(0.55, 1.0, _roll_timer / roll_duration))
	velocity.x = _roll_dir.x * speed
	velocity.z = _roll_dir.z * speed
	move_and_slide()
	if _roll_timer >= roll_duration:
		_roll_timer = -1.0
		_roll_cooldown_left = roll_cooldown
		Sfx.play("step", global_position, -4.0)
	return true


## Franchit une marche : on soulève le corps de max_step_height, on avance,
## puis on le redescend jusqu'au sol. Si le chemin est libre et que le point
## d'arrivée est un sol assez plat et pas plus haut que max_step_height, le
## corps y est placé. Le visuel est abaissé d'autant puis remonte en douceur,
## pour que la montée ne fasse pas sauter l'image.
func _try_step_up(direction: Vector3, delta: float) -> bool:
	var start := global_transform
	var up := Vector3.UP * max_step_height
	var forward := direction.normalized() * maxf(walk_speed * delta, 0.12)
	# Place au-dessus ?
	if test_move(start, up):
		return false
	var raised := start.translated(up)
	# Toujours bloqué une fois soulevé : obstacle trop haut.
	if test_move(raised, forward):
		return false
	var advanced := raised.translated(forward)
	var hit := KinematicCollision3D.new()
	if not test_move(advanced, -up, hit):
		return false # rien dessous : ce n'est pas une marche
	if hit.get_normal().y < 0.7:
		return false # pente trop raide
	var landed := advanced.translated(hit.get_travel())
	var rise := landed.origin.y - start.origin.y
	if rise <= 0.02 or rise > max_step_height:
		return false
	global_transform = landed
	velocity.y = 0.0
	# Le visuel part d'où il en était (escalier : montées enchaînées).
	_step_rise = _step_remaining() + rise
	_step_duration = clampf(0.18 + rise * 0.5, 0.2, 0.42)
	_step_time = 0.0
	if _soldier:
		_soldier.play_step(_step_duration)
	return true


## Hauteur dont le visuel est encore en dessous du corps pendant une montée :
## elle diminue vite au début (la jambe pousse) puis ralentit en arrivant.
func _step_remaining() -> float:
	if _step_rise <= 0.0:
		return 0.0
	var t := clampf(_step_time / _step_duration, 0.0, 1.0)
	if t >= 1.0:
		_step_rise = 0.0
		return 0.0
	return _step_rise * (1.0 - ease(t, 0.45))


## Pas : bruit d'herbe au sec, éclaboussure (son + gouttes) dans la mare.
func _on_footstep(run: float) -> void:
	if _wade > 0.05:
		Sfx.play("splash", global_position, lerpf(-8.0, -2.0, _wade), 0.15)
		HIT_FX.burst(self, global_position + Vector3.UP * (0.05 + 0.1 * _wade), Color(0.6, 0.68, 0.78), 8, 1.6, 0.03, 0.45)
	else:
		Sfx.play("step", global_position, lerpf(-10.0, -4.0, run), 0.15)


## Mare : enfoncement progressif (le décor ne peut pas être creusé, on
## abaisse donc le visuel ; l'eau opaque cache le bas du corps) et sillage.
func _update_wading(delta: float) -> void:
	var target := NATURE.pond_wade(Vector2(global_position.x, global_position.z))
	_wade = move_toward(_wade, target, delta * 2.5)
	# Après une montée de marche, le visuel rattrape le corps en douceur.
	_step_time += delta
	visual.position.y = -WADE_DEPTH * _wade - _step_remaining()
	var moving := clampf(Vector2(velocity.x, velocity.z).length() / walk_speed, 0.0, 1.0)
	for water in get_tree().get_nodes_in_group("water"):
		var mesh := water as GeometryInstance3D
		if mesh and mesh.material_override is ShaderMaterial:
			var mat := mesh.material_override as ShaderMaterial
			mat.set_shader_parameter("wake_position", Vector2(global_position.x, global_position.z))
			mat.set_shader_parameter("wake_strength", (0.25 + 0.75 * moving) * minf(_wade * 3.0, 1.0))


func _start_attack(kind: int) -> void:
	_last_kind = kind
	_attack_kind = kind
	_attack_timer = 0.0
	_attack_hit_done = false
	_queued = false
	if _soldier:
		_soldier.play_attack(kind)
	# Les coups légers sifflent plus aigu, le coup vertical plus grave.
	var pitch: float = [1.1, 1.15, 0.85, 1.0][kind]
	Sfx.play("swing", global_position + Vector3.UP, -3.0, 0.08, pitch)
	_lunge = _forward() * float(HITS[kind]["lunge"])


## Touche tous les ennemis vivants dans la zone du coup en cours.
func _strike() -> void:
	var forward := _forward()
	var hit := false
	var params: Dictionary = HITS[_attack_kind]
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var e := enemy as Node3D
		if e == null or not e.is_alive():
			continue
		var to := e.global_position - global_position
		to.y = 0.0
		if to.length() <= params["reach"] and forward.dot(to.normalized()) >= params["arc"]:
			e.take_damage(params["damage"], global_position)
			HIT_FX.burst(self, e.global_position + Vector3.UP * 1.1 - to.normalized() * 0.2, Color(0.9, 0.88, 0.8), 14)
			Sfx.play("hit_bone", e.global_position + Vector3.UP)
			hit = true
	if hit:
		_shake(params["shake"])
		_hit_stop(0.07 if _attack_kind == 2 else 0.05)


## Micro-pause : le temps de jeu ralentit presque à l'arrêt quelques
## centièmes de seconde (temps réel), ce qui donne du poids à l'impact.
func _hit_stop(duration: float) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _shake(amount: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("shake"):
		camera.shake(amount)


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
	_add_action("dodge", [KEY_CTRL, KEY_L], [MOUSE_BUTTON_MIDDLE])


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
