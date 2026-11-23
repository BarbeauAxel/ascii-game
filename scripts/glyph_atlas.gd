class_name GlyphAtlas
extends Node
## Génère un atlas de glyphes au lancement.
##
## Godot ne sait pas dessiner du texte directement dans une Image : on passe donc
## par un SubViewport 2D transparent dans lequel un Node2D dessine chaque
## caractère avec draw_string(). Après un rendu, on récupère l'Image du viewport
## et on en fait une ImageTexture que le shader peut lire.
##
## Résultat : une grille de cases carrées de `cell` pixels (une ligne par
## chaîne de `rows`), glyphes blancs sur fond transparent (le shader n'utilise
## que le canal alpha comme masque).

## Si vrai, l'atlas est aussi sauvegardé dans user://glyph_atlas_<taille>.png (debug).
@export var save_debug_png := false


## Génère l'atlas (coroutine : à appeler avec `await`).
## `rows` : une chaîne de glyphes par ligne de l'atlas.
## Retourne null si le rendu n'est pas disponible (ex : mode headless).
func generate(rows: PackedStringArray, cell: int, font: Font, font_size: int) -> ImageTexture:
	var columns := 0
	for row in rows:
		columns = maxi(columns, row.length())

	var viewport := SubViewport.new()
	viewport.size = Vector2i(cell * columns, cell * rows.size())
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.snap_2d_transforms_to_pixel = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var canvas := GlyphCanvas.new()
	canvas.rows = rows
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

	return ImageTexture.create_from_image(image)


## Node2D interne qui dessine les glyphes, chacun centré dans sa case.
class GlyphCanvas extends Node2D:
	var rows := PackedStringArray()
	var cell := 8
	var font: Font
	var font_size := 10

	func _draw() -> void:
		var ascent := font.get_ascent(font_size)
		var descent := font.get_descent(font_size)
		# Ligne de base choisie pour centrer verticalement la boîte ascent+descent.
		var baseline := roundf((float(cell) + ascent - descent) * 0.5)
		for r in rows.size():
			var glyphs := rows[r]
			for i in glyphs.length():
				var ch := glyphs[i]
				var width := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				var x := roundf(float(i * cell) + (float(cell) - width) * 0.5)
				var y := float(r * cell) + baseline
				draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
