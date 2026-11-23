@tool
class_name Nature
extends Node3D
## Sol, herbe au vent, arbres morts et buissons, générés en code (graine fixe).
##
## - Sol : grand plan texturé (bruit triplanaire terre / herbe rase) + collision.
## - Herbe : ~70 000 brins en touffes dans une MultiMesh (un seul appel de
##   rendu), animés par grass.gdshader. Plus dense par plaques (bruit), clairsemée
##   dans la nef et sur le chemin. En ASCII, les brins fins et alignés
##   deviennent des traits orientés / | \ qui ondulent avec le vent.
## - Arbres morts : branches récursives tordues (cylindres effilés), fusionnées
##   en un seul maillage par arbre avec SurfaceTool.
## - Buissons : amas de sphères aplaties, fusionnés de la même façon.
## - Mare : surface d'eau (water.gdshader) au contour irrégulier, berge de
##   pierres, roseaux. La pluie (rain.gd) y fait apparaître des ronds de gouttes.

@export var seed := 4242
@export var ground_size := 110.0
## Nombre de touffes (chacune compte 7 à 15 brins).
@export var tuft_count := 13000
## Demi-largeur de la zone herbeuse (mètres, autour de l'origine).
@export var grass_extent := 30.0

const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const STONE := preload("res://scripts/world/stone_material.gd")

# Zones sans herbe (ou presque) : nef dallée et chemin.
const NAVE_RECT := Rect2(-5.3, -16.8, 10.6, 16.4)
const PATH_RECT := Rect2(-1.4, -0.4, 2.8, 14.5)
# Mare : centre et rayon moyen (contour irrégulier, voir pond_radius()).
const POND_CENTER := Vector2(-10.5, -1.0)
const POND_RADIUS := 3.4

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_rng.seed = seed
	_build_ground()
	_build_pond()
	_build_grass()
	_build_trees()
	_build_bushes()


# --- Sol -----------------------------------------------------------------------------

func _build_ground() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.02
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.17, 0.155, 0.12))  # terre sombre
	ramp.set_color(1, Color(0.27, 0.31, 0.19))   # herbe rase
	ramp.add_point(0.55, Color(0.22, 0.22, 0.15))
	tex.color_ramp = ramp
	var normal := NoiseTexture2D.new()
	normal.width = 512
	normal.height = 512
	normal.seamless = true
	normal.as_normal_map = true
	normal.bump_strength = 1.2
	normal.noise = noise

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.normal_enabled = true
	mat.normal_texture = normal
	mat.roughness = 1.0
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.12, 0.12, 0.12)

	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = mat
	add_child(ground)

	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ground_size, 1.0, ground_size)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	body.add_child(col)
	add_child(body)


# --- Herbe ---------------------------------------------------------------------------

func _build_grass() -> void:
	var patches := FastNoiseLite.new()
	patches.seed = seed + 1
	patches.frequency = 0.09

	var xforms: Array[Transform3D] = []
	var customs := PackedColorArray()
	for t in tuft_count:
		var center := Vector2(_rng.randf_range(-grass_extent, grass_extent), _rng.randf_range(-grass_extent, grass_extent))
		var patch := patches.get_noise_2d(center.x, center.y) * 0.5 + 0.5
		var keep := smoothstep(0.25, 0.65, patch)
		if NAVE_RECT.has_point(center) or PATH_RECT.has_point(center):
			keep *= 0.12
		# Mare : pas d'herbe dans l'eau, roseaux hauts et secs sur la rive.
		var shore := _pond_distance(center)
		if shore < 0.15:
			continue
		var reeds := shore < 0.9
		if reeds:
			keep = 0.9
		if _rng.randf() > keep:
			continue
		var blades := _rng.randi_range(7, 15)
		var tall := lerpf(0.35, 0.95, patch)
		var dry := clampf(_rng.randf_range(-0.2, 0.6) + (1.0 - patch) * 0.4, 0.0, 1.0)
		if reeds:
			tall = _rng.randf_range(1.1, 1.6)
			dry = _rng.randf_range(0.5, 1.0)
		for b in blades:
			var p := center + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.22
			if _pond_distance(p) < 0.1:
				continue
			var h := tall * _rng.randf_range(0.55, 1.15)
			var w := _rng.randf_range(0.8, 1.4)
			# Inclinaison naturelle aléatoire + orientation.
			var lean := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, 0.35))
			var rot := lean * Basis(Vector3.UP, _rng.randf() * TAU)
			xforms.append(Transform3D(rot * Basis.from_scale(Vector3(w, h, w)), Vector3(p.x, 0.0, p.y)))
			customs.append(Color(_rng.randf_range(0.7, 1.2), dry, clampf(h / 0.6, 0.5, 1.5), 0.0))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _blade_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])

	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	var grass := MultiMeshInstance3D.new()
	grass.name = "Grass"
	grass.multimesh = mm
	grass.material_override = mat
	# Des dizaines de milliers de brins : pas d'ombres portées (coût), mais
	# ils reçoivent celles du décor.
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass)


