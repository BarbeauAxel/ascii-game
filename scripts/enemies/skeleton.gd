extends CharacterBody3D
## Squelette ennemi, construit en code et animé de façon procédurale (même
## principe que soldier.gd : hiérarchie de pivots portant des os simples).
##
## Comportement (machine à états) :
##   ERRANCE   : marche lente vers des points tirés autour de son poste ;
##   POURSUITE : le joueur est à portée de vue -> il fonce sur lui, mâchoire
##               qui claque ;
##   ATTAQUE   : armé au-dessus de la tête, puis coup vers le bas ; le joueur
##               n'est touché que s'il est encore devant et à portée ;
##   CHANCELLE : touché, il recule (recul + éclat blanc) ;
##   VAINCU    : effondré en tas d'os pour de bon ; son âme s'échappe en
##               particules bleues qui s'élèvent quelques secondes.
##   ÉVEIL     : (gardien) se relève lentement d'un tas d'os, puis attaque.
##
## Gardien (`is_boss`) : même squelette, agrandi (`size_scale`), avec heaume à
## cornes, couronne, cape et grande hache ; deux attaques en alternance
## (coup vertical, balayage large) ; ne chancelle qu'un coup sur `poise`.
##
## Les os sont exagérés (2 à 3 fois l'épaisseur réelle) : à 5 px par
## cellule, un os réaliste tiendrait dans moins d'une cellule et disparaîtrait.
##
## Déplacements : chemins calculés sur la carte de navigation
## (NavigationAgent3D, voir world/navigation.gd) pour contourner murs et
## piliers. Si la carte n'est pas prête, direction directe ; s'il bute malgré
## tout contre un obstacle, il le longe un instant.

signal died
signal health_changed(health: float, max_health: float)
## Durée pendant laquelle l'âme s'échappe après la défaite (secondes).
const SOUL_TIME := 3.5

@export var max_health := 30.0
@export var walk_speed := 1.0
@export var chase_speed := 2.6
@export var sight_range := 9.0
@export var attack_range := 1.5
@export var attack_damage := 12.0
@export var wander_radius := 4.0
@export var bone_color := Color(0.8, 0.76, 0.64)
@export var eye_color := Color(1.0, 0.35, 0.08)
## Lueur propre des os (0 = aucune).
@export var bone_glow := 0.18
## Couleur de l'âme qui s'échappe à la défaite (particules).
@export var soul_color := Color(0.6, 0.85, 1.0)

@export_group("Attaque")
## Armé (le joueur a le temps de parer / reculer), impact, fin de l'attaque (s).
@export var attack_windup := 0.55
@export var attack_strike := 0.72
@export var attack_end := 1.3

@export_group("Gardien")
@export var is_boss := false
## Échelle de tout le squelette (visuel, collision, portée de vue).
@export var size_scale := 1.0
## Ne chancelle qu'un coup reçu sur `poise` (1 = à chaque coup).
@export var poise := 1
## Apparaît effondré et se relève (durée de l'éveil en secondes, 0 = debout).
@export var rise_time := 0.0

enum State { WANDER, CHASE, ATTACK, STAGGER, DEAD, RISING }

