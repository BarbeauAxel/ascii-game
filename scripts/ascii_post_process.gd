class_name AsciiPostProcess
extends MeshInstance3D
## Pilote le quad de post-traitement ASCII (enfant de la caméra).
##
## - choisit une police (police du dossier fonts/, sinon police mono système,
##   sinon police par défaut de Godot) ;
## - génère l'atlas des glyphes à la taille de cellule courante, puis l'analyse :
##   descripteur de forme 3x3 de chaque glyphe + rampe de densité triée ;
## - transmet le tout au shader ;
## - expose des méthodes de debug (activer/désactiver, contours, taille de cellule…).
##
## Le quad est caché dans la scène (visible = false) pour ne pas masquer la vue
## de l'éditeur : il n'est affiché qu'une fois l'atlas prêt, au lancement.

signal settings_changed

## Taille max du jeu de glyphes (doit correspondre au tableau glyph_shape du shader : 3 vec4 par glyphe).
const MAX_GLYPHS := 128
## Taille max de la rampe (tableau `ramp` du shader).
const MAX_RAMP := 32
## Tailles de cellule accessibles avec +/-.
const CELL_SIZES: Array[int] = [4, 5, 6, 7, 8, 10]

## Taille de cellule initiale (pixels).
@export var cell_size: int = 5
## Glyphes candidats. Le premier doit être l'espace. Les quatre glyphes
## directionnels | / - \ sont obligatoires (contours et traits orientés).
## Moins de glyphes = shader plus rapide (la correspondance de forme les teste tous).
@export var glyph_set := " .,:;'`\"^~-_=+*!?/\\|()[]{}<>#%@&$ilIoOxXvVwWmMnNHT01"
## Nombre de niveaux visés pour la rampe de densité (les doublons sont retirés).
@export_range(4, 32) var ramp_levels: int = 24
## Police imposée (optionnelle). Sinon : premier fichier de `fonts_dir`, puis police système.
@export var custom_font: Font
## Dossier scanné pour trouver une police (.ttf / .otf / .woff / .woff2).
@export_dir var fonts_dir := "res://fonts"
## Taille de police = taille de cellule + font_size_padding (polices vectorielles).
@export var font_size_padding: int = 2
## Police pixel (fichier de fonts/ ou custom_font) : taille de sa grille native
## (8 pour Press Start 2P). La taille de police devient alors le plus grand
## multiple de cette valeur qui tient dans la cellule, sans antialiasing, pour
## des pixels nets. 0 = traiter la police comme une police vectorielle classique.
@export var font_pixel_size: int = 8

@export_group("Joueur en cellules fines (F5)")
## Personnage dessiné en cellules plus petites que le décor (plus de détail).
@export var fine_target_path: NodePath
## Taille des cellules fines (pixels). Ignorée si >= cell_size.
@export var fine_cell_size: int = 3
## Calques de rendu du personnage (voir soldier.gd, CHARACTER_LAYER).
@export_flags_3d_render var character_layers: int = 2

var ascii_enabled := true
var fine_enabled := true
var edges_enabled := true
var shape_matching_enabled := true
## Rampe générée (pour affichage / debug), du plus clair au plus dense.
var ramp_text := ""

var _material: ShaderMaterial
var _atlas_generator: GlyphAtlas
var _font: Font
## Pour une police pixel : copie lissée utilisée quand la cellule est plus
## petite que la grille native, où un rendu sans antialiasing perdrait des
## pixels entiers.
var _font_smooth: Font
var _is_pixel_font := false
var _build_id := 0
# Passe « joueur fin » : caméra jumelle qui ne voit que le personnage.
var _fine_target: Node3D
var _mask_viewport: SubViewport
var _mask_camera: Camera3D
var _fine_ready := false


