shader_type spatial;
// Encosta do vulcão do horizonte, low poly: basalto violeta em cor chapada (as facetas
// vêm da malha) com rios de lava descendo da cratera, mais largos perto do topo. Os rios
// têm largura mínima e borda suavizada por fwidth: de longe não viram fio serrilhado.
// UV.x é a volta em torno do cone (0 a 1) e UV.y a altura (0 na base, 1 na borda).
// Só aritmética (impacto baixo).

uniform vec3 cor_rocha : source_color = vec3(0.23, 0.17, 0.2);
uniform vec3 cor_topo : source_color = vec3(0.32, 0.2, 0.22);
uniform vec3 cor_lava : source_color = vec3(1.0, 0.42, 0.1);
uniform float energia = 3.0;

void fragment() {
	float a = UV.x * 6.2831853;
	float h = UV.y;
	// Os rios serpenteiam: a fase muda com a altura
	float rio = sin(a * 9.0 + sin(h * 7.0 + a * 2.0) * 1.6);
	float largura = mix(0.03, 0.09, h * h);
	float w = fwidth(rio) + 0.0001;
	float mascara = smoothstep(1.0 - largura * 2.0 - w, 1.0 - largura * 0.5 + w, rio) * smoothstep(0.15, 0.7, h);
	// Fio mais fino que o pixel (muito longe): apaga suave
	mascara *= 1.0 - smoothstep(largura, largura * 3.0, w);
	// Brilho da cratera escorrendo pela borda
	mascara = max(mascara, smoothstep(0.93, 1.0, h));
	float pulso = 0.88 + 0.12 * sin(TIME * 0.9);
	ALBEDO = mix(mix(cor_rocha, cor_topo, h), cor_lava * 0.4, mascara);
	EMISSION = cor_lava * mascara * energia * pulso;
	ROUGHNESS = 1.0;
}
