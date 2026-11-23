extends Node3D
## Script racine : touches de debug et petit HUD.
##
## F1 : effet ASCII on/off       F2 : contours on/off
## F4 : glyphes par surface      F5 : cellules fines sur le personnage
## Molette : zoom de la caméra (géré par camera_follow.gd)
## +/- : taille de cellule       F3 : HUD on/off      Échap : quitter

@onready var post: AsciiPostProcess = $Camera3D/AsciiPostProcess
@onready var hud: Label = $HUD/Label


func _ready() -> void:
	post.settings_changed.connect(_update_hud)
	_update_hud()

	# Arguments de debug après "--" (ex : godot --path . -- --no-ascii --no-edges)
	var args := OS.get_cmdline_user_args()
	if "--no-edges" in args:
		post.toggle_edges()
	if "--no-surface-glyphs" in args:
		post.toggle_surface_glyphs()
	if "--no-fine-player" in args:
		post.toggle_fine_player()
	if "--debug-ids" in args:
		post.set_debug_view(1)
	for arg in args:
		if arg.begins_with("--debug-view="):
			post.set_debug_view(arg.trim_prefix("--debug-view=").to_int())
		elif arg.begins_with("--hold="):
			# Simule une touche maintenue (tests automatisés), ex : --hold=move_forward
			_hold_action.call_deferred(StringName(arg.trim_prefix("--hold=")))
	if "--no-ascii" in args:
		post.toggle_enabled()


func _hold_action(action: StringName) -> void:
	if InputMap.has_action(action):
		Input.action_press(action)
	else:
		push_warning("--hold : action inconnue '%s'" % action)


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
	elif key.keycode == KEY_F4:
		post.toggle_surface_glyphs()
	elif key.keycode == KEY_F5:
		post.toggle_fine_player()
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
	var on_off := func(value: bool) -> String: return "ON" if value else "OFF"
	hud.text = "F1 ASCII : %s   F2 contours : %s   F4 glyphes/surface : %s   F5 joueur fin : %s\n+/- cellule : %d px (joueur %d px)   Molette zoom   F3 HUD   Échap quitter   Police : %s" % [
		on_off.call(post.ascii_enabled),
		on_off.call(post.edges_enabled),
		on_off.call(post.surface_glyphs_enabled),
		on_off.call(post.fine_player_enabled),
		post.cell_size,
		post.get_fine_cell_size(),
		post.get_font_name(),
	]