## Attaques, animées sur tout le corps (mêmes conventions que soldier.gd :
## épaule x vers l'avant / le haut, y pivot gauche +, z écarté ; poignet ≈ -1
## lame dans l'axe du bras ; buste x + = penché en avant ; bassin (rotation,
## descente, roulis) ; jambes [cuisse G, genou G, cuisse D, genou D]).
## Choisies au hasard, jamais deux fois la même de suite. Le rythme (armé,
## impact, fin) vient de attack_windup / attack_strike / attack_end.
## reach : portée ajoutée à attack_range ; arc : cosinus minimal (−0,15 =
## très large) ; damage : facteur de attack_damage ; lunge : élan (m/s).
const MOVES := [
	{ # 0 : coup vertical, armé au-dessus de la tête, pas en avant
		"reach": 0.4, "arc": 0.35, "damage": 1.0, "lunge": 0.0,
		"start": {"arm": [Vector3(2.7, 0.0, 0.25), 0.9, 0.0], "off": [Vector3(0.6, 0.0, -0.4), 0.8],
			"torso": Vector2(-0.25, 0.3), "hips": Vector3(-0.2, 0.0, 0.0), "legs": [0.1, -0.1, -0.15, -0.05]},
		"end": {"arm": [Vector3(-0.3, 0.0, 0.0), 0.1, 0.0], "off": [Vector3(-0.3, 0.0, -0.5), 0.5],
			"torso": Vector2(0.5, -0.45), "hips": Vector3(0.15, 0.15, 0.0), "legs": [-0.35, -0.25, 0.55, -0.7]},
	},
	{ # 1 : balayage horizontal, de droite à gauche
		"reach": 0.9, "arc": -0.15, "damage": 0.7, "lunge": 0.0,
		"start": {"arm": [Vector3(1.35, -1.35, 0.15), 0.4, -1.0], "off": [Vector3(0.35, 0.0, -0.55), 0.9],
			"torso": Vector2(0.05, -0.65), "hips": Vector3(-0.45, 0.07, 0.05), "legs": [0.3, -0.4, -0.3, -0.3]},
		"end": {"arm": [Vector3(1.45, 1.1, 0.0), 0.2, -1.0], "off": [Vector3(-0.45, 0.0, -0.4), 0.6],
			"torso": Vector2(-0.1, 0.8), "hips": Vector3(0.5, 0.1, -0.06), "legs": [0.35, -0.5, -0.4, -0.25]},
	},
	{ # 2 : estoc, épée ramenée puis fente en avant
		"reach": 1.1, "arc": 0.65, "damage": 0.85, "lunge": 4.5,
		"start": {"arm": [Vector3(0.4, 0.25, 0.1), 1.6, -1.15], "off": [Vector3(0.7, 0.0, 0.0), 1.1],
			"torso": Vector2(-0.05, 0.55), "hips": Vector3(-0.5, 0.08, 0.0), "legs": [0.2, -0.4, -0.3, -0.3]},
		"end": {"arm": [Vector3(1.5, -0.1, 0.0), 0.05, -1.2], "off": [Vector3(-0.55, 0.0, -0.4), 0.4],
			"torso": Vector2(0.45, -0.3), "hips": Vector3(0.2, 0.2, 0.0), "legs": [-0.6, -0.15, 0.7, -0.6]},
	},
]

## Calque « cellules fines » partagé avec le soldat (soldier.gd, FINE_LAYER).
const FINE_LAYER := 3
const NATURE := preload("res://scripts/world/nature.gd")

var state := State.WANDER
var health := 0.0
var home := Vector3.ZERO

var _player: Node3D
var _state_time := 0.0
var _hit_done := false
var _wander_target := Vector3.ZERO
var _wander_wait := 0.0
var _knockback := Vector3.ZERO
var _avoid_time := 0.0
var _avoid_sign := 1.0
var _rng := RandomNumberGenerator.new()
# Ligne de vue : le joueur n'est repéré, attaqué et touché que si aucun mur ne
# s'interpose. Sans elle, un squelette caché derrière un mur pouvait frapper
# au travers.
var _sees_player := false
var _los_timer := 0.0
var _last_seen := Vector3.ZERO
var _lost_time := 0.0
var _rattle_timer := 0.0
var _wade := 0.0   # profondeur dans la mare (voir player.gd)
var _attack_kind := 0       # index dans MOVES
var _last_kind := -1
var _lunged := false
# Réaction au coup reçu : direction de l'attaquant (repère du squelette) et
# intensité qui retombe.
var _hit_local := Vector3.FORWARD
var _react := 0.0
var _hits_taken := 0
var _voice_pitch := 1.0     # sons plus graves pour un grand squelette
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _collision: CollisionShape3D
var _agent: NavigationAgent3D
var _nav_target := Vector3.INF   # cible actuelle du calcul de chemin
# Âme qui s'échappe à la défaite : particules bleues qui montent.
var _wisps: CPUParticles3D

# Squelette visuel
var _visual: Node3D
var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _head: Node3D
var _jaw: Node3D
var _thigh: Array[Node3D] = []
var _knee: Array[Node3D] = []
var _ankle: Array[Node3D] = []
var _shoulder: Array[Node3D] = []
var _elbow: Array[Node3D] = []
var _hand: Array[Node3D] = []
var _phase := 0.0
var _time := 0.0
var _walk := 0.0
var _collapse := 0.0
var _flash := 0.0
var _materials: Array[StandardMaterial3D] = []

