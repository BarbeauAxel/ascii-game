class_name GlyphAtlas
extends Node
## Génère et analyse l'atlas de glyphes au lancement.
##
## 1. Rendu : Godot ne sait pas dessiner du texte directement dans une Image ;
##    on passe donc par un SubViewport 2D transparent dans lequel un Node2D
##    dessine chaque caractère avec draw_string(), puis on relit l'Image.
## 2. Analyse : pour chaque glyphe, on mesure sa couverture (part de pixels
##    allumés) dans une grille 3x3 : c'est son « descripteur de forme ». Le
##    shader compare ces descripteurs à la luminance 3x3 de chaque cellule.
##    On en déduit aussi une rampe de densité triée automatiquement.
##
## Atlas : une ligne de cases carrées de `cell` pixels, glyphes blancs sur fond
## transparent (le shader n'utilise que le canal alpha comme masque).

## Si vrai, l'atlas est aussi sauvegardé dans user://glyph_atlas_<taille>.png (debug).
@export var save_debug_png := false


## Rend une ligne de glyphes (coroutine : à appeler avec `await`).
## Retourne null si le rendu n'est pas disponible (ex : mode headless).
func render(glyphs: String, cell: int, font: Font, font_size: int) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(cell * glyphs.length(), cell)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.snap_2d_transforms_to_pixel = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var canvas := GlyphCanvas.new()
	canvas.glyphs = glyphs
	canvas.cell = cell
	canvas.font = font
	canvas.font_size = font_size
	viewport.add_child(canvas)
	add_child(viewport)

	# On attend que le viewport ait été rendu au moins une fois.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := viewport.get_texture().get_image()
	viewport.queue_free()

	if image == null or image.is_empty():
		push_warning("GlyphAtlas : impossible de lire l'image du viewport (rendu indisponible ?)")
		return null

	if save_debug_png:
		image.save_png("user://glyph_atlas_%d.png" % cell)
	return image


## Analyse l'atlas rendu. Retourne un dictionnaire :
##   "shapes"   : Array de PackedFloat32Array(9), couverture 3x3 normalisée
##                (la région la plus remplie de tout l'atlas vaut 1) ;
##   "means"    : PackedFloat32Array, moyenne des 9 régions (densité) ;
##   "spreads"  : PackedFloat32Array, écart-type des 9 régions (0 = glyphe uniforme) ;
##   "asymmetry": PackedFloat32Array, différence gauche/droite (0 = symétrique).
static func analyze(image: Image, glyph_count: int, cell: int) -> Dictionary:
	var third := float(cell) / 3.0
	var shapes: Array = []
	var max_region := 0.0

	for g in glyph_count:
		var regions := PackedFloat32Array()
		regions.resize(9)
		for y in cell:
			for x in cell:
				var alpha := image.get_pixel(g * cell + x, y).a
				if alpha <= 0.0:
					continue
				# Un pixel peut chevaucher deux régions (cellule non divisible
				# par 3) : on répartit sa couverture au prorata de la surface.
				for ry in 3:
					var oy := _overlap(y, ry * third, (ry + 1) * third)
					if oy <= 0.0:
						continue
					for rx in 3:
						var ox := _overlap(x, rx * third, (rx + 1) * third)
						if ox > 0.0:
							regions[ry * 3 + rx] += alpha * ox * oy
		for i in 9:
			regions[i] /= third * third
			max_region = maxf(max_region, regions[i])
		shapes.append(regions)

	var means := PackedFloat32Array()
	var spreads := PackedFloat32Array()
	var asymmetry := PackedFloat32Array()
	for g in shapes.size():
		# Les Packed*Array sont copiés à l'affectation : on modifie puis on réécrit.
		var regions: PackedFloat32Array = shapes[g]
		var mean := 0.0
		for i in 9:
			if max_region > 0.0:
				regions[i] /= max_region
			mean += regions[i]
		shapes[g] = regions
		mean /= 9.0
		var variance := 0.0
		for i in 9:
			variance += (regions[i] - mean) * (regions[i] - mean)
		means.append(mean)
		spreads.append(sqrt(variance / 9.0))
		# Miroir gauche/droite : colonnes 0 et 2 de la grille 3x3.
		asymmetry.append((absf(regions[0] - regions[2]) + absf(regions[3] - regions[5]) + absf(regions[6] - regions[8])) / 3.0)

	return {"shapes": shapes, "means": means, "spreads": spreads, "asymmetry": asymmetry}


## Construit une rampe d'au plus `levels` glyphes de densité strictement
## croissante. La rampe sert aux zones sans forme particulière : à densité
## proche, on préfère les glyphes uniformes et symétriques (un "<" répété sur
## tout un sol créerait un faux motif). Les glyphes de `excluded` (index) ne
## sont jamais utilisés.
static func build_ramp(analysis: Dictionary, levels: int, excluded: PackedInt32Array) -> PackedInt32Array:
	var means: PackedFloat32Array = analysis["means"]
	var spreads: PackedFloat32Array = analysis["spreads"]
	var asymmetry: PackedFloat32Array = analysis["asymmetry"]
	var max_mean := 0.0
	for m in means:
		max_mean = maxf(max_mean, m)

	# Le premier niveau est toujours le glyphe le moins dense (l'espace).
	var ramp := PackedInt32Array([0])
	for k in range(1, levels):
		var target := max_mean * float(k) / float(maxi(levels - 1, 1))
		var last_mean := means[ramp[ramp.size() - 1]]
		var best := -1
		var best_score := INF
		for g in means.size():
			# Uniquement des glyphes plus denses que le niveau précédent : la
			# rampe ne peut pas s'effondrer sur un même glyphe.
			if g in excluded or means[g] <= last_mean + 0.005:
				continue
			# L'asymétrie mesurée est bruitée aux petites tailles (glyphe décalé
			# d'un demi-pixel) : elle ne sert qu'à départager à densité proche.
			var score := absf(means[g] - target) + 0.15 * spreads[g] + 0.25 * asymmetry[g]
			if score < best_score:
				best_score = score
				best = g
		if best == -1:
			break # plus aucun glyphe plus dense
		ramp.append(best)
	return ramp


## Longueur du recouvrement entre le pixel [p, p+1] et l'intervalle [a, b].
static func _overlap(p: int, a: float, b: float) -> float:
	return maxf(0.0, minf(float(p + 1), b) - maxf(float(p), a))


## Node2D interne qui dessine les glyphes, chacun centré dans sa case.
class GlyphCanvas extends Node2D:
	var glyphs := ""
	var cell := 8
	var font: Font
	var font_size := 10

	func _draw() -> void:
		var ascent := font.get_ascent(font_size)
		var descent := font.get_descent(font_size)
		# Ligne de base choisie pour centrer verticalement la boîte ascent+descent.
		var baseline := roundf((float(cell) + ascent - descent) * 0.5)
		for i in glyphs.length():
			var ch := glyphs[i]
			var width := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var x := roundf(float(i * cell) + (float(cell) - width) * 0.5)
			draw_string(font, Vector2(x, baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
