// =============================================================================
// Post-traitement "ASCII 3D" haute densité
// -----------------------------------------------------------------------------
// Appliqué sur un QuadMesh 2x2 enfant de la caméra. Le vertex shader place le
// quad directement en clip space pour qu'il couvre tout l'écran. Le fragment
// shader lit l'image de la scène (couleur, profondeur, normales), la découpe en
// cellules et remplace chaque cellule par un glyphe de l'atlas généré au
// lancement (scripts/glyph_atlas.gd + scripts/ascii_post_process.gd).
//
// Choix du glyphe, par ordre de priorité :
//   1. contour géométrique (Sobel profondeur / normales)   -> | / - \
//   2. trait orienté (texture striée : gradient de luminance cohérent,
//      orientation guidée aussi par les normales)            -> | / - \
//   3. correspondance de forme : la luminance 3x3 de la cellule est comparée
//      au descripteur 3x3 de chaque glyphe, le plus proche gagne
//      (moitié haute claire -> " ^ ', moitié basse -> _ . , …)
//   4. cellule uniforme : rampe de densité triée automatiquement.
//
// Atlas : une ligne de cases carrées de cell_size px, glyphe i en colonne i.
// =============================================================================
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

// --- Textures fournies par le moteur (Forward+ requis pour les normales) ---
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, filter_nearest, repeat_disable;

// --- Atlas et descripteurs (remplis par le script) ---
uniform sampler2D glyph_atlas : filter_nearest, repeat_disable;
uniform int glyph_count = 1;
// 3 vec4 par glyphe : [r0 r1 r2 r3] [r4 r5 r6 r7] [r8 densité - -]
// (couverture des 9 régions 3x3, normalisée sur l'atlas entier).
uniform vec4 glyph_shape[384];
uniform int ramp_count = 1;
uniform int ramp[32];             // index de glyphes, du plus clair au plus dense
uniform ivec4 dir_glyphs;         // index des glyphes | / - \

uniform int cell_size : hint_range(2, 32) = 5;

group_uniforms tonemapping;
// Courbe appliquée à la luminance linéaire de la scène AVANT le choix du glyphe :
// t = 1 - exp(-l * exposure)  puis  t^(1/gamma)  puis contraste autour de 0.5.
uniform float exposure : hint_range(0.1, 16.0) = 3.0;
uniform float gamma : hint_range(0.2, 4.0) = 1.6;          // > 1 : éclaircit les tons sombres
uniform float contrast : hint_range(0.2, 3.0) = 1.1;
// Plancher appliqué à toute la géométrie (pas au ciel) : les zones sombres
// gardent des glyphes discrets au lieu de tomber au noir total.
uniform float dark_floor : hint_range(0.0, 0.5) = 0.08;

group_uniforms glyphes;
uniform bool use_shape_matching = true;
// Amplifie les écarts de luminance dans la cellule avant comparaison :
// plus haut = plus de glyphes « de forme », moins de glyphes de rampe.
uniform float shape_contrast : hint_range(0.5, 4.0) = 1.8;
// Variance de luminance en dessous de laquelle la cellule est « uniforme » (rampe).
uniform float flat_threshold : hint_range(0.0, 0.05) = 0.008;

group_uniforms contours_et_traits;
uniform bool enable_edges = true;
// Rupture de profondeur (silhouette) : Laplacien de la profondeur, exprimé en
// « cellules » (taille d'une cellule projetée dans le monde). Une pente
// régulière (sol vu en biais) donne 0 ; un objet devant un autre, beaucoup plus.
uniform float edge_threshold_depth : hint_range(0.0, 20.0) = 3.0;
// Arête vive (pli) : angle maximal entre la normale de la cellule et celles
// de ses 4 voisines (à une demi-cellule), en 1 - cos(angle). Une surface
// courbe lisse, même petite, ne tourne que peu d'un échantillon à l'autre ;
// un pli (coin de mur, pièce posée sur une autre) donne un saut net.
uniform float edge_threshold_normal : hint_range(0.0, 2.0) = 0.5;
// Rugosité à partir de laquelle une surface est « souple » (herbe, sol,
// buissons) : pas de contours, seulement glyphes de forme et traits.
// Les matériaux durs (pierre, métal, bois, tissu) restent en dessous.
uniform float soft_roughness : hint_range(0.0, 1.0) = 0.99;
uniform bool enable_strokes = true;
// Force minimale du gradient de luminance (unités tonemappées) pour un trait.
uniform float stroke_threshold : hint_range(0.0, 1.0) = 0.12;
// Cohérence minimale (0 = gradients en tous sens, 1 = parfaitement alignés).
uniform float stroke_coherence : hint_range(0.0, 1.0) = 0.65;
// Poids des normales dans l'orientation des traits.
uniform float stroke_normal_weight : hint_range(0.0, 4.0) = 0.5;

