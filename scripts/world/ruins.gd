@tool
class_name Ruins
extends Node3D
## Chapelle gothique en ruine, construite en code (graine fixe = toujours la
## même ruine).
##
## Toute la maçonnerie est faite de pierres de taille individuelles posées
## assise par assise, avec un appareil décalé, de légères irrégularités et un
## joint de mortier sombre : en ASCII, chaque bloc se lit grâce aux contours
## et aux variations de teinte. Les blocs sont regroupés dans deux MultiMesh
## (boîtes et tambours de colonnes) : quelques milliers de pierres pour
## seulement deux appels de rendu.
##
## Plan (vue de dessus, la caméra est au sud-est) :
##   - nef de 9 x 15 m : mur ouest haut percé de deux fenêtres en arc brisé,
##     chevet nord très haut avec une grande baie à meneau, mur est effondré ;
##   - façade sud réduite au portail en arc brisé et à des murets (côté
##     caméra : rien ne doit cacher le joueur) ;
##   - deux rangées de piliers, dont certains brisés et un effondré ;
##   - dallage disjoint, emmarchement et autel éclairé de cierges au nord ;
##   - éboulis, cimetière à l'est, chemin dallé vers le sud.

@export var seed := 1337
@export var stone_color := Color(0.5, 0.49, 0.46)
@export var moss_color := Color(0.27, 0.33, 0.19)
@export var mortar_color := Color(0.1, 0.1, 0.1)

## Au-dessus de cette hauteur, les pierres n'ont pas de collision (le joueur
## ne peut pas les atteindre) : beaucoup moins de formes pour la physique.
const COLLISION_MAX_HEIGHT := 2.6
const FLICKER_SCRIPT := preload("res://scripts/world/flicker_light.gd")
const STONE := preload("res://scripts/world/stone_material.gd")

# Limites de la nef (intérieur des murs)
const NAVE_X := 4.5
const NAVE_Z0 := -16.0
const NAVE_Z1 := -1.0
const WALL_T := 0.8

var _rng := RandomNumberGenerator.new()
var _boxes: Array[Transform3D] = []
var _box_colors := PackedColorArray()
var _drums: Array[Transform3D] = []
var _drum_colors := PackedColorArray()
var _body: StaticBody3D


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_boxes.clear(); _box_colors.clear(); _drums.clear(); _drum_colors.clear()
	_rng.seed = seed

	_body = StaticBody3D.new()
	_body.name = "Collision"
	add_child(_body)

	_build_walls()
	_build_pillars()
	_build_floor()
	_build_altar()
	_build_rubble()
	_build_graveyard()
	_build_path()

	var box := BoxMesh.new()
	_add_multimesh("Stones", box, _boxes, _box_colors)
	var drum := CylinderMesh.new()
	drum.top_radius = 0.5
	drum.bottom_radius = 0.5
	drum.height = 1.0
	drum.radial_segments = 16
	drum.rings = 1
	_add_multimesh("Drums", drum, _drums, _drum_colors)


# --- Murs --------------------------------------------------------------------------

