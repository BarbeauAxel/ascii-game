extends Node3D
## Script racine : touches de debug, HUD et compteur de FPS.
##
## F1 : effet ASCII on/off           F2 : contours et traits orientés on/off
## F3 : pluie on/off                 F4 : compteur de FPS              F6 : HUD on/off
## F7 : correspondance de forme on/off (sinon rampe de densité seule)
## F11 : plein écran                 +/- : taille de cellule
## Molette : zoom (géré par camera_follow.gd)       Échap : quitter
## F5 : personnage en cellules fines on/off
##
## Le nom du personnage est un Label du HUD (police pixel nette, au-dessus de
## l'ASCII), replacé chaque frame au-dessus de sa tête.

@onready var post: AsciiPostProcess = $Camera3D/AsciiPostProcess
@onready var hud: Label = $HUD/Label
@onready var fps_label: Label = $HUD/FpsLabel
@onready var rain: Node = $Rain  # rain.gd
@onready var player: Node3D = $Player
@onready var player_name: Label = $HUD/PlayerName
@onready var health_back: ColorRect = $HUD/HealthBack
@onready var health_fill: ColorRect = $HUD/HealthBack/HealthFill
@onready var objective: Label = $HUD/Objective
@onready var message: Label = $HUD/Message

# Objectif : vaincre tous les squelettes.
var _skeleton_total := 0
var _defeated := 0

## Hauteur du nom au-dessus des pieds du personnage (mètres).
const NAME_HEIGHT := 2.25

var _fps_timer := 0.0


func _ready() -> void:
	post.settings_changed.connect(_update_hud)
	player.health_changed.connect(_on_health_changed)
	# Les squelettes sont créés par Enemies (enfant prêt avant ce nœud).
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_signal("died"):
			enemy.died.connect(_on_skeleton_died)
			_skeleton_total += 1
	objective.visible = _skeleton_total > 0
	_update_objective()
	_update_hud()

	# Arguments de debug après "--" (ex : godot --path . -- --no-ascii --no-edges)
	var args := OS.get_cmdline_user_args()
	if "--no-edges" in args:
		post.toggle_edges()
	if "--no-shape" in args:
		post.toggle_shape_matching()
	if "--fps" in args:
		fps_label.visible = true
	if "--no-fine" in args:
		post.toggle_fine()
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
	_place_name()
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


## Place le nom au-dessus de la tête, aligné sur des pixels entiers.
func _place_name() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var head := player.global_position + Vector3.UP * NAME_HEIGHT
	player_name.visible = not cam.is_position_behind(head)
	var screen := cam.unproject_position(head)
	player_name.position = (screen - player_name.size * 0.5).round()
	# Barre de vie juste sous le nom.
	health_back.visible = player_name.visible
	health_back.position = (screen + Vector2(-health_back.size.x * 0.5, player_name.size.y * 0.5 + 2.0)).round()


func _on_skeleton_died() -> void:
	_defeated += 1
	_update_objective()
	if _defeated >= _skeleton_total:
		_victory()


func _update_objective() -> void:
	objective.text = "Squelettes vaincus : %d / %d" % [_defeated, _skeleton_total]


## Tous les squelettes vaincus : les cierges s'embrasent, une colonne de
## lumière s'élève de l'autel, message de victoire.
func _victory() -> void:
	for light in $Ruins.find_children("*", "OmniLight3D", true, false):
		if "base_energy" in light:
			light.base_energy *= 2.5
		light.light_color = Color(1.0, 0.85, 0.6)
		light.omni_range *= 1.6
	var column := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.5
	cyl.height = 14.0
	column.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.55)
	mat.roughness = 1.0
	column.material_override = mat
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.position = Vector3(0.0, 0.54 + 7.0, -15.0)
	add_child(column)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.5)
	glow.light_energy = 4.0
	glow.omni_range = 12.0
	glow.position = Vector3(0.0, 2.5, -14.0)
	add_child(glow)
	var tween := create_tween()
	tween.tween_property(message, "modulate:a", 1.0, 1.5)


func _on_health_changed(health: float, max_health: float) -> void:
	health_fill.size.x = (health_back.size.x - 2.0) * clampf(health / max_health, 0.0, 1.0)


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
		rain.toggle()
		_update_hud()
	elif key.keycode == KEY_F5:
		post.toggle_fine()
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
	hud.text = "F1 ASCII : %s   F2 contours/traits : %s   F3 pluie : %s   F5 joueur fin : %s   F7 forme : %s   F4 FPS   F6 HUD   F11 plein écran\n+/- cellule : %d px   Molette zoom   Maj courir   Clic G / J attaquer   Clic D / K parer   Échap quitter   Police : %s   Rampe : %s" % [
		on_off.call(post.ascii_enabled),
		on_off.call(post.edges_enabled),
		on_off.call(rain.active),
		on_off.call(post.fine_enabled),
		on_off.call(post.shape_matching_enabled),
		post.cell_size,
		post.get_font_name(),
		post.ramp_text,
	]
