class_name AsciiPostProcess
extends MeshInstance3D
## Pilote le quad de post-traitement ASCII (enfant de la caméra).
##
## - choisit une police (police du dossier fonts/, sinon police mono système,
##   sinon police par défaut de Godot) ;
## - génère l'atlas de glyphes à la taille de cellule courante ;
## - expose des méthodes de debug (activer/désactiver, contours, taille de cellule).
##
## Le quad est caché dans la scène (visible = false) pour ne pas masquer la vue
## de l'éditeur : il n'est affiché qu'une fois l'atlas prêt, au lancement.

signal settings_changed

## Rampe de luminance, du plus sombre au plus clair.
const RAMP := " .:-=+*#%@"
## Glyphes directionnels, dans l'ordre attendu par le shader.
const EDGE_GLYPHS := "|/-\\"
## Tailles de cellule accessibles avec +/-.
const CELL_SIZES: Array[int] = [6, 8, 10, 12]

## Taille de cellule initiale (pixels).
@export var cell_size: int = 8
## Police imposée (optionnelle). Sinon : premier fichier de `fonts_dir`, puis police système.
@export var custom_font: Font
## Dossier scanné pour trouver une police (.ttf / .otf / .woff / .woff2).
@export_dir var fonts_dir := "res://fonts"
## Taille de police = cell_size + font_size_padding (les capitales n'occupent ~70 % de la hauteur).
@export var font_size_padding: int = 2

var ascii_enabled := true
var edges_enabled := true

var _material: ShaderMaterial
var _atlas_generator: GlyphAtlas
var _font: Font
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
	add_child(_atlas_generator)
	_font = _pick_font()

	_material.set_shader_parameter("ramp_count", RAMP.length())
	_material.set_shader_parameter("glyph_count", RAMP.length() + EDGE_GLYPHS.length())
	_material.set_shader_parameter("enable_edges", edges_enabled)

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


func get_font_name() -> String:
	return _font.get_font_name() if _font else "?"


# --- Interne ----------------------------------------------------------------

## Régénère l'atlas pour la taille de cellule courante puis met à jour le shader.
func _rebuild_atlas() -> void:
	_build_id += 1
	var my_id := _build_id
	var size := cell_size
	var texture := await _atlas_generator.generate(RAMP + EDGE_GLYPHS, size, _font, size + font_size_padding)
	if my_id != _build_id:
		return # une génération plus récente a été lancée entre-temps
	if texture == null:
		return
	# On met à jour cell_size et atlas ensemble pour qu'ils restent cohérents.
	_material.set_shader_parameter("glyph_atlas", texture)
	_material.set_shader_parameter("cell_size", size)


func _pick_font() -> Font:
	if custom_font:
		return custom_font

	var from_dir := _find_font_in_dir(fonts_dir)
	if from_dir:
		return from_dir

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
