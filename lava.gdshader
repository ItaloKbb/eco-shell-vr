shader_type spatial;
// Campo de lava (I de Incrível): placas de crosta escura com veios incandescentes entre
// elas e poças inteiras derretidas, tudo andando devagar. Três leituras da mesma textura
// de ruído em escalas diferentes (barato no Quest), em coordenadas do mundo.

uniform sampler2D ruido : repeat_enable, filter_linear_mipmap;
uniform vec3 cor_crosta = vec3(0.05, 0.035, 0.03);
uniform vec3 cor_lava = vec3(1.0, 0.28, 0.03);
uniform vec3 cor_quente = vec3(1.0, 0.72, 0.22);
uniform float energia = 3.0;

varying vec3 mundo;

void vertex() {
	mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = mundo.xz;
	float grande = texture(ruido, p * 0.004 + vec2(TIME * 0.002, 0.0)).r;
	float medio = texture(ruido, p * 0.019 - vec2(0.0, TIME * 0.006)).r;
	float fino = texture(ruido, p * 0.07 + vec2(TIME * 0.01, TIME * 0.004)).r;
	// Veios: onde o ruído médio cruza o meio, mais largos onde o grande está alto
	float veio = 1.0 - smoothstep(0.0, 0.05 + 0.06 * grande, abs(medio - 0.5));
	// Poças: a crosta derrete inteira onde o ruído grande é alto
	float poca = smoothstep(0.6, 0.7, grande + (fino - 0.5) * 0.15);
	float lava = max(veio * (0.45 + 0.55 * fino), poca);
	float pulso = 0.8 + 0.2 * sin(TIME * 1.3 + grande * 20.0);
	vec3 quente = mix(cor_lava, cor_quente, fino * poca);
	ALBEDO = mix(cor_crosta * (0.7 + 0.6 * fino), quente * 0.4, lava);
	EMISSION = quente * lava * energia * pulso;
	ROUGHNESS = mix(0.95, 0.45, lava);
}
