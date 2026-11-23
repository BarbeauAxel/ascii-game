extends Camera3D
## Caméra 3e personne : suit la cible avec un décalage fixe (vue plongeante)
## et un lissage exponentiel indépendant du framerate.

@export var target_path: NodePath
## Décalage par rapport à la cible (au-dessus et derrière).
@export var follow_offset := Vector3(0.0, 6.0, 8.0)
## Hauteur du point visé au-dessus des pieds de la cible.
@export var look_height := 1.0
## Plus la valeur est grande, plus la caméra rattrape vite la cible.
@export var smoothing := 5.0

var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target:
		global_position = _target.global_position + follow_offset
		look_at(_target.global_position + Vector3.UP * look_height, Vector3.UP)


# En _physics_process pour rester synchronisée avec le CharacterBody3D (pas de saccades).
func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var desired := _target.global_position + follow_offset
	global_position = global_position.lerp(desired, 1.0 - exp(-smoothing * delta))
	look_at(_target.global_position + Vector3.UP * look_height, Vector3.UP)