func _build_walls() -> void:
	var x0 := -NAVE_X - WALL_T * 0.5
	var x1 := NAVE_X + WALL_T * 0.5
	var zn := NAVE_Z0 - WALL_T * 0.5
	var zs := NAVE_Z1 + WALL_T * 0.5

	# Chevet nord : très haut, grande baie à meneau au centre.
	var north_len := x1 - x0
	_wall(Vector2(x0, zn), Vector2(x1, zn), 8.2, 0.25, [
		_opening(north_len * 0.5, 2.6, 2.0, 5.0, true),
	])
	# Mur ouest : haut, deux fenêtres, s'effrite vers le sud.
	var west_len := zs - zn
	_wall(Vector2(x0, zn), Vector2(x0, zs), 6.6, 0.45, [
		_opening(west_len * 0.3, 1.5, 1.7, 3.7, false),
		_opening(west_len * 0.68, 1.5, 1.7, 3.7, false),
	])
	# Mur est (côté caméra) : effondré, une fenêtre encore lisible.
	_wall(Vector2(x1, zn), Vector2(x1, zs), 3.4, 0.9, [
		_opening(west_len * 0.25, 1.5, 1.7, 3.7, false),
	])
	# Façade sud : portail en arc brisé entre deux piédroits, murets autour.
	var south_len := x1 - x0
	var door := _opening(south_len * 0.5, 2.4, 0.0, 2.5, false)
	_wall(Vector2(x0, zs), Vector2(x0 + south_len * 0.5 - 1.95, zs), 1.3, 0.8, [])
	_wall(Vector2(x0 + south_len * 0.5 + 1.95, zs), Vector2(x1, zs), 1.0, 0.9, [])
	# Piédroits + arc du portail (pleine hauteur, sans ruine).
	var portal_a := Vector2(x0 + south_len * 0.5 - 1.95, zs)
	_wall(portal_a, Vector2(portal_a.x + 3.9, zs), 5.0, 0.0, [
		_opening(1.95, door["span"], 0.0, 2.5, false),
	], 0.42, 4.2)


## Décrit une baie en arc brisé (équilatéral) : centre (abscisse le long du
## mur), largeur, appui, naissance de l'arc, meneau central éventuel.
func _opening(center: float, span: float, sill: float, spring: float, mullion: bool) -> Dictionary:
	return {"center": center, "span": span, "sill": sill, "spring": spring, "mullion": mullion, "ring": 0.36}


## Mur de pierres de taille de a à b (positions au sol, plan XZ), assise par
## assise. `ruin` (0 à 1) abaisse le sommet de façon irrégulière.
## `min_top` : hauteur garantie (piédroits d'un portail).
func _wall(a: Vector2, b: Vector2, max_height: float, ruin: float, openings: Array, course_h := 0.42, min_top := 0.0) -> void:
	var length := a.distance_to(b)
	var dir2 := (b - a) / length
	var dir := Vector3(dir2.x, 0.0, dir2.y)
	var normal := dir.cross(Vector3.UP)
	var wall_basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).orthonormalized()
	var origin := Vector3(a.x, 0.0, a.y)

	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.25
	noise.fractal_octaves = 3

	var y := 0.0
	var course := 0
	while y < max_height:
		var h := course_h * _rng.randf_range(0.85, 1.15)
		# Appareil décalé : une assise sur deux commence par une demi-pierre.
		var t := -_rng.randf_range(0.3, 0.5) if course % 2 == 1 else -_rng.randf_range(0.0, 0.15)
		while t < length:
			var w := _rng.randf_range(0.55, 1.05)
			var t0 := maxf(t, 0.0)
			var t1 := minf(t + w, length)
			t += w
			# Sommet ruiné, mesuré au milieu de la pierre.
			var tm := (t0 + t1) * 0.5
			var top := max_height * (1.0 - ruin * clampf(0.5 + noise.get_noise_1d(tm * 4.0) * 1.1, 0.0, 1.0))
			top = maxf(top, min_top)
			if y + h * 0.5 > top:
				continue
			# Découpe autour des baies.
			var span := _trim_to_openings(t0, t1, y, h, openings)
			if span.x < 0.0:
				continue
			t0 = span.x
			t1 = span.y
			if t1 - t0 < 0.12:
				continue
			tm = (t0 + t1) * 0.5
			var jitter := Basis(Vector3.UP, _rng.randf_range(-0.012, 0.012))
			var center := origin + dir * tm + Vector3.UP * (y + h * 0.5) + normal * _rng.randf_range(-0.01, 0.01)
			var color := _stone_tint(y)
			# Pierre légèrement plus petite que sa place : le joint sombre apparaît.
			_box(center, Vector3(t1 - t0 - 0.04, h - 0.04, WALL_T * _rng.randf_range(0.98, 1.02)), wall_basis * jitter, true, color)
			_box(center, Vector3(t1 - t0, h, WALL_T * 0.97), wall_basis, false, mortar_color)
		y += h
		course += 1

	for o in openings:
		_arch(origin, dir, wall_basis, o)


