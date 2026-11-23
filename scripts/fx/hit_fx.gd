extends RefCounted
## Effets de combat ponctuels : éclats (os, étincelles) et poussière.
##
## CPUParticles3D « one shot » créées à la volée puis libérées. Les
## particules sont sur le calque des personnages (cellules fines) : de près,
## elles deviennent de petits glyphes nets autour de l'impact.

const FINE_LAYER := 3


## Gerbe d'éclats projetés depuis `pos`. `from` : n'importe quel nœud de la
## scène (l'effet est rattaché à la racine de la scène, pas à lui : il survit
## à sa disparition).
static func burst(from: Node, pos: Vector3, color: Color, amount := 14, speed := 3.2, size := 0.05, lifetime := 0.55, gravity := 9.8) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.roughness = 0.9
	mesh.material = mat
	p.mesh = mesh
	p.layers = 1 | (1 << (FINE_LAYER - 1))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tree := from.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)


## Poussière qui s'élève lentement (ossements purifiés).
static func dust(from: Node, pos: Vector3, color: Color) -> void:
	burst(from, pos, color, 40, 0.9, 0.06, 1.6, -0.6)
