@tool
class_name Soldier
extends Node3D
## Soldat en armure, construit en code et animé de façon procédurale.
##
## Pas de modèle importé : le corps est une hiérarchie de pivots (hanches,
## colonne, buste, cou, tête, épaules, coudes, mains, cuisses, genoux,
## chevilles) portant des pièces d'armure simples (cylindres effilés,
## sphères, boîtes). Les proportions suivent un adulte de ~1,80 m
## (environ 7,5 têtes) : c'est la silhouette, plus que le détail des
## maillages, qui se lit une fois convertie en glyphes.
##
## L'animation (repos, marche, course, saut) est calculée chaque frame à
## partir de la vitesse du CharacterBody3D parent : un cycle de pas dont la
## fréquence suit la vitesse réelle (les pieds ne glissent pas), balancier
## des bras, rotation du bassin, inclinaison du buste, respiration au repos.
## La cape et les pans du tabard suivent avec un léger retard (ressort amorti).
##
## Repère : le soldat regarde vers -Z, pieds en y = 0.
## Rotation positive autour de X = le membre part vers l'avant.

## Vitesse (m/s) à laquelle l'allure « marche » est complète.
@export var walk_speed_ref := 3.2
## Vitesse (m/s) à laquelle l'allure « course » est complète.
@export var run_speed_ref := 6.5
## Longueur d'un cycle complet (deux pas), en mètres, en marche puis en course.
@export var stride_walk := 1.5
@export var stride_run := 2.3

@export_group("Couleurs")
@export var tabard_color := Color(0.56, 0.08, 0.06)
@export var cloth_color := Color(0.50, 0.45, 0.36)
@export var trousers_color := Color(0.24, 0.22, 0.2)
@export var leather_color := Color(0.26, 0.16, 0.09)
@export var steel_color := Color(0.62, 0.64, 0.67)
@export var dark_steel_color := Color(0.34, 0.35, 0.37)
@export var shield_color := Color(0.30, 0.11, 0.07)

@export_group("Éclairage du personnage")
## Lumières qui n'éclairent que le soldat (calque de rendu 2) : sans elles,
## l'armure reflète surtout le ciel noir et devient une silhouette sombre
## une fois convertie en glyphes.
@export var character_lights := true
## Lumière de face (côté caméra), douce.
@export var key_energy := 1.1
@export var key_color := Color(1.0, 0.9, 0.78)
## Contre-jour (derrière, en haut) : liseré lumineux sur les bords.
@export var rim_energy := 3.0
@export var rim_color := Color(0.62, 0.74, 1.0)

## Calque de rendu réservé au personnage (bit 2).
const CHARACTER_LAYER := 2

var _body: CharacterBody3D

# Pivots animés
var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _head: Node3D
var _thigh: Array[Node3D] = []    # [gauche, droite]
var _knee: Array[Node3D] = []
var _ankle: Array[Node3D] = []
var _shoulder: Array[Node3D] = []
var _elbow: Array[Node3D] = []
var _hand: Array[Node3D] = []
var _cape_top: Node3D
var _cape_low: Node3D
var _tabard_front: Node3D
var _tabard_back: Node3D

# État de l'animation
var _phase := 0.0       # phase du cycle de pas (radians)
var _time := 0.0
var _walk := 0.0        # 0 = arrêt, 1 = marche (lissé)
var _run := 0.0         # 0 = marche, 1 = course (lissé)
var _air := 0.0         # 0 = au sol, 1 = en l'air (lissé)
var _cape_angle := 0.0
var _cape_velocity := 0.0

var _hips_height := 0.98
var _key_light: OmniLight3D
var _rim_light: OmniLight3D

# Matériaux
var _m_steel: StandardMaterial3D
var _m_dark_steel: StandardMaterial3D
var _m_mail: StandardMaterial3D
var _m_leather: StandardMaterial3D
var _m_cloth: StandardMaterial3D
var _m_trousers: StandardMaterial3D
var _m_tabard: StandardMaterial3D
var _m_cape: StandardMaterial3D
var _m_shield: StandardMaterial3D
var _m_slit: StandardMaterial3D


func _ready() -> void:
	# Les nœuds construits ici n'ont pas d'« owner » : ils ne sont jamais
	# sauvegardés dans la scène, même quand l'éditeur exécute ce script.
	for child in get_children():
		child.queue_free()
	_thigh.clear(); _knee.clear(); _ankle.clear()
	_shoulder.clear(); _elbow.clear(); _hand.clear()
	_make_materials()
	_build()
	if character_lights:
		_key_light = _light("KeyLight", key_color, key_energy, 5.0)
		_rim_light = _light("RimLight", rim_color, rim_energy, 4.5)
	_body = _find_body()


