shader_type spatial;
// Areia do deserto, low poly: cor chapada em três tons pela altura (planície clara em
// volta da pista, laranja nos vales das dunas, dourado nas cristas). As facetas vêm da
// malha (normal por triângulo) e do sol. Sem ondulação fina nem brilho de grão: ruído
// de alta frequência cintila no headset. Custo: só aritmética (impacto baixo).

uniform vec3 planicie : source_color = vec3(0.96, 0.78, 0.55);
uniform vec3 vale : source_color = vec3(0.9, 0.56, 0.3);
uniform vec3 crista : source_color = vec3(1.0, 0.83, 0.55);

varying float altura;

void vertex() {
	altura = VERTEX.y;
}

void fragment() {
	vec3 cor = mix(planicie, vale, smoothstep(0.3, 2.0, altura));
	cor = mix(cor, crista, smoothstep(4.5, 9.0, altura));
	ALBEDO = cor;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
