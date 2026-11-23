// =============================================================================
// Post-traitement "ASCII 3D"
// -----------------------------------------------------------------------------
// Appliqué sur un QuadMesh 2x2 enfant de la caméra. Le vertex shader place le
// quad directement en clip space pour qu'il couvre tout l'écran, quel que soit
// le point de vue. Le fragment shader lit l'image de la scène (couleur,
// profondeur, normales + rugosité), la découpe en cellules et remplace chaque
// cellule par un glyphe tiré d'un atlas généré au lancement
// (voir scripts/glyph_atlas.gd et scripts/ascii_post_process.gd).
//
// Atlas : une grille de cases carrées, une ligne par type de surface :
//   ligne 0 : rampe par défaut " .:-=+*#%@" puis glyphes directionnels "|/-\"
//   ligne 1 : sol     " ~<>+"
//   ligne 2 : murs    " []HN#"
// Les tables tier_* indiquent où commence chaque palier de luminosité et
// combien de variantes il contient.
//
// Identifiant de surface : encodé dans la ROUGHNESS des matériaux (valeurs
// réservées surface_roughness_*), relue dans hint_normal_roughness_texture.
// =============================================================================
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

// --- Textures fournies par le moteur (Forward+ requis pour les normales) ---
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, filter_nearest, repeat_disable;

// --- Atlas de glyphes (blanc sur transparent, on n'utilise que l'alpha) ---
uniform sampler2D glyph_atlas : filter_nearest, repeat_disable;       // cases de cell_size
uniform sampler2D glyph_atlas_fine : filter_nearest, repeat_disable;  // cases de fine_cell_size
uniform int atlas_columns = 14;
uniform int atlas_rows = 3;
uniform int edge_column = 10;     // colonne du premier glyphe directionnel (ligne 0)
// Tables remplies par le script (MAX_SURFACES = 4, MAX_TIERS = 16) :
uniform int tier_count[4];        // nombre de paliers par ligne
uniform int tier_start[64];       // [ligne * 16 + palier] -> première colonne
uniform int tier_variants[64];    // [ligne * 16 + palier] -> nombre de variantes

// --- Paramètres exposés ---
uniform int cell_size : hint_range(2, 32) = 8;
uniform int fine_cell_size : hint_range(2, 32) = 4; // cellules du personnage
uniform float edge_threshold_depth : hint_range(0.0, 4.0) = 0.35;
uniform float edge_threshold_normal : hint_range(0.0, 8.0) = 1.5;
uniform float color_boost : hint_range(0.0, 4.0) = 1.6;
uniform bool use_color = true;
uniform bool enable_edges = true;
uniform bool enable_surface_glyphs = true; // glyphes spécifiques sol / murs
uniform bool enable_fine_player = true;    // cellules plus petites sur le personnage

// --- Réglages fins supplémentaires ---
uniform float luminance_gain : hint_range(0.1, 8.0) = 1.5;      // éclaircit la rampe (scène sombre)
uniform float ramp_contrast : hint_range(0.25, 4.0) = 1.6;      // >1 : tons moyens -> glyphes clairsemés (n'affecte pas la couleur)
uniform float surface_ramp_gain : hint_range(0.5, 6.0) = 2.5;  // étale la luminosité sur les paliers sol / murs
uniform float saturation_boost : hint_range(0.0, 3.0) = 1.3;    // >1 = couleurs plus saturées
uniform float edge_brightness : hint_range(0.0, 4.0) = 1.3;     // multiplicateur de luminosité des contours
uniform float edge_min_brightness : hint_range(0.0, 1.0) = 0.3; // les contours restent visibles dans le noir
uniform vec3 mono_color : source_color = vec3(0.75, 0.9, 0.75); // couleur si use_color = false
uniform float max_depth = 500.0;                                 // borne la profondeur du ciel