func _process(delta: float) -> void:
	if _hips == null:
		return
	_time += delta
	_update_lights()

	# --- Mesure de l'allure ---------------------------------------------------
	var speed := 0.0
	var on_floor := true
	var vertical := 0.0
	if _body and not Engine.is_editor_hint():
		speed = Vector2(_body.velocity.x, _body.velocity.z).length()
		on_floor = _body.is_on_floor()
		vertical = _body.velocity.y

	var k := 1.0 - exp(-8.0 * delta)
	_walk = lerpf(_walk, clampf(speed / walk_speed_ref, 0.0, 1.0), k)
	_run = lerpf(_run, clampf((speed - walk_speed_ref) / (run_speed_ref - walk_speed_ref), 0.0, 1.0), k)
	_air = lerpf(_air, 0.0 if on_floor else 1.0, 1.0 - exp(-12.0 * delta))

	# La phase avance de 2π par cycle : distance parcourue / longueur du cycle.
	var stride := lerpf(stride_walk, stride_run, _run)
	_phase = fmod(_phase + speed / stride * TAU * delta, TAU)
	# À l'arrêt, on ramène doucement les jambes en position neutre.
	if speed < 0.05:
		_phase = lerp_angle(_phase, 0.0 if cos(_phase) > 0.0 else PI, k * 0.5)

	var s := sin(_phase)
	var c := cos(_phase)
	var w := _walk * (1.0 - _air)
	var r := _run
	var idle := 1.0 - _walk

	# --- Jambes ---------------------------------------------------------------
	var leg_swing := lerpf(0.42, 0.75, r) * w
	var knee_lift := lerpf(0.75, 1.5, r) * w
	for i in 2:
		var side := 1.0 if i == 0 else -1.0     # la jambe droite est en opposition
		var leg := s * side
		# Le genou plie quand la jambe repasse vers l'avant (phase de vol).
		var swinging := maxf(0.0, c * side)
		var thigh := leg * leg_swing + 0.08 * r * w
		var knee := -(0.08 * w + knee_lift * swinging * swinging)
		# En l'air : jambes repliées, l'une plus que l'autre.
		thigh = lerpf(thigh, 0.55 if i == 0 else 0.15, _air)
		knee = lerpf(knee, -0.95 if i == 0 else -0.45, _air)
		_thigh[i].rotation = Vector3(thigh, 0.0, side * -0.03)
		_knee[i].rotation.x = knee
		# Pied à plat au sol, pointe qui se relève en fin de pas.
		_ankle[i].rotation.x = -(thigh + knee) * 0.85 + maxf(0.0, -leg) * 0.25 * w

	# --- Bassin et buste --------------------------------------------------------
	var bob := (absf(c) - 0.5) * lerpf(0.045, 0.08, r) * w
	var crouch := 0.04 * r * w + 0.06 * _air
	_hips.position.y = _hips_height + bob - crouch
	_hips.rotation = Vector3(0.0, s * 0.14 * w, -s * 0.03 * w)
	# Buste penché en avant à la course, contre-rotation par rapport au bassin.
	var breath := sin(_time * 1.7)
	_spine.rotation = Vector3(-(0.03 * w + 0.2 * r * w) - 0.1 * _air, -s * 0.24 * w, s * 0.025 * w)
	_chest.rotation.x = breath * 0.018 * idle
	_chest.position.y = 0.18 + breath * 0.004 * idle
	# La tête compense le balancement et regarde un peu autour d'elle au repos.
	_head.rotation = Vector3(
		0.1 * r * w + sin(_time * 0.31) * 0.05 * idle,
		s * 0.1 * w + sin(_time * 0.43) * 0.25 * idle,
		0.0)

	# --- Bras -------------------------------------------------------------------
	var arm_swing := lerpf(0.32, 0.85, r) * w
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		# Opposé à la jambe du même côté ; le bras du bouclier bouge moins.
		var weight := 0.55 if i == 0 else 1.0
		var arm := -s * side * arm_swing * weight
		var abduct := (-0.14 if i == 0 else 0.1) - side * 0.05 * _air
		_shoulder[i].rotation = Vector3(arm + 0.08 + 0.35 * _air, 0.0, abduct + side * breath * 0.01 * idle)
		var bend := 0.25 + r * w * 0.95 + maxf(0.0, arm) * 0.5 + 0.4 * _air
		if i == 0:
			bend += 0.55 # bouclier tenu devant le flanc
		_elbow[i].rotation.x = bend

	# --- Cape et tabard (retard amorti) ---------------------------------------
	var cape_target := -(0.06 + speed * 0.06 + absf(s) * 0.05 * w) - vertical * 0.04 + _spine.rotation.x
	var accel := (cape_target - _cape_angle) * 60.0 - _cape_velocity * 9.0
	_cape_velocity += accel * delta
	_cape_angle += _cape_velocity * delta
	_cape_angle = clampf(_cape_angle, -1.1, 0.25)
	_cape_top.rotation.x = _cape_angle - _spine.rotation.x
	_cape_low.rotation.x = _cape_angle * 0.6 + sin(_time * 2.3 + _phase) * 0.05 * (0.3 + w)
	_tabard_front.rotation.x = maxf(0.0, maxf(_thigh[0].rotation.x, _thigh[1].rotation.x)) * 0.75
	_tabard_back.rotation.x = minf(0.0, minf(_thigh[0].rotation.x, _thigh[1].rotation.x)) * 0.75 - speed * 0.03


