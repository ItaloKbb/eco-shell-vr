shader_type spatial;
// Campo de lava (I de Incrível), low poly: placas grandes de crosta em cor chapada
// (dois tons de basalto violeta) com veios incandescentes entre elas e poças inteiras
// derretidas, andando devagar. Duas leituras da mesma textura de ruído, só em escalas
// grandes (a leitura fina cintilava no headset); os veios têm a borda suavizada por
// fwidth e somem com a distância em vez de virarem serrilhado. O pulso é o mesmo no
// campo todo (sem pisca-pisca por ponto). Custo: 2 leituras de textura (impacto baixo).

uniform sampler2D ruido : repeat_enable, filter_linear_mipmap;
uniform vec3 cor_crosta : source_color = vec3(0.16, 0.12, 0.15);
uniform vec3 cor_crosta_clara : source_color = vec3(0.23, 0.17, 0.2);
uniform vec3 cor_lava : source_color = vec3(1.0, 0.42, 0.1);
uniform vec3 cor_quente : source_color = vec3(1.0, 0.76, 0.23);
uniform float energia = 2.2;

varying vec3 mundo;

void vertex() {
	mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = mundo.xz;
	float grande = texture(ruido, p * 0.004 + vec2(TIME * 0.002, 0.0)).r;
	float medio = texture(ruido, p * 0.016 - vec2(0.0, TIME * 0.005)).r;
	// Veio: onde o ruído médio cruza o meio, mais largo onde o grande está alto
	float distancia_veio = abs(medio - 0.5);
	float w = fwidth(medio) + 0.0001;
	float largura_veio = 0.025 + 0.04 * grande;
	float veio = 1.0 - smoothstep(largura_veio - w, largura_veio + w, distancia_veio);
	// Longe, o veio fica mais fino que o pixel: apaga suave em vez de cintilar
	veio *= 1.0 - smoothstep(largura_veio * 0.5, largura_veio * 1.5, w);
	// Poças: a crosta derrete inteira onde o ruído grande é alto
	float wg = fwidth(grande) + 0.0001;
	float poca = smoothstep(0.64 - wg, 0.66 + wg, grande);
	float lava = max(veio, poca);
	// Placas de crosta em dois tons chapados
	vec3 crosta = mix(cor_crosta, cor_crosta_clara, smoothstep(0.5 - w, 0.5 + w, medio));
	vec3 quente = mix(cor_lava, cor_quente, poca);
	float pulso = 0.88 + 0.12 * sin(TIME * 1.1);
	ALBEDO = mix(crosta, quente * 0.4, lava);
	EMISSION = quente * lava * energia * pulso;
	ROUGHNESS = mix(1.0, 0.5, lava);
}
