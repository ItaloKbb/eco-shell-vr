shader_type spatial;
// Mesas e rochas do deserto, low poly: camadas largas de arenito (uma a cada 12 m de
// altura, alternando três tons de vermelho e laranja) e o topo plano mais claro. As
// facetas vêm da malha (LowPoly.facetar). Sem listras finas: camada grossa e borda
// suavizada não cintilam de longe. Custo: só aritmética (impacto baixo).

uniform vec3 escura : source_color = vec3(0.72, 0.27, 0.16);
uniform vec3 media : source_color = vec3(0.85, 0.4, 0.23);
uniform vec3 clara : source_color = vec3(0.93, 0.54, 0.31);
uniform vec3 topo : source_color = vec3(0.97, 0.71, 0.47);
uniform float camada = 12.0;

varying vec3 mundo;
varying vec3 normal_mundo;

void vertex() {
	mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// Qual camada (0, 1, 2) e a transição suave de meio metro entre elas
	float h = mundo.y / camada;
	float w = fwidth(h) + 0.04;
	float passo = smoothstep(0.5 - w, 0.5 + w, fract(h));
	float k = mod(floor(h), 3.0);
	vec3 a = k < 1.0 ? escura : (k < 2.0 ? media : clara);
	vec3 b = k < 1.0 ? media : (k < 2.0 ? clara : escura);
	vec3 cor = mix(a, b, passo);
	cor = mix(cor, topo, smoothstep(0.75, 0.9, normalize(normal_mundo).y));
	ALBEDO = cor;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
