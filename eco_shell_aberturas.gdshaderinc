// Aberturas do casco Eco Shell (vidro do teto, janelas laterais, recorte do para-lama).
// A malha só separa os quads por região; a borda exata, lisa, é recortada aqui por
// pixel, com as mesmas contas de eco_shell_casco.gd, que preenche estes uniforms.

uniform float centro_y = 0.3;
// Vidro do teto: centro em Z, meia largura, meio comprimento
uniform vec3 vidro = vec3(-0.4, 0.22, 0.62);
// Janelas laterais: centro em Z, centro em Y, meio comprimento, meia altura
uniform vec4 janela = vec4(0.03, 0.45, 0.36, 0.08);
// Para-lama dianteiro: centro em Z, centro em Y, raio, |x| mínimo
uniform vec4 para_lama = vec4(-0.75, 0.245, 0.27, 0.22);

// Distância aproximada (m) até a borda do vidro do teto; negativa = dentro
float borda_vidro(vec3 p) {
	if (p.y < centro_y + 0.1) return 1.0;
	return (length(vec2(p.x, p.z - vidro.x) / vidro.yz) - 1.0) * vidro.y;
}

float borda_janela(vec3 p) {
	if (abs(p.x) < 0.1) return 1.0;
	return (length(vec2(p.z - janela.x, p.y - janela.y) / janela.zw) - 1.0) * janela.w;
}

float borda_para_lama(vec3 p) {
	if (abs(p.x) < para_lama.w) return 1.0;
	return length(vec2(p.z - para_lama.x, p.y - para_lama.y)) - para_lama.z;
}

bool no_vidro(vec3 p) {
	return borda_vidro(p) < 0.0 || borda_janela(p) < 0.0;
}