group_uniforms couleur;
uniform bool use_color = true;
uniform float saturation : hint_range(0.0, 2.0) = 0.6;              // palette naturelle, désaturée
uniform float highlight_saturation : hint_range(0.0, 3.0) = 1.4;    // sources de lumière : couleurs vives
uniform vec3 global_tint : source_color = vec3(0.86, 0.9, 1.0);     // teinte globale (nuit légèrement bleutée)
uniform float color_boost : hint_range(0.0, 4.0) = 1.15;            // luminosité des glyphes
uniform float edge_brightness : hint_range(0.0, 4.0) = 1.25;
uniform float edge_min_brightness : hint_range(0.0, 1.0) = 0.22;
// Les glyphes de trait (| / - \) couvrent peu de pixels : on les éclaircit pour
// que la cellule garde la luminosité moyenne de la zone. Densité de référence
// (0 = pas de compensation) et gain maximal.
uniform float line_density_target : hint_range(0.0, 1.0) = 0.35;
uniform float line_max_gain : hint_range(1.0, 4.0) = 2.0;
uniform vec3 mono_color : source_color = vec3(0.75, 0.9, 0.75);     // si use_color = false

group_uniforms;
uniform float max_depth = 500.0;
// Debug : 0 = rendu ASCII, 1 = luminance après tonemapping (par pixel).
uniform int debug_view = 0;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

void vertex() {
	// Écriture directe en clip space : le quad 2x2 (-1..1) couvre tout l'écran.
	// z = 1.0 correspond au plan proche en Z inversé (Godot 4.3+), donc jamais clippé.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Profondeur linéaire (distance positive à la caméra). Marche en perspective
// comme en orthographique (w = 1).
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

// Courbe de tonemapping (luminance linéaire -> 0..1).
float tonemap(float l) {
	float t = 1.0 - exp(-max(l, 0.0) * exposure); // compresse les hautes lumières
	t = pow(t, 1.0 / gamma);                      // relève les tons sombres
	t = (t - 0.5) * contrast + 0.5;
	return clamp(t, 0.0, 1.0);
}

// Inverse exact de l'encodage sRGB de sortie (vues de debug lisibles au pixel près).
float srgb_to_linear(float x) {
	return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4);
}

// Orientation d'un tenseur de structure (Jxx, Jyy, Jxy) quantifiée en
// index de glyphe directionnel. Axe Y écran vers le bas.
//   gradient horizontal -> trait vertical "|", bas-droite -> "/",
//   vertical -> "-", bas-gauche -> "\"
int direction_glyph(vec3 J) {
	float theta = 0.5 * atan(2.0 * J.z, J.x - J.y);
	if (theta < 0.0) {
		theta += PI;
	}
	int dir = int(floor(theta / (PI * 0.25) + 0.5)) % 4;
	return dir == 0 ? dir_glyphs.x : (dir == 1 ? dir_glyphs.y : (dir == 2 ? dir_glyphs.z : dir_glyphs.w));
}