var _m_bone: StandardMaterial3D
var _m_joint: StandardMaterial3D
var _m_rag: StandardMaterial3D
var _m_rust: StandardMaterial3D
var _m_socket: StandardMaterial3D
var _m_eye: StandardMaterial3D


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("characters")
	_rng.randomize()
	health = max_health
	home = global_position
	_wander_target = home
	_time = _rng.randf() * 10.0

	_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3 * size_scale
	capsule.height = 1.75 * size_scale
	_collision.shape = capsule
	_collision.position = Vector3(0, 0.875 * size_scale, 0)
	add_child(_collision)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.5
	_agent.path_max_distance = 2.0
	add_child(_agent)
	_voice_pitch = 1.0 / size_scale
	# Boîte englobante lue par le shader ASCII (test de profondeur des cellules fines).
	set_meta("fine_height", 2.1 * size_scale)
	set_meta("fine_radius", 0.9 * size_scale)

	_make_materials()
	_make_soul_fx()
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_build()
	_visual.scale = Vector3.ONE * size_scale
	_visual.rotation.y = _rng.randf() * TAU
	if rise_time > 0.0:
		_set_state(State.RISING)
		_collapse = 1.0


func is_alive() -> bool:
	return state != State.DEAD


## Appelé par le joueur quand son épée touche.
func take_damage(amount: float, from: Vector3) -> void:
	if state == State.DEAD:
		return
	if state == State.RISING:
		return
	health -= amount
	health_changed.emit(maxf(health, 0.0), max_health)
	_flash = 1.0
	_hits_taken += 1
	var push := global_position - from
	push.y = 0.0
	_knockback = push.normalized() * 2.0 / size_scale
	# Direction de l'attaquant dans le repère du squelette (avant = -Z).
	_hit_local = (_visual.global_basis.inverse() * (from - global_position))
	_hit_local.y = 0.0
	_hit_local = _hit_local.normalized()
	_react = 1.0
	if health <= 0.0:
		_set_state(State.DEAD)
		# Plus d'obstacle pour les autres (le joueur passe sur le tas d'os),
		# mais la collision avec le sol reste : sinon la gravité l'entraînerait
		# sous la terre.
		set_deferred("collision_layer", 0)
		Sfx.play("collapse", global_position + Vector3.UP * 0.5, 0.0, 0.08, _voice_pitch)
		get_tree().create_timer(0.35).timeout.connect(func() -> void:
			Sfx.play("soul", global_position + Vector3.UP, -2.0, 0.05, _voice_pitch))
		died.emit()
	elif _hits_taken % poise == 0:
		_set_state(State.STAGGER)


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0
	_hit_done = false


