extends Node3D
## Script racine : touches de debug et petit HUD.
##
## F1 : effet ASCII on/off   F2 : contours on/off   +/- : taille de cellule
## F3 : HUD on/off           Échap : quitter

@onready var post: AsciiPostProcess = $Camera3D/AsciiPostProcess
@onready var hud: Label = $HUD/Label


func _ready() -> void:
	post.settings_changed.connect(_update_hud)
	_update_hud()

	# Arguments de debug après "--" (ex : godot --path . -- --no-ascii --no-edges)
	var args := OS.get_cmdline_user_args()
	if "--no-edges" in args:
		post.toggle_edges()
	if "--no-ascii" in args:
		post.toggle_enabled()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	# Le caractère tapé (unicode) gère "+" / "-" quel que soit le clavier.
	var typed := char(key.unicode) if key.unicode > 0 else ""

	if key.keycode == KEY_F1:
		post.toggle_enabled()
	elif key.keycode == KEY_F2:
		post.toggle_edges()
	elif key.keycode == KEY_F3:
		hud.visible = not hud.visible
	elif key.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif typed == "+" or key.keycode in [KEY_PLUS, KEY_KP_ADD, KEY_EQUAL]:
		post.step_cell_size(1)
	elif typed == "-" or key.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		post.step_cell_size(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func _update_hud() -> void:
	hud.text = "F1 ASCII : %s   F2 contours : %s   +/- cellule : %d px   F3 HUD   Échap quitter\nPolice : %s" % [
		"ON" if post.ascii_enabled else "OFF",
		"ON" if post.edges_enabled else "OFF",
		post.cell_size,
		post.get_font_name(),
	]
