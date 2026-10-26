shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Feixe estável para VR: gradiente vertical amplo e pulsos lentos, sem ruído fino.

uniform vec3 cor : source_color = vec3(0.1, 0.85, 1.0);
uniform float altura = 80.0;
uniform float forca = 0.7;
uniform float fase = 0.0;

varying float subida;

void vertex() {
	subida = VERTEX.y / altura + 0.5;
}

void fragment() {
	float eixo = pow(abs(dot(NORMAL, VIEW)), 1.6);
	float nasce = smoothstep(0.0, 0.025, subida);
	float some = 1.0 - smoothstep(0.55, 1.0, subida);
	float base = 0.65 + 0.35 * exp(-subida * 14.0);
	float faixa = 0.88 + 0.12 * sin(TIME * 0.9 - subida * 8.0 + fase * TAU);
	float energia = eixo * nasce * some * base * faixa * forca;
	ALBEDO = cor * energia;
	ALPHA = clamp(energia, 0.0, 1.0);
}