# --- Construction ---------------------------------------------------------------

func _build() -> void:
	# Bassin
	_hips = _joint(self, "Hips", Vector3(0.0, _hips_height, 0.0))
	_mesh(_hips, _cyl(0.15, 0.16, 0.16), _m_trousers, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.75))
	_mesh(_hips, _cyl(0.168, 0.205, 0.2), _m_mail, Vector3(0, -0.05, 0), Vector3.ZERO, Vector3(1, 1, 0.8))
	_mesh(_hips, _cyl(0.172, 0.172, 0.055), _m_leather, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1, 1, 0.8))
	_mesh(_hips, _box(Vector3(0.06, 0.05, 0.02)), _m_steel, Vector3(0, 0.06, -0.14))
	# Pans du tabard (devant / derrière), écartés par les cuisses.
	_tabard_front = _joint(_hips, "TabardFront", Vector3(0, 0.04, -0.142))
	_mesh(_tabard_front, _box(Vector3(0.25, 0.5, 0.016)), _m_tabard, Vector3(0, -0.25, 0))
	_tabard_back = _joint(_hips, "TabardBack", Vector3(0, 0.04, 0.142))
	_mesh(_tabard_back, _box(Vector3(0.25, 0.48, 0.016)), _m_tabard, Vector3(0, -0.24, 0))
	# Fourreau vide (l'épée est en main), sur la hanche gauche.
	var scabbard := _joint(_hips, "Scabbard", Vector3(-0.19, 0.03, 0.02), Vector3(-0.5, 0.0, -0.12))
	_mesh(scabbard, _cyl(0.024, 0.018, 0.72), _m_leather, Vector3(0, -0.36, 0), Vector3.ZERO, Vector3(1, 1, 0.55))
	_mesh(scabbard, _cyl(0.026, 0.026, 0.05), _m_steel, Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(1, 1, 0.6))
	_mesh(scabbard, _cyl(0.02, 0.012, 0.05), _m_steel, Vector3(0, -0.72, 0), Vector3.ZERO, Vector3(1, 1, 0.6))

	# Jambes
	for i in 2:
		var x := -0.095 if i == 0 else 0.095
		var thigh := _joint(_hips, "Thigh%d" % i, Vector3(x, -0.05, 0))
		_mesh(thigh, _cyl(0.078, 0.058, 0.44), _m_trousers, Vector3(0, -0.22, 0))
		var knee := _joint(thigh, "Knee%d" % i, Vector3(0, -0.44, 0))
		_mesh(knee, _sphere(0.052), _m_steel, Vector3(0, 0.0, -0.036), Vector3.ZERO, Vector3(1, 1, 0.7))
		_mesh(knee, _cyl(0.058, 0.043, 0.42), _m_dark_steel, Vector3(0, -0.2, -0.004), Vector3.ZERO, Vector3(1, 1, 0.92))
		var ankle := _joint(knee, "Ankle%d" % i, Vector3(0, -0.42, 0))
		_mesh(ankle, _cyl(0.056, 0.05, 0.13), _m_leather, Vector3(0, 0.04, 0))
		_mesh(ankle, _box(Vector3(0.1, 0.095, 0.26)), _m_leather, Vector3(0, -0.022, -0.05))
		_mesh(ankle, _box(Vector3(0.104, 0.025, 0.27)), _m_trousers, Vector3(0, -0.058, -0.05))
		_thigh.append(thigh)
		_knee.append(knee)
		_ankle.append(ankle)

	# Colonne et buste
	_spine = _joint(_hips, "Spine", Vector3(0, 0.08, 0))
	_mesh(_spine, _cyl(0.16, 0.152, 0.2), _m_cloth, Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(1, 1, 0.74))
	_chest = _joint(_spine, "Chest", Vector3(0, 0.18, 0))
	_mesh(_chest, _cyl(0.2, 0.162, 0.27), _m_cloth, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 1, 0.64))
	# Plastron bombé + arête centrale.
	_mesh(_chest, _sphere(0.19, 0.36), _m_steel, Vector3(0, 0.085, -0.028), Vector3.ZERO, Vector3(0.95, 0.85, 0.62))
	_mesh(_chest, _box(Vector3(0.018, 0.22, 0.02)), _m_steel, Vector3(0, 0.08, -0.142), Vector3(-0.12, 0, 0))
	# Dossière plus sombre.
	_mesh(_chest, _sphere(0.18, 0.34), _m_dark_steel, Vector3(0, 0.09, 0.03), Vector3.ZERO, Vector3(0.95, 0.85, 0.55))
	# Gorgerin.
	_mesh(_chest, _cyl(0.095, 0.15, 0.08), _m_dark_steel, Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1, 1, 0.85))
	# Épaulières (fixées au buste, deux lames chacune).
	for side in [-1.0, 1.0]:
		_mesh(_chest, _sphere(0.105), _m_steel, Vector3(side * 0.215, 0.2, 0), Vector3(0, 0, side * -0.35), Vector3(1.05, 0.72, 1.12))
		_mesh(_chest, _sphere(0.1), _m_dark_steel, Vector3(side * 0.245, 0.14, 0), Vector3(0, 0, side * -0.6), Vector3(0.9, 0.5, 1.05))

	# Cape, en deux segments pour qu'elle ondule.
	_cape_top = _joint(_chest, "CapeTop", Vector3(0, 0.23, 0.1))
	_mesh(_cape_top, _box(Vector3(0.42, 0.46, 0.018)), _m_cape, Vector3(0, -0.23, 0))
	_cape_low = _joint(_cape_top, "CapeLow", Vector3(0, -0.46, 0))
	_mesh(_cape_low, _box(Vector3(0.45, 0.44, 0.018)), _m_cape, Vector3(0, -0.22, 0))

	# Cou et tête : heaume fermé à fente de vision, cimier rouge.
	var neck := _joint(_chest, "Neck", Vector3(0, 0.26, 0))
	_mesh(neck, _cyl(0.12, 0.165, 0.1), _m_mail, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 1, 0.92))
	_head = _joint(neck, "Head", Vector3(0, 0.07, 0))
	_mesh(_head, _cyl(0.108, 0.114, 0.17), _m_steel, Vector3(0, 0.06, 0))
	_mesh(_head, _sphere(0.108), _m_steel, Vector3(0, 0.145, 0), Vector3.ZERO, Vector3(1, 0.72, 1))
	_mesh(_head, _box(Vector3(0.17, 0.02, 0.03)), _m_slit, Vector3(0, 0.085, -0.105))
	_mesh(_head, _box(Vector3(0.022, 0.13, 0.03)), _m_dark_steel, Vector3(0, 0.03, -0.108))
	_mesh(_head, _box(Vector3(0.026, 0.05, 0.2)), _m_tabard, Vector3(0, 0.235, 0.01))
	_mesh(_head, _box(Vector3(0.02, 0.035, 0.12)), _m_tabard, Vector3(0, 0.215, 0.13), Vector3(-0.5, 0, 0))

	# Bras : gauche = bouclier, droit = épée.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var shoulder := _joint(_chest, "Shoulder%d" % i, Vector3(side * 0.215, 0.2, 0))
		_mesh(shoulder, _cyl(0.056, 0.046, 0.29), _m_cloth, Vector3(0, -0.145, 0))
		var elbow := _joint(shoulder, "Elbow%d" % i, Vector3(0, -0.29, 0))
		_mesh(elbow, _sphere(0.046), _m_steel, Vector3(0, 0, 0.018))
		_mesh(elbow, _cyl(0.048, 0.04, 0.25), _m_dark_steel, Vector3(0, -0.13, 0))
		var hand := _joint(elbow, "Hand%d" % i, Vector3(0, -0.26, 0))
		_mesh(hand, _cyl(0.056, 0.046, 0.06), _m_steel, Vector3(0, 0.015, 0))
		_mesh(hand, _box(Vector3(0.07, 0.095, 0.09)), _m_leather, Vector3(0, -0.05, 0))
		_shoulder.append(shoulder)
		_elbow.append(elbow)
		_hand.append(hand)

	# Épée longue dans la main droite, lame vers l'avant et le bas.
	var sword := _joint(_hand[1], "Sword", Vector3(0, -0.055, 0), Vector3(1.15, 0, 0))
	_mesh(sword, _cyl(0.017, 0.017, 0.13), _m_leather, Vector3(0, 0.0, 0))
	_mesh(sword, _sphere(0.027), _m_steel, Vector3(0, 0.08, 0))
	_mesh(sword, _box(Vector3(0.22, 0.026, 0.03)), _m_steel, Vector3(0, -0.075, 0))
	_mesh(sword, _box(Vector3(0.05, 0.82, 0.012)), _m_steel, Vector3(0, -0.5, 0))
	_mesh(sword, _box(Vector3(0.03, 0.06, 0.012)), _m_steel, Vector3(0, -0.935, 0), Vector3(0, 0, PI / 4.0), Vector3(1, 1, 1))

	# Bouclier rond sur l'avant-bras gauche, face vers l'extérieur.
	var shield := _joint(_elbow[0], "Shield", Vector3(-0.075, -0.13, -0.02), Vector3(0, 0, PI / 2.0))
	_mesh(shield, _cyl(0.3, 0.3, 0.024, 24), _m_dark_steel, Vector3(0, 0.0, 0))
	_mesh(shield, _cyl(0.282, 0.282, 0.03, 24), _m_shield, Vector3(0, 0.004, 0))
	_mesh(shield, _box(Vector3(0.07, 0.032, 0.56)), _m_steel, Vector3(0, 0.006, 0))
	_mesh(shield, _sphere(0.075, 0.075, true), _m_steel, Vector3(0, 0.02, 0))


