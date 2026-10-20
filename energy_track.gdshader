shader_type spatial;
// fog_disabled: a energia brilha através da névoa, então a pista fica visível de longe
render_mode cull_disabled, fog_disabled;
// Pista de energia: vidro escuro com bordas neon, linha central, travessas a cada 2 m
// e pulsos de energia correndo no sentido em que a pista foi criada.
// UV.x = posição na largura (0 a 1), UV.y = metros desde o início da pista.

uniform vec3 cor_borda : source_color = vec3(0.1843, 0.5529, 1.0);
uniform vec3 cor_pulso : source_color = vec3(0.9608, 0.6196, 0.2);
uniform float brilho = 4.0;
uniform float velocidade_pulso = 0.8;

void fragment() {
	float lado = min(UV.x, 1.0 - UV.x);
	float borda = 1.0 - smoothstep(0.0, 0.07, lado);
	float centro = 1.0 - smoothstep(0.004, 0.012, abs(UV.x - 0.5));
	float travessa = 1.0 - smoothstep(0.008, 0.025, abs(fract(UV.y * 0.5) - 0.5) * 2.0);
	float pulso = pow(fract(UV.y * 0.1 - TIME * velocidade_pulso), 10.0);

	ALBEDO = vec3(0.01, 0.02, 0.06);
	METALLIC = 0.6;
	ROUGHNESS = 0.15;
	ALPHA = clamp(0.55 + borda + travessa * 0.3, 0.0, 1.0);
	EMISSION = cor_borda * (borda * brilho + centro * 1.2 + travessa * 0.6 + 0.08)
		+ cor_pulso * pulso * (0.6 + borda * 3.0);
}
