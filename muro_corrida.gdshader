shader_type spatial;
render_mode cull_disabled;
// Muro de proteção da pista: concreto claro com blocos vermelhos e brancos alternados
// (estilo autódromo de Carros) e uma faixa escura de pneu raspado embaixo.
// UV.x = 0 em baixo a 1 em cima, UV.y = metros ao longo da pista.

void fragment() {
	float bloco = mod(floor(UV.y / 3.0), 2.0);
	vec3 cor = bloco < 1.0 ? vec3(0.78, 0.1, 0.08) : vec3(0.92, 0.9, 0.86);
	// Faixa de borracha raspada na base
	cor = mix(cor, vec3(0.08), (1.0 - smoothstep(0.08, 0.18, UV.x)) * 0.7);
	ALBEDO = cor;
	ROUGHNESS = 0.75;
}