## Brin : ruban effilé de hauteur 1, en 3 segments, légèrement courbé vers l'avant.
## UV.y = hauteur relative (utilisée par le shader).
func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 3
	var width := 0.075
	var pts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for i in segments + 1:
		var y := float(i) / segments
		var half := width * 0.5 * (1.0 - y * 0.85)
		var z := -y * y * 0.18
		pts.append(Vector3(-half, y, z)); uvs.append(Vector2(0, y))
		pts.append(Vector3(half, y, z)); uvs.append(Vector2(1, y))
	for i in segments:
		var a := i * 2
		_tri(st, pts, uvs, a, a + 1, a + 2)
		_tri(st, pts, uvs, a + 1, a + 3, a + 2)
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, pts: Array[Vector3], uvs: Array[Vector2], i0: int, i1: int, i2: int) -> void:
	for i in [i0, i1, i2]:
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


# --- Mare ---------------------------------------------------------------------------------

## Rayon de la mare dans la direction `angle` (contour irrégulier, déterministe).
static func pond_radius(angle: float) -> float:
	return POND_RADIUS * (1.0 + 0.17 * sin(3.0 * angle + 1.0) + 0.09 * sin(5.0 * angle + 2.0) + 0.05 * sin(9.0 * angle))


## Distance (mètres) d'un point au bord de la mare : négative dans l'eau.
func _pond_distance(p: Vector2) -> float:
	var d := p - POND_CENTER
	return d.length() - pond_radius(d.angle())


func _build_pond() -> void:
	# Disque polaire assez fin pour que les vagues déforment les sommets.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 64
	var rings := 10
	var water_y := 0.03
	var pts: Array[Vector3] = []
	pts.append(Vector3(POND_CENTER.x, water_y, POND_CENTER.y))
	for ring in range(1, rings + 1):
		for k in segments:
			var a := TAU * k / segments
			var r := pond_radius(a) * float(ring) / rings
			pts.append(Vector3(POND_CENTER.x + cos(a) * r, water_y, POND_CENTER.y + sin(a) * r))
	st.set_normal(Vector3.UP)
	for k in segments:
		var k1 := (k + 1) % segments
		_water_tri(st, pts[0], pts[1 + k1], pts[1 + k])
		for ring in range(1, rings):
			var i0 := 1 + (ring - 1) * segments
			var i1 := 1 + ring * segments
			_water_tri(st, pts[i0 + k], pts[i0 + k1], pts[i1 + k])
			_water_tri(st, pts[i0 + k1], pts[i1 + k1], pts[i1 + k])
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	var water := MeshInstance3D.new()
	water.name = "Pond"
	water.mesh = st.commit()
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.add_to_group("rain_receivers")
	add_child(water)

	# Berge : pierres plates et galets le long du bord.
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.36, 0.36, 0.34)
	rock_mat.albedo_texture = STONE.get_material().albedo_texture
	rock_mat.uv1_triplanar = true
	rock_mat.uv1_world_triplanar = true
	rock_mat.uv1_scale = Vector3(1.5, 1.5, 1.5)
	rock_mat.roughness = 0.9
	var rocks := SurfaceTool.new()
	rocks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := 0.0
	while a < TAU:
		var size := _rng.randf_range(0.18, 0.45)
		var r := pond_radius(a) + _rng.randf_range(-0.1, 0.25)
		var pos := Vector3(POND_CENTER.x + cos(a) * r, size * 0.15, POND_CENTER.y + sin(a) * r)
		var sphere := SphereMesh.new()
		sphere.radius = size
		sphere.height = size * 2.0
		sphere.radial_segments = 7
		sphere.rings = 4
		var basis_rock := Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)))
		rocks.append_from(sphere, 0, Transform3D(basis_rock * Basis.from_scale(Vector3(1.3, 0.45, 1.0)), pos))
		a += _rng.randf_range(0.12, 0.45)
	var shore := MeshInstance3D.new()
	shore.name = "PondRocks"
	shore.mesh = rocks.commit()
	shore.material_override = rock_mat
	add_child(shore)


func _water_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)


# --- Arbres morts ----------------------------------------------------------------------