## Retourne (t0, t1) raccourci pour ne pas empiéter sur une baie, ou (-1, -1)
## si la pierre tombe entièrement dans le vide.
func _trim_to_openings(t0: float, t1: float, y: float, h: float, openings: Array) -> Vector2:
	for o in openings:
		var c: float = o["center"]
		var span: float = o["span"]
		var sill: float = o["sill"]
		var spring: float = o["spring"]
		var ring: float = o["ring"]
		if y + h <= sill + 0.01:
			continue
		var half := span * 0.5
		if y + h > spring:
			# Au-dessus de la naissance : largeur de l'arc à cette hauteur
			# (cercle de rayon `span` centré sur la naissance opposée), plus
			# l'épaisseur des claveaux.
			var v := maxf(y - spring, 0.0)
			var r := span + ring
			if v >= r * 0.866:
				continue
			half = sqrt(maxf(r * r - v * v, 0.0)) - span * 0.5
		var lo := c - half
		var hi := c + half
		if t1 <= lo or t0 >= hi:
			continue
		if t0 >= lo and t1 <= hi:
			return Vector2(-1.0, -1.0)
		if t0 < lo:
			t1 = lo
		else:
			t0 = hi
	return Vector2(t0, t1)


## Arc brisé équilatéral en claveaux, plus appui et meneau éventuels.
func _arch(origin: Vector3, dir: Vector3, wall_basis: Basis, o: Dictionary) -> void:
	var c: float = o["center"]
	var span: float = o["span"]
	var spring: float = o["spring"]
	var ring: float = o["ring"]
	var n := 6
	var radius := span + ring * 0.5
	for side: float in [1.0, -1.0]:
		for i in n:
			var a0 := deg_to_rad(60.0) * float(i) / n
			var a1 := deg_to_rad(60.0) * float(i + 1) / n
			var am := (a0 + a1) * 0.5
			# Côté droit : cercle centré sur la naissance gauche (u = -span/2).
			var u := (-span * 0.5 + radius * cos(am)) * side
			var v := radius * sin(am)
			var tangent := dir * (-sin(am) * side) + Vector3.UP * cos(am)
			var radial := dir * (cos(am) * side) + Vector3.UP * sin(am)
			var rot := Basis(tangent, radial, tangent.cross(radial))
			var center := origin + dir * (c + u) + Vector3.UP * (spring + v)
			var size := Vector3(radius * (a1 - a0) - 0.04, ring - 0.03, WALL_T * 1.06)
			_box(center, size, rot, false, _stone_tint(spring + v).lightened(0.06))
	# Clé de voûte.
	_box(origin + dir * c + Vector3.UP * (spring + radius * 0.866 + 0.05), Vector3(0.24, ring + 0.1, WALL_T * 1.1), wall_basis, false, _stone_tint(spring))
	if o["sill"] > 0.0:
		_box(origin + dir * c + Vector3.UP * (o["sill"] - 0.06), Vector3(span + 0.2, 0.12, WALL_T * 1.15), wall_basis, false, _stone_tint(1.0))
	if o["mullion"]:
		var height: float = spring - o["sill"] + span * 0.4
		_box(origin + dir * c + Vector3.UP * (o["sill"] + height * 0.5), Vector3(0.16, height, WALL_T * 0.5), wall_basis, false, _stone_tint(2.0))
		# Deux petits arcs sous le grand (remplage simplifié).
		for side: float in [-1.0, 1.0]:
			_box(origin + dir * (c + side * span * 0.25) + Vector3.UP * (spring + span * 0.18), Vector3(span * 0.3, 0.1, WALL_T * 0.5), wall_basis * Basis(dir.cross(Vector3.UP).normalized(), side * 0.5), false, _stone_tint(2.0))


# --- Piliers -----------------------------------------------------------------------

