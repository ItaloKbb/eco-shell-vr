shader_type spatial;
render_mode unshaded;
// Tela da câmera traseira no painel: imagem espelhada (como câmera de ré), linhas de
// varredura leves, moldura neon e as guias de distância.

uniform sampler2D tela : source_color, filter_linear;
uniform vec3 cor : source_color = vec3(0.1843, 0.5529, 1.0);

void fragment() {
	vec3 c = texture(tela, vec2(1.0 - UV.x, UV.y)).rgb;
	float varredura = 0.93 + 0.07 * sin(UV.y * 200.0);
	float borda = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float moldura = 1.0 - smoothstep(0.015, 0.03, borda);
	// Guias: duas linhas convergindo para o fundo da imagem
	float y = 1.0 - UV.y;
	float guia = 0.0;
	if (y < 0.45) {
		float meio = abs(UV.x - 0.5);
		float alvo = 0.32 - y * 0.35;
		guia = 1.0 - smoothstep(0.004, 0.009, abs(meio - alvo));
	}
	ALBEDO = mix(c * varredura, cor * 1.5, max(moldura, guia * 0.7));
}
