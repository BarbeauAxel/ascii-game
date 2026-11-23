extends Node3D
## Script racine : touches de debug, HUD et compteur de FPS.
##
## F1 : effet ASCII on/off           F2 : contours et traits orientés on/off
## F4 : compteur de FPS              F6 : HUD on/off
## F7 : correspondance de forme on/off (sinon rampe de densité seule)
## F11 : plein écran                 +/- : taille de cellule
## Molette : zoom (géré par camera_follow.gd)       Échap : quitter
## (F3 : pluie et F5 : joueur fin arrivent aux étapes 2 et 3.)

@onready var post: AsciiPostProcess = $Camera3D/AsciiPostProcess
@onready var hud: Label = $HUD/Label
@onready var fps_label: Label = $HUD/FpsLabel

var _fps_timer := 0.0


func _ready() -> void:
	post.settings_changed.connect(_update_hud)
	_update_hud()

	# Arguments de debug après "--" (ex : godot --path . -- --no-ascii --no-edges)
	var args := OS.get_cmdline_user_args()
	if "--no-edges" in args:
		post.toggle_edges()
	if "--no-shape" in args:
		post.toggle_shape_matching()
	if "--fps" in args:
		fps_label.visible = true
	if "--no-snap" in args:
		$Camera3D.snap_to_cells = false
	for arg in args:
		if arg.begins_with("--debug-view="):
			post.set_debug_view(arg.trim_prefix("--debug-view=").to_int())
		elif arg.begins_with("--zoom="):
			# Palier de zoom initial (index dans zoom_levels de la caméra).
			$Camera3D.zoom_index = arg.trim_prefix("--zoom=").to_int()
		elif arg.begins_with("--hold="):
			# Simule une touche maintenue (tests automatisés), ex : --hold=move_forward
			_hold_action.call_deferred(StringName(arg.trim_prefix("--hold=")))
	if "--no-ascii" in args:
		post.toggle_enabled()


func _process(delta: float) -> void:
	# Mise à jour du compteur 4 fois par seconde (lisible, et sans coût notable).
	if not fps_label.visible:
		return
	_fps_timer -= delta
	if _fps_timer > 0.0:
		return
	_fps_timer = 0.25
	var fps := Engine.get_frames_per_second()
	var size := get_viewport().get_visible_rect().size
	fps_label.text = "%d FPS  (%.1f ms)\n%dx%d" % [fps, 1000.0 / maxf(fps, 1.0), size.x, size.y]


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
	elif key.keycode == KEY_F4:
		fps_label.visible = not fps_label.visible
		_fps_timer = 0.0
	elif key.keycode == KEY_F6:
		hud.visible = not hud.visible
	elif key.keycode == KEY_F7:
		post.toggle_shape_matching()
	elif key.keycode == KEY_F11:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
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
	hud.text = "F1 ASCII : %s   F2 contours/traits : %s   F7 forme : %s   F4 FPS   F6 HUD   F11 plein écran\n+/- cellule : %d px   Molette zoom   Échap quitter   Police : %s   Rampe : %s" % [
		on_off.call(post.ascii_enabled),
		on_off.call(post.edges_enabled),
		on_off.call(post.shape_matching_enabled),
		post.cell_size,
		post.get_font_name(),
		post.ramp_text,
	]