func _build_pillars() -> void:
	# Hauteurs : quelques piliers intacts (avec chapiteau), d'autres brisés.
	var heights := [5.2, 2.1, 5.2, 0.9, 3.4, 5.2, 1.6, 0.0]
	var i := 0
	for z in [-3.4, -6.6, -9.8, -13.0]:
		for x in [-2.5, 2.5]:
			var h: float = heights[i]
			i += 1
			if h <= 0.0:
				_fallen_pillar(Vector3(x, 0, z), Vector3(0.75, 0, 0.66).normalized())
			else:
				_pillar(Vector3(x, 0, z), h)


func _pillar(base: Vector3, height: float) -> void:
	var color := _stone_tint(0.5)
	_box(base + Vector3.UP * 0.15, Vector3(1.0, 0.3, 1.0), Basis(), true, color.darkened(0.1))
	_box(base + Vector3.UP * 0.36, Vector3(0.82, 0.12, 0.82), Basis(), false, color)
	var y := 0.42
	var intact := height >= 5.0
	while y < height - 0.05:
		var h := minf(_rng.randf_range(0.5, 0.65), height - y)
		var offset := Vector3(_rng.randf_range(-0.02, 0.02), 0, _rng.randf_range(-0.02, 0.02))
		_drum(base + offset + Vector3.UP * (y + h * 0.5), 0.34, h - 0.03, Basis(Vector3.UP, _rng.randf() * TAU))
		y += h
	if intact:
		_box(base + Vector3.UP * (y + 0.12), Vector3(0.9, 0.24, 0.9), Basis(), false, color.lightened(0.05))
		_box(base + Vector3.UP * (y + 0.32), Vector3(1.05, 0.16, 1.05), Basis(), false, color)
	var shape := CylinderShape3D.new()
	shape.radius = 0.42
	shape.height = minf(height, COLLISION_MAX_HEIGHT)
	_collider(shape, Transform3D(Basis(), base + Vector3.UP * shape.height * 0.5))


## Pilier effondré : socle en place, tambours couchés et dispersés au sol.
func _fallen_pillar(base: Vector3, fall_dir: Vector3) -> void:
	_box(base + Vector3.UP * 0.15, Vector3(1.0, 0.3, 1.0), Basis(), true, _stone_tint(0.0))
	var side := fall_dir.cross(Vector3.UP)
	var axis := Basis(side.normalized(), PI * 0.5)
	var d := 0.9
	for k in 7:
		var h := _rng.randf_range(0.5, 0.62)
		var drift := side * _rng.randf_range(-0.15, 0.15) * k * 0.3
		var center := base + fall_dir * (d + h * 0.5) + drift + Vector3.UP * 0.33
		var roll := Basis(fall_dir, _rng.randf_range(-0.2, 0.2))
		_drum(center, 0.34, h - 0.04, roll * axis * Basis(Vector3.UP, _rng.randf() * TAU))
		var shape := CylinderShape3D.new()
		shape.radius = 0.34
		shape.height = h
		_collider(shape, Transform3D(roll * axis, center))
		d += h + _rng.randf_range(0.0, 0.35)


# --- Sol, autel, éboulis ---------------------------------------------------------------

## Dallage disjoint de la nef : dalles inclinées, certaines manquantes.
func _build_floor() -> void:
	var size := 0.9
	var x := -NAVE_X + 0.05
	while x < NAVE_X - 0.3:
		var z := NAVE_Z0 + 0.05
		while z < NAVE_Z1 - 0.2:
			if _rng.randf() > 0.14 and z > -13.1:
				var tilt := Basis(Vector3.RIGHT, _rng.randf_range(-0.035, 0.035)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.035, 0.035))
				var top := _rng.randf_range(0.02, 0.06)
				var c := _stone_tint(0.0).darkened(_rng.randf_range(0.05, 0.25))
				_box(Vector3(x + size * 0.5, top - 0.06, z + size * 0.5), Vector3(size - 0.06, 0.12, size - 0.06), tilt * Basis(Vector3.UP, _rng.randf_range(-0.03, 0.03)), false, c)
			z += size
		x += size


