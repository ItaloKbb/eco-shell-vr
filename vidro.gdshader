shader_type spatial;
render_mode cull_disabled, depth_draw_never, fog_disabled;
// Policarbonato do vidro: limpo, só um reflexo leve nas bordas (fresnel).
// Rente à lataria, o piloto olha por ele em ângulo raso; qualquer opacidade ou emissão
// vira um véu leitoso (e o glow da cena borra), então por dentro ele quase some.
// Batidas trincam o vidro: raios irregulares saindo do ponto, anéis quebrados em volta
// e o centro estilhaçado, em branco translúcido (ainda dá para ver através).

#include "res://eco_shell_aberturas.gdshaderinc"

// Preenchidas por eco_shell_casco.gd: xyz = ponto no vidro, w = intensidade
uniform vec4 trincas[6];

varying vec3 local;

void vertex() {
	local = VERTEX;
}

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

// Trinca vista de cima (o vidro é quase horizontal): q em metros a partir do ponto
float trinca(vec2 q, float w, float semente) {
	float r = length(q);
	float alcance = 0.1 + 0.2 * w;
	if (r > alcance) {
		return 0.0;
	}
	float a = atan(q.y, q.x);
	float n = 9.0;
	float id = floor((a / TAU + 0.5) * n);
	float rumo = (id + 0.5 + (hash(id + semente) - 0.5) * 0.7) / n * TAU - PI;
	// Raios: cada um com comprimento próprio, ondulando um pouco
	float d = abs(sin(a - rumo + sin(r * 60.0 + id) * 0.03)) * r;
	float raio = (1.0 - smoothstep(0.0008, 0.002, d)) * step(r, alcance * (0.45 + 0.55 * hash(id * 7.0 + semente)));
	// Anéis em pedaços
	float passo = 0.03;
	float anel = 1.0 - smoothstep(0.0008, 0.002, abs(fract(r / passo) - 0.5) * passo);
	anel *= step(0.55, hash(floor(a * 2.5) + floor(r / passo) * 13.0 + semente)) * step(r, alcance * 0.65);
	// Centro estilhaçado
	float centro = 1.0 - smoothstep(0.004, 0.012 + 0.02 * w, r);
	return max(max(raio, anel * 0.8), centro * 0.9) * smoothstep(alcance, alcance * 0.7, r);
}

void fragment() {
	if (!no_vidro(local)) {
		discard;
	}
	float quebra = 0.0;
	for (int i = 0; i < 6; i++) {
		float w = trincas[i].w;
		if (w > 0.0) {
			quebra = max(quebra, trinca(local.xz - trincas[i].xz, w, float(i) * 3.7 + trincas[i].x * 11.0));
		}
	}
	float borda = pow(1.0 - abs(dot(NORMAL, VIEW)), 5.0);
	ALBEDO = mix(vec3(0.55, 0.75, 1.0), vec3(0.9, 0.95, 1.0), quebra);
	ALPHA = max((0.02 + 0.25 * borda) * (FRONT_FACING ? 1.0 : 0.3), quebra * 0.8);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.0, 0.6, quebra);
	SPECULAR = 0.5;
}