func _physics_process(delta: float) -> void:
	_state_time += delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var to_player := Vector3.ZERO
	var dist := INF
	if _player and _player.has_method("is_alive") and _player.is_alive():
		to_player = _player.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()
		# Rayon testé 10 fois par seconde, seulement si le joueur est à portée.
		_los_timer -= delta
		if dist < sight_range * 1.6 and _los_timer <= 0.0:
			_los_timer = 0.1
			_sees_player = _line_of_sight(1.3)
		elif dist >= sight_range * 1.6:
			_sees_player = false
		if _sees_player:
			_last_seen = _player.global_position
			_lost_time = 0.0
		else:
			_lost_time += delta

	var desired := Vector3.ZERO
	var face := Vector3.ZERO
	match state:
		State.WANDER:
			if dist < sight_range and _sees_player:
				_set_state(State.CHASE)
				Sfx.play("rattle", global_position + Vector3.UP * 1.4, 0.0, 0.08, _voice_pitch)
			elif _wander_wait > 0.0:
				_wander_wait -= delta
			else:
				var to_target := _wander_target - global_position
				to_target.y = 0.0
				if to_target.length() < 0.5:
					var a := _rng.randf() * TAU
					_wander_target = _reachable(home + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.5, wander_radius))
					_wander_wait = _rng.randf_range(1.0, 3.5)
				else:
					desired = _nav_direction(_wander_target) * walk_speed
		State.CHASE:
			if dist > sight_range * 1.6 or _lost_time > 2.5:
				# Perdu de vue trop longtemps : retour au poste.
				_set_state(State.WANDER)
				_wander_target = home
			elif dist < attack_range and _sees_player:
				_set_state(State.ATTACK)
				# Attaque tirée au hasard, différente de la précédente.
				var choices: Array[int] = [0, 1, 2]
				choices.erase(_last_kind)
				_attack_kind = choices[_rng.randi() % choices.size()]
				_last_kind = _attack_kind
				_lunged = false
				Sfx.play("rattle", global_position + Vector3.UP * 1.4, 2.0, 0.08, _voice_pitch)
			elif _sees_player:
				desired = _nav_direction(_player.global_position) * chase_speed
				# Claquements d'os de temps en temps pendant la poursuite.
				_rattle_timer -= delta
				if _rattle_timer <= 0.0:
					_rattle_timer = _rng.randf_range(1.8, 3.5)
					Sfx.play("rattle", global_position + Vector3.UP * 1.4, -4.0, 0.08, _voice_pitch)
			else:
				# Va voir là où il l'a aperçu pour la dernière fois.
				var to_last := _last_seen - global_position
				to_last.y = 0.0
				if to_last.length() > 0.5:
					desired = _nav_direction(_last_seen) * chase_speed
		State.ATTACK:
			face = to_player
			var move: Dictionary = MOVES[_attack_kind]
			# Fente : élan vers l'avant à la fin de l'armé.
			if not _lunged and _state_time >= attack_windup and float(move["lunge"]) > 0.0:
				_lunged = true
				_knockback = -_visual.global_basis.z * float(move["lunge"])
			if not _hit_done and _state_time >= attack_strike:
				_hit_done = true
				var forward := -_visual.global_basis.z
				Sfx.play("swing", global_position + Vector3.UP * 1.5, 0.0, 0.08, _voice_pitch)
				var reach := attack_range + float(move["reach"])
				var arc: float = move["arc"]
				var damage := attack_damage * float(move["damage"])
				if dist < reach and forward.dot(to_player.normalized()) > arc and _line_of_sight(1.0):
					_player.take_damage(damage, global_position)
			if _state_time >= attack_end:
				_set_state(State.CHASE)
		State.STAGGER:
			if _state_time >= 0.45:
				_set_state(State.CHASE)
		State.DEAD:
			pass
		State.RISING:
			if _state_time >= rise_time:
				_set_state(State.CHASE)

	# Contournement : s'il bute contre un mur, il le longe un moment.
	if _avoid_time > 0.0:
		_avoid_time -= delta
		desired = desired.rotated(Vector3.UP, _avoid_sign * PI * 0.5)

	# Mare : il s'enfonce (visuel abaissé) et ralentit.
	_wade = move_toward(_wade, NATURE.pond_wade(Vector2(global_position.x, global_position.z)), delta * 2.5)
	_visual.position.y = -0.55 * _wade
	desired *= lerpf(1.0, 0.5, _wade)
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	horizontal = horizontal.lerp(desired, 1.0 - exp(-10.0 * delta)) + _knockback
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	if desired.length() > 0.1 and is_on_wall() and _avoid_time <= 0.0:
		_avoid_time = 0.7
		_avoid_sign = 1.0 if _rng.randf() < 0.5 else -1.0

	# Orientation : vers la direction de marche, ou vers le joueur en attaque.
	if face == Vector3.ZERO and desired.length() > 0.1:
		face = desired
	if face.length() > 0.01 and state != State.DEAD:
		var yaw := atan2(-face.x, -face.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, 1.0 - exp(-8.0 * delta))