## Emmarchement (3 marches), plate-forme, autel et cierges.
func _build_altar() -> void:
	var front := -13.2
	var step_h := 0.18
	var step_d := 0.5
	for k in 3:
		var z0 := front - step_d * k
		var y := step_h * (k + 1)
		var x := -NAVE_X
		while x < NAVE_X:
			var w := minf(_rng.randf_range(0.9, 1.5), NAVE_X - x)
			var depth := (z0 - NAVE_Z0) if k == 2 else step_d
			_box(Vector3(x + w * 0.5, y * 0.5, z0 - depth * 0.5), Vector3(w - 0.03, y, depth - 0.03), Basis(), k == 2, _stone_tint(0.3))
			x += w
	# Rampe de collision invisible : un CharacterBody3D ne gravit pas les marches.
	var run := step_d * 3.0
	var rise := step_h * 3.0
	var ramp := BoxShape3D.new()
	ramp.size = Vector3(NAVE_X * 2.0, 0.1, sqrt(run * run + rise * rise))
	_collider(ramp, Transform3D(Basis(Vector3.RIGHT, atan2(rise, run)), Vector3(0, rise * 0.5 - 0.05, front - run * 0.5)))

	# Autel : bloc massif et table débordante.
	var top_y := rise
	var altar_z := -15.0
	_box(Vector3(0, top_y + 0.5, altar_z), Vector3(1.9, 1.0, 0.8), Basis(), true, _stone_tint(1.0).darkened(0.15))
	_box(Vector3(0, top_y + 1.06, altar_z), Vector3(2.2, 0.12, 1.0), Basis(), false, _stone_tint(1.0))

	# Cierges : cire claire, flamme émissive, une lumière vacillante par groupe.
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.85, 0.8, 0.68)
	wax.roughness = 0.6
	var flame := StandardMaterial3D.new()
	flame.albedo_color = Color(1.0, 0.7, 0.3)
	flame.emission_enabled = true
	flame.emission = Color(1.0, 0.55, 0.15)
	flame.emission_energy_multiplier = 4.0
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for group in [Vector3(-0.75, 0, altar_z), Vector3(0.75, 0, altar_z), Vector3(-2.6, 0, -14.3), Vector3(2.6, 0, -14.3)]:
		var base_y := top_y + 1.12 if absf(group.x) < 1.0 else top_y
		for k in 3:
			var p: Vector3 = group + Vector3(_rng.randf_range(-0.18, 0.18), 0, _rng.randf_range(-0.15, 0.15))
			var h := _rng.randf_range(0.15, 0.4) if base_y > 1.0 else _rng.randf_range(0.4, 0.9)
			_simple_mesh(_cylinder_mesh(0.035, h), wax, Vector3(p.x, base_y + h * 0.5, p.z))
			_simple_mesh(_sphere_mesh(0.028), flame, Vector3(p.x, base_y + h + 0.04, p.z), Vector3(1, 1.8, 1))
		var light := OmniLight3D.new()
		light.set_script(FLICKER_SCRIPT)
		light.light_color = Color(1.0, 0.62, 0.28)
		light.set("base_energy", 1.6)
		light.omni_range = 5.5
		light.omni_attenuation = 1.3
		light.shadow_enabled = absf(group.x) < 1.0
		light.position = Vector3(group.x, base_y + 0.9, group.z + 0.3)
		add_child(light)


## Pierres tombées au pied des murs, surtout là où ils sont effondrés.
func _build_rubble() -> void:
	var spots := [
		[Vector3(NAVE_X + 1.2, 0, -8.0), 3.0, 40],   # mur est, dehors
		[Vector3(NAVE_X - 1.0, 0, -6.0), 2.2, 18],   # mur est, dedans
		[Vector3(-2.5, 0, 0.6), 1.6, 12],            # façade sud
		[Vector3(3.2, 0, 1.0), 1.6, 14],
		[Vector3(-NAVE_X - 1.3, 0, -3.0), 1.5, 10],  # mur ouest
	]
	for spot in spots:
		var center: Vector3 = spot[0]
		var radius: float = spot[1]
		for k: int in spot[2]:
			var p := center + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * radius
			var s := Vector3(_rng.randf_range(0.3, 0.9), _rng.randf_range(0.22, 0.42), _rng.randf_range(0.3, 0.6))
			var rot := Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)))
			_box(p + Vector3.UP * s.y * 0.35, s, rot, s.x > 0.6, _stone_tint(0.0))