void fragment() {
	vec2 texel = 1.0 / VIEWPORT_SIZE;

	if (debug_view == 1) {
		float t = tonemap(dot(texture(screen_texture, SCREEN_UV).rgb, LUMA));
		ALBEDO = vec3(srgb_to_linear(t));
	} else {
		// -----------------------------------------------------------------
		// 1. Cellule courante
		// -----------------------------------------------------------------
		float cs = float(cell_size);
		vec2 cell = floor(FRAGCOORD.xy / cs);
		vec2 cell_origin = cell * cs;
		vec2 local = fract(FRAGCOORD.xy / cs); // position du pixel dans sa cellule (0..1)
		vec2 center_uv = (cell_origin + 0.5 * cs) * texel;
		// Ciel / fond : profondeur brute nulle en Z inversé.
		bool is_sky = texture(depth_texture, center_uv).r <= 0.0;

		// -----------------------------------------------------------------
		// 2. Luminance 3x3 de la cellule (une valeur par sous-région) + couleur moyenne
		// -----------------------------------------------------------------
		float v[9];
		vec3 col = vec3(0.0);
		float mean = 0.0;
		for (int y = 0; y < 3; y++) {
			for (int x = 0; x < 3; x++) {
				vec2 uv = (cell_origin + (vec2(float(x), float(y)) + 0.5) * (cs / 3.0)) * texel;
				vec3 c = texture(screen_texture, uv).rgb;
				col += c;
				float t = tonemap(dot(c, LUMA));
				if (!is_sky) {
					t = mix(dark_floor, 1.0, t);
				}
				v[y * 3 + x] = t;
				mean += t;
			}
		}
		col /= 9.0;
		mean /= 9.0;
		float variance = 0.0;
		for (int i = 0; i < 9; i++) {
			variance += (v[i] - mean) * (v[i] - mean);
		}
		variance /= 9.0;

		// -----------------------------------------------------------------
		// 3. Glyphe de base : rampe (cellule uniforme) ou correspondance de forme
		// -----------------------------------------------------------------
		int glyph;
		if (!use_shape_matching || variance < flat_threshold) {
			int level = clamp(int(mean * float(ramp_count - 1) + 0.5), 0, ramp_count - 1);
			glyph = ramp[level];
		} else {
			// Écarts amplifiés autour de la moyenne pour favoriser les formes.
			vec4 ea = vec4(v[0], v[1], v[2], v[3]);
			vec4 eb = vec4(v[4], v[5], v[6], v[7]);
			float ec = v[8];
			ea = clamp(mean + (ea - mean) * shape_contrast, 0.0, 1.0);
			eb = clamp(mean + (eb - mean) * shape_contrast, 0.0, 1.0);
			ec = clamp(mean + (ec - mean) * shape_contrast, 0.0, 1.0);
			float best = 1e9;
			glyph = 0;
			for (int g = 0; g < glyph_count; g++) {
				vec4 da = ea - glyph_shape[g * 3];
				vec4 db = eb - glyph_shape[g * 3 + 1];
				float dc = ec - glyph_shape[g * 3 + 2].x;
				float d = dot(da, da) + dot(db, db) + dc * dc;
				if (d < best) {
					best = d;
					glyph = g;
				}
			}
		}

		// -----------------------------------------------------------------
		// 4. Contours géométriques et traits orientés
		// -----------------------------------------------------------------
		bool is_edge = false;
		bool is_line = false;  // contour ou trait : glyphe directionnel
		if (enable_edges || enable_strokes) {
			// Profondeur et normales sur une grille 3x3 espacée d'une demi-cellule.
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
			// Indices :  0 1 2 / 3 4 5 / 6 7 8
			float gxd = (d[2] + 2.0 * d[5] + d[8]) - (d[0] + 2.0 * d[3] + d[6]);
			float gyd = (d[6] + 2.0 * d[7] + d[8]) - (d[0] + 2.0 * d[1] + d[2]);
			float depth_mag = max(length(vec2(gxd, gyd)), 1e-6);
			// Taille d'une cellule dans le monde, à la profondeur de la cellule :
			// constante en orthographique (P[3][3] = 1), proportionnelle à la
			// distance en perspective.
			float ortho = PROJECTION_MATRIX[3][3];
			float cell_world = cs * 2.0 * mix(d[4], 1.0, ortho) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
			// Laplacien positif = la cellule est devant ses voisines : le contour
			// est dessiné sur l'objet du premier plan, pas sur le fond.
			float depth_lap = (d[1] + d[3] + d[5] + d[7] - 4.0 * d[4]) / cell_world;
			vec3 gxn = (n[2] + 2.0 * n[5] + n[8]) - (n[0] + 2.0 * n[3] + n[6]);
			vec3 gyn = (n[6] + 2.0 * n[7] + n[8]) - (n[0] + 2.0 * n[1] + n[2]);
			float normal_mag2 = dot(gxn, gxn) + dot(gyn, gyn);
			float crease = 1.0 - min(min(dot(n[4], n[1]), dot(n[4], n[7])), min(dot(n[4], n[3]), dot(n[4], n[5])));
			vec3 J_normal = normal_mag2 > 1e-6
				? vec3(dot(gxn, gxn), dot(gyn, gyn), dot(gxn, gyn)) / normal_mag2
				: vec3(0.0);

			// Matières souples (herbe, sol, feuillage : rugosité >= soft_roughness) :
			// jamais cernées, sinon chaque touffe d'herbe devient une boucle de contour.
			bool soft = texture(normal_roughness_texture, center_uv).a >= soft_roughness;
			bool depth_edge = enable_edges && !soft && depth_lap > edge_threshold_depth;
			bool normal_edge = enable_edges && !soft && crease > edge_threshold_normal;

			if (depth_edge || normal_edge) {
				// 4a. Contour : orientation combinée profondeur + normales.
				vec3 J = vec3(0.0);
				if (depth_edge) {
					vec2 g = vec2(gxd, gyd) / depth_mag;
					J += vec3(g.x * g.x, g.y * g.y, g.x * g.y);
				}
				if (normal_edge) {
					J += J_normal;
				}
				glyph = direction_glyph(J);
				is_edge = true;
				is_line = true;
			} else if (enable_strokes && !is_sky) {
				// 4b. Trait orienté : tenseur de structure de la luminance, à
				// partir des 4 gradients 2x2 de la grille 3x3. Les rayures
				// (herbe, pierre striée) donnent des gradients de signes
				// alternés mais d'orientation commune : le tenseur les cumule.
				vec3 J_lum = vec3(0.0);
				for (int qy = 0; qy < 2; qy++) {
					for (int qx = 0; qx < 2; qx++) {
						int i = qy * 3 + qx;
						float gx = 0.5 * ((v[i + 1] + v[i + 4]) - (v[i] + v[i + 3]));
						float gy = 0.5 * ((v[i + 3] + v[i + 4]) - (v[i] + v[i + 1]));
						J_lum += vec3(gx * gx, gy * gy, gx * gy);
					}
				}
				float trace = J_lum.x + J_lum.y;
				float strength = sqrt(trace * 0.25);
				float coherence = trace > 1e-6
					? sqrt((J_lum.x - J_lum.y) * (J_lum.x - J_lum.y) + 4.0 * J_lum.z * J_lum.z) / trace
					: 0.0;
				if (strength > stroke_threshold && coherence > stroke_coherence) {
					glyph = direction_glyph(J_lum / trace + J_normal * stroke_normal_weight);
					is_line = true;
				}
			}
		}

		// -----------------------------------------------------------------
		// 5. Masque du glyphe dans l'atlas, à la position locale du pixel
		// -----------------------------------------------------------------
		vec2 atlas_uv = vec2((float(glyph) + local.x) / float(glyph_count), local.y);
		float mask = texture(glyph_atlas, atlas_uv).a;

		// -----------------------------------------------------------------
		// 6. Couleur : palette naturelle désaturée, lumières chaudes vives
		// -----------------------------------------------------------------
		float brightness = clamp(mean * color_boost, 0.0, 1.0);
		if (is_edge) {
			brightness = clamp(max(brightness * edge_brightness, edge_min_brightness), 0.0, 1.0);
		}
		if (is_line && line_density_target > 0.0) {
			float density = glyph_shape[glyph * 3 + 2].y;
			brightness = clamp(brightness * clamp(line_density_target / max(density, 0.01), 1.0, line_max_gain), 0.0, 1.0);
		}

		vec3 tint;
		if (use_color) {
			// Teinte normalisée (composante max = 1).
			float m = max(col.r, max(col.g, col.b));
			vec3 hue = m > 1e-5 ? col / m : vec3(1.0);
			// Saturation faible pour le décor, forte pour les zones très
			// lumineuses (lanterne, cristal, lune) qui ressortent.
			float highlight = smoothstep(0.55, 1.0, 1.0 - exp(-dot(col, LUMA) * exposure));
			float sat = mix(saturation, highlight_saturation, highlight);
			hue = max(mix(vec3(dot(hue, LUMA)), hue, sat), vec3(0.0));
			tint = hue * global_tint;
		} else {
			tint = mono_color;
		}

		// Retour en linéaire pour la sortie (le moteur applique ensuite l'encodage sRGB).
		ALBEDO = tint * pow(brightness, 2.2) * mask;
	}
}