## Applique la pose d'attaque à l'instant `t` (secondes depuis le début).
func _apply_attack_pose(t: float) -> void:
	var move: Dictionary = MOVES[_attack_kind]
	var raise := smoothstep(0.0, attack_windup, t)
	var strike := smoothstep(attack_windup, attack_strike, t)
	# Bassin et jambes partent un peu avant le bras.
	var body := smoothstep(attack_windup * 0.75, attack_strike * 0.92, t)
	var weight := minf(raise, 1.0 - smoothstep(attack_strike + 0.15, attack_end, t))
	var a: Dictionary = move["start"]
	var b: Dictionary = move["end"]
	var arm_a: Array = a["arm"]
	var arm_b: Array = b["arm"]
	_shoulder[1].rotation = _shoulder[1].rotation.lerp((arm_a[0] as Vector3).lerp(arm_b[0], strike), weight)
	_elbow[1].rotation.x = lerpf(_elbow[1].rotation.x, lerpf(arm_a[1], arm_b[1], strike), weight)
	_hand[1].rotation.x = lerpf(0.0, lerpf(arm_a[2], arm_b[2], strike), weight)
	var off_a: Array = a["off"]
	var off_b: Array = b["off"]
	_shoulder[0].rotation = _shoulder[0].rotation.lerp((off_a[0] as Vector3).lerp(off_b[0], body), weight)
	_elbow[0].rotation.x = lerpf(_elbow[0].rotation.x, lerpf(off_a[1], off_b[1], body), weight)
	var torso: Vector2 = (a["torso"] as Vector2).lerp(b["torso"], strike)
	# Rotation x positive = buste rejeté en arrière : « penché en avant » est négatif.
	_spine.rotation.x -= torso.x * weight
	_spine.rotation.y += torso.y * weight
	var hips: Vector3 = (a["hips"] as Vector3).lerp(b["hips"], body)
	_hips.rotation.y = lerpf(_hips.rotation.y, hips.x, weight)
	_hips.rotation.z = lerpf(_hips.rotation.z, hips.z, weight)
	_hips.position.y -= hips.y * weight
	var legs_a: Array = a["legs"]
	var legs_b: Array = b["legs"]
	for i in 2:
		var thigh := lerpf(legs_a[i * 2], legs_b[i * 2], body)
		var knee := lerpf(legs_a[i * 2 + 1], legs_b[i * 2 + 1], body)
		_thigh[i].rotation.x = lerpf(_thigh[i].rotation.x, thigh, weight)
		_knee[i].rotation.x = lerpf(_knee[i].rotation.x, knee, weight)
		_ankle[i].rotation.x = -(_thigh[i].rotation.x + _knee[i].rotation.x) * 0.8
	_head.rotation.y -= (hips.x + torso.y) * 0.6 * weight
	_head.rotation.x += 0.4 * torso.x * weight


## Direction (horizontale, normalisée) vers `target` en suivant le chemin
## calculé sur la carte de navigation. Le chemin n'est recalculé que si la
## cible a bougé de plus de 0,5 m.
func _nav_direction(target: Vector3) -> Vector3:
	var direct := target - global_position
	direct.y = 0.0
	if _nav_target.distance_to(target) > 0.5:
		_nav_target = target
		_agent.target_position = target
	if direct.length() < 1.2 or _agent.is_navigation_finished():
		return direct.normalized()
	var to_next := _agent.get_next_path_position() - global_position
	to_next.y = 0.0
	# Carte pas encore prête (ou point déjà atteint) : direction directe.
	if to_next.length() < 0.05:
		return direct.normalized()
	return to_next.normalized()