## Cimetière à l'est : stèles et croix penchées.
func _build_graveyard() -> void:
	for row in 3:
		for col in 5:
			if _rng.randf() < 0.2:
				continue
			var p := Vector3(8.0 + col * 1.6 + _rng.randf_range(-0.3, 0.3), 0, -13.0 + row * 2.6 + _rng.randf_range(-0.3, 0.3))
			var lean := Basis.from_euler(Vector3(_rng.randf_range(-0.22, 0.12), _rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.12, 0.12)))
			var c := _stone_tint(0.0).darkened(0.1)
			if _rng.randf() < 0.55:
				# Stèle : dalle + sommet arrondi (tambour couché).
				var h := _rng.randf_range(0.6, 0.95)
				_box(p + lean * Vector3(0, h * 0.5, 0), Vector3(0.55, h, 0.13), lean, true, c)
				_drum(p + lean * Vector3(0, h, 0), 0.275, 0.13, lean * Basis(Vector3.RIGHT, PI * 0.5))
			else:
				# Croix.
				var h := _rng.randf_range(0.9, 1.25)
				_box(p + lean * Vector3(0, h * 0.5, 0), Vector3(0.13, h, 0.13), lean, true, c)
				_box(p + lean * Vector3(0, h * 0.72, 0), Vector3(0.55, 0.12, 0.12), lean, false, c)
			# Tertre : dalle de pierre basse devant la tombe.
			_box(p + Vector3(0, 0.04, 0.75), Vector3(0.7, 0.08, 1.3), Basis(Vector3.UP, _rng.randf_range(-0.1, 0.1)), false, _stone_tint(0.0).darkened(0.3))


## Chemin dallé, du portail vers le sud.
func _build_path() -> void:
	var z := NAVE_Z1 + 0.9
	while z < 14.0:
		var x := -1.1 + _rng.randf_range(-0.15, 0.15)
		while x < 1.0:
			var w := _rng.randf_range(0.5, 0.85)
			if _rng.randf() > 0.25 + (z / 14.0) * 0.35:
				_box(Vector3(x + w * 0.5, 0.0, z), Vector3(w - 0.07, 0.1, _rng.randf_range(0.45, 0.65)), Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12)), false, _stone_tint(0.0).darkened(0.2))
			x += w
		z += 0.62


# --- Utilitaires ---------------------------------------------------------------------

func _stone_tint(y: float) -> Color:
	var c := stone_color * _rng.randf_range(0.7, 1.12)
	# Mousse : plus fréquente près du sol.
	if _rng.randf() < 0.4 * exp(-y * 0.5):
		c = c.lerp(moss_color, _rng.randf_range(0.25, 0.75))
	c.a = 1.0
	return c


func _box(center: Vector3, size: Vector3, rot: Basis, collide: bool, color: Color) -> void:
	_boxes.append(Transform3D(rot * Basis.from_scale(size), center))
	_box_colors.append(color)
	if collide and center.y - size.y * 0.5 < COLLISION_MAX_HEIGHT:
		var shape := BoxShape3D.new()
		shape.size = size
		_collider(shape, Transform3D(rot, center))


func _drum(center: Vector3, radius: float, height: float, rot: Basis) -> void:
	_drums.append(Transform3D(rot * Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), center))
	_drum_colors.append(_stone_tint(center.y))


func _collider(shape: Shape3D, xform: Transform3D) -> void:
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = xform
	_body.add_child(col)


func _add_multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D], colors: PackedColorArray) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = mm
	instance.material_override = STONE.get_material()
	add_child(instance)


func _simple_mesh(mesh: Mesh, material: Material, pos: Vector3, scl := Vector3.ONE) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	m.scale = scl
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


func _cylinder_mesh(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 8
	m.rings = 1
	return m


func _sphere_mesh(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m
