class_name Rain
extends Node3D
## Pluie (F3) : gouttes en GPUParticles3D, éclaboussures au sol, ronds sur la
## mare, brouillard qui s'épaissit. Construite en code.
##
## La zone de pluie suit le joueur (la caméra orthographique ne voit qu'un
## rectangle de terrain autour de lui). Les particules sont en coordonnées
## monde : une goutte déjà tombée ne suit pas le joueur.
##
## Les gouttes sont des traits verticaux opaques (le shader ASCII ne lit que
## l'image opaque) et « souples » (rugosité 1.0) : elles deviennent des
## glyphes | / sans être cernées de contours.

## Nœud suivi (le joueur).
@export var target_path: NodePath
## Côté du carré couvert par la pluie (mètres) : couvre le zoom le plus large.
@export var area := 48.0
## Hauteur d'apparition des gouttes.
@export var drop_height := 14.0
@export var drop_count := 3500
@export var drop_speed := 17.0
@export var splash_count := 2000
## Vent : inclinaison des gouttes (m/s horizontaux).
@export var wind := Vector3(2.0, 0.0, 0.8)
## Durée du fondu (début / fin d'averse), en secondes.
@export var fade_time := 1.5
## Brouillard multiplié par ce facteur sous la pluie.
@export var fog_boost := 3.0

var active := false
var _amount := 0.0
var _target: Node3D
var _drops: GPUParticles3D
var _splashes: GPUParticles3D
var _env: Environment
var _fog_density := 0.0
var _fog_height_density := 0.0


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_drops = _make_drops()
	_splashes = _make_splashes()
	_drops.emitting = false
	_splashes.emitting = false
	var world := get_viewport().find_world_3d()
	if world and world.environment:
		_env = world.environment
	elif get_tree().current_scene:
		var we := get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
		if we:
			_env = we.environment
	if _env:
		_fog_density = _env.fog_density
		_fog_height_density = _env.fog_height_density
	if "--rain" in OS.get_cmdline_user_args():
		set_active(true)
		_amount = 1.0
		Sfx.set_rain.call_deferred(1.0)


func toggle() -> void:
	set_active(not active)


func set_active(on: bool) -> void:
	active = on
	_drops.emitting = on
	_splashes.emitting = on


func _process(delta: float) -> void:
	if _target:
		var p := _target.global_position
		global_position = Vector3(p.x, 0.0, p.z)
	var wanted := 1.0 if active else 0.0
	if is_equal_approx(_amount, wanted) and _amount == 0.0:
		return
	_amount = move_toward(_amount, wanted, delta / fade_time)
	Sfx.set_rain(_amount)
	# Ronds de gouttes sur l'eau.
	for node in get_tree().get_nodes_in_group("rain_receivers"):
		var mesh := node as GeometryInstance3D
		if mesh and mesh.material_override is ShaderMaterial:
			(mesh.material_override as ShaderMaterial).set_shader_parameter("rain_amount", _amount)
	# Brouillard plus dense sous l'averse.
	if _env:
		_env.fog_density = lerpf(_fog_density, _fog_density * fog_boost, _amount)
		_env.fog_height_density = lerpf(_fog_height_density, _fog_height_density * 1.5, _amount)


func _make_drops() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(area * 0.5, 0.5, area * 0.5)
	var fall := Vector3(wind.x, -drop_speed, wind.z)
	process.direction = fall.normalized()
	process.spread = 0.0
	process.initial_velocity_min = fall.length() * 0.9
	process.initial_velocity_max = fall.length() * 1.1
	process.gravity = Vector3.ZERO
	process.scale_min = 0.7
	process.scale_max = 1.2

	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.45)
	quad.material = _drop_material(Color(0.42, 0.48, 0.6), 0.9)

	var p := GPUParticles3D.new()
	p.name = "Drops"
	p.amount = drop_count
	# Durée de vie = temps de chute jusqu'un peu sous le sol (caché par lui).
	p.lifetime = (drop_height + 0.5) / drop_speed
	p.preprocess = p.lifetime
	p.local_coords = false
	p.process_material = process
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0.0, drop_height, 0.0)
	p.visibility_aabb = AABB(Vector3(-area * 0.5, -drop_height - 2.0, -area * 0.5), Vector3(area, drop_height + 4.0, area))
	add_child(p)
	return p


func _make_splashes() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(area * 0.5, 0.0, area * 0.5)
	process.direction = Vector3.UP
	process.spread = 35.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.3

	var drop := SphereMesh.new()
	drop.radius = 0.025
	drop.height = 0.05
	drop.radial_segments = 4
	drop.rings = 2
	drop.material = _drop_material(Color(0.6, 0.68, 0.8), 0.0)

	var p := GPUParticles3D.new()
	p.name = "Splashes"
	p.amount = splash_count
	p.lifetime = 0.3
	p.local_coords = false
	p.process_material = process
	p.draw_pass_1 = drop
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0.0, 0.04, 0.0)
	p.visibility_aabb = AABB(Vector3(-area * 0.5, -1.0, -area * 0.5), Vector3(area, 3.0, area))
	add_child(p)
	return p


## Matériau des gouttes : opaque, émissif (visible de nuit), rugosité 1.0
## (« souple » pour le shader ASCII). `billboard` > 0 : trait vertical tourné
## vers la caméra autour de l'axe Y.
func _drop_material(color: Color, billboard: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.4
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.35
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard > 0.0:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
	return m
