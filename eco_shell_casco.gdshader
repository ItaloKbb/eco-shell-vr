shader_type spatial;
render_mode cull_disabled;
// Pintura do casco Eco Shell: lataria metálica com faixas neon laterais,
// farol branco no bico e lanterna vermelha na cauda (tudo por UV, ver eco_shell_casco.gd).

uniform vec3 cor_lataria : source_color = vec3(0.0784, 0.0784, 0.2353);
uniform vec3 cor_faixa : source_color = vec3(0.9216, 0.3608, 0.1804);
uniform vec3 cor_filete : source_color = vec3(0.1843, 0.5529, 1.0);
uniform float faixa_altura = -0.05;
uniform float faixa_largura = 0.05;
uniform float filete_altura = 0.3;
uniform float filete_largura = 0.015;
uniform float brilho = 3.0;

float banda(float v, float centro, float largura) {
	float d = abs(v - centro);
	return 1.0 - smoothstep(largura * 0.6, largura, d);
}

void fragment() {
	// Faixas só no corpo, somem perto do bico e da cauda
	float corpo = smoothstep(0.06, 0.14, UV.x) * (1.0 - smoothstep(0.82, 0.92, UV.x));
	float faixa = banda(UV.y, faixa_altura, faixa_largura) * corpo;
	float filete = banda(UV.y, filete_altura, filete_largura) * corpo;
	float farol = (1.0 - smoothstep(0.012, 0.02, UV.x)) * banda(UV.y, 0.0, 0.45);
	float lanterna = smoothstep(0.975, 0.99, UV.x) * banda(UV.y, 0.0, 0.6);

	float pintura = max(max(faixa, filete), max(farol, lanterna));
	vec3 cor = cor_faixa * faixa + cor_filete * filete
		+ vec3(1.0, 0.94, 0.82) * farol + vec3(1.0, 0.05, 0.05) * lanterna;

	ALBEDO = mix(cor_lataria, cor, pintura);
	METALLIC = mix(0.85, 0.0, pintura);
	ROUGHNESS = mix(0.22, 0.5, pintura);
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.1;
	EMISSION = cor * brilho + cor_filete * 0.04;

	// Lado de dentro (visto pela abertura do cockpit): fibra escura fosca
	if (!FRONT_FACING) {
		ALBEDO = vec3(0.025, 0.025, 0.04);
		METALLIC = 0.0;
		ROUGHNESS = 0.9;
		CLEARCOAT = 0.0;
		EMISSION = vec3(0.0);
	}
}
