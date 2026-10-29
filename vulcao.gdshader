shader_type spatial;
// Encosta do vulcão do horizonte: basalto escuro com rios de lava descendo da cratera,
// mais acesos e mais grossos perto do topo. UV.x é a volta em torno do cone (0 a 1) e
// UV.y a altura (0 na base, 1 na borda da cratera).

uniform vec3 cor_rocha = vec3(0.07, 0.055, 0.05);
uniform vec3 cor_lava = vec3(1.0, 0.3, 0.04);
uniform float energia = 4.0;

void fragment() {
	float a = UV.x * 6.2831853;
	float h = UV.y;
	// Os rios serpenteiam: a fase muda com a altura
	float rio = sin(a * 9.0 + sin(h * 7.0 + a * 2.0) * 1.6);
	float largura = mix(0.004, 0.06, h * h);
	float mascara = smoothstep(1.0 - largura * 2.0, 1.0 - largura * 0.5, rio) * smoothstep(0.15, 0.7, h);
	// Brilho da cratera escorrendo pela borda
	mascara = max(mascara, smoothstep(0.93, 1.0, h));
	float pulso = 0.85 + 0.15 * sin(TIME * 0.9 + a * 3.0);
	ALBEDO = mix(cor_rocha * (0.8 + 0.4 * h), cor_lava * 0.4, mascara);
	EMISSION = cor_lava * mascara * energia * pulso;
	ROUGHNESS = 0.95;
}
