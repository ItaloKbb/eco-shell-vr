shader_type spatial;
// Chão plano dos mapas (gramado do Sistema S, pátio do Parque Industrial), low poly:
// manchas grandes de cor chapada em dois tons (uma a cada ~100 a 200 m), como campos
// vistos de cima, com a borda suave. Sem textura nem ruído fino: nada cintila no
// headset, de perto ou de longe. Só aritmética (impacto baixo).

uniform vec3 cor_a : source_color = vec3(0.36, 0.76, 0.29);
uniform vec3 cor_b : source_color = vec3(0.49, 0.83, 0.35);

varying vec2 mundo;

void vertex() {
	mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	// Duas ondas largas tortas: o sinal do produto vira mancha
	float onda = sin(mundo.x * 0.021 + sin(mundo.y * 0.013) * 2.2) * sin(mundo.y * 0.017 + sin(mundo.x * 0.011) * 1.8);
	float w = fwidth(onda) + 0.02;
	float mancha = smoothstep(-w, w, onda);
	ALBEDO = mix(cor_a, cor_b, mancha);
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
