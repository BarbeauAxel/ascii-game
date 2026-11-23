class_name StoneMaterial
extends RefCounted
## Matériau de pierre partagé par toute la maçonnerie (ruine, tombes, chemin).
##
## La couleur de chaque pierre vient de la MultiMesh (couleur d'instance) ;
## le matériau ajoute un grain : une texture de bruit en projection
## triplanaire (coordonnées monde, donc pas besoin d'UV) et une carte de
## normales tirée du même bruit. En ASCII, ce grain fait varier la luminance
## à l'intérieur des cellules : la pierre se couvre de glyphes de forme au
## lieu d'une rampe uniforme.

static var _material: StandardMaterial3D


static func get_material() -> StandardMaterial3D:
	if _material:
		return _material
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.6

	var albedo := NoiseTexture2D.new()
	albedo.width = 256
	albedo.height = 256
	albedo.seamless = true
	albedo.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.55, 0.55))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	albedo.color_ramp = ramp

	var normal := NoiseTexture2D.new()
	normal.width = 256
	normal.height = 256
	normal.seamless = true
	normal.as_normal_map = true
	normal.bump_strength = 1.5
	normal.noise = noise

	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.albedo_texture = albedo
	_material.normal_enabled = true
	_material.normal_texture = normal
	_material.normal_scale = 0.35
	_material.roughness = 0.92
	_material.uv1_triplanar = true
	_material.uv1_world_triplanar = true
	_material.uv1_scale = Vector3(0.45, 0.45, 0.45)
	return _material