func _build_trees() -> void:
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.42, 0.38, 0.33)
	bark.albedo_texture = STONE.get_material().albedo_texture
	bark.uv1_triplanar = true
	bark.uv1_world_triplanar = true
	bark.uv1_scale = Vector3(1.2, 0.3, 1.2)
	bark.roughness = 0.95
	bark.rim_enabled = true
	bark.rim = 0.6

	var spots := [
		Vector3(-10.0, 0, -9.0), Vector3(-9.5, 0, 4.5), Vector3(-15.0, 0, -18.0),
		Vector3(9.0, 0, -19.0), Vector3(16.0, 0, -4.0), Vector3(-17.0, 0, 9.0),
		Vector3(12.0, 0, 9.5), Vector3(-6.0, 0, -22.0), Vector3(19.0, 0, -15.0),
	]
	var body := StaticBody3D.new()
	body.name = "TreeCollision"
	add_child(body)
	for i in spots.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var height := _rng.randf_range(1.8, 2.6)
		var radius := _rng.randf_range(0.17, 0.26)
		var dir := (Vector3.UP + Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15))).normalized()
		_branch(st, Vector3.ZERO, dir, height, radius, 0)
		# Racines : quelques départs qui plongent dans le sol.
		for r in 4:
			var a := TAU * (float(r) + _rng.randf_range(0, 0.6)) / 4.0
			var rdir := Vector3(cos(a), -0.25, sin(a)).normalized()
			_limb(st, Vector3(0, 0.25, 0), Vector3(0, 0.25, 0) + rdir * _rng.randf_range(0.6, 1.0), radius * 0.7, radius * 0.15)
		var tree := MeshInstance3D.new()
		tree.name = "DeadTree%d" % i
		tree.mesh = st.commit()
		tree.material_override = bark
		tree.position = spots[i]
		tree.rotation.y = _rng.randf() * TAU
		add_child(tree)
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius * 1.2
		shape.height = 2.0
		col.shape = shape
		col.position = spots[i] + Vector3.UP
		body.add_child(col)


## Branche récursive : deux segments un peu coudés, puis 2 ou 3 sous-branches.
func _branch(st: SurfaceTool, start: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	var p := start
	var d := dir
	var r := radius
	for k in 2:
		d = (d + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.5), _rng.randf_range(-1, 1)) * 0.22).normalized()
		var end := p + d * length * 0.5
		var r_end := r * 0.8
		_limb(st, p, end, r, r_end)
		p = end
		r = r_end
	if depth >= 4 or r < 0.015:
		return
	var children := _rng.randi_range(2, 3)
	for c in children:
		# Écart à la branche mère, autour d'un axe aléatoire.
		var axis := d.cross(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))).normalized()
		if axis.length_squared() < 0.5:
			axis = d.cross(Vector3.RIGHT).normalized()
		var spread := _rng.randf_range(0.35, 0.85)
		var child_dir := d.rotated(axis, spread)
		# Les branches hautes retombent un peu (arbre mort, sans feuilles).
		child_dir = (child_dir + Vector3.DOWN * 0.08 * depth).normalized()
		_branch(st, p, child_dir, length * _rng.randf_range(0.6, 0.78), r * _rng.randf_range(0.55, 0.7), depth + 1)


## Cylindre effilé entre deux points, ajouté au maillage en cours.
func _limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var y := (b - a) / length
	var helper := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var x := helper.cross(y).normalized()
	var z := x.cross(y)
	var cyl := CylinderMesh.new()
	cyl.top_radius = maxf(r1, 0.004)
	cyl.bottom_radius = maxf(r0, 0.004)
	cyl.height = length + r1 # léger recouvrement aux coudes
	cyl.radial_segments = 6 if r0 > 0.05 else 4
	cyl.rings = 1
	st.append_from(cyl, 0, Transform3D(Basis(x, y, z), (a + b) * 0.5))


# --- Buissons ----------------------------------------------------------------------------

func _build_bushes() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.16, 0.08)
	mat.albedo_texture = STONE.get_material().albedo_texture
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(2.5, 2.5, 2.5)
	mat.roughness = 1.0
	mat.rim_enabled = true
	mat.rim = 0.4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var placed := 0
	while placed < 26:
		var p := Vector3(_rng.randf_range(-24, 24), 0, _rng.randf_range(-26, 20))
		var p2 := Vector2(p.x, p.z)
		if NAVE_RECT.grow(1.2).has_point(p2) or PATH_RECT.grow(1.0).has_point(p2) or p2.length() < 3.0 or _pond_distance(p2) < 1.0:
			continue
		placed += 1
		var lumps := _rng.randi_range(3, 7)
		var size := _rng.randf_range(0.35, 0.7)
		for k in lumps:
			var s := SphereMesh.new()
			s.radius = size * _rng.randf_range(0.6, 1.0)
			s.height = s.radius * 2.0
			s.radial_segments = 8
			s.rings = 5
			var off := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * size * 0.9
			var xf := Transform3D(Basis.from_scale(Vector3(1.0, _rng.randf_range(0.55, 0.85), 1.0)), p + off + Vector3.UP * s.radius * 0.45)
			st.append_from(s, 0, xf)
	var bushes := MeshInstance3D.new()
	bushes.name = "Bushes"
	bushes.mesh = st.commit()
	bushes.material_override = mat
	add_child(bushes)
