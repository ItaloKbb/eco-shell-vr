shader_type spatial;
// Ponta da pirâmide: cristal escuro e liso com as arestas acesas no vermelho do núcleo.
// `alerta` (0 a 1) acende tudo quando a ponta está mirando ou voando como míssil.

uniform vec3 cor : source_color = vec3(1.0, 0.2, 0.35);
uniform float alerta = 0.0;

void fragment() {
	// As faces planas de uma pirâmide de 4 lados: aresta onde a normal muda (fwidth)
	float aresta = clamp(length(fwidth(NORMAL)) * 6.0, 0.0, 1.0);
	float borda = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	float pisca = 0.7 + 0.3 * sin(TIME * 18.0);
	ALBEDO = vec3(0.03, 0.02, 0.04);
	METALLIC = 0.8;
	ROUGHNESS = 0.15;
	EMISSION = cor * (borda * (0.6 + 2.0 * alerta) + aresta * 2.0 + alerta * 1.2 * pisca);
}