func _ready() -> void:
	_material = material_override as ShaderMaterial
	if _material == null:
		push_error("AsciiPostProcess : material_override doit être un ShaderMaterial.")
		return

	# Le quad ne doit jamais être éliminé par le frustum culling.
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_validate_glyph_set()
	_atlas_generator = GlyphAtlas.new()
	# Debug : "-- --save-atlas" écrit l'atlas en PNG dans user://
	_atlas_generator.save_debug_png = "--save-atlas" in OS.get_cmdline_user_args()
	add_child(_atlas_generator)
	_font = _pick_font()

	_material.set_shader_parameter("enable_edges", edges_enabled)
	_material.set_shader_parameter("enable_strokes", edges_enabled)
	_material.set_shader_parameter("use_shape_matching", shape_matching_enabled)
	_material.set_shader_parameter("dir_glyphs", Vector4i(
		glyph_set.find("|"), glyph_set.find("/"), glyph_set.find("-"), glyph_set.find("\\")))

	_fine_target = get_node_or_null(fine_target_path) as Node3D
	if _fine_target:
		_setup_fine_pass()

	await _rebuild_atlas()
	visible = ascii_enabled


func _process(_delta: float) -> void:
	if not (fine_enabled and _fine_ready and _fine_target and _mask_viewport):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# La caméra jumelle copie exactement la caméra principale.
	var vp_size := Vector2i(get_viewport().get_visible_rect().size)
	if _mask_viewport.size != vp_size:
		_mask_viewport.size = vp_size
	_mask_camera.global_transform = cam.global_transform
	_mask_camera.projection = cam.projection
	_mask_camera.size = cam.size
	_mask_camera.fov = cam.fov
	_mask_camera.near = cam.near
	_mask_camera.far = cam.far
	# Intervalle de profondeur occupé par le personnage (boîte englobante
	# généreuse : cape et épée comprises), en distance le long de la vue.
	var inv := cam.global_transform.affine_inverse()
	var base := _fine_target.global_position
	var dmin := INF
	var dmax := -INF
	for x: float in [-0.8, 0.8]:
		for y: float in [0.0, 2.1]:
			for z: float in [-0.8, 0.8]:
				var d := -(inv * (base + Vector3(x, y, z))).z
				dmin = minf(dmin, d)
				dmax = maxf(dmax, d)
	_material.set_shader_parameter("player_depth_range", Vector2(dmin, dmax))


# --- API de debug -----------------------------------------------------------

func toggle_enabled() -> void:
	ascii_enabled = not ascii_enabled
	visible = ascii_enabled
	settings_changed.emit()


## Contours géométriques et traits orientés (texture) ensemble.
func toggle_edges() -> void:
	edges_enabled = not edges_enabled
	_material.set_shader_parameter("enable_edges", edges_enabled)
	_material.set_shader_parameter("enable_strokes", edges_enabled)
	settings_changed.emit()


func toggle_shape_matching() -> void:
	shape_matching_enabled = not shape_matching_enabled
	_material.set_shader_parameter("use_shape_matching", shape_matching_enabled)
	settings_changed.emit()


## Personnage en cellules fines on/off (F5).
func toggle_fine() -> void:
	fine_enabled = not fine_enabled
	_apply_fine()
	settings_changed.emit()


## Vue de debug du shader : 0 = rendu ASCII, 1 = luminance après tonemapping.
func set_debug_view(mode: int) -> void:
	_material.set_shader_parameter("debug_view", mode)


## step = +1 ou -1 : passe à la taille de cellule suivante / précédente.
func step_cell_size(step: int) -> void:
	var index := CELL_SIZES.find(cell_size)
	if index == -1:
		index = CELL_SIZES.find(5)
	index = clampi(index + step, 0, CELL_SIZES.size() - 1)
	if CELL_SIZES[index] == cell_size:
		return
	cell_size = CELL_SIZES[index]
	_rebuild_atlas()
	settings_changed.emit()


func get_font_name() -> String:
	return _font.get_font_name() if _font else "?"


# --- Interne ----------------------------------------------------------------

func _validate_glyph_set() -> void:
	if glyph_set.length() > MAX_GLYPHS:
		push_warning("glyph_set : %d glyphes, tronqué à %d" % [glyph_set.length(), MAX_GLYPHS])
		glyph_set = glyph_set.substr(0, MAX_GLYPHS)
	if not glyph_set.begins_with(" "):
		glyph_set = " " + glyph_set.replace(" ", "")
	for required in ["|", "/", "-", "\\"]:
		if glyph_set.find(required) == -1:
			glyph_set += required


