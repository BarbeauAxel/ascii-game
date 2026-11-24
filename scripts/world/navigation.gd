extends NavigationRegion3D
## Carte de navigation calculée au lancement.
##
## Le décor est construit en code (ruins.gd, nature.gd) : la carte ne peut
## donc pas être précalculée dans l'éditeur. Au démarrage, on analyse les
## formes de collision des nœuds du groupe `navigation_source` (sol, murs,
## piliers, tombes, arbres, rampe de l'autel) et on en déduit les surfaces où
## un personnage peut marcher. Les squelettes y calculent leurs chemins
## (NavigationAgent3D) : ils contournent piliers et murs au lieu de s'y
## coincer.
##
## Ce nœud doit être placé après Ruins et Nature dans la scène (ils doivent
## avoir construit leurs collisions avant le calcul).

## Demi-côté de la zone analysée autour de l'origine (mètres).
@export var bake_extent := 34.0
## Rayon des personnages : la carte s'écarte d'autant des obstacles.
## (Valeurs multiples de la cellule de 0,25 m, sinon Godot les arrondit.)
@export var agent_radius := 0.5


func _ready() -> void:
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav.geometry_source_group_name = &"navigation_source"
	# Même résolution que la carte par défaut du NavigationServer (0,25 m).
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	nav.agent_radius = agent_radius
	nav.agent_height = 2.0
	nav.agent_max_climb = 0.25
	nav.agent_max_slope = 40.0
	nav.filter_baking_aabb = AABB(Vector3(-bake_extent, -1.0, -bake_extent), Vector3(bake_extent * 2.0, 8.0, bake_extent * 2.0))
	navigation_mesh = nav
	var t0 := Time.get_ticks_msec()
	bake_navigation_mesh(false)
	print("Navigation : %d polygones calculés en %d ms" % [nav.get_polygon_count(), Time.get_ticks_msec() - t0])
