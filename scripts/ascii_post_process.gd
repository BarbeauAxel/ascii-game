class_name AsciiPostProcess
extends MeshInstance3D
## Pilote le quad de post-traitement ASCII (enfant de la caméra).
##
## - choisit une police (police du dossier fonts/, sinon police mono système,
##   sinon police par défaut de Godot) ;
## - génère deux atlas de glyphes : un à la taille de cellule du décor, un à la
##   moitié pour le personnage ;
## - décrit au shader les rampes de glyphes par type de surface ;
## - expose des méthodes de debug (activer/désactiver, contours, taille de cellule…).
##
## Le quad est caché dans la scène (visible = false) pour ne pas masquer la vue
## de l'éditeur : il n'est affiché qu'une fois l'atlas prêt, au lancement.

signal settings_changed

## Rampes de glyphes par type de surface (une ligne de l'atlas chacune).
## Chaque rampe est une liste de « paliers » du plus sombre au plus clair. Un
## palier peut contenir plusieurs variantes de même densité (ex : "<>") : le
## shader en choisit une au hasard par cellule pour casser la répétition.
## L'index dans ce tableau = identifiant de surface dans le shader :
##   0 : défaut (et personnage)   1 : sol   2 : murs / piliers
const SURFACE_TIERS := [
	[" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"],
	[" ", "~", "<>", "+"],
	[" ", "[]", "HN", "#"],
]
## Glyphes directionnels (ajoutés à la fin de la ligne 0), ordre attendu par le shader.
const EDGE_GLYPHS := "|/-\\"
## Doivent correspondre aux tailles des tableaux uniformes du shader.
const MAX_SURFACES := 4
const MAX_TIERS := 16
## Tailles de cellule accessibles avec +/-.
const CELL_SIZES: Array[int] = [6, 8, 10, 12]

## Taille de cellule initiale (pixels). Le personnage utilise la moitié.
@export var cell_size: int = 8
## Police imposée (optionnelle). Sinon : premier fichier de `fonts_dir`, puis police système.
@export var custom_font: Font
## Dossier scanné pour trouver une police (.ttf / .otf / .woff / .woff2).
@export_dir var fonts_dir := "res://fonts"
## Taille de police = taille de cellule + font_size_padding (les capitales n'occupent ~70 % de la hauteur).
@export var font_size_padding: int = 2
## Police pixel (fichier de fonts/ ou custom_font) : taille de sa grille native
## (8 pour Press Start 2P). La taille de police devient alors le plus grand
## multiple de cette valeur qui tient dans la cellule, sans antialiasing, pour
## des pixels nets. 0 = traiter la police comme une police vectorielle classique.
@export var font_pixel_size: int = 8

var ascii_enabled := true
var edges_enabled := true
var surface_glyphs_enabled := true
var fine_player_enabled := true

var _material: ShaderMaterial
var _atlas_generator: GlyphAtlas
var _font: Font
## Pour une police pixel : copie lissée utilisée quand la cellule est plus
## petite que la grille native (ex : cellules de 4 px du personnage), où un
## rendu sans antialiasing perdrait des pixels entiers.
var _font_smooth: Font
var _is_pixel_font := false
var _atlas_rows := PackedStringArray()
var _build_id := 0


func _ready() -> void:
	_material = material_override as ShaderMaterial
	if _material == null:
		push_error("AsciiPostProcess : material_override doit être un ShaderMaterial.")
		return

	# Le quad ne doit jamais être éliminé par le frustum culling.
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_atlas_generator = GlyphAtlas.new()
	# Debug : "-- --save-atlas" écrit les atlas en PNG dans user://
	_atlas_generator.save_debug_png = "--save-atlas" in OS.get_cmdline_user_args()
	add_child(_atlas_generator)
	_font = _pick_font()

	_setup_surface_tables()
	_material.set_shader_parameter("enable_edges", edges_enabled)
	_material.set_shader_parameter("enable_surface_glyphs", surface_glyphs_enabled)
	_material.set_shader_parameter("enable_fine_player", fine_player_enabled)

	await _rebuild_atlas()
	visible = ascii_enabled


# --- API de debug -----------------------------------------------------------

func toggle_enabled() -> void:
	ascii_enabled = not ascii_enabled
	visible = ascii_enabled
	settings_changed.emit()


func toggle_edges() -> void:
	edges_enabled = not edges_enabled
	_material.set_shader_parameter("enable_edges", edges_enabled)
	settings_changed.emit()


func toggle_surface_glyphs() -> void:
	surface_glyphs_enabled = not surface_glyphs_enabled
	_material.set_shader_parameter("enable_surface_glyphs", surface_glyphs_enabled)
	settings_changed.emit()


func toggle_fine_player() -> void:
	fine_player_enabled = not fine_player_enabled
	_material.set_shader_parameter("enable_fine_player", fine_player_enabled)
	settings_changed.emit()


## Vue de debug du shader : 0 = normal, 1 = identifiants de surface en couleurs unies.
func set_debug_view(mode: int) -> void:
	_material.set_shader_parameter("debug_view", mode)


## step = +1 ou -1 : passe à la taille de cellule suivante / précédente.
func step_cell_size(step: int) -> void:
	var index := CELL_SIZES.find(cell_size)
	if index == -1:
		index = 1
	index = clampi(index + step, 0, CELL_SIZES.size() - 1)
	if CELL_SIZES[index] == cell_size:
		return
	cell_size = CELL_SIZES[index]
	_rebuild_atlas()
	settings_changed.emit()