## Régénère et analyse l'atlas pour la taille de cellule courante, puis met à jour le shader.
func _rebuild_atlas() -> void:
	_build_id += 1
	var my_id := _build_id
	var size := cell_size

	var image := await _atlas_generator.render(glyph_set, size, _font_for_cell(size), _font_size_for_cell(size))
	if my_id != _build_id:
		return # une génération plus récente a été lancée entre-temps
	if image == null:
		return

	var analysis := GlyphAtlas.analyze(image, glyph_set.length(), size)
	# Les glyphes directionnels sont réservés aux contours et traits orientés.
	var directional := PackedInt32Array([glyph_set.find("|"), glyph_set.find("/"), glyph_set.find("-"), glyph_set.find("\\")])
	var ramp := GlyphAtlas.build_ramp(analysis, mini(ramp_levels, MAX_RAMP), directional)

	# Descripteurs : 3 vec4 par glyphe -> [r0 r1 r2 r3] [r4 r5 r6 r7] [r8 densité 0 0]
	var shapes := PackedColorArray()
	var means: PackedFloat32Array = analysis["means"]
	for g in glyph_set.length():
		var r: PackedFloat32Array = analysis["shapes"][g]
		shapes.append(Color(r[0], r[1], r[2], r[3]))
		shapes.append(Color(r[4], r[5], r[6], r[7]))
		shapes.append(Color(r[8], means[g], 0.0, 0.0))

	if "--print-glyphs" in OS.get_cmdline_user_args():
		# Debug : mesures de chaque glyphe, triées par densité.
		var order := range(glyph_set.length())
		order.sort_custom(func(x: int, y: int) -> bool: return means[x] < means[y])
		for g: int in order:
			print("  '%s'  densité %.3f  dispersion %.3f  asymétrie %.3f" % [
				glyph_set[g], means[g], analysis["spreads"][g], analysis["asymmetry"][g]])

	ramp_text = ""
	for g in ramp:
		ramp_text += glyph_set[g]
	print("Atlas %d px : %d glyphes, rampe (%d niveaux) : \"%s\"" % [size, glyph_set.length(), ramp.size(), ramp_text])

	# On met à jour taille de cellule, atlas et descripteurs ensemble.
	_material.set_shader_parameter("glyph_atlas", ImageTexture.create_from_image(image))
	_material.set_shader_parameter("glyph_count", glyph_set.length())
	_material.set_shader_parameter("glyph_shape", shapes)
	_material.set_shader_parameter("ramp", ramp)
	_material.set_shader_parameter("ramp_count", ramp.size())
	_material.set_shader_parameter("cell_size", size)

	# Atlas des cellules fines (mêmes descripteurs de forme et même rampe :
	# ils ne dépendent pas de la taille).
	_fine_ready = false
	if _mask_viewport and fine_cell_size < size:
		var fine_image := await _atlas_generator.render(glyph_set, fine_cell_size, _font_for_cell(fine_cell_size), _font_size_for_cell(fine_cell_size))
		if my_id != _build_id:
			return
		if fine_image:
			_material.set_shader_parameter("fine_glyph_atlas", ImageTexture.create_from_image(fine_image))
			_material.set_shader_parameter("fine_cell_size", fine_cell_size)
			_fine_ready = true
	_apply_fine()
	settings_changed.emit()


## Crée la caméra jumelle et son viewport : seul le calque du personnage y est
## rendu, sur fond transparent. Le shader lit l'alpha comme masque.
func _setup_fine_pass() -> void:
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "PlayerMask"
	_mask_viewport.transparent_bg = true
	_mask_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_mask_viewport.positional_shadow_atlas_size = 0
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mask_camera = Camera3D.new()
	_mask_camera.cull_mask = character_layers
	# Environnement propre : fond vide (transparent), ni brouillard ni SSAO.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	_mask_camera.environment = env
	_mask_viewport.add_child(_mask_camera)
	add_child(_mask_viewport)
	_mask_camera.current = true
	_material.set_shader_parameter("player_mask", _mask_viewport.get_texture())


## Active la passe fine dans le shader seulement si tout est prêt.
func _apply_fine() -> void:
	var on := fine_enabled and _fine_ready
	_material.set_shader_parameter("fine_enabled", on)
	if _mask_viewport:
		_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


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
