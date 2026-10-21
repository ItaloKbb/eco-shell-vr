shader_type spatial;
// fog_disabled: a energia brilha através da névoa, então o rastro fica visível de longe
render_mode cull_disabled, fog_disabled, depth_draw_always;
// Parede de luz estilo Tron: vidro azul translúcido, mais forte e brilhante no topo
// (onde sai da asa), bordas neon, linhas de varredura finas e pulsos de energia
// correndo no sentido em que o rastro foi criado.
// UV.x = altura na parede (0 = topo, 1 = base), UV.y = metros desde o início.

uniform vec3 cor_borda : source_color = vec3(0.1843, 0.5529, 1.0);
uniform vec3 cor_pulso : source_color = vec3(0.6, 0.9, 1.0);
uniform float brilho = 4.0;
uniform float velocidade_pulso = 0.8;

void fragment() {
	float topo = 1.0 - smoothstep(0.0, 0.06, UV.x);
	float base = smoothstep(0.94, 1.0, UV.x);
	// A luz desce do topo e vai sumindo para a base, como a cortina das motos do Tron
	float cortina = pow(1.0 - UV.x, 1.5);
	float varredura = 0.85 + 0.15 * sin(UV.x * 120.0);
	float travessa = 1.0 - smoothstep(0.01, 0.03, abs(fract(UV.y * 0.5) - 0.5) * 2.0);
	float pulso = pow(fract(UV.y * 0.1 - TIME * velocidade_pulso), 10.0);

	ALBEDO = vec3(0.01, 0.03, 0.08);
	METALLIC = 0.4;
	ROUGHNESS = 0.2;
	ALPHA = clamp(0.18 + 0.4 * cortina + topo + base * 0.6, 0.0, 1.0);
	EMISSION = cor_borda * (topo * brilho + base * brilho * 0.5 + cortina * varredura * 0.9 + travessa * 0.3)
		+ cor_pulso * pulso * (0.4 + topo * 3.0);
}