## Les lumières sont « top level » : elles suivent le soldat sans tourner avec
## lui, et restent placées par rapport à la caméra (face et contre-jour).
func _update_lights() -> void:
	if _key_light == null:
		return
	var camera := get_viewport().get_camera_3d() if not Engine.is_editor_hint() else null
	var to_camera := Vector3(1, 0, 1).normalized()
	if camera:
		to_camera = camera.global_basis.z
		to_camera.y = 0.0
		to_camera = to_camera.normalized()
	var center := global_position + Vector3.UP * 1.1
	_key_light.global_position = center + to_camera * 1.6 + Vector3.UP * 1.4
	_rim_light.global_position = center - to_camera * 1.4 + Vector3.UP * 1.2


func _light(light_name: String, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	light.top_level = true
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 0.8
	light.shadow_enabled = false
	light.light_specular = 0.8
	light.light_cull_mask = 1 << (CHARACTER_LAYER - 1)
	add_child(light)
	return light


func _make_materials() -> void:
	# Métal à moitié seulement : un métal pur ne renvoie que l'environnement
	# (le ciel nocturne, noir) et perdrait toute lecture en glyphes.
	_m_steel = _mat(steel_color, 0.45, 0.35)
	_m_dark_steel = _mat(dark_steel_color, 0.4, 0.45)
	_m_mail = _mat(dark_steel_color.lerp(steel_color, 0.4), 0.35, 0.7)
	_m_leather = _mat(leather_color, 0.0, 0.75, 0.25)
	_m_cloth = _mat(cloth_color, 0.0, 0.9, 0.45)
	_m_trousers = _mat(trousers_color, 0.0, 0.9, 0.35)
	_m_tabard = _mat(tabard_color, 0.0, 0.85, 0.5)
	_m_cape = _mat(tabard_color.darkened(0.15), 0.0, 0.9, 0.5)
	_m_shield = _mat(shield_color, 0.0, 0.7, 0.3)
	_m_slit = _mat(Color(0.02, 0.02, 0.02), 0.0, 1.0)


## `rim` : liseré de lumière sur les bords (aide la silhouette à se détacher du décor).
func _mat(color: Color, metallic: float, roughness: float, rim := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.metallic_specular = 0.6
	m.roughness = roughness
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.6
	return m


# --- Utilitaires -------------------------------------------------------------------

func _joint(parent: Node3D, joint_name: String, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var joint := Node3D.new()
	joint.name = joint_name
	joint.position = pos
	joint.rotation = rot
	parent.add_child(joint)
	return joint


func _mesh(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation = rot
	instance.scale = scl
	# Calque 1 (monde) + calque du personnage (éclairé par ses propres lumières).
	instance.layers = 1 | (1 << (CHARACTER_LAYER - 1))
	parent.add_child(instance)
	return instance


func _cyl(top: float, bottom: float, height: float, segments := 14) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


func _sphere(radius: float, height := -1.0, hemisphere := false) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 if height < 0.0 else height
	m.is_hemisphere = hemisphere
	m.radial_segments = 16
	m.rings = 8
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _find_body() -> CharacterBody3D:
	var node := get_parent()
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null
