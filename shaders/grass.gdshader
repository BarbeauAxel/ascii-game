shader_type spatial;
// Brins d'herbe (MultiMesh) : dégradé sombre à la base -> clair à la pointe,
// courbure par le vent (rafales qui traversent le champ + frémissement).
//
// Chaque instance porte dans INSTANCE_CUSTOM :
//   x = variation de luminosité, y = variation de teinte (vert -> paille),
//   z = raideur (les brins courts plient moins).
render_mode cull_disabled, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.1, 0.13, 0.07);
uniform vec3 tip_color : source_color = vec3(0.55, 0.64, 0.33);
uniform vec3 dry_color : source_color = vec3(0.58, 0.52, 0.32);
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_strength : hint_range(0.0, 2.0) = 0.35;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.0;
// Taille des rafales (mètres entre deux fronts de vent).
uniform float gust_size = 7.0;

varying float v_height;
varying vec3 v_custom;

void vertex() {
	v_height = UV.y;
	v_custom = INSTANCE_CUSTOM.xyz;

	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 dir = normalize(wind_direction);
	// Front de rafale qui avance dans la direction du vent.
	float phase = dot(world.xz, dir) / gust_size * 6.2831 - TIME * wind_speed * 2.0;
	float gust = sin(phase) * 0.5 + 0.5;
	gust = gust * gust;
	// Frémissement propre à chaque brin.
	float flutter = sin(TIME * 4.0 + world.x * 3.1 + world.z * 2.3) * 0.12;
	float bend = (0.25 + gust + flutter) * wind_strength * v_custom.z;

	// Décalage horizontal en espace monde, croissant avec la hauteur (au carré :
	// la base reste plantée), ramené en espace local de l'instance.
	vec3 offset = vec3(dir.x, 0.0, dir.y) * bend * v_height * v_height;
	offset.y = -bend * bend * v_height * 0.3;
	mat3 to_local = inverse(mat3(MODEL_MATRIX));
	VERTEX += to_local * offset;
	// Normale tournée vers le ciel : éclairage proche de celui du sol (pas de
	// faces arrière noires), légèrement inclinée par le vent.
	NORMAL = normalize(to_local * normalize(vec3(dir.x * bend * 0.5, 1.0, dir.y * bend * 0.5)));
}

void fragment() {
	// Rendu double face : sans ceci, la face arrière d'un brin aurait une
	// normale retournée (éclairée par en dessous, donc noire). On éclaire
	// tout le brin comme le sol, vers le ciel (espace vue).
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 tip = mix(tip_color, dry_color, v_custom.y);
	ALBEDO = mix(base_color, tip, smoothstep(0.0, 1.0, v_height)) * v_custom.x;
	ROUGHNESS = 1.0;
	// Base des touffes dans l'ombre.
	AO = mix(0.6, 1.0, v_height);
	AO_LIGHT_AFFECT = 0.6;
}
