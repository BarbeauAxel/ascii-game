extends Node3D
## Place les squelettes à leurs postes au lancement : nef de la chapelle,
## cimetière, bord de la mare. Chacun erre autour de son poste.

const SKELETON := preload("res://scripts/enemies/skeleton.gd")

## Postes de garde (position au sol).
@export var posts: Array[Vector3] = [
	Vector3(-1.5, 0.1, -8.0),   # nef
	Vector3(1.8, 0.1, -11.5),   # nef, près de l'autel
	Vector3(10.5, 0.1, -9.0),   # cimetière
	Vector3(13.0, 0.1, -4.5),   # cimetière
	Vector3(-7.0, 0.1, 3.5),    # près de la mare
]


func _ready() -> void:
	if "--no-enemies" in OS.get_cmdline_user_args():
		return
	for i in posts.size():
		var skeleton := CharacterBody3D.new()
		skeleton.set_script(SKELETON)
		skeleton.name = "Skeleton%d" % i
		skeleton.position = posts[i]
		add_child(skeleton)
