shader_type spatial;
// Eau de la mare : surface opaque sombre, vagues douces, et reflet de la lune
// en paillettes.
//
// Reflet de la lune : la caméra plonge vers le sol, la lune n'est donc jamais
// dans le champ. On la place « derrière » la mare, à l'opposé de la caméra,
// un peu plus bas que le rayon réfléchi par une eau parfaitement plate : seules
// les facettes de vague inclinées dans le bon sens renvoient la lune, ce qui
// donne des paillettes qui scintillent avec les vagues.
//
// Pluie (rain_amount > 0) : anneaux de gouttes qui s'élargissent à la surface.
//
// Opaque volontairement : le shader ASCII lit l'image des objets opaques
// (une surface transparente n'y apparaîtrait pas).
render_mode specular_schlick_ggx, cull_disabled;

uniform vec3 deep_color : source_color = vec3(0.015, 0.03, 0.045);
uniform vec3 shallow_color : source_color = vec3(0.07, 0.1, 0.13);
uniform vec3 sky_color : source_color = vec3(0.1, 0.13, 0.22);
uniform vec3 moon_color : source_color = vec3(0.8, 0.86, 1.0);
// 1 = la lune exactement dans l'axe du reflet d'une eau plate (toute la mare
// brille) ; plus bas = paillettes sur les seules vagues inclinées.
uniform float moon_elevation = 0.68;
uniform float glint_sharpness = 1800.0;
uniform float glint_strength = 5.0;
uniform float wave_height = 0.06;
uniform float wave_scale = 1.0;
uniform float wave_speed = 0.8;
uniform float rain_amount : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Hauteur de la surface (sans unité, multipliée par wave_height).
float height(vec2 p, float time) {
	float t = time * wave_speed;
	float h = sin(dot(p, vec2(0.8, 0.6)) * wave_scale * 3.0 + t * 1.3) * 0.5
		+ sin(dot(p, vec2(-0.5, 0.85)) * wave_scale * 4.7 + t * 1.7) * 0.3
		+ sin(dot(p, vec2(0.95, -0.3)) * wave_scale * 7.3 + t * 2.3) * 0.2
		// Ridules fines : morcellent le reflet de la lune en petites paillettes.
		+ sin(dot(p, vec2(0.3, 0.95)) * wave_scale * 15.0 + t * 3.1) * 0.12
		+ sin(dot(p, vec2(-0.85, -0.5)) * wave_scale * 19.0 + t * 3.7) * 0.08;
	if (rain_amount > 0.0) {
		// Une goutte par case de 0,7 m, à un instant propre à chaque case.
		vec2 cell = floor(p / 0.7);
		for (int i = 0; i < 4; i++) {
			vec2 c = cell + vec2(float(i % 2), float(i / 2)) - 0.5;
			vec2 center = (c + vec2(hash(c), hash(c + 7.3))) * 0.7;
			float phase = fract(time * 1.2 + hash(c + 3.1));
			float d = length(p - center);
			float ring = sin((d - phase * 0.45) * 45.0) * exp(-abs(d - phase * 0.45) * 18.0);
			h += ring * (1.0 - phase) * rain_amount * 1.5;
		}
	}
	return h;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += height(world.xz, TIME) * wave_height;
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Normale par différences finies : inclut les détails fins (anneaux de pluie)
	// trop petits pour la grille de sommets.
	float e = 0.03;
	float hx = height(world.xz + vec2(e, 0.0), TIME) - height(world.xz - vec2(e, 0.0), TIME);
	float hz = height(world.xz + vec2(0.0, e), TIME) - height(world.xz - vec2(0.0, e), TIME);
	vec3 n = normalize(vec3(-hx * wave_height / (2.0 * e), 1.0, -hz * wave_height / (2.0 * e)));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Direction vers la caméra (constante en orthographique) et rayon réfléchi.
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	vec3 back = INV_VIEW_MATRIX[2].xyz;
	vec3 moon = normalize(vec3(-back.x, back.y * moon_elevation, -back.z));
	float glint = pow(max(dot(r, moon), 0.0), glint_sharpness);
	float fresnel = 0.08 + 0.92 * pow(1.0 - max(dot(n, v), 0.0), 5.0);

	ALBEDO = mix(deep_color, shallow_color, fresnel);
	EMISSION = moon_color * glint * glint_strength + sky_color * fresnel * 0.6;
	ROUGHNESS = 0.08;
	SPECULAR = 0.5;
}