// --- Identifiants de surface (valeurs de roughness réservées) ---
// Précision du buffer : ~1/255. Garder ces valeurs espacées d'au moins 0.03
// et ne pas les utiliser pour d'autres matériaux.
uniform float surface_roughness_floor = 0.62;
uniform float surface_roughness_wall = 0.66;
uniform float surface_roughness_player = 0.70;
uniform float surface_roughness_tolerance = 0.012;

// --- Debug : 0 = rendu ASCII, 1 = identifiants de surface en couleurs unies,
//             2 = roughness en niveaux de gris ---
uniform int debug_view = 0;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const int SURFACE_DEFAULT = 0;
const int SURFACE_FLOOR = 1;
const int SURFACE_WALL = 2;
const int SURFACE_PLAYER = 3;
const int MAX_TIERS = 16;

void vertex() {
	// Écriture directe en clip space : le quad 2x2 (-1..1) couvre tout l'écran.
	// z = 1.0 correspond au plan proche en Z inversé (Godot 4.3+), donc jamais clippé.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Profondeur linéaire (distance positive à la caméra, en mètres).
float linear_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_texture, uv).r;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	view.xyz /= view.w;
	return clamp(-view.z, 0.001, max_depth);
}

// Normale en espace vue, décodée depuis [0,1].
vec3 view_normal(vec2 uv) {
	vec3 n = texture(normal_roughness_texture, uv).xyz * 2.0 - 1.0;
	return n / max(length(n), 1e-4); // normalisation sans risque de NaN
}

// Roughness sous un point de l'écran. Pour un shader spatial, Godot fournit
// dans hint_normal_roughness_texture la roughness déjà décodée (mesuré en
// 4.3 : valeur du matériau à ~1/255 près, objets dynamiques compris). Le
// codage 7 bits / « 1 - r » ne concerne que le buffer interne (effets compositor).
float roughness_at(vec2 uv) {
	return texture(normal_roughness_texture, uv).a;
}

// Type de surface sous un point de l'écran, d'après la roughness.
int surface_at(vec2 uv) {
	float r = roughness_at(uv);
	if (abs(r - surface_roughness_player) < surface_roughness_tolerance) {
		return SURFACE_PLAYER;
	}
	if (abs(r - surface_roughness_wall) < surface_roughness_tolerance) {
		return SURFACE_WALL;
	}
	if (abs(r - surface_roughness_floor) < surface_roughness_tolerance) {
		return SURFACE_FLOOR;
	}
	return SURFACE_DEFAULT;
}

// Inverse exact de l'encodage sRGB de sortie : la valeur lue dans la capture
// d'écran (0..255) vaut alors x * 255 (vue de debug 2).
float srgb_to_linear(float x) {
	return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4);
}