## Point de la carte de navigation le plus proche (une cible d'errance tirée
## dans un mur est ramenée sur le sol praticable).
func _reachable(point: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return point
	return NavigationServer3D.map_get_closest_point(map, point)


## Vrai si rien de solide (mur, pilier, rocher…) ne sépare le squelette du
## joueur, à la hauteur donnée. Les personnages ne bloquent pas la vue.
func _line_of_sight(height: float) -> bool:
	var from := global_position + Vector3.UP * height
	var to := _player.global_position + Vector3.UP * height
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array[RID] = []
	for node in get_tree().get_nodes_in_group("characters"):
		if node is CollisionObject3D:
			exclude.append((node as CollisionObject3D).get_rid())
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Animation ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk = lerpf(_walk, clampf(speed / 1.4, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	_phase = fmod(_phase + speed / 1.3 * TAU * delta, TAU)
	if state == State.RISING:
		# Éveil : le tas d'os se redresse lentement.
		_collapse = 1.0 - smoothstep(0.3, rise_time, _state_time)
	else:
		var target_collapse := 1.0 if state == State.DEAD else 0.0
		_collapse = move_toward(_collapse, target_collapse, delta * 4.0)
	_flash = move_toward(_flash, 0.0, delta * 5.0)

	var s := sin(_phase)
	var c := cos(_phase)
	var w := _walk
	var idle := 1.0 - w
	var k := _collapse
	# Démarche raide et saccadée : le sinus est « écrasé ».
	var jerk := signf(s) * pow(absf(s), 0.6)

	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var thigh := jerk * side * 0.5 * w
		var knee := -(0.12 + 0.8 * maxf(0.0, c * side) * w)
		# Effondré : assis, jambes écartées en avant.
		_thigh[i].rotation = Vector3(lerpf(thigh, 1.45, k), 0.0, lerpf(side * -0.04, side * 0.5, k))
		_knee[i].rotation.x = lerpf(knee, -0.15, k)
		_ankle[i].rotation.x = lerpf(-(thigh + knee) * 0.8, 0.5, k)

	_hips.position.y = lerpf(0.95 + (absf(c) - 0.5) * 0.04 * w, 0.17, k)
	_hips.rotation = Vector3(lerpf(0.0, -0.35, k), s * 0.12 * w, s * 0.05 * w)
	var hunch := 0.18 + 0.12 * (1.0 if state == State.CHASE else 0.0)
	_spine.rotation = Vector3(lerpf(-hunch + sin(_time * 1.3) * 0.03 * idle, 1.05, k), -s * 0.2 * w, 0.0)
	_head.rotation = Vector3(
		lerpf(0.15 + sin(_time * 2.1) * 0.06, 0.6, k),
		sin(_time * 0.7) * 0.4 * idle,
		lerpf(sin(_time * 1.7) * 0.08, 0.7, k))
	var chatter := 1.0 if state == State.CHASE or state == State.ATTACK else 0.15
	_jaw.rotation.x = absf(sin(_time * 17.0)) * 0.35 * chatter

	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var arm := -jerk * side * 0.35 * w
		_shoulder[i].rotation = Vector3(lerpf(arm + 0.1, 0.2, k), 0.0, lerpf(side * -0.12, side * -0.9, k))
		_elbow[i].rotation.x = lerpf(0.35 + 0.3 * w, 0.1, k)

	# Attaque : repos -> pose armée -> pose finale -> repos, sur tout le corps.
	_hand[1].rotation = Vector3.ZERO
	if state == State.ATTACK:
		_apply_attack_pose(_state_time)

	# Réaction au coup : le corps part à l'opposé de l'attaquant (frappé de
	# face : buste rejeté en arrière ; de côté : il plie de l'autre côté),
	# bras qui s'écartent. Plus marqué quand il chancelle.
	_react = move_toward(_react, 0.0, delta * 2.6)
	if _react > 0.0:
		var r := _react * _react * (1.0 if state == State.STAGGER else 0.45)
		_spine.rotation.x -= _hit_local.z * 0.7 * r
		_spine.rotation.z += _hit_local.x * 0.6 * r
		_head.rotation.x -= _hit_local.z * 0.5 * r
		_head.rotation.z += _hit_local.x * 0.5 * r
		_hips.position.y -= 0.05 * r
		for i in 2:
			var side := -1.0 if i == 0 else 1.0
			_shoulder[i].rotation.z += side * 0.5 * r

	# Éclat blanc quand il est touché ; yeux qui s'éteignent à terre.
	for m in _materials:
		m.emission_energy_multiplier = _flash * 1.5
	# Lueur pâle permanente des os : de nuit, ils se détachent du décor sombre.
	_m_bone.emission_energy_multiplier += bone_glow

	# Vaincu : les yeux s'éteignent et l'âme s'échappe quelques secondes.
	_m_eye.emission_energy_multiplier = lerpf(6.0, 0.0, k)
	_wisps.emitting = state == State.DEAD and _state_time < SOUL_TIME


# --- Construction ---------------------------------------------------------------------

func _build() -> void:
	_hips = _joint(_visual, Vector3(0, 0.95, 0))
	_mesh(_hips, _box(Vector3(0.26, 0.1, 0.12)), _m_bone, Vector3(0, -0.02, 0))
	for side: float in [-1.0, 1.0]:
		_mesh(_hips, _sphere(0.045), _m_joint, Vector3(side * 0.1, -0.05, 0))
	# Haillons qui pendent de la ceinture (matière souple : pas de contours).
	_mesh(_hips, _box(Vector3(0.3, 0.38, 0.012)), _m_rag, Vector3(0, -0.2, -0.075), Vector3(0.08, 0, 0))
	_mesh(_hips, _box(Vector3(0.22, 0.3, 0.012)), _m_rag, Vector3(0.03, -0.16, 0.075), Vector3(-0.1, 0, 0.1))
	_mesh(_hips, _box(Vector3(0.3, 0.035, 0.16)), _m_rag, Vector3(0, 0.035, 0))

	for i in 2:
		var x := -0.1 if i == 0 else 0.1
		var thigh := _joint(_hips, Vector3(x, -0.05, 0))
		_mesh(thigh, _cyl(0.05, 0.04, 0.4), _m_bone, Vector3(0, -0.2, 0))
		var knee := _joint(thigh, Vector3(0, -0.41, 0))
		_mesh(knee, _sphere(0.06), _m_joint, Vector3.ZERO)
		_mesh(knee, _cyl(0.042, 0.032, 0.42), _m_bone, Vector3(0, -0.21, 0))
		var ankle := _joint(knee, Vector3(0, -0.43, 0))
		_mesh(ankle, _box(Vector3(0.09, 0.06, 0.19)), _m_bone, Vector3(0, -0.06, -0.045))
		_thigh.append(thigh)
		_knee.append(knee)
		_ankle.append(ankle)

	# Colonne : vertèbres empilées.
	_spine = _joint(_hips, Vector3(0, 0.05, 0))
	for v in 5:
		_mesh(_spine, _box(Vector3(0.08, 0.045, 0.07)), _m_joint, Vector3(0, 0.03 + v * 0.055, 0.02))
	_chest = _joint(_spine, Vector3(0, 0.28, 0))
	# Cage thoracique : anneaux aplatis, plus étroits vers le bas.
	for r in 4:
		var radius := 0.15 - r * 0.014
		var rib := TorusMesh.new()
		rib.inner_radius = radius - 0.03
		rib.outer_radius = radius
		rib.rings = 16
		rib.ring_segments = 4
		_mesh(_chest, rib, _m_bone, Vector3(0, 0.2 - r * 0.055, -0.01), Vector3(0.12, 0, 0), Vector3(1.0, 1.0, 0.72))
	_mesh(_chest, _box(Vector3(0.05, 0.2, 0.03)), _m_bone, Vector3(0, 0.12, -0.1))
	_mesh(_chest, _box(Vector3(0.4, 0.05, 0.05)), _m_bone, Vector3(0, 0.255, -0.02))

	var neck := _joint(_chest, Vector3(0, 0.29, 0.01))
	_mesh(neck, _cyl(0.035, 0.035, 0.07), _m_joint, Vector3(0, 0.02, 0))
	_head = _joint(neck, Vector3(0, 0.06, 0))
	_mesh(_head, _sphere(0.115), _m_bone, Vector3(0, 0.09, 0.005), Vector3.ZERO, Vector3(0.88, 0.95, 1.0))
	for side: float in [-1.0, 1.0]:
		_mesh(_head, _sphere(0.032), _m_socket, Vector3(side * 0.042, 0.095, -0.088))
		_mesh(_head, _sphere(0.016), _m_eye, Vector3(side * 0.042, 0.095, -0.102))
	_mesh(_head, _box(Vector3(0.025, 0.03, 0.02)), _m_socket, Vector3(0, 0.05, -0.108))
	if is_boss:
		# Heaume à cornes et couronne rouillée.
		_mesh(_head, _cyl(0.125, 0.13, 0.08), _m_rust, Vector3(0, 0.16, 0.005))
		var crown := TorusMesh.new()
		crown.inner_radius = 0.115
		crown.outer_radius = 0.14
		crown.rings = 16
		crown.ring_segments = 4
		_mesh(_head, crown, _m_rust, Vector3(0, 0.205, 0.005))
		for k in 5:
			var a := TAU * k / 5.0
			_mesh(_head, _box(Vector3(0.025, 0.07, 0.025)), _m_rust, Vector3(cos(a) * 0.128, 0.245, sin(a) * 0.128 + 0.005))
		for side: float in [-1.0, 1.0]:
			_mesh(_head, _cyl(0.0, 0.03, 0.2), _m_bone, Vector3(side * 0.14, 0.2, 0.0), Vector3(0, 0, side * -0.9))
		var eyes := OmniLight3D.new()
		eyes.light_color = eye_color
		eyes.light_energy = 1.4
		eyes.omni_range = 3.5
		eyes.position = Vector3(0, 0.1, -0.2)
		_head.add_child(eyes)
		# Cape en lambeaux dans le dos.
		_mesh(_chest, _box(Vector3(0.42, 0.75, 0.015)), _m_rag, Vector3(0, -0.1, 0.13), Vector3(-0.12, 0, 0))
	_jaw = _joint(_head, Vector3(0, 0.025, 0.02))
	_mesh(_jaw, _box(Vector3(0.13, 0.045, 0.11)), _m_bone, Vector3(0, -0.02, -0.065))

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var shoulder := _joint(_chest, Vector3(side * 0.19, 0.23, 0))
		_mesh(shoulder, _sphere(0.055), _m_joint, Vector3.ZERO)
		_mesh(shoulder, _cyl(0.04, 0.032, 0.28), _m_bone, Vector3(0, -0.14, 0))
		var elbow := _joint(shoulder, Vector3(0, -0.29, 0))
		_mesh(elbow, _sphere(0.045), _m_joint, Vector3.ZERO)
		_mesh(elbow, _cyl(0.034, 0.028, 0.25), _m_bone, Vector3(0, -0.125, 0))
		var hand := _joint(elbow, Vector3(0, -0.26, 0))
		_mesh(hand, _box(Vector3(0.07, 0.1, 0.045)), _m_bone, Vector3(0, -0.04, 0))
		_shoulder.append(shoulder)
		_elbow.append(elbow)
		_hand.append(hand)
		if i == 1 and is_boss:
			# Grande hache : long manche, fer en croissant, pointe.
			var axe := _joint(hand, Vector3(0, -0.05, 0), Vector3(1.25, 0, 0))
			_mesh(axe, _cyl(0.02, 0.02, 1.0), _m_rag, Vector3(0, -0.3, 0))
			_mesh(axe, _box(Vector3(0.28, 0.26, 0.02)), _m_rust, Vector3(0.12, -0.7, 0))
			_mesh(axe, _box(Vector3(0.06, 0.38, 0.02)), _m_rust, Vector3(0.27, -0.7, 0))
			_mesh(axe, _box(Vector3(0.05, 0.12, 0.02)), _m_rust, Vector3(0, -0.86, 0))
		elif i == 1:
			# Épée rouillée et ébréchée.
			var sword := _joint(hand, Vector3(0, -0.05, 0), Vector3(1.2, 0, 0))
			_mesh(sword, _cyl(0.015, 0.015, 0.11), _m_rag, Vector3(0, 0.0, 0))
			_mesh(sword, _box(Vector3(0.16, 0.022, 0.025)), _m_rust, Vector3(0, -0.065, 0))
			_mesh(sword, _box(Vector3(0.055, 0.62, 0.015)), _m_rust, Vector3(0, -0.39, 0))
			_mesh(sword, _box(Vector3(0.03, 0.05, 0.01)), _m_rust, Vector3(0.008, -0.72, 0), Vector3(0, 0, 0.5))


func _make_soul_fx() -> void:
	_wisps = CPUParticles3D.new()
	_wisps.emitting = false
	_wisps.amount = 24
	_wisps.lifetime = 2.2
	_wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_wisps.emission_sphere_radius = 0.45
	_wisps.direction = Vector3.UP
	_wisps.spread = 15.0
	_wisps.initial_velocity_min = 0.7
	_wisps.initial_velocity_max = 1.3
	_wisps.gravity = Vector3(0.0, 0.5, 0.0)
	_wisps.scale_amount_min = 0.6
	_wisps.scale_amount_max = 1.4
	var mote := BoxMesh.new()
	mote.size = Vector3.ONE * 0.05
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = soul_color
	mat.roughness = 1.0
	mote.material = mat
	_wisps.mesh = mote
	_wisps.layers = 1 | (1 << (FINE_LAYER - 1))
	_wisps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wisps.position = Vector3(0, 0.35, 0)
	add_child(_wisps)


func _make_materials() -> void:
	_m_bone = _mat(bone_color, 0.0, 0.75, 0.3)
	_m_joint = _mat(bone_color.darkened(0.3), 0.0, 0.8, 0.0)
	_m_rust = _mat(Color(0.36, 0.25, 0.17), 0.4, 0.7, 0.0)
	_m_rag = _mat(Color(0.2, 0.17, 0.13), 0.0, 1.0, 0.0)
	_m_socket = _mat(Color(0.02, 0.02, 0.02), 0.0, 0.9, 0.0)
	_materials = [_m_bone, _m_joint, _m_rust, _m_rag]
	for m in _materials:
		m.emission_enabled = true
		m.emission = Color(0.92, 0.95, 1.0)
		m.emission_energy_multiplier = 0.0
	_m_eye = _mat(eye_color, 0.0, 0.5, 0.0)
	_m_eye.emission_enabled = true
	_m_eye.emission = eye_color
	_m_eye.emission_energy_multiplier = 6.0


func _mat(color: Color, metallic: float, roughness: float, rim: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
	return m


func _joint(parent: Node3D, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	j.rotation = rot
	parent.add_child(j)
	return j


func _mesh(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	m.rotation = rot
	m.scale = scl
	# Calque 1 (monde) + calque 3 : dessiné en cellules fines, comme le soldat.
	m.layers = 1 | (1 << (FINE_LAYER - 1))
	parent.add_child(m)


func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 8
	m.rings = 1
	return m


func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 10
	m.rings = 6
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
