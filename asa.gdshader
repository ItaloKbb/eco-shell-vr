shader_type spatial;
render_mode cull_disabled;
// Asa do modo planador, desenhada num PlaneMesh: o contorno enflechado e afilado é
// recortado aqui (UV.x = envergadura, UV.y = corda, 0 = bordo de ataque). Pintura azul
// do casco com nervuras escuras; LED no bordo de ataque, na ponta e no bordo de fuga,
// com um pulso de luz correndo da raiz para a ponta.

uniform vec3 cor_lataria : source_color = vec3(0.09, 0.42, 0.82);
uniform vec3 cor_led : source_color = vec3(0.1843, 0.5529, 1.0);
uniform float brilho = 4.0;
// 0 a 1: acompanha a abertura das asas
uniform float energia = 1.0;
// 1 = asa direita (raiz em UV.x = 0), -1 = esquerda (raiz em UV.x = 1)
instance uniform float lado = 1.0;

void fragment() {
	float vao = lado > 0.0 ? UV.x : 1.0 - UV.x;
	float frente = 0.32 * vao;
	float tras = 1.0 - 0.22 * vao;
	if (UV.y < frente || UV.y > tras) {
		discard;
	}
	float corda = (UV.y - frente) / (tras - frente);

	float ataque = 1.0 - smoothstep(0.04, 0.1, corda);
	float fuga = smoothstep(0.95, 0.98, corda);
	float ponta = smoothstep(0.95, 0.985, vao);
	float pulso = pow(0.5 + 0.5 * sin((vao * 2.0 - TIME * 1.8) * TAU), 10.0);
	float nervura = 1.0 - smoothstep(0.004, 0.012, abs(fract(vao * 7.0) - 0.5) - 0.48);

	vec3 cor = mix(cor_lataria, vec3(0.02, 0.06, 0.14), nervura * 0.7);
	float luz = ataque * (1.0 + 2.5 * pulso) + ponta * 1.5 + fuga * 0.5;
	cor = mix(cor, vec3(0.02), max(ataque, ponta));

	ALBEDO = cor;
	METALLIC = 0.2;
	ROUGHNESS = 0.25;
	CLEARCOAT = 1.0;
	EMISSION = cor_led * luz * energia * brilho;
}