// Pseudo-aléatoire stable par cellule (choix des variantes de glyphes).
float cell_hash(vec2 c) {
	return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 texel = 1.0 / VIEWPORT_SIZE;

	if (debug_view == 1) {
		// Vue de debug : chaque type de surface en couleur unie, par pixel.
		int s = surface_at(SCREEN_UV);
		vec3 debug_color = vec3(0.08);
		if (s == SURFACE_FLOOR) {
			debug_color = vec3(0.1, 0.3, 1.0);
		} else if (s == SURFACE_WALL) {
			debug_color = vec3(0.6, 0.1, 1.0);
		} else if (s == SURFACE_PLAYER) {
			debug_color = vec3(1.0, 0.8, 0.0);
		}
		ALBEDO = debug_color;
	} else if (debug_view == 2) {
		// Vue de debug : roughness en niveaux de gris (valeur = pixel / 255).
		ALBEDO = vec3(srgb_to_linear(clamp(roughness_at(SCREEN_UV), 0.0, 1.0)));
	} else {
		// -----------------------------------------------------------------
		// 1. Découpage en cellules. Si la petite cellule qui contient ce pixel
		//    tombe sur le personnage, on utilise la grille fine pour ce pixel.
		// -----------------------------------------------------------------
		float cs = float(cell_size);
		bool fine = false;
		if (enable_fine_player) {
			float fs = float(fine_cell_size);
			vec2 fine_center_uv = (floor(FRAGCOORD.xy / fs) + 0.5) * fs * texel;
			if (surface_at(fine_center_uv) == SURFACE_PLAYER) {
				fine = true;
				cs = fs;
			}
		}

		vec2 cell = floor(FRAGCOORD.xy / cs);
		vec2 center_uv = (cell + 0.5) * cs * texel;
		vec2 local = fract(FRAGCOORD.xy / cs); // position du pixel dans sa cellule (0..1)

		// -----------------------------------------------------------------
		// 2. Couleur moyenne de la cellule (centre + 4 échantillons en diagonale)
		// -----------------------------------------------------------------
		vec2 q = vec2(cs * 0.25) * texel;
		vec3 col = texture(screen_texture, center_uv).rgb;
		col += texture(screen_texture, center_uv + vec2(-q.x, -q.y)).rgb;
		col += texture(screen_texture, center_uv + vec2( q.x, -q.y)).rgb;
		col += texture(screen_texture, center_uv + vec2(-q.x,  q.y)).rgb;
		col += texture(screen_texture, center_uv + vec2( q.x,  q.y)).rgb;
		col /= 5.0;

		// La texture d'écran est en linéaire : on repasse en perceptuel (~gamma 2.2)
		// pour que la rampe se répartisse comme l'œil perçoit la luminosité.
		float lum = dot(col, LUMA);
		float perceptual = pow(clamp(lum * luminance_gain, 0.0, 1.0), 1.0 / 2.2);

		// -----------------------------------------------------------------
		// 3. Luminance -> palier de la rampe de la surface -> colonne de l'atlas
		// -----------------------------------------------------------------
		// La courbe de contraste ne sert qu'au choix du glyphe : la couleur garde
		// la luminosité d'origine, donc les zones moyennes restent lisibles.
		float ramp_value = pow(perceptual, ramp_contrast);

		int surface = surface_at(center_uv);
		int row = 0; // défaut et personnage : rampe classique
		if (enable_surface_glyphs && (surface == SURFACE_FLOOR || surface == SURFACE_WALL)) {
			row = surface;
		}
		// Palier 0 (vide) uniquement sous le même seuil que la rampe par défaut,
		// puis le reste de la plage est réparti sur les paliers visibles. Sinon
		// une rampe courte (4 paliers) laisserait vides les zones peu éclairées.
		int tiers = max(tier_count[row], 1);
		float blank = 1.0 / float(max(tier_count[0], 1));
		int tier = 0;
		if (ramp_value >= blank) {
			float t = (ramp_value - blank) / (1.0 - blank);
			if (row != 0) {
				// Les surfaces n'occupent qu'une partie de la plage de luminosité :
				// on l'étale pour profiter de tous leurs paliers.
				t = clamp(t * surface_ramp_gain, 0.0, 1.0);
			}
			tier = clamp(1 + int(t * float(tiers - 1)), 1, max(tiers - 1, 1));
		}
		int tier_index = row * MAX_TIERS + tier;
		int variants = max(tier_variants[tier_index], 1);
		int variant = min(int(cell_hash(cell) * float(variants)), variants - 1);
		int column = tier_start[tier_index] + variant;
		bool is_edge = false;

		// -----------------------------------------------------------------
		// 4. Contours : Sobel 3x3 sur la profondeur linéaire et sur les normales.
		//    Les échantillons sont espacés d'une demi-cellule : la grille 3x3
		//    couvre exactement la cellule courante.
		// -----------------------------------------------------------------
		if (enable_edges) {
			vec2 h = vec2(cs * 0.5) * texel;
			float d[9];
			vec3 n[9];
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					int k = (y + 1) * 3 + (x + 1);
					vec2 uv = center_uv + vec2(float(x), float(y)) * h;
					d[k] = linear_depth(uv, INV_PROJECTION_MATRIX);
					n[k] = view_normal(uv);
				}
			}
			// Indices :  0 1 2
			//            3 4 5
			//            6 7 8
			float gxd = (d[2] + 2.0 * d[5] + d[8]) - (d[0] + 2.0 * d[3] + d[6]);
			float gyd = (d[6] + 2.0 * d[7] + d[8]) - (d[0] + 2.0 * d[1] + d[2]);
			// Gradient relatif à la profondeur du centre : un même seuil marche
			// de près comme de loin.
			gxd /= d[4];
			gyd /= d[4];
			float depth_mag = length(vec2(gxd, gyd));

			vec3 gxn = (n[2] + 2.0 * n[5] + n[8]) - (n[0] + 2.0 * n[3] + n[6]);
			vec3 gyn = (n[6] + 2.0 * n[7] + n[8]) - (n[0] + 2.0 * n[1] + n[2]);
			float normal_mag = sqrt(dot(gxn, gxn) + dot(gyn, gyn));

			bool depth_edge = depth_mag > edge_threshold_depth;
			bool normal_edge = normal_mag > edge_threshold_normal;

			if (depth_edge || normal_edge) {
				// Orientation du gradient via un tenseur de structure (Jxx, Jyy, Jxy) :
				// combine profondeur et normales sans souci de signe.
				vec3 J = vec3(0.0);
				if (depth_edge) {
					vec2 g = vec2(gxd, gyd) / depth_mag;
					J += vec3(g.x * g.x, g.y * g.y, g.x * g.y);
				}
				if (normal_edge) {
					J += vec3(dot(gxn, gxn), dot(gyn, gyn), dot(gxn, gyn)) / (normal_mag * normal_mag);
				}
				// Angle du gradient dans [0, PI). Le trait du contour est perpendiculaire.
				float theta = 0.5 * atan(2.0 * J.z, J.x - J.y);
				if (theta < 0.0) {
					theta += PI;
				}
				// Quantification sur 4 directions (axe Y écran vers le bas) :
				// 0 : gradient horizontal -> trait vertical   "|"
				// 1 : gradient bas-droite -> trait montant     "/"
				// 2 : gradient vertical   -> trait horizontal  "-"
				// 3 : gradient bas-gauche -> trait descendant  "\"
				int dir = int(floor(theta / (PI * 0.25) + 0.5)) % 4;
				row = 0;
				column = edge_column + dir;
				is_edge = true;
			}
		}

		// -----------------------------------------------------------------
		// 5. Lecture du glyphe dans l'atlas, à la position locale du pixel
		// -----------------------------------------------------------------
		vec2 atlas_uv = vec2(
			(float(column) + local.x) / float(atlas_columns),
			(float(row) + local.y) / float(atlas_rows));
		float mask = fine ? texture(glyph_atlas_fine, atlas_uv).a : texture(glyph_atlas, atlas_uv).a;

		// -----------------------------------------------------------------
		// 6. Couleur finale = masque × couleur de la cellule (fond noir)
		// -----------------------------------------------------------------
		// Luminosité perçue du glyphe (le glyphe porte déjà l'info de densité,
		// donc on peut éclaircir franchement la couleur).
		float brightness = clamp(perceptual * color_boost, 0.0, 1.0);
		if (is_edge) {
			brightness = clamp(max(brightness * edge_brightness, edge_min_brightness), 0.0, 1.0);
		}

		vec3 tint;
		if (use_color) {
			// Teinte normalisée (composante max = 1) puis saturation renforcée.
			float m = max(col.r, max(col.g, col.b));
			vec3 hue = m > 1e-5 ? col / m : vec3(1.0);
			hue = max(mix(vec3(dot(hue, LUMA)), hue, saturation_boost), vec3(0.0));
			tint = hue;
		} else {
			tint = mono_color;
		}

		// Retour en linéaire pour la sortie (le moteur applique ensuite l'encodage sRGB).
		ALBEDO = tint * pow(brightness, 2.2) * mask;
	}
}
