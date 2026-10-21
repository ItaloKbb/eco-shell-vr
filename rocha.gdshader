shader_type spatial;
// Mesas de rocha do horizonte: camadas horizontais de arenito em tons de vermelho e
// laranja (pela altura no mundo), com o topo mais claro.

varying vec3 mundo;

void vertex() {
	mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float camada = sin(mundo.y * 0.55 + sin(mundo.x * 0.05 + mundo.z * 0.04) * 1.5) * 0.5 + 0.5;
	float fina = sin(mundo.y * 3.1) * 0.5 + 0.5;
	vec3 cor = mix(vec3(0.55, 0.22, 0.12), vec3(0.78, 0.42, 0.22), camada);
	cor *= 0.88 + 0.12 * fina;
	cor = mix(cor, vec3(0.85, 0.6, 0.38), smoothstep(0.8, 0.98, NORMAL.y));
	ALBEDO = cor;
	ROUGHNESS = 0.95;
}