func get_fine_cell_size() -> int:
	return maxi(floori(cell_size / 2.0), 2)


func get_font_name() -> String:
	return _font.get_font_name() if _font else "?"


# --- Interne ----------------------------------------------------------------

## Construit les lignes de l'atlas et les tables (début / nombre de variantes
## de chaque palier) que le shader utilise pour trouver la bonne colonne.
func _setup_surface_tables() -> void:
	var tier_count := PackedInt32Array()
	tier_count.resize(MAX_SURFACES)
	var tier_start := PackedInt32Array()
	tier_start.resize(MAX_SURFACES * MAX_TIERS)
	var tier_variants := PackedInt32Array()
	tier_variants.resize(MAX_SURFACES * MAX_TIERS)

	_atlas_rows.clear()
	for surface in SURFACE_TIERS.size():
		var tiers: Array = SURFACE_TIERS[surface]
		assert(tiers.size() <= MAX_TIERS, "Trop de paliers pour la surface %d" % surface)
		var row := ""
		for t in tiers.size():
			var variants: String = tiers[t]
			tier_start[surface * MAX_TIERS + t] = row.length()
			tier_variants[surface * MAX_TIERS + t] = variants.length()
			row += variants
		tier_count[surface] = tiers.size()
		if surface == 0:
			# Les glyphes directionnels suivent la rampe par défaut.
			_material.set_shader_parameter("edge_column", row.length())
			row += EDGE_GLYPHS
		_atlas_rows.append(row)

	var columns := 0
	for row in _atlas_rows:
		columns = maxi(columns, row.length())

	_material.set_shader_parameter("atlas_columns", columns)
	_material.set_shader_parameter("atlas_rows", _atlas_rows.size())
	_material.set_shader_parameter("tier_count", tier_count)
	_material.set_shader_parameter("tier_start", tier_start)
	_material.set_shader_parameter("tier_variants", tier_variants)


## Régénère les deux atlas pour la taille de cellule courante puis met à jour le shader.
func _rebuild_atlas() -> void:
	_build_id += 1
	var my_id := _build_id
	var size := cell_size
	var fine := get_fine_cell_size()

	var atlas := await _atlas_generator.generate(_atlas_rows, size, _font_for_cell(size), _font_size_for_cell(size))
	var atlas_fine := await _atlas_generator.generate(_atlas_rows, fine, _font_for_cell(fine), _font_size_for_cell(fine))
	if my_id != _build_id:
		return # une génération plus récente a été lancée entre-temps
	if atlas == null or atlas_fine == null:
		return
	# On met à jour tailles et atlas ensemble pour qu'ils restent cohérents.
	_material.set_shader_parameter("glyph_atlas", atlas)
	_material.set_shader_parameter("glyph_atlas_fine", atlas_fine)
	_material.set_shader_parameter("cell_size", size)
	_material.set_shader_parameter("fine_cell_size", fine)


## Taille de police à utiliser pour une taille de cellule donnée.
func _font_size_for_cell(cell: int) -> int:
	if _is_pixel_font:
		if cell >= font_pixel_size:
			# Plus grand multiple de la grille native : chaque pixel de la police
			# tombe exactement sur 1, 2, 3… pixels de l'écran.
			return floori(float(cell) / font_pixel_size) * font_pixel_size
		return cell # cellule plus petite que la grille : réduction inévitable
	return cell + font_size_padding


## Police à utiliser pour une taille de cellule donnée (nette ou lissée).
func _font_for_cell(cell: int) -> Font:
	if _is_pixel_font and cell < font_pixel_size:
		return _font_smooth
	return _font


func _pick_font() -> Font:
	var file_font: Font = custom_font if custom_font else _find_font_in_dir(fonts_dir)
	if file_font:
		if font_pixel_size > 0 and file_font is FontFile:
			_setup_pixel_font(file_font)
		return file_font

	# Police monospace du système (présente sur Windows / la plupart des Linux).
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray([
		"Consolas", "Cascadia Mono", "DejaVu Sans Mono", "Liberation Mono",
		"Noto Sans Mono", "Ubuntu Mono", "Courier New", "monospace",
	])
	system_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	if system_font.get_font_name() != "":
		return system_font

	# Dernier recours : police par défaut du moteur.
	return ThemeDB.fallback_font


## Configure une police pixel : rendu net (sans antialiasing ni hinting, pixels
## entiers) et prépare une copie lissée pour les cellules trop petites.
func _setup_pixel_font(font: FontFile) -> void:
	_is_pixel_font = true
	_font_smooth = font.duplicate() as Font
	(_font_smooth as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED


func _find_font_in_dir(path: String) -> Font:
	var dir := DirAccess.open(path)
	if dir == null:
		return null
	for file in dir.get_files():
		# Dans un export, les fichiers sources apparaissent en ".import" / ".remap".
		var file_name := file.trim_suffix(".import").trim_suffix(".remap")
		if file_name.get_extension().to_lower() in ["ttf", "otf", "woff", "woff2"]:
			var resource := load(path.path_join(file_name))
			if resource is Font:
				return resource
	return null
