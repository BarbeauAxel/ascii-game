extends Node3D
## Torches éteintes que le héros allume en passant à côté.
##
## Au départ, la ruine n'est éclairée que par la lune, la lanterne du portail
## et les cierges de l'autel. Chaque torche (applique murale ou piquet planté
## au sol) s'embrase quand le joueur passe à moins de `ignite_distance` :
## souffle, crépitements, flamme qui grandit, lumière vacillante qui monte en
## douceur, braises qui s'envolent. La ruine s'éclaire ainsi au fil de
## l'exploration. Construites en code, comme le reste du décor.

## Distance (horizontale) à laquelle le joueur allume une torche.
@export var ignite_distance := 1.7
## Intensité et portée de la lumière d'une torche allumée.
@export var light_energy := 2.2
@export var light_range := 6.5

const FLICKER_SCRIPT := preload("res://scripts/world/flicker_light.gd")

## Emplacements : position (point d'accroche), direction vers laquelle la
## torche est tournée (en sortant du mur), type ("wall" applique, "post" piquet).
const SPOTS := [
	[Vector3(-4.38, 1.9, -4.0), Vector3.RIGHT, "wall"],    # mur ouest, intérieur
	[Vector3(-4.38, 1.9, -9.0), Vector3.RIGHT, "wall"],
	[Vector3(-2.3, 1.9, -15.88), Vector3.BACK, "wall"],    # chevet nord
	[Vector3(2.3, 1.9, -15.88), Vector3.BACK, "wall"],
	[Vector3(-1.96, 1.9, -3.4), Vector3.RIGHT, "wall"],    # piliers
	[Vector3(1.96, 1.9, -9.8), Vector3.LEFT, "wall"],
	[Vector3(-1.6, 1.9, -0.08), Vector3.BACK, "wall"],     # portail, dehors
	[Vector3(1.6, 1.9, -0.08), Vector3.BACK, "wall"],
	[Vector3(9.4, 0.0, -7.6), Vector3.BACK, "post"],       # cimetière
	[Vector3(12.6, 0.0, -11.2), Vector3.BACK, "post"],
]

var _torches: Array[Dictionary] = []
var _check := 0.0
var _time := 0.0


func _ready() -> void:
	var iron := _mat(Color(0.2, 0.2, 0.21), 0.6, 0.6)
	var wood := _mat(Color(0.3, 0.2, 0.12), 0.0, 0.9)
	var pitch := _mat(Color(0.08, 0.07, 0.06), 0.0, 1.0)
	var flame_outer := _flame_mat(Color(1.0, 0.45, 0.1), 3.0)
	var flame_inner := _flame_mat(Color(1.0, 0.85, 0.45), 4.0)

	for spot in SPOTS:
		var root := Node3D.new()
		add_child(root)
		var out: Vector3 = spot[1]
		# Repère : +Z local = sortie du mur.
		root.global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP), spot[0])
		var flame_anchor: Vector3
		if spot[2] == "wall":
			# Applique : patte de fer, manche incliné vers l'extérieur, coupelle.
			_mesh(root, _box(Vector3(0.06, 0.18, 0.04)), iron, Vector3(0, 0, 0.02))
			_mesh(root, _box(Vector3(0.04, 0.04, 0.2)), iron, Vector3(0, -0.06, 0.1))
			_mesh(root, _cyl(0.025, 0.02, 0.42), wood, Vector3(0, 0.08, 0.2), Vector3(0.35, 0, 0))
			_mesh(root, _cyl(0.06, 0.035, 0.08), iron, Vector3(0, 0.27, 0.27), Vector3(0.35, 0, 0))
			_mesh(root, _cyl(0.05, 0.05, 0.05), pitch, Vector3(0, 0.3, 0.28))
			flame_anchor = Vector3(0, 0.36, 0.29)
		else:
			# Piquet planté : long manche, coupelle en haut.
			_mesh(root, _cyl(0.035, 0.045, 1.6), wood, Vector3(0, 0.8, 0))
			_mesh(root, _cyl(0.07, 0.04, 0.1), iron, Vector3(0, 1.62, 0))
			_mesh(root, _cyl(0.06, 0.06, 0.05), pitch, Vector3(0, 1.66, 0))
			flame_anchor = Vector3(0, 1.72, 0)

		var flame := Node3D.new()
		flame.position = flame_anchor
		flame.visible = false
		root.add_child(flame)
		_mesh(flame, _sphere(0.075), flame_outer, Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 1.9, 1))
		_mesh(flame, _sphere(0.045), flame_inner, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 1.6, 1))

		var light := OmniLight3D.new()
		light.set_script(FLICKER_SCRIPT)
		light.light_color = Color(1.0, 0.6, 0.25)
		light.omni_range = light_range
		light.omni_attenuation = 1.2
		light.set("base_energy", 0.0)
		light.set("flicker", 0.22)
		light.position = flame_anchor + Vector3(0, 0.15, 0.05)
		light.visible = false
		root.add_child(light)

		var embers := CPUParticles3D.new()
		embers.emitting = false
		embers.amount = 10
		embers.lifetime = 1.2
		embers.direction = Vector3.UP
		embers.spread = 25.0
		embers.initial_velocity_min = 0.4
		embers.initial_velocity_max = 0.9
		embers.gravity = Vector3(0.15, 0.4, 0.0)
		embers.scale_amount_min = 0.5
		embers.scale_amount_max = 1.0
		var ember_mesh := BoxMesh.new()
		ember_mesh.size = Vector3.ONE * 0.025
		ember_mesh.material = _flame_mat(Color(1.0, 0.55, 0.15), 3.0)
		embers.mesh = ember_mesh
		embers.position = flame_anchor + Vector3(0, 0.1, 0)
		root.add_child(embers)

		_torches.append({"root": root, "flame": flame, "light": light, "embers": embers, "lit": false, "age": 0.0, "seed": randf() * 10.0})


func _process(delta: float) -> void:
	_time += delta
	# Flammes allumées : elles grandissent à l'allumage puis ondulent.
	for torch in _torches:
		if torch["lit"]:
			torch["age"] += delta
			var grow := smoothstep(0.0, 0.6, torch["age"])
			var s: float = torch["seed"]
			var flame: Node3D = torch["flame"]
			flame.scale = Vector3(grow * (1.0 + 0.08 * sin(_time * 13.0 + s)), grow * (1.0 + 0.2 * sin(_time * 9.0 + s * 2.0)), grow)
			var light: OmniLight3D = torch["light"]
			light.set("base_energy", light_energy * grow)

	# Allumage : test de distance quelques fois par seconde.
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.1
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	for torch in _torches:
		if torch["lit"]:
			continue
		var root: Node3D = torch["root"]
		var t := Vector2(root.global_position.x, root.global_position.z)
		if p.distance_to(t) < ignite_distance:
			_ignite(torch)


func _ignite(torch: Dictionary) -> void:
	torch["lit"] = true
	torch["age"] = 0.0
	(torch["flame"] as Node3D).visible = true
	(torch["light"] as Node3D).visible = true
	(torch["embers"] as CPUParticles3D).emitting = true
	var flame: Node3D = torch["flame"]
	Sfx.play("ignite", flame.global_position, -3.0)


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _flame_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 1.0 # matière « souple » : pas de contour ASCII autour de la flamme
	return m


func _mesh(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	m.rotation = rot
	m.scale = scl
	parent.add_child(m)


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


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
	m.radial_segments = 8
	m.rings = 5
	return m
