extends Node
## Sons du jeu, synthétisés en code au lancement : aucun fichier audio.
##
## Chargé en autoload (« Sfx », voir project.godot). Chaque son est calculé
## échantillon par échantillon (bruit filtré, sinusoïdes, enveloppes), puis
## stocké dans un AudioStreamWAV 16 bits mono à 22 050 Hz.
##
##   Combat     : swing (épée qui fend l'air), hit_bone (os qui craquent),
##                block (bouclier qui sonne), hurt (coup encaissé)
##   Squelettes : rattle (claquements d'os), collapse (effondrement),
##                soul (souffle de l'âme qui s'échappe)
##   Divers     : step (pas dans l'herbe), victory (accord final),
##                rumble (grondement, éveil du gardien)
##   Ambiance   : vent + grillons (boucle), pluie (boucle, suit F3)
##
## Les sons ponctuels sont positionnés en 3D. L'« oreille »
## (AudioListener3D) est placée sur le joueur, orientée comme la caméra :
## un son à droite de l'écran s'entend à droite.

const RATE := 22050

var _streams := {}
var _rng := RandomNumberGenerator.new()
var _listener: AudioListener3D
var _ambience: AudioStreamPlayer
var _rain: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return # pas de son à générer en mode sans affichage (tests, vérifications)
	_rng.seed = 1234
	var t0 := Time.get_ticks_msec()
	_streams["swing"] = _wav(_swing())
	_streams["hit_bone"] = _wav(_hit_bone())
	_streams["block"] = _wav(_block())
	_streams["hurt"] = _wav(_hurt())
	_streams["step"] = _wav(_step())
	_streams["rattle"] = _wav(_rattle())
	_streams["collapse"] = _wav(_collapse())
	_streams["soul"] = _wav(_soul())
	_streams["victory"] = _wav(_victory())
	_streams["rumble"] = _wav(_rumble())
	_streams["ignite"] = _wav(_ignite())
	_streams["splash"] = _wav(_splash())
	_ambience = _loop_player(_night_loop(), -16.0)
	_rain = _loop_player(_rain_loop(), -80.0)
	print("Sons synthétisés en %d ms" % (Time.get_ticks_msec() - t0))

	_listener = AudioListener3D.new()
	add_child(_listener)
	_listener.make_current()


func _process(_delta: float) -> void:
	if _listener == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if player and cam:
		_listener.global_transform = Transform3D(cam.global_basis, player.global_position + Vector3.UP * 1.5)


## Joue un son à une position du monde. `pitch_var` : variation aléatoire de
## hauteur (deux coups ne sonnent jamais exactement pareil).
func play(sound: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.08, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + _rng.randf_range(-pitch_var, pitch_var))
	p.unit_size = 6.0
	p.max_distance = 45.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## Joue un son non positionné (musique, interface).
func play_global(sound: String, volume_db := 0.0) -> void:
	if not _streams.has(sound):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Volume de la pluie, de 0 (sèche) à 1 (averse).
func set_rain(amount: float) -> void:
	if _rain:
		_rain.volume_db = linear_to_db(maxf(amount, 0.0001)) - 9.0


# --- Recettes ---------------------------------------------------------------------------

## Épée qui fend l'air : bruit dont la bande de fréquences descend.
func _swing() -> PackedFloat32Array:
	var d := _buf(0.28)
	var lp := 0.0
	var lp2 := 0.0
	for i in d.size():
		var t := float(i) / d.size()
		lp += lerpf(0.45, 0.06, t) * (_noise() - lp)
		lp2 += 0.03 * (lp - lp2)
		d[i] = (lp - lp2) * pow(sin(PI * t), 2.0) * 1.5
	return d


## Os qui craquent : claquement sec, choc sourd, petits cliquetis.
func _hit_bone() -> PackedFloat32Array:
	var d := _buf(0.22)
	var hp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var n := _noise()
		hp += 0.5 * (n - hp)
		d[i] = (n - hp) * exp(-t * 55.0) * 0.65 + sin(TAU * 170.0 * t) * exp(-t * 28.0) * 0.45
	_add_clicks(d, 6, 0.0, 0.08, 0.35)
	return d


