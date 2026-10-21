shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Feixe de luz que sobe do portal até o céu: marca onde ele está de longe, através da
// névoa. Mais forte no eixo (de frente para a câmera), some para cima e pulsa devagar.

uniform vec3 cor : source_color = vec3(0.1, 0.85, 1.0);
uniform float altura = 80.0;
uniform float forca = 0.7;

varying float subida;

void vertex() {
	subida = VERTEX.y / altura + 0.5;
}

void fragment() {
	float eixo = pow(abs(dot(NORMAL, VIEW)), 2.5);
	float some = (1.0 - smoothstep(0.0, 1.0, subida)) * smoothstep(0.0, 0.04, subida);
	float pulso = 0.8 + 0.2 * sin(TIME * 1.5 - subida * 12.0);
	ALBEDO = cor * eixo * some * pulso * forca;
}
