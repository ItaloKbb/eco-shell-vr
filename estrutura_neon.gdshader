shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Estruturas do mundo neon (rampas, loops, pontes). Cada face traz em UV a posição
// em metros dentro dela e em UV2 o tamanho da face: o contorno de luz tem largura
// constante em qualquer tamanho. COLOR.r marca as faces de rodagem, que ganham
// faixas transversais lentas (referência de velocidade sem cintilar no VR).
// Contorno largo e halo forte: as bordas das peças se destacam do piso escuro de longe.
uniform vec3 base_color : source_color = vec3(0.01, 0.018, 0.05);
uniform vec3 edge_color : source_color = vec3(0.1, 0.85, 1.0);
uniform vec3 stripe_color : source_color = vec3(0.95, 0.2, 0.85);
uniform float edge_width = 0.15;
uniform float stripe_spacing = 3.0;
uniform float emission_energy = 2.6;

void fragment() {
	vec2 p = UV;
	vec2 size = UV2;
	float d = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
	float aa = max(fwidth(d), 0.0001);
	float edge = 1.0 - smoothstep(edge_width, edge_width + aa * 1.5, d);
	float halo = (1.0 - smoothstep(0.0, edge_width * 6.0, d)) * 0.5;
	float faixa_pos = abs(fract(p.y / stripe_spacing - TIME * 0.15) - 0.5) * 2.0;
	float faixa = (1.0 - smoothstep(0.04, 0.08, faixa_pos)) * COLOR.r;
	vec3 color = base_color + edge_color * (edge + halo) + stripe_color * faixa * 0.45;
	ALBEDO = color;
	EMISSION = color * emission_energy;
}