## Bouclier : partiels métalliques inharmoniques qui résonnent.
func _block() -> PackedFloat32Array:
	var d := _buf(0.8)
	var partials := [[620.0, 1.0, 6.0], [1480.0, 0.6, 9.0], [2350.0, 0.4, 12.0], [3310.0, 0.25, 17.0]]
	for i in d.size():
		var t := float(i) / RATE
		var v := _noise() * exp(-t * 90.0) * 0.5
		for p in partials:
			v += sin(TAU * p[0] * t) * p[1] * exp(-t * p[2])
		d[i] = v * 0.32
	return d


## Coup encaissé : choc grave qui retombe + souffle.
func _hurt() -> PackedFloat32Array:
	var d := _buf(0.32)
	var lp := 0.0
	var phase := 0.0
	for i in d.size():
		var t := float(i) / RATE
		phase += TAU * (115.0 - 70.0 * t) / RATE
		lp += 0.12 * (_noise() - lp)
		d[i] = sin(phase) * exp(-t * 11.0) * 0.8 + lp * exp(-t * 18.0) * 0.9
	return d


## Pas dans l'herbe : froissement court et étouffé.
func _step() -> PackedFloat32Array:
	var d := _buf(0.1)
	var lp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		lp += 0.18 * (_noise() - lp)
		d[i] = lp * exp(-t * 40.0) * 1.4 + sin(TAU * 75.0 * t) * exp(-t * 50.0) * 0.3
	return d


## Claquements d'os : salve de petits clics secs.
func _rattle() -> PackedFloat32Array:
	var d := _buf(0.5)
	_add_clicks(d, 11, 0.0, 0.42, 0.9)
	return d


## Effondrement : cascade de clics qui s'espace, deux chocs sourds.
func _collapse() -> PackedFloat32Array:
	var d := _buf(1.0)
	_add_clicks(d, 26, 0.0, 0.75, 0.45)
	for hit: float in [0.12, 0.48]:
		var start := int(hit * RATE)
		for i in range(start, d.size()):
			var t := float(i - start) / RATE
			d[i] += sin(TAU * 80.0 * t) * exp(-t * 14.0) * 0.6
	return d


## Âme : souffle aérien qui monte, voix fantomatique légèrement vibrée.
func _soul() -> PackedFloat32Array:
	var d := _buf(2.0)
	var lp := 0.0
	var phase := 0.0
	var phase2 := 0.0
	for i in d.size():
		var t := float(i) / RATE
		var env := smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.9, 2.0, t))
		var f := 380.0 * pow(2.0, t * 0.6) * (1.0 + 0.01 * sin(TAU * 5.5 * t))
		phase += TAU * f / RATE
		phase2 += TAU * f * 1.5 / RATE
		lp += 0.08 * (_noise() - lp)
		d[i] = (sin(phase) * 0.35 + sin(phase2) * 0.12 + lp * 0.5) * env * 0.7
	return d


## Torche qui s'embrase : souffle qui s'ouvre (bruit dont le filtre monte),
## puis crépitements.
func _ignite() -> PackedFloat32Array:
	var d := _buf(0.9)
	var lp := 0.0
	for i in d.size():
		var t := float(i) / RATE
		lp += lerpf(0.04, 0.3, smoothstep(0.0, 0.25, t)) * (_noise() - lp)
		d[i] = lp * smoothstep(0.0, 0.08, t) * exp(-maxf(t - 0.15, 0.0) * 5.0) * 1.3
	_add_clicks(d, 14, 0.1, 0.85, 0.35)
	return d


## Pas dans l'eau : clapotis (bruit filtré qui retombe) et gouttelettes.
func _splash() -> PackedFloat32Array:
	var d := _buf(0.35)
	var lp := 0.0
	var lp2 := 0.0
	for i in d.size():
		var t := float(i) / RATE
		lp += 0.25 * (_noise() - lp)
		lp2 += 0.05 * (lp - lp2)
		d[i] = (lp - lp2) * exp(-t * 14.0) * 1.6 + sin(TAU * (260.0 - 300.0 * t) * t) * exp(-t * 30.0) * 0.3
	_add_clicks(d, 8, 0.03, 0.3, 0.25)
	return d


