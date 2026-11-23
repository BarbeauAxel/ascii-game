// =============================================================================
// Post-traitement "ASCII 3D"
// -----------------------------------------------------------------------------
// Appliqué sur un QuadMesh 2x2 enfant de la caméra. Le vertex shader place le
// quad directement en clip space pour qu'il couvre tout l'écran, quel que soit
// le point de vue. Le fragment shader lit l'image de la scène (couleur,
// profondeur, normales), la découpe en cellules et remplace chaque cellule par
// un glyphe tiré d'un atlas généré au lancement (voir scripts/glyph_atlas.gd).
//
// Atlas : une seule ligne de cases carrées de cell_size pixels :
//   [0 .. ramp_count-1]            -> rampe de luminance  " .:-=+*#%@"
//   [ramp_count .. ramp_count+3]   -> glyphes directionnels "|", "/", "-", "\"
// =============================================================================
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

// --- Textures fournies par le moteur (Forward+ requis pour les normales) ---
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, filter_nearest, repeat_disable;

// --- Atlas de glyphes (blanc sur transparent, on n'utilise que l'alpha) ---
uniform sampler2D glyph_atlas : filter_nearest, repeat_disable;
uniform int ramp_count = 10;   // nombre de glyphes de la rampe de luminance
uniform int glyph_count = 14;  // nombre total de cases dans l'atlas

// --- Paramètres exposés ---
uniform int cell_size : hint_range(2, 32) = 8;
uniform float edge_threshold_depth : hint_range(0.0, 4.0) = 0.35;
uniform float edge_threshold_normal : hint_range(0.0, 8.0) = 1.5;
uniform float color_boost : hint_range(0.0, 4.0) = 1.6;
uniform bool use_color = true;
uniform bool enable_edges = true;

// --- Réglages fins supplémentaires ---
uniform float luminance_gain : hint_range(0.1, 8.0) = 1.5;      // éclaircit la rampe (scène sombre)
uniform float ramp_contrast : hint_range(0.25, 4.0) = 1.6;      // >1 : tons moyens -> glyphes clairsemés (n'affecte pas la couleur)
uniform float saturation_boost : hint_range(0.0, 3.0) = 1.3;    // >1 = couleurs plus saturées
uniform float edge_brightness : hint_range(0.0, 4.0) = 1.3;     // multiplicateur de luminosité des contours
uniform float edge_min_brightness : hint_range(0.0, 1.0) = 0.3; // les contours restent visibles dans le noir
uniform vec3 mono_color : source_color = vec3(0.75, 0.9, 0.75); // couleur si use_color = false
uniform float max_depth = 500.0;                                 // borne la profondeur du ciel

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

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

void fragment() {
	float cs = float(cell_size);
	vec2 texel = 1.0 / VIEWPORT_SIZE;

	// ---------------------------------------------------------------------
	// 1. Découpage en cellules
	// ---------------------------------------------------------------------
	vec2 cell = floor(FRAGCOORD.xy / cs);
	vec2 center_uv = (cell + 0.5) * cs * texel;
	vec2 local = fract(FRAGCOORD.xy / cs); // position du pixel dans sa cellule (0..1)

	// ---------------------------------------------------------------------
	// 2. Couleur moyenne de la cellule (centre + 4 échantillons en croix diagonale)
	// ---------------------------------------------------------------------
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

	// ---------------------------------------------------------------------
	// 3. Luminance -> index dans la rampe
	// ---------------------------------------------------------------------
	// La courbe de contraste ne sert qu'au choix du glyphe : la couleur garde
	// la luminosité d'origine, donc les zones moyennes restent lisibles.
	float ramp_value = pow(perceptual, ramp_contrast);
	int glyph = clamp(int(ramp_value * float(ramp_count)), 0, ramp_count - 1);
	bool is_edge = false;

	// ---------------------------------------------------------------------
	// 4. Contours : Sobel 3x3 sur la profondeur linéaire et sur les normales.
	//    Les échantillons sont espacés d'une demi-cellule : la grille 3x3
	//    couvre exactement la cellule courante.
	// ---------------------------------------------------------------------
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
			glyph = ramp_count + dir;
			is_edge = true;
		}
	}

	// ---------------------------------------------------------------------
	// 5. Lecture du glyphe dans l'atlas, à la position locale du pixel
	// ---------------------------------------------------------------------
	vec2 atlas_uv = vec2((float(glyph) + local.x) / float(glyph_count), local.y);
	float mask = texture(glyph_atlas, atlas_uv).a;

	// ---------------------------------------------------------------------
	// 6. Couleur finale = masque × couleur de la cellule (fond noir)
	// ---------------------------------------------------------------------
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
