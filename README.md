# ASCII 3D Prototype (Godot 4.3+)

Une vraie scène 3D (Forward+) convertie à l'écran en glyphes ASCII colorés par
un shader de post-traitement. Un personnage (chapeau large, épée rose) se
déplace dans une petite salle éclairée par la lune, une lanterne orange et un
cristal cyan.

## Lancer

1. Ouvrir Godot **4.3 ou plus récent**, *Importer* → choisir `project.godot`.
2. F5 (scène principale : `scenes/main.tscn`).

> Le quad ASCII est caché dans l'éditeur (`visible = false`) pour ne pas masquer
> la vue 3D : il s'active au lancement, une fois l'atlas de glyphes généré.

## Contrôles

| Touche                     | Action                                  |
|----------------------------|-----------------------------------------|
| ZQSD / WASD / flèches      | Se déplacer                             |
| Espace                     | Sauter                                  |
| F1                         | Effet ASCII on/off (comparer au rendu brut) |
| F2                         | Contours on/off                         |
| F4                         | Glyphes par surface (sol / murs) on/off |
| F5                         | Cellules fines sur le personnage on/off |
| `+` / `-` (ou pavé num.)   | Taille de cellule : 6 → 8 → 10 → 12 px (personnage : moitié) |
| F3                         | Afficher/masquer le HUD                 |
| Échap                      | Quitter                                 |

Arguments de debug (après `--`), pratiques avec `--write-movie` pour capturer
des comparaisons :

| Argument               | Effet |
|------------------------|-------|
| `--no-ascii`           | démarre sans l'effet (rendu 3D brut) |
| `--no-edges`           | démarre sans contours |
| `--no-surface-glyphs`  | démarre sans glyphes par surface |
| `--no-fine-player`     | démarre sans cellules fines sur le personnage |
| `--debug-ids`          | affiche les identifiants de surface en couleurs unies |
| `--debug-view=2`       | affiche la roughness en niveaux de gris (valeur = pixel / 255) |

Exemple : `godot --path . -- --debug-ids`

Les déplacements utilisent les touches *physiques* : ZQSD sur AZERTY et WASD sur
QWERTY correspondent aux mêmes touches.

## Structure

```
project.godot          config (Forward+, 1280x720, MSAA off)
export_presets.cfg     presets Windows / Linux
scenes/main.tscn       niveau, lumières, environnement, caméra + quad ASCII, HUD
scenes/player.tscn     personnage (CharacterBody3D + primitives)
scripts/main.gd        touches de debug, HUD
scripts/player.gd      déplacement, gravité, saut, actions d'entrée
scripts/camera_follow.gd   caméra 3e personne en vue plongeante
scripts/ascii_post_process.gd  pilote du quad : choix de police, atlas, réglages
scripts/glyph_atlas.gd génération de l'atlas de glyphes au lancement
shaders/ascii.gdshader le shader de post-traitement
fonts/                 (optionnel) déposez-y une police .ttf/.otf
```

## Pipeline du shader (`shaders/ascii.gdshader`)

Le post-traitement est un `MeshInstance3D` avec un `QuadMesh` 2x2, enfant de la
caméra. Le vertex shader écrit directement en clip space
(`POSITION = vec4(VERTEX.xy, 1.0, 1.0)`) : le quad couvre toujours l'écran.
`render_mode unshaded, depth_test_disabled` : pas d'éclairage, pas de test de
profondeur. Comme il lit `hint_screen_texture`, il est rendu après la passe
opaque et voit donc toute la scène.

Pour chaque pixel, le fragment shader :

1. **Cellules** : calcule la cellule de `cell_size` px qui contient le pixel, son
   centre en UV, et la position locale du pixel dans la cellule (0..1).
2. **Couleur et luminance** : moyenne de 5 échantillons de `hint_screen_texture`
   (centre + 4 diagonales). Luminance Rec.709, convertie en perceptuel
   (gamma 1/2.2), avec `luminance_gain` pour éclaircir une scène sombre.
3. **Rampe** : la luminance choisit un palier dans la rampe de la surface sous
   le centre de la cellule (voir *Glyphes par surface*). Par défaut :
   ` .:-=+*#%@` (10 niveaux).
