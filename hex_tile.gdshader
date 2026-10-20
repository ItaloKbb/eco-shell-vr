shader_type spatial;

// COLOR: rgb = cor do corpo, a = intensidade do brilho
// INSTANCE_CUSTOM: rgb = cor do neon, a = atraso da animação de surgimento

uniform float glow_energy = 2.5;
uniform float body_emission = 0.06;
uniform float rise_depth = 8.0;
instance uniform float reveal = 1.0;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec4 body;
varying vec4 neon;
varying float scale_y;
varying float seed;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	body = COLOR;
	neon = INSTANCE_CUSTOM;
	scale_y = length(MODEL_MATRIX[1].xyz);
	seed = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);

	// Surge de baixo para cima quando o chunk é criado
	float delay = INSTANCE_CUSTOM.a;
	float t = clamp((reveal - delay) / max(1.0 - delay, 0.001), 0.0, 1.0);
	float e = 1.0 - pow(1.0 - t, 3.0);
	VERTEX.y -= (1.0 - e) * rise_depth / scale_y;
}

void fragment() {
	float side = 1.0 - abs(local_normal.y);
	float top = step(0.9, local_normal.y);

	// Faixa neon na borda superior das laterais (em unidades do mundo)
	float dist_top = (1.0 - local_pos.y) * scale_y;
	float rim = side * (1.0 - smoothstep(0.05, 0.14, dist_top));

	// Contorno hexagonal interno na face de cima
	vec2 p = local_pos.xz;
	float d = max(abs(p.x), max(abs(p.x * 0.5 + p.y * 0.866), abs(p.x * 0.5 - p.y * 0.866))) / 0.866;
	float line = top * smoothstep(0.80, 0.84, d) * (1.0 - smoothstep(0.88, 0.92, d));

	float pulse = 0.85 + 0.15 * sin(TIME * (0.4 + seed * 0.6) + seed * 6.283);
	// Alguns tiles esmaecem lentamente de tempos em tempos
	float wave = sin(TIME * (0.3 + seed * 0.3) + seed * 40.0);
	float glitch = seed > 0.9 ? mix(1.0, 0.3, smoothstep(0.6, 1.0, wave)) : 1.0;

	float g = (rim + line) * body.a * pulse * glitch;

	ALBEDO = body.rgb;
	METALLIC = 0.6;
	ROUGHNESS = 0.35;
	EMISSION = body.rgb * body_emission + neon.rgb * g * glow_energy;
}
