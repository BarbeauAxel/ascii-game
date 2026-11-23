# ASCII 3D Prototype (Godot 4.3+)

Une vraie scène 3D (Forward+) convertie à l'écran en glyphes ASCII colorés par
un shader de post-traitement haute densité (cellules de 5 px, correspondance
de forme, traits orientés). Un personnage (chapeau large, épée rose) se
déplace dans une petite salle éclairée par la lune, une lanterne orange et un
cristal cyan, vue d'en haut en isométrique façon MMO RPG.

## Lancer

1. Ouvrir Godot **4.3 ou plus récent**, *Importer* → choisir `project.godot`.
2. F5 (scène principale : `scenes/main.tscn`).

> Le quad ASCII est caché dans l'éditeur (`visible = false`) pour ne pas masquer
> la vue 3D : il s'active au lancement, une fois l'atlas de glyphes généré.

## Contrôles

| Touche                     | Action                                  |
|----------------------------|-----------------------------------------|
| ZQSD / WASD / flèches      | Se déplacer (Z = vers le haut de l'écran) |
| Espace                     | Sauter                                  |
| Molette                    | Zoom par paliers                        |
| F1                         | Effet ASCII on/off (comparer au rendu brut) |
| F2                         | Contours et traits orientés on/off      |
| F4                         | Compteur de FPS                         |
| F6                         | Afficher/masquer le HUD                 |
| F7                         | Correspondance de forme on/off (sinon rampe de densité seule) |
| F11                        | Plein écran                             |
| `+` / `-` (ou pavé num.)   | Taille de cellule : 4, 5, 6, 7, 8, 10 px |
| Échap                      | Quitter                                 |

F3 (pluie) et F5 (personnage en cellules fines) arriveront aux étapes 2 et 3.

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
scenes/player.tscn     personnage (CharacterBody3D + primitives)
scripts/main.gd        touches de debug, HUD, compteur de FPS
scripts/player.gd      déplacement, gravité, saut, actions d'entrée
scripts/camera_follow.gd   caméra isométrique orthographique, calage, zoom
scripts/ascii_post_process.gd  pilote du quad : police, atlas, analyse, réglages
scripts/glyph_atlas.gd rendu et analyse de l'atlas de glyphes
shaders/ascii.gdshader le shader de post-traitement
fonts/                 police pixel Press Start 2P (OFL) + sa licence
```

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
   - **contour géométrique** : Sobel sur la profondeur linéaire et sur les
     normales (`edge_threshold_depth`, `edge_threshold_normal`) ;
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
| tonemapping | `exposure` | 3.0 | compresse les hautes lumières (`1 - exp(-l × exposure)`) |
| | `gamma` | 1.6 | > 1 éclaircit les tons sombres |
| | `contrast` | 1.1 | contraste autour de 0.5 |
| | `dark_floor` | 0.08 | plancher : glyphes discrets dans le noir (pas sur le ciel) |
| glyphes | `use_shape_matching` | true | correspondance de forme (F7) |
| | `shape_contrast` | 1.8 | plus haut = plus de glyphes « de forme » |
| | `flat_threshold` | 0.003 | sous cette variance, la cellule utilise la rampe |
| contours et traits | `enable_edges` / `enable_strokes` | true | contours / traits orientés (F2) |
| | `edge_threshold_depth` | 0.35 | seuil Sobel profondeur (relatif) |
| | `edge_threshold_normal` | 1.5 | seuil Sobel normales |
| | `stroke_threshold` | 0.12 | force minimale du gradient pour un trait |
| | `stroke_coherence` | 0.65 | alignement minimal des gradients (0 à 1) |
| | `stroke_normal_weight` | 0.5 | poids des normales dans l'orientation |
| couleur | `saturation` | 0.6 | saturation du décor |
| | `highlight_saturation` | 1.4 | saturation des sources de lumière |
| | `global_tint` | bleu nuit léger | teinte globale |
| | `color_boost` | 1.15 | luminosité des glyphes |
| | `edge_brightness`, `edge_min_brightness` | 1.25 / 0.22 | luminosité des contours |
| | `use_color`, `mono_color` | true / vert | rendu monochrome |
| — | `debug_view` | 0 | 1 = luminance après tonemapping |

**Réglages conseillés** :
- tout est trop dense → baissez `gamma` ou `exposure` ;
- les ombres sont trop noires → montez `dark_floor` ;
- pas assez de formes, trop de rampe → montez `shape_contrast` ou baissez `flat_threshold` ;
- trop de traits orientés parasites → montez `stroke_threshold` ou `stroke_coherence` ;
- le sol se couvre de contours au loin → montez `edge_threshold_depth`.

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

Mesuré en 1920x1080, sans V-Sync, sur une GTX 1650 SUPER (scène actuelle) :

| Mode | FPS | ms / image |
|------|-----|------------|
| Rendu 3D brut (F1) | ~640 | 1.56 |
| ASCII complet | ~365 | 2.73 |
| ASCII, rampe seule (F7) | ~392 | 2.54 |

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

- Police **Press Start 2P** de CodeMan38, licence SIL Open Font License 1.1 :
  voir `fonts/README.md` et `fonts/OFL-PressStart2P.txt`.
