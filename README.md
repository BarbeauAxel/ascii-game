# ASCII 3D Prototype (Godot 4.3+)

Une vraie scène 3D (Forward+) convertie à l'écran en glyphes ASCII colorés par
un shader de post-traitement haute densité (cellules de 5 px, correspondance
de forme, traits orientés). Un soldat en armure (heaume, plastron, cape,
bouclier rond, épée longue), animé de façon procédurale, explore de nuit les
ruines d'une chapelle gothique au milieu d'une prairie, avec arbres morts et
cimetière. Tout le décor est construit en code, sans asset importé.

## Lancer

1. Ouvrir Godot **4.3 ou plus récent**, *Importer* → choisir `project.godot`.
2. F5 (scène principale : `scenes/main.tscn`).

> Le quad ASCII est caché dans l'éditeur (`visible = false`) pour ne pas masquer
> la vue 3D : il s'active au lancement, une fois l'atlas de glyphes généré.

## Contrôles

| Touche                     | Action                                  |
|----------------------------|-----------------------------------------|
| ZQSD / WASD / flèches      | Se déplacer (Z = vers le haut de l'écran) |
| Maj (maintenue)            | Courir                                  |
| Espace                     | Sauter                                  |
| Clic gauche / J            | Attaquer (coup d'épée)                  |
| Clic droit / K (maintenu)  | Parer (bouclier)                        |
| Molette                    | Zoom par paliers                        |
| F1                         | Effet ASCII on/off (comparer au rendu brut) |
| F2                         | Contours et traits orientés on/off      |
| F3                         | Pluie on/off                            |
| F5                         | Personnages en cellules fines on/off    |
| F4                         | Compteur de FPS                         |
| F6                         | Afficher/masquer le HUD de debug (masqué par défaut) |
| F7                         | Correspondance de forme on/off (sinon rampe de densité seule) |
| F11                        | Plein écran                             |
| `+` / `-` (ou pavé num.)   | Taille de cellule : 4, 5, 6, 7, 8, 10 px |
| R                          | Recommencer la partie                   |
| Curseur en bas à gauche    | Volume général (0 % par défaut, mémorisé) |
| Échap                      | Pause (Reprendre / Recommencer / Quitter) |

Les déplacements utilisent les touches *physiques* : ZQSD sur AZERTY et WASD sur
QWERTY correspondent aux mêmes touches.

### Arguments de debug

À placer après `--`, par exemple `godot --path . -- --fps --zoom=3`. Pratiques
avec `--write-movie` pour capturer des comparaisons.

| Argument               | Effet |
|------------------------|-------|
| `--no-ascii`           | démarre sans l'effet (rendu 3D brut) |
| `--no-edges`           | démarre sans contours ni traits orientés |
| `--no-shape`           | démarre sans correspondance de forme (rampe seule) |
| `--no-snap`            | désactive le calage de la caméra sur la grille de cellules |
| `--fps`                | affiche le compteur de FPS dès le départ |
| `--zoom=<n>`           | palier de zoom initial (index dans `zoom_levels`) |
| `--debug-view=1`       | affiche la luminance après tonemapping (pour régler la courbe) |
| `--save-atlas`         | enregistre l'atlas de glyphes en PNG dans `user://` |
| `--print-glyphs`       | affiche dans la console la densité / dispersion / asymétrie mesurées de chaque glyphe |
| `--hold=<action>`      | maintient une action (ex : `--hold=move_forward`), pour tester les déplacements sans clavier |
| `--rain`               | démarre sous la pluie |
| `--no-fine`           | démarre sans les cellules fines des personnages |
| `--no-enemies`        | démarre sans squelettes |
| `--no-title`          | saute l'écran titre (aussi sauté avec `--hold=`) |

Mesurer les performances : `godot --path . --resolution 1920x1080 --disable-vsync --print-fps`.

## Caméra isométrique (`scripts/camera_follow.gd`)

- **Projection orthographique** à angle fixe : `yaw_degrees = 45` (vue
  diagonale) et `pitch_degrees = 50` (plongée). Seul le point visé suit le
  joueur (lissage `follow_smoothing`).
- **Calage sur la grille de cellules** (`snap_to_cells`) : la position de la
  caméra, dans le plan de l'écran, est arrondie à un multiple exact de la
  taille d'une cellule. Le décor glisse donc d'une case entière à la fois et
  garde les mêmes glyphes au lieu de scintiller. Ça ne fonctionne qu'en
  orthographique, où un déplacement de caméra décale l'image d'un nombre fixe
  de pixels.
- **Zoom à la molette par paliers** (`zoom_levels` : hauteur visible en mètres,
  7 à 24 m). La transition est lissée. Une fois le palier atteint, la taille est
  exacte et la grille redevient stable.
- **Déplacements relatifs à la caméra** (`player.gd`) : les axes de la caméra
  sont projetés au sol, donc Z va vers le haut de l'écran.
- **Murs est et sud abaissés** (1 m), côté caméra, pour qu'ils ne masquent
  jamais le joueur.

Pour une isométrique « vraie » (style Dofus), mettez `pitch_degrees` à environ
35. Pour une vue plus plongeante, montez-le vers 60–70.

## Structure

```
project.godot          config (Forward+, 1280x720, MSAA off)
export_presets.cfg     presets Windows / Linux
scenes/main.tscn       niveau, lumières, environnement, caméra + quad ASCII, HUD
scenes/player.tscn     joueur (CharacterBody3D + nœud Visual/Soldier)
scripts/main.gd        touches de debug, HUD, compteur de FPS
scripts/player.gd      déplacement (marche / course), gravité, saut, actions d'entrée
scripts/soldier.gd     soldat : construction en code + animation procédurale
scripts/world/ruins.gd chapelle en ruine, piliers, autel, éboulis, cimetière, chemin
scripts/world/nature.gd    sol, herbe (MultiMesh), arbres morts, buissons
scripts/world/stone_material.gd  matériau de pierre partagé (grain triplanaire)
scripts/world/flicker_light.gd   lumière de flamme vacillante
shaders/grass.gdshader brins d'herbe : dégradé, vent
shaders/water.gdshader mare : vagues, paillettes de lune, ronds de pluie
scripts/world/rain.gd  pluie (F3) : gouttes, éclaboussures, brouillard
scripts/enemies/skeleton.gd  squelette : construction, animation, comportement
scripts/enemies/enemy_spawner.gd  placement des squelettes
scripts/fx/hit_fx.gd   éclats, étincelles, poussière (particules ponctuelles)
scripts/audio/sfx.gd   sons synthétisés en code (autoload « Sfx »)
scripts/ui/menus.gd    écran titre et menu pause
scripts/camera_follow.gd   caméra isométrique orthographique, calage, zoom
scripts/ascii_post_process.gd  pilote du quad : police, atlas, analyse, réglages
scripts/glyph_atlas.gd rendu et analyse de l'atlas de glyphes
shaders/ascii.gdshader le shader de post-traitement
fonts/                 police pixel Press Start 2P (OFL) + sa licence
```

## Le soldat (`scripts/soldier.gd`)

Aucun modèle importé : le soldat est construit en code au lancement (le script
est aussi exécuté dans l'éditeur, on le voit donc dans la scène).

- **Squelette de pivots** : hanches → colonne → buste → cou → tête ; épaules
  → coudes → mains ; cuisses → genoux → chevilles. Chaque pivot porte des
  pièces simples (cylindres effilés, sphères aplaties, boîtes). Proportions
  d'un adulte de 1,80 m, environ 7,5 têtes.
- **Équipement** : heaume fermé à fente de vision et cimier rouge, camail de
  mailles, gorgerin, plastron bombé à arête, épaulières à deux lames, jupe de
  mailles, ceinture à boucle, tabard rouge (pans avant / arrière), cape en deux
  segments, cubitières et genouillères, grèves, bottes, bouclier rond à umbo
  sur l'avant-bras gauche, épée longue en main droite, fourreau à la hanche.
- **Animation procédurale**, calculée à partir de la vitesse du
  `CharacterBody3D` :
  - repos : respiration du buste, regard qui balaie lentement ;
  - marche / course (Maj) : la phase du cycle avance avec la distance
    parcourue (`stride_walk`, `stride_run`), donc les pieds ne glissent pas.
    Ciseaux des jambes, genou plié pendant le passage du pied, pied à plat puis
    pointe relevée, balancier des bras opposé aux jambes, rotation du bassin et
    contre-rotation des épaules, buste penché à la course, rebond vertical ;
  - saut : jambes repliées, bras écartés ;
  - cape et pans du tabard : ressort amorti (retard, ondulation), les pans
    s'écartent avec les cuisses.
- **Éclairage propre au personnage** : une lumière de face (côté caméra) et un
  contre-jour bleuté qui n'éclairent **que** le soldat (calque de rendu 2,
  `light_cull_mask`). Sans eux, l'armure reflète surtout le ciel nocturne et
  devient une silhouette noire une fois en glyphes. Les tissus ont un liseré
  (`rim`) pour se détacher du fond.
- **Métal à moitié** (`metallic` ≈ 0,45) pour la même raison.
- Couleurs et intensités réglables dans l'inspecteur (`Player/Visual/Soldier`).
- **Cellules fines (F5)** : tous les personnages (soldat, squelettes) sont
  dessinés en cellules de 3 px, le décor en 5 px, d'où beaucoup plus de
  détail sur eux.
  - **Masque** : une caméra jumelle, dans un SubViewport qui suit exactement
    la caméra principale, ne voit que le calque « fin » (calque 3,
    `FINE_LAYER`). Son alpha sert de masque au shader ASCII. Tout nouveau
    personnage n'a qu'à placer ses maillages sur ce calque et à rejoindre le
    groupe `characters`.
  - **Occultation** : un pixel du masque n'est retenu que si la profondeur
    de la scène y tombe dans l'intervalle de profondeur d'un personnage (16
    au plus). Un mur placé devant reste en cellules normales.
  - **Atlas** : les cellules fines ont leur propre atlas, rendu à leur
    taille ; descripteurs de forme et rampe sont partagés.
  - **Coût et réglages** : environ 0,2 ms en 1080p. Réglages : `fine_cell_size`
    et `character_layers` sur `Camera3D/AsciiPostProcess`.
  - **Lumières du soldat** : elles restent sur le calque 2 et n'éclairent que
    lui.
- **Nom flottant** : un `Label` du HUD en police pixel, placé chaque image
  au-dessus de la tête (`main.gd`, `NAME_HEIGHT`). Il reste net, au-dessus de
  l'ASCII, au lieu d'être converti en glyphes illisibles. Le texte se change
  dans `HUD/PlayerName`.

## Écran titre et pause (`scripts/ui/menus.gd`)

- **Titre** : au lancement, « OSSUAIRE » (nom provisoire, `game_title`),
  les commandes et l'objectif s'affichent devant le décor assombri. Le jeu est
  en pause derrière, mais l'herbe ondule, les cierges vacillent et l'ambiance
  sonore joue : shaders et son ne dépendent pas de la pause. Entrée, Espace
  ou clic pour commencer. Le titre n'est montré qu'une fois par session :
  « Recommencer » et R relancent directement la partie.
- **Pause** : Échap ouvre Reprendre / Recommencer / Quitter, au clavier
  (flèches + Entrée) ou à la souris. Échap referme le menu.
- **HUD de debug** (états F1…F11, police, rampe) : masqué par défaut, F6
  l'affiche.

## Objectif : vaincre les squelettes, puis le Gardien

Il faut d'abord vaincre les 5 squelettes ; le compteur en haut de l'écran
suit la progression. Un squelette vaincu s'effondre en tas d'os pour de bon :
ses yeux s'éteignent et son âme s'échappe en particules bleues.

Quand les 5 sont vaincus, la terre gronde (son `rumble`, secousse) et **le
Gardien de l'ossuaire** se relève lentement devant l'autel. C'est le même
squelette que les autres, réglé autrement (`spawn_boss()` dans
`enemy_spawner.gd`) :

- **Apparence** : 1,6 fois plus grand, heaume à cornes, couronne rouillée,
  cape en lambeaux, grande hache. Ses yeux éclairent ce qui l'entoure de
  rouge. Ses sons sont plus graves.
- **Résistance** : 120 PV, soit une dizaine de coups d'épée, avec une barre de vie en
  haut de l'écran. Il ne chancelle qu'un coup sur trois (`poise`).
- **Attaques** : coup vertical lourd (28 dégâts, armé 0,85 s) et large
  balayage en arc (20 dégâts, plus de portée, difficile à esquiver de
  côté), en alternance. La parade de face réduit les deux.

Sa défaite déclenche la victoire : les cierges de l'autel s'embrasent, une
colonne de lumière dorée s'élève, le message « La chapelle est purifiée »
apparaît avec un accord de victoire. **R** relance la partie (à tout moment).

## Son (`scripts/audio/sfx.gd`)

Aucun fichier audio : tous les sons sont synthétisés en code au lancement
(environ 0,3 s), échantillon par échantillon, à partir de bruit filtré, de
sinusoïdes et d'enveloppes. Ils sont stockés en AudioStreamWAV 16 bits mono à
22 050 Hz. Le module est un autoload, `Sfx.play("nom", position)`.

| Son | Quand | Recette |
|-----|-------|---------|
| `swing` | coup d'épée | bruit dont la bande descend (« whoosh ») |
| `hit_bone` | épée qui touche | claquement filtré + choc à 170 Hz + cliquetis |
| `block` | parade réussie | 4 partiels métalliques inharmoniques qui résonnent |
| `hurt` | coup encaissé | choc grave qui retombe + souffle |
| `step` | chaque pas du soldat | froissement étouffé, plus fort en courant |
| `rattle` | squelette qui repère, poursuit, arme son coup | salve de clics secs |
| `collapse` | squelette vaincu | cascade de clics + deux chocs sourds |
| `soul` | âme qui s'échappe | voix aérienne qui monte, légèrement vibrée |
| `rumble` | éveil du Gardien | grondement grave modulé + cliquetis |
| `victory` | Gardien vaincu | cloche puis accord majeur |
| ambiance | en boucle | vent par rafales + grillons |
| pluie | en boucle, suit F3 | bruissement + impacts de gouttes |

Les sons ponctuels sont positionnés en 3D. L'« oreille » (AudioListener3D)
est placée sur le joueur et orientée comme la caméra : un squelette à droite
de l'écran s'entend à droite. Les pas suivent le cycle de marche
(`footstep` dans `soldier.gd` : un pied touche le sol à chaque demi-cycle). En
mode `--headless`, rien n'est synthétisé.

**Volume** : un curseur en bas à gauche règle le bus principal, à 0 % par
défaut. La courbe est au carré, car l'oreille est logarithmique : 50 % donne
environ −12 dB et 0 coupe le son. La valeur est mémorisée dans
`user://settings.cfg`. Un clic sur le curseur ne déclenche pas de coup
d'épée, et il ne prend jamais le focus clavier, donc les flèches ne le
modifient pas.

## Combat et squelettes

- **Soldat** (`player.gd`) : 100 PV.
  - **Attaque** (clic gauche ou J) : chaque clic donne un coup tiré au
    hasard parmi la taille, le revers et le vertical, jamais deux fois le
    même de suite. Un clic pendant un coup enchaîne le suivant dès sa fin. En
    courant, c'est un estoc. Chaque coup a sa propre animation et sa zone :

    | Coup | Geste | Portée | Arc | Dégâts |
    |------|-------|--------|-----|--------|
    | Taille | horizontale, de droite à gauche | 2,0 m | très large (côtés compris) | 10 |
    | Revers | diagonal, remonte de gauche à droite | 1,9 m | large | 10 |
    | Vertical | armé au-dessus de l'épaule, frappe vers le bas | 1,9 m | étroit | 18 (+ secousse) |
    | Estoc | en courant (Maj) : fente en avant, épée pointée | 2,5 m | très étroit | 16 |

    Les animations engagent tout le corps. Elles sont décrites par des poses
    clés dans `soldier.gd` (`MOVES`) : bras de l'épée (épaule, coude,
    poignet), bras du bouclier en contrepoids, buste (penché, torsion), bassin
    (rotation, descente) et jambes (appuis fléchis, pas en avant pour le coup
    vertical, fente pour l'estoc). Chaque coup passe par une anticipation
    (pose armée), l'impact, puis un accompagnement. Le bassin et les jambes
    partent juste avant le bras, et la tête compense la rotation pour garder
    les yeux sur la cible. Pendant un coup, le soldat avance à peine, ce qui
    l'engage et évite que ses pieds glissent. Les effets (portée, arc,
    dégâts, élan) sont dans `player.gd` (`HITS`). L'impact tombe sur l'image
    clé de chaque animation.
  - **Parade** (clic droit ou K, maintenu) : le bouclier passe devant le buste.
    Un coup reçu de face n'inflige que 15 % des dégâts, et l'on avance au
    ralenti sans se retourner.
  - **Coup reçu** : éclat rouge et recul. À 0 PV, le soldat bascule sur le
    dos, puis réapparaît au point de départ au bout de 3 s.
  - **Barre de vie** sous le nom, dans le HUD.
  - **Retours d'impact** (`scripts/fx/hit_fx.gd`) : éclats d'os quand on
    touche, étincelles quand on pare, micro-pause du jeu de 50 à 70 ms et
    secousse de caméra. La secousse se fait par cellules entières, donc le
    décor saute d'une case sans scintiller (`shake_max_cells` sur la caméra).
- **Squelettes** (`scripts/enemies/skeleton.gd`) : construits en code comme le
  soldat (crâne, mâchoire, cage thoracique en anneaux, vertèbres, os longs,
  haillons, épée rouillée), animés de façon procédurale avec une démarche
  raide et saccadée. 30 PV, soit 3 coups légers (ou 2 avec le coup vertical).
  - **Comportement** : errance autour de leur poste, poursuite dès que le
    joueur est à 9 m (la mâchoire claque), attaque armée au-dessus de la
    tête (0,55 s pour parer ou reculer), chancellement et léger recul quand
    ils sont touchés.
  - **Défaite** : effondrés en tas d'os pour de bon, les yeux s'éteignent et
    l'âme s'échappe en particules bleues.
  - **Lisibilité** : os exagérés (2 à 3 fois l'épaisseur réelle) et légère
    lueur pâle. À 5 px par cellule, des os réalistes disparaîtraient.
  - **Ligne de vue** : un rayon physique vérifie qu'aucun mur, pilier ou
    rocher ne les sépare du joueur, à trois moments : pour le repérer (à
    1,3 m, il peut voir par une fenêtre), pour lancer une attaque et au moment
    de l'impact (à 1 m). Quand ils le perdent de vue, ils vont voir là où ils
    l'ont aperçu pour la dernière fois, puis rentrent à leur poste au bout de
    2,5 s.
  - **Déplacements** : contournement simple des murs, sans navmesh.
- **Postes** (`enemy_spawner.gd`) : deux dans la nef, deux au cimetière, un
  près de la mare.

## Le décor (`scripts/world/`)

Construit en code au lancement, avec une graine fixe : c'est toujours le même
décor. Les scripts tournent aussi dans l'éditeur, on voit donc la ruine dans la
scène.

- **Chapelle en ruine** (`ruins.gd`) : murs en pierres de taille posées assise
  par assise (appareil décalé, teintes et mousse variables, joint de mortier
  sombre). Sommet effrité par un bruit, fenêtres et portail en arc brisé
  (claveaux, clé, appui, meneau), piliers en tambours (intacts avec chapiteau,
  brisés, un effondré). S'y ajoutent un dallage disjoint, l'emmarchement, un
  autel à cierges, des éboulis, un cimetière (stèles, croix penchées) et un
  chemin dallé. Les murs côté caméra (est, sud) sont effondrés pour ne jamais
  cacher le joueur. Des milliers de pierres tiennent dans 2 MultiMesh,
  donc 2 appels de rendu. Collisions uniquement sous 2,6 m.
- **Nature** (`nature.gd`) : sol texturé ; herbe en touffes, environ 70 000
  brins dans une MultiMesh, plus dense par plaques, rare dans la nef et sur le
  chemin ; 9 arbres morts aux branches récursives tordues (un maillage fusionné
  par arbre) ; buissons.
- **Vent** (`grass.gdshader`) : rafales qui traversent la prairie et
  frémissement de chaque brin ; la base reste plantée.
- **Mare** (`nature.gd` + `water.gdshader`) : eau opaque sombre, au contour
  irrégulier, avec vagues et rides fines, berge de pierres et roseaux. La
  lune n'est jamais dans le champ (vue plongeante) : son reflet est simulé
  derrière la mare, un peu sous l'axe du reflet d'une eau plate. Seules les
  facettes de vague bien inclinées la renvoient, d'où des paillettes qui
  scintillent (`moon_elevation`, `glint_sharpness`). Pas de SSR : il ne
  fonctionne pas en orthographique.
- **Pluie** (F3, `rain.gd`) : environ 3 500 gouttes (GPUParticles3D), traits
  verticaux courts et discrets, inclinés par le vent, et 2 000 éclaboussures au sol. La zone suit
  le joueur. Sous l'averse, des ronds de gouttes apparaissent sur la mare et
  le brouillard s'épaissit ; fondu de 1,5 s au début et à la fin. Les gouttes
  sont opaques, car le shader ASCII ne lit que l'image opaque, et « souples » :
  elles deviennent des `|` sans contours.
- **Lumières** : lune froide (ombres), lanterne au portail et cierges de
  l'autel qui vacillent (`flicker_light.gd`).
- **Ambiance** : brouillard au ras du sol et occlusion ambiante (SSAO).
- **Matières souples** : herbe, sol et buissons ont une rugosité de 1.0. Le
  shader ASCII ne les cerne jamais (`soft_roughness`), sinon chaque touffe
  deviendrait une boucle de contour. Les matériaux durs restent sous 0.99.

## Pipeline du shader (`shaders/ascii.gdshader`)

Le post-traitement est un `MeshInstance3D` avec un `QuadMesh` 2x2, enfant de la
caméra. Le vertex shader écrit directement en clip space
(`POSITION = vec4(VERTEX.xy, 1.0, 1.0)`) : le quad couvre toujours l'écran.
`render_mode unshaded, depth_test_disabled`. Comme il lit
`hint_screen_texture`, il est rendu après la passe opaque et voit donc toute la
scène.

Pour chaque pixel, le fragment shader :

1. **Cellule** : trouve la cellule de `cell_size` px (5 par défaut) qui contient
   le pixel et la position du pixel dans cette cellule.
2. **Luminance 3x3** : lit la couleur de la scène au centre de 9 sous-régions
   de la cellule. Chaque luminance passe par la **courbe de tonemapping**
   (`exposure`, `gamma`, `contrast`), puis par un **plancher** (`dark_floor`)
   appliqué à toute la géométrie mais pas au ciel : les zones sombres gardent
   des glyphes discrets au lieu de tomber au noir.
3. **Glyphe de base** :
   - cellule uniforme (variance < `flat_threshold`) → **rampe de densité** ;
   - sinon → **correspondance de forme** : les 9 luminances (écarts amplifiés
     par `shape_contrast`) sont comparées au descripteur 3x3 de chaque glyphe,
     et le plus proche gagne. Une cellule claire en haut donne `"` `^` `'`,
     claire en bas `_` `.` `,`, etc.
4. **Contours et traits orientés** (prioritaires) :
   - **contour de silhouette** : Laplacien de la profondeur linéaire, exprimé
     en tailles de cellule (`edge_threshold_depth`). Une pente régulière (le
     sol vu en biais) donne 0, et le contour est dessiné sur l'objet du premier
     plan. Fonctionne en orthographique comme en perspective ;
   - **pli** : angle maximal entre la normale de la cellule et celles de ses 4
     voisines (`edge_threshold_normal`, en 1 − cos). Une petite surface courbe
     (casque, épaulière) ne tourne que peu d'un échantillon à l'autre et garde
     ses glyphes de forme ; un coin de mur donne un contour ;
   - **trait orienté** : tenseur de structure des gradients de luminance de la
     cellule. S'ils sont forts (`stroke_threshold`) et alignés
     (`stroke_coherence`), la cellule devient un trait. Son orientation tient
     aussi compte des normales (`stroke_normal_weight`). C'est ce qui
     transformera l'herbe et les surfaces striées en `/ | \`.
   - L'orientation est quantifiée sur 4 directions → `|` `/` `-` `\`.
5. **Masque** : lecture du glyphe dans l'atlas à la position locale du pixel.
6. **Couleur** : teinte de la cellule désaturée (`saturation`) pour une palette
   naturelle, multipliée par `global_tint` (nuit légèrement bleutée). Les zones
   très lumineuses (lanterne, cristal) gardent une saturation forte
   (`highlight_saturation`) et ressortent. Fond noir.

### Réglages du shader

Tout se règle dans l'inspecteur : `Camera3D/AsciiPostProcess` → *Material
Override*. Les uniforms sont rangés par groupes.

| Groupe | Uniform | Défaut | Rôle |
|--------|---------|--------|------|
| tonemapping | `exposure` | 3.0 (5.0 dans `main.tscn`) | compresse les hautes lumières (`1 - exp(-l × exposure)`) |
| | `gamma` | 1.6 | > 1 éclaircit les tons sombres |
| | `contrast` | 1.1 | contraste autour de 0.5 |
| | `dark_floor` | 0.08 | plancher : glyphes discrets dans le noir (pas sur le ciel) |
| glyphes | `use_shape_matching` | true | correspondance de forme (F7) |
| | `shape_contrast` | 1.8 | plus haut = plus de glyphes « de forme » |
| | `flat_threshold` | 0.008 | sous cette variance, la cellule utilise la rampe |
| contours et traits | `enable_edges` / `enable_strokes` | true | contours / traits orientés (F2) |
| | `edge_threshold_depth` | 3.0 | rupture de profondeur minimale, en cellules |
| | `edge_threshold_normal` | 0.5 | pli minimal (1 − cos de l'angle ; 0.5 = 60°) |
| | `soft_roughness` | 0.99 | rugosité au-delà de laquelle une surface n'est jamais cernée |
| | `stroke_threshold` | 0.12 | force minimale du gradient pour un trait |
| | `stroke_coherence` | 0.65 | alignement minimal des gradients (0 à 1) |
| | `stroke_normal_weight` | 0.5 | poids des normales dans l'orientation |
| couleur | `saturation` | 0.6 | saturation du décor |
| | `highlight_saturation` | 1.4 | saturation des sources de lumière |
| | `global_tint` | bleu nuit léger | teinte globale |
| | `color_boost` | 1.15 | luminosité des glyphes |
| | `edge_brightness`, `edge_min_brightness` | 1.25 / 0.22 | luminosité des contours |
| | `line_density_target`, `line_max_gain` | 0.35 / 2.0 | éclaircit les glyphes de trait, peu couvrants |
| | `use_color`, `mono_color` | true / vert | rendu monochrome |
| — | `debug_view` | 0 | 1 = luminance après tonemapping |

**Réglages conseillés** :
- tout est trop dense → baissez `gamma` ou `exposure` ;
- les ombres sont trop noires → montez `dark_floor` ;
- pas assez de formes, trop de rampe → montez `shape_contrast` ou baissez `flat_threshold` ;
- trop de traits orientés parasites → montez `stroke_threshold` ou `stroke_coherence` ;
- le personnage est couvert de contours → montez `edge_threshold_normal` ;
- les silhouettes ne sont pas cernées → baissez `edge_threshold_depth`.

## Atlas et analyse des glyphes

`scripts/glyph_atlas.gd`, appelé par `scripts/ascii_post_process.gd` au lancement
et à chaque changement de taille de cellule. Rien n'est stocké en binaire.

1. **Rendu** : Godot ne dessine pas de texte directement dans une `Image`. Le
   script crée donc un `SubViewport` 2D transparent (une case de `cell_size` px
   par glyphe) dans lequel un `Node2D` dessine chaque caractère avec
   `draw_string`. L'image est ensuite relue avec `get_texture().get_image()`.
2. **Analyse** : pour chaque glyphe, le script mesure la couverture de ses 9
   régions 3x3. Quand la cellule n'est pas divisible par 3, chaque pixel est
   réparti au prorata de sa surface. Ces 9 valeurs forment le **descripteur de
   forme**, normalisé sur l'atlas entier et envoyé au shader
   (`glyph_shape`, 3 `vec4` par glyphe).
3. **Rampe** : construite automatiquement à partir des densités mesurées,
   jusqu'à `ramp_levels` niveaux (24), strictement croissante. À densité
   proche, on préfère les glyphes uniformes et symétriques. Les glyphes
   directionnels `| / - \` sont réservés aux contours. En 5 px avec Press Start
   2P, la rampe générée est `` `.^'_:~{+TlvIno?wmHON#M`` (affichée dans le HUD
   et la console).

Le jeu de glyphes candidats est `glyph_set` (propriété exportée du quad, 52
glyphes par défaut). Le premier doit être l'espace, et `| / - \` sont
obligatoires. Moins de glyphes = shader plus rapide.

### Police

Choix de la police, dans l'ordre :
1. `custom_font` (propriété exportée du quad) ;
2. le premier `.ttf/.otf/.woff(2)` du dossier `fonts/`. Par défaut c'est
   **Press Start 2P**, une police pixel sous licence OFL (voir `fonts/README.md`) ;
3. une police monospace du système (Consolas, DejaVu Sans Mono, …) ;
4. la police par défaut de Godot.

Pour une police pixel (`font_pixel_size` > 0, 8 par défaut), la taille de police
est le plus grand multiple de la grille native qui tient dans la cellule, sans
antialiasing : les glyphes sont nets en cellules de 8 et 10 px. Sous 8 px, dont
les 5 px par défaut, une copie lissée de la police est utilisée. Les glyphes
y sont trop petits pour être lisibles un par un, mais la correspondance de
forme travaille sur leur rendu réel.

Pour voir l'atlas généré, lancez avec `-- --save-atlas`. Il est écrit dans
`user://glyph_atlas_<taille>.png`, soit sous Windows
`%APPDATA%\Godot\app_userdata\ASCII 3D Prototype\`.

## Performances

Mesuré en 1920x1080, sans V-Sync, sur une GTX 1650 SUPER, au zoom le plus
large (toute l'herbe à l'écran, pire cas) :

| Mode | FPS | ms / image |
|------|-----|------------|
| Rendu 3D brut (F1) | ~155–210 | 4.7–6.5 |
| ASCII complet | ~153 | 6.5 |
| ASCII + pluie (F3) | ~140–155 | 6.4–7.2 |
| ASCII + 5 squelettes | ~145 | 6.9 |

Avec l'ancienne salle de test, sans décor : 640 FPS en rendu brut et 365 en
ASCII.

Le shader ASCII coûte environ 1.2 ms en 1080p, dont 0.2 ms pour la
correspondance de forme. Leviers si besoin : réduire `glyph_set`, désactiver
les traits orientés, augmenter `cell_size`.

## Exporter un exécutable

1. *Éditeur → Gérer les modèles d'export* → télécharger les modèles de votre version.
2. *Projet → Exporter* : les presets **Windows Desktop** et **Linux** sont déjà
   définis (`export_presets.cfg`, PCK intégré à l'exécutable).
3. *Exporter le projet*, ou en ligne de commande :

```sh
godot --headless --path . --export-release "Windows Desktop" build/windows/ascii3d.exe
godot --headless --path . --export-release "Linux" build/linux/ascii3d.x86_64
```

(Créez les dossiers `build/windows` et `build/linux` avant.) Le rendu Forward+
demande un GPU compatible Vulkan, ou D3D12 sous Windows.

## Crédits

- Décor, personnage et textures : générés en code (bruit procédural), aucun
  asset externe.
- Police **Press Start 2P** de CodeMan38, licence SIL Open Font License 1.1 :
  voir `fonts/README.md` et `fonts/OFL-PressStart2P.txt`.