4. **Contours** : grille 3x3 espacée d'une demi-cellule (elle couvre donc la
   cellule entière).
   - Sobel sur la **profondeur linéaire** (reconstruite avec
     `INV_PROJECTION_MATRIX`), divisée par la profondeur du centre pour qu'un
     même seuil marche de près comme de loin → `edge_threshold_depth`.
   - Sobel sur les **normales** (`hint_normal_roughness_texture`) → `edge_threshold_normal`.
   - Si un des deux dépasse son seuil, l'orientation du gradient est calculée
     avec un tenseur de structure (combine profondeur et normales sans
     problème de signe), puis quantifiée sur 4 directions → `|` `/` `-` `\`.
5. **Glyphe** : lecture de l'atlas (grille de cases carrées, une ligne par
   surface) à la position locale du pixel ; l'alpha sert de masque.
6. **Couleur finale** : `masque × teinte de la cellule × luminosité`. La teinte
   est normalisée puis saturée (`saturation_boost`), la luminosité est
   multipliée par `color_boost`. Les contours ont une luminosité minimale pour
   rester lisibles dans l'ombre. Les cellules vides donnent un fond noir.

### Identifiant de surface : encodé dans la roughness

Le shader lit déjà `hint_normal_roughness_texture` pour les normales. Son canal
alpha contient la **roughness** de chaque pixel. On réserve donc quelques
valeurs de roughness comme identifiants de surface :

| Surface          | Roughness | Matériaux |
|------------------|-----------|-----------|
| sol              | 0.62      | `Mat_floor` |
| murs / piliers   | 0.66      | `Mat_wall`, `Mat_pillar` |
| personnage       | 0.70      | tous les matériaux de `player.tscn` (épée comprise) |
| défaut           | autre     | caisses (0.9), lanterne, poteau, cristal (1.0)… |

- Pas de rendu supplémentaire, et l'identifiant respecte la profondeur
  (un joueur caché derrière un pilier n'est pas détecté).
- Tolérance ±0.012 (`surface_roughness_tolerance`). Mesuré sous 4.3 : la
  texture fournit la roughness du matériau à ~1/255 près, objets en mouvement
  compris. Gardez les valeurs réservées espacées d'au moins 0.03, et n'utilisez
  pas 0.60–0.72 pour d'autres matériaux.
- `rendering/anti_aliasing/screen_space_roughness_limiter/enabled` est désactivé
  dans `project.godot` : ce filtre modifie la roughness selon la courbure et
  fausserait les identifiants.
- Les valeurs sont des uniforms (`surface_roughness_floor`, `_wall`,
  `_player`) si vous voulez les changer.
- Pour ajouter un type de surface : une valeur de roughness réservée + un test
  dans `surface_at()` + une rampe dans `SURFACE_TIERS`
  (`scripts/ascii_post_process.gd`).

### Glyphes par surface

Chaque surface a sa rampe (une ligne de l'atlas), définie dans `SURFACE_TIERS` :

| Surface         | Paliers (sombre → clair) |
|-----------------|--------------------------|
| défaut, personnage | ` ` `.` `:` `-` `=` `+` `*` `#` `%` `@` |
| sol             | ` ` `~` `<>` `+` |
| murs / piliers  | ` ` `[]` `HN` `#` |

- Un palier peut contenir plusieurs variantes de même densité (`<>`, `[]`,
  `HN`). Le shader en tire une au hasard par cellule pour casser la répétition.
- Une cellule n'est vide que si elle l'aurait été avec la rampe par défaut. Le
  reste de la plage est réparti sur les paliers visibles, étalé par
  `surface_ramp_gain`, car le sol et les murs n'occupent qu'une partie de la
  plage de luminosité.
- Les contours (`|` `/` `-` `\`) restent prioritaires sur toutes les surfaces.

### Personnage en cellules fines

Pour chaque pixel, le shader regarde d'abord la petite cellule (`fine_cell_size`
= `cell_size / 2`) qui le contient. Si son centre est sur le personnage, tout le
pipeline (couleur, rampe, contours) s'exécute sur cette grille fine, avec un
second atlas généré à cette taille. Sinon, il utilise la grille normale.

En bordure de silhouette, une grande cellule peut être à moitié recouverte de
petites : son glyphe n'apparaît alors que sur la partie hors personnage.

### Uniforms

| Uniform                 | Défaut | Rôle |
|-------------------------|--------|------|
| `cell_size`             | 8      | taille d'une cellule en pixels (fixée par le script avec l'atlas) |
| `edge_threshold_depth`  | 0.35   | seuil Sobel profondeur (relatif) |
| `edge_threshold_normal` | 1.5    | seuil Sobel normales |
| `color_boost`           | 1.6    | luminosité des glyphes |
| `use_color`             | true   | couleur de la scène, sinon `mono_color` |
| `enable_edges`          | true   | contours directionnels |
| `enable_surface_glyphs` | true   | rampes spécifiques sol / murs |
| `enable_fine_player`    | true   | cellules fines sur le personnage |
| `fine_cell_size`        | 4      | taille des cellules du personnage (fixée par le script) |
| `surface_ramp_gain`     | 2.5    | étale la luminosité sur les paliers sol / murs |
| `surface_roughness_*`   | 0.62 / 0.66 / 0.70 ±0.012 | identifiants de surface |
| `debug_view`            | 0      | 1 = identifiants, 2 = roughness |
| `ramp_contrast`         | 1.6    | courbe appliquée au seul choix du glyphe : >1 = tons moyens en glyphes clairsemés |
| `luminance_gain`, `saturation_boost`, `edge_brightness`, `edge_min_brightness`, `mono_color`, `max_depth` | — | réglages fins |

Tout se règle dans l'inspecteur : `Camera3D/AsciiPostProcess` → *Material Override*.

**Réglages conseillés** : si le sol se couvre de `-` au loin, montez
`edge_threshold_depth`. Si les surfaces arrondies (capsule, piliers) se
remplissent de contours, montez `edge_threshold_normal`.

## Atlas de glyphes (`scripts/glyph_atlas.gd`)

Généré au lancement, rien n'est stocké en binaire. Godot ne dessine pas de texte
directement dans une `Image`, donc le script crée un `SubViewport` 2D
transparent (14 colonnes × 3 lignes de cases de `cell_size` px). Un `Node2D` y
dessine chaque caractère (`draw_string`, blanc, centré dans sa case). Après un
rendu, l'image est récupérée avec `get_texture().get_image()` et transformée en
`ImageTexture` passée au shader. Deux atlas sont générés, à `cell_size` et à
`cell_size / 2` pour le personnage. Ils sont régénérés quand on change `cell_size`.

Choix de la police, dans l'ordre :
1. `custom_font` (propriété exportée du quad) ;
2. le premier `.ttf/.otf/.woff(2)` du dossier `fonts/` ;
3. une police monospace du système (Consolas, DejaVu Sans Mono, …) ;
4. la police par défaut de Godot.

Pour voir l'atlas généré, activez `save_debug_png` dans `glyph_atlas.gd` : il est
écrit dans `user://glyph_atlas_<taille>.png`.

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
