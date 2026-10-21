shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Texto do visor do capacete: cada pixel da tela de baixa resolução vira um ponto de
// luz (grade de LEDs), com halo em volta, uma faixa de varredura descendo devagar e
// uma cintilação leve. Aditivo: o preto some e só a luz aparece sobre o mundo.

uniform sampler2D tela : source_color, filter_nearest;
uniform vec2 resolucao = vec2(200.0, 84.0);
uniform float intensidade = 2.0;

void fragment() {
	vec2 px = 1.0 / resolucao;
	vec4 t = texture(tela, UV);
	vec3 luz = t.rgb * t.a;

	// Halo: vizinhos em anel, cor do próprio texto
	vec3 halo = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec4 v = texture(tela, UV + vec2(cos(a), sin(a)) * px * 1.6);
		halo += v.rgb * v.a;
	}
	halo /= 8.0;

	// Grade de pixels; fwidth suaviza a borda para não cintilar (moiré) no headset
	vec2 celula = abs(fract(UV * resolucao) - 0.5);
	float w = fwidth(UV.x * resolucao.x);
	float ponto = mix(0.45, 1.0, 1.0 - smoothstep(0.4 - w, 0.4 + w, max(celula.x, celula.y)));

	float faixa = exp(-pow((fract(TIME * 0.22) - UV.y) * 7.0, 2.0)) * 0.6;
	float cintila = 0.95 + 0.05 * sin(TIME * 41.0) * sin(TIME * 7.3);

	ALBEDO = (luz * ponto * (1.0 + faixa) + halo * 0.4) * intensidade * cintila;
}
