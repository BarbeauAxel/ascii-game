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


## Fait se relever le Gardien de l'ossuaire devant l'autel (combat final).
func spawn_boss() -> CharacterBody3D:
	var boss := CharacterBody3D.new()
	boss.set_script(SKELETON)
	boss.name = "Gardien"
	boss.set("is_boss", true)
	boss.set("size_scale", 1.6)
	boss.set("max_health", 120.0)
	boss.set("walk_speed", 0.9)
	boss.set("chase_speed", 2.2)
	boss.set("sight_range", 16.0)
	boss.set("attack_range", 2.3)
	boss.set("attack_damage", 28.0)
	boss.set("attack_windup", 0.85)
	boss.set("attack_strike", 1.0)
	boss.set("attack_end", 1.75)
	boss.set("poise", 3)
	boss.set("rise_time", 2.6)
	boss.set("bone_color", Color(0.72, 0.68, 0.58))
	boss.set("eye_color", Color(1.0, 0.18, 0.05))
	boss.position = boss_post
	add_child(boss)
	return boss


## Où le gardien se relève (devant l'autel).
@export var boss_post := Vector3(0.0, 0.1, -12.2)


func _ready() -> void:
	if "--no-enemies" in OS.get_cmdline_user_args():
		return
	for i in posts.size():
		var skeleton := CharacterBody3D.new()
		skeleton.set_script(SKELETON)
		skeleton.name = "Skeleton%d" % i
		skeleton.position = posts[i]
		add_child(skeleton)
