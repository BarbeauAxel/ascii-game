extends CanvasLayer
## Écran titre et menu pause.
##
## - Titre : affiché au lancement, le jeu est en pause derrière (l'herbe
##   ondule, les cierges vacillent, l'ambiance sonore joue : les shaders et
##   le son ne dépendent pas de la pause). Entrée, Espace ou clic : la partie
##   commence. Il n'est montré qu'une fois par session : « Recommencer »
##   relance directement la partie.
## - Pause : Échap. Reprendre / Recommencer / Quitter, au clavier (flèches +
##   Entrée) ou à la souris. Échap referme le menu.
##
## Construit en code ; police pixel du projet, nette au-dessus de l'ASCII.

## Nom du jeu (provisoire, à changer librement).
@export var game_title := "OSSUAIRE"
@export var subtitle := "Une nuit dans la chapelle en ruine"

const FONT := preload("res://fonts/PressStart2P-Regular.ttf")
const GOLD := Color(0.95, 0.84, 0.6)
const PALE := Color(0.82, 0.8, 0.74)

## Vrai une fois le titre passé (survit au rechargement de la scène).
static var title_seen := false

enum Mode { TITLE, PLAYING, PAUSED }
var mode := Mode.PLAYING

var _dim: ColorRect
var _title_box: VBoxContainer
var _press: Label
var _pause_box: VBoxContainer
var _resume: Button
var _blink := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	var args := OS.get_cmdline_user_args()
	# Les arguments de test (captures, déplacements simulés) sautent le titre.
	var skip := title_seen or "--no-title" in args
	for arg in args:
		if arg.begins_with("--hold="):
			skip = true
	if skip:
		_set_mode(Mode.PLAYING)
	else:
		_set_mode(Mode.TITLE)


func _process(delta: float) -> void:
	if mode == Mode.TITLE:
		_blink += delta
		_press.modulate.a = 0.45 + 0.55 * absf(sin(_blink * 2.2))


func _unhandled_input(event: InputEvent) -> void:
	match mode:
		Mode.TITLE:
			var key := event as InputEventKey
			var mouse := event as InputEventMouseButton
			var start := (key and key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]) \
				or (mouse and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT)
			if start:
				title_seen = true
				_set_mode(Mode.PLAYING)
				get_viewport().set_input_as_handled()
			elif key and key.pressed and key.keycode == KEY_ESCAPE:
				get_tree().quit()
		Mode.PLAYING:
			if event.is_action_pressed("ui_cancel"):
				_set_mode(Mode.PAUSED)
				get_viewport().set_input_as_handled()
		Mode.PAUSED:
			if event.is_action_pressed("ui_cancel"):
				_set_mode(Mode.PLAYING)
				get_viewport().set_input_as_handled()


func _set_mode(m: Mode) -> void:
	mode = m
	get_tree().paused = m != Mode.PLAYING
	_dim.visible = m != Mode.PLAYING
	_title_box.visible = m == Mode.TITLE
	_pause_box.visible = m == Mode.PAUSED
	# Pendant le titre, le HUD de jeu (nom, vie, objectif) est masqué.
	var hud := get_parent().get_node_or_null("HUD") as CanvasLayer
	if hud:
		hud.visible = m != Mode.TITLE
	if m == Mode.PAUSED:
		_resume.grab_focus()
	if m == Mode.PLAYING:
		# Une micro-pause d'impact en cours ne doit pas rester figée.
		Engine.time_scale = 1.0


# --- Construction -------------------------------------------------------------------------

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.02, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	# Écran titre
	_title_box = _centered_box()
	_title_box.add_child(_label(game_title, 48, GOLD, 8))
	_title_box.add_child(_label(subtitle, 8, PALE))
	_title_box.add_child(_spacer(40))
	_press = _label("Entrée : commencer", 16, Color(1, 1, 1))
	_title_box.add_child(_press)
	_title_box.add_child(_spacer(36))
	_title_box.add_child(_label(
		"ZQSD / WASD : se déplacer     Maj : courir     Espace : sauter\n" +
		"Clic gauche / J : attaquer     Clic droit / K : parer\n" +
		"Molette : zoom     F3 : pluie     Échap : pause",
		8, PALE))
	_title_box.add_child(_spacer(16))
	_title_box.add_child(_label("Objectif : vaincre les 5 squelettes de la chapelle", 8, GOLD))

	# Menu pause
	_pause_box = _centered_box()
	_pause_box.add_child(_label("Pause", 32, GOLD, 6))
	_pause_box.add_child(_spacer(24))
	_resume = _button("Reprendre", func() -> void: _set_mode(Mode.PLAYING))
	_pause_box.add_child(_resume)
	_pause_box.add_child(_button("Recommencer", func() -> void:
		Engine.time_scale = 1.0
		get_tree().paused = false
		get_tree().reload_current_scene()))
	_pause_box.add_child(_button("Quitter", func() -> void: get_tree().quit()))


func _centered_box() -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	# La boîte pilote la visibilité de son conteneur centré.
	box.visibility_changed.connect(func() -> void: center.visible = box.visible)
	return box


func _label(text: String, size: int, color: Color, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_constant_override("line_spacing", 6)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", PALE)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", 4)
	b.pressed.connect(action)
	return b


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
