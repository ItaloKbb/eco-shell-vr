shader_type spatial;
render_mode unshaded, fog_disabled;
// Núcleo da pirâmide: plasma vermelho-magenta (a cor do inimigo, contra o azul do
// jogador) com veios que se mexem, borda mais quente (fresnel) e pulsação.
// `furia` (0 a 1) acelera e esquenta tudo durante a perseguição.

uniform vec3 cor_fria : source_color = vec3(0.55, 0.05, 0.35);
uniform vec3 cor_quente : source_color = vec3(1.0, 0.25, 0.3);
uniform float furia = 0.0;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float t = TIME * (0.8 + 2.5 * furia);
	vec3 p = normalize(local) * 3.0;
	float veios = sin(p.x * 2.1 + t) * sin(p.y * 2.7 - t * 1.3) * sin(p.z * 1.9 + t * 0.7);
	veios = pow(abs(veios), 0.35);
	float borda = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float pulso = 0.8 + 0.2 * sin(t * 3.0);
	vec3 cor = mix(cor_fria, cor_quente, clamp(veios * 0.8 + borda + furia * 0.3, 0.0, 1.0));
	ALBEDO = cor * (1.2 + 1.3 * borda + 0.8 * veios) * pulso * (1.0 + furia * 0.6);
}