## Grondement : la terre tremble (éveil du gardien).
func _rumble() -> PackedFloat32Array:
	var d := _buf(3.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in d.size():
		var t := float(i) / RATE
		lp += 0.02 * (_noise() - lp)
		lp2 += 0.05 * (lp - lp2)
		var env := smoothstep(0.0, 0.6, t) * (1.0 - smoothstep(2.0, 3.0, t))
		d[i] = (lp2 * 9.0 + sin(TAU * 42.0 * t) * 0.3) * env * (0.8 + 0.2 * sin(TAU * 7.0 * t))
	_add_clicks(d, 30, 0.3, 2.6, 0.25)
	return d


## Victoire : cloche puis accord majeur qui s'épanouit.
func _victory() -> PackedFloat32Array:
	var d := _buf(4.5)
	var notes := [220.0, 277.18, 329.63, 440.0, 554.37]
	for i in d.size():
		var t := float(i) / RATE
		var env := smoothstep(0.0, 1.2, t) * exp(-maxf(t - 1.5, 0.0) * 0.9)
		var v := 0.0
		for n: float in notes:
			v += sin(TAU * n * t) + 0.5 * sin(TAU * n * 1.003 * t)
		var bell := sin(TAU * 880.0 * t) * exp(-t * 2.5) + 0.4 * sin(TAU * 2349.0 * t) * exp(-t * 4.0)
		d[i] = v * env * 0.07 + bell * 0.3
	return d


## Nuit : vent par rafales (bruit très filtré, modulé lentement) et grillons.
func _night_loop() -> PackedFloat32Array:
	var seconds := 8.0
	var d := _buf(seconds + 0.5)
	var lp := 0.0
	var lp2 := 0.0
	for i in d.size():
		var t := float(i) / RATE
		lp += 0.03 * (_noise() - lp)
		lp2 += 0.01 * (lp - lp2)
		var gust := 0.55 + 0.3 * sin(TAU * t / seconds) + 0.15 * sin(TAU * 3.0 * t / seconds + 1.0)
		d[i] = (lp - lp2 * 0.5) * gust * 2.5
	# Grillons : trilles de 3 impulsions vers 4,5 kHz, à intervalles irréguliers.
	var t_chirp := 0.3
	while t_chirp < seconds:
		var f := _rng.randf_range(4200.0, 4800.0)
		for k in 3:
			var start := int((t_chirp + k * 0.045) * RATE)
			for j in int(0.03 * RATE):
				if start + j < d.size():
					var tt := float(j) / RATE
					d[start + j] += sin(TAU * f * tt) * sin(PI * tt / 0.03) * 0.05
		t_chirp += _rng.randf_range(0.5, 1.6)
	return _make_loop(d, int(seconds * RATE))


## Pluie : bruissement continu + impacts de gouttes.
func _rain_loop() -> PackedFloat32Array:
	var seconds := 4.0
	var d := _buf(seconds + 0.3)
	var lp := 0.0
	var lp2 := 0.0
	for i in d.size():
		lp += 0.35 * (_noise() - lp)
		lp2 += 0.04 * (lp - lp2)
		d[i] = (lp - lp2) * 0.8
	_add_clicks(d, 140, 0.0, seconds + 0.2, 0.12)
	return _make_loop(d, int(seconds * RATE))


# --- Outils -----------------------------------------------------------------------------

func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


func _buf(seconds: float) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(int(seconds * RATE))
	return d


## Ajoute `count` clics (petites salves aiguës très brèves) entre t0 et t1.
func _add_clicks(d: PackedFloat32Array, count: int, t0: float, t1: float, amp: float) -> void:
	for c in count:
		var start := int(_rng.randf_range(t0, t1) * RATE)
		var f := _rng.randf_range(1600.0, 3400.0)
		var a := amp * _rng.randf_range(0.5, 1.0)
		for j in int(0.008 * RATE):
			if start + j >= d.size():
				break
			var t := float(j) / RATE
			d[start + j] += (sin(TAU * f * t) * 0.7 + _noise() * 0.3) * exp(-t * 600.0) * a


## Rend une boucle sans clic : la fin (au-delà de `length`) est fondue dans le début.
func _make_loop(d: PackedFloat32Array, length: int) -> PackedFloat32Array:
	var fade := d.size() - length
	for i in fade:
		var w := float(i) / fade
		d[i] = d[i] * w + d[length + i] * (1.0 - w)
	d.resize(length)
	return d


func _wav(d: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(d.size() * 2)
	for i in d.size():
		bytes.encode_s16(i * 2, int(clampf(d[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = d.size()
	return w


func _loop_player(d: PackedFloat32Array, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _wav(d, true)
	p.volume_db = volume_db
	add_child(p)
	p.play()
	return p
