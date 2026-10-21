shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, fog_disabled;
// Casca esférica do portal: quase transparente de frente (o vórtice aparece por dentro)
// e cada vez mais brilhante para a borda (fresnel), com faixas de energia em espiral
// correndo pela superfície. Dá o volume de esfera de qualquer ângulo.

uniform vec3 cor : source_color = vec3(0.1, 0.85, 1.0);

varying vec3 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec3 p = normalize(local);
	float t = TIME;
	float borda = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	// Espiral em volta do eixo vertical (3 voltas inteiras: sem emenda no atan)
	float faixas = 0.5 + 0.5 * sin(p.y * 9.0 + atan(p.z, p.x) * 3.0 + t * 1.5);
	faixas *= 0.75 + 0.25 * sin(p.x * 7.0 + p.z * 5.0 - t * 1.1);
	ALBEDO = cor * borda * (0.6 + 0.9 * faixas) * 2.0;
	ALPHA = clamp(borda * 1.1, 0.0, 1.0) * (0.45 + 0.55 * faixas);
}
