# Polices

## Police incluse : Press Start 2P

- Fichier : `PressStart2P-Regular.ttf`
- Auteur : CodeMan38 (The Press Start 2P Project Authors), 2012
- Licence : SIL Open Font License 1.1, voir `OFL-PressStart2P.txt`
  (nom réservé : « Press Start 2P »)
- Source : https://github.com/google/fonts/tree/main/ofl/pressstart2p

C'est une police pixel monospace dessinée sur une grille de 8×8 : elle tombe
pile sur les cellules de 8 px du shader. Le script la rend nette
(`font_pixel_size = 8` dans `AsciiPostProcess`) : taille de police = plus grand
multiple de 8 qui tient dans la cellule, sans antialiasing. Pour les cellules
plus petites que 8 px (personnage, cellules de 6 px), une copie lissée est
utilisée, car un rendu sans antialiasing y perdrait des pixels entiers.

## Changer de police

Le premier `.ttf` / `.otf` / `.woff` / `.woff2` trouvé dans ce dossier est utilisé
automatiquement. Pour en utiliser une autre :

- **Autre police pixel** : remplacez le fichier et réglez `font_pixel_size` sur
  la taille de sa grille native (souvent 8, parfois 5, 6, 7, 10 ou 16).
- **Police vectorielle classique** (ex : JetBrains Mono, IBM Plex Mono) :
  mettez `font_pixel_size = 0`. La taille devient alors `cellule +
  font_size_padding`.
- Joignez toujours le fichier de licence de la police.

Si le dossier ne contient aucune police, le jeu utilise une police monospace du
système (Consolas, DejaVu Sans Mono, Liberation Mono…), puis en dernier recours
la police par défaut de Godot.
