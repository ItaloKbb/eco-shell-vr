shader_type spatial;
render_mode cull_disabled;
// Asfalto das pistas de corrida, o mesmo em todos os mapas (cada pista passa a sua
// paleta, ver PistaCorrida.paleta). Estilo low poly + Tron:
//  - asfalto liso, só um degradê suave da borda (mais escura) para o meio;
//  - faixa de borda lisa na cor do mapa, sem zebra: listra de alto contraste
//    passando rápido no chão enjoa em VR;
//  - linhas de faixa contínuas e discretas (sem tracejado, que pisca a alta velocidade);
//  - filete neon na beira, pulsando devagar ao longo da pista (emissão, sem luz real);
//  - largada/chegada em xadrez grande.
// Sem ruído nem detalhe fino: toda borda é suavizada por fwidth, então nada cintila
// no headset nem de longe. Custo: só aritmética, sem textura (impacto baixo).
// UV.x = largura (0 a 1), UV.y = metros desde a amostra 0.

uniform float largura = 12.0;
// Onde ficam as linhas de largada e de chegada (m); no circuito fechado a chegada é
// a mesma linha depois de uma volta (= comprimento)
uniform float linha_largada = 0.0;
uniform float linha_chegada = 630.0;
uniform vec3 asfalto : source_color = vec3(0.23, 0.2, 0.25);
uniform vec3 faixa : source_color = vec3(0.91, 0.39, 0.23);
uniform vec3 linha : source_color = vec3(0.96, 0.9, 0.78);
uniform vec3 neon : source_color = vec3(0.18, 0.9, 1.0);
// Faixas de rolamento (linhas divisórias = faixas - 1)
uniform float faixas = 3.0;

// 1 dentro de [a, b], 0 fora, com borda suavizada pelo tamanho do pixel (w = fwidth(v),
// medido no fragment: derivadas só valem lá)
float banda(float v, float a, float b, float w) {
	return smoothstep(a - w, a + w, v) * (1.0 - smoothstep(b - w, b + w, v));
}

// Xadrez com filtro de caixa (Inigo Quilez): as casas viram cinza ao longe em vez de
// formar moiré
float xadrez(vec2 q, vec2 w) {
	vec2 i = 2.0 * (abs(fract((q - 0.5 * w) * 0.5) - 0.5) - abs(fract((q + 0.5 * w) * 0.5) - 0.5)) / w;
	return 0.5 - 0.5 * i.x * i.y;
}

void fragment() {
	float x = UV.x * largura;
	float d = UV.y;
	float borda = min(x, largura - x);
	float wx = fwidth(x) + 0.0001;
	float wb = fwidth(borda) + 0.0001;

	// Asfalto: mais escuro junto da faixa, clareando suave até o meio
	vec3 cor = asfalto * mix(0.82, 1.06, smoothstep(0.0, largura * 0.5, borda));
	float rugosidade = 0.85;
	float brilho = 0.0;

	// Linhas de faixa: contínuas, finas e com pouco contraste (70% da cor da linha)
	int divisorias = int(faixas) - 1;
	for (int k = 1; k <= divisorias; k++) {
		float centro = largura * float(k) / faixas;
		cor = mix(cor, mix(asfalto, linha, 0.7), banda(x, centro - 0.07, centro + 0.07, wx));
	}
	// Faixa de borda lisa, com uma linha clara separando do asfalto
	cor = mix(cor, faixa, banda(borda, 0.22, 1.0, wb));
	cor = mix(cor, linha, banda(borda, 1.0, 1.16, wb));

	// Largada/chegada: duas fileiras de casas de 1,5 m
	float ate_linha = min(abs(d - linha_largada), abs(d - linha_chegada));
	float na_linha = 1.0 - smoothstep(1.4, 1.5 + fwidth(d), ate_linha);
	// Derivadas fora do if (dentro de desvio elas ficam indefinidas na GPU)
	vec2 q = vec2(x, d - linha_largada + 1.5) / 1.5;
	float casa = xadrez(q, fwidth(q) + 0.0001);
	cor = mix(cor, mix(asfalto * 0.35, linha, casa), na_linha);
	rugosidade = mix(rugosidade, 0.6, na_linha);

	// Filete neon na beira: onda lenta (~80 m) correndo para a frente, sem piscar
	float pulso = 0.8 + 0.2 * sin(d * 0.08 - TIME * 2.5);
	float filete = 1.0 - smoothstep(0.22 - wb, 0.22 + wb, borda);
	cor = mix(cor, neon, filete);
	brilho = filete * pulso;

	ALBEDO = cor;
	ROUGHNESS = rugosidade;
	EMISSION = neon * brilho * 2.2;
}
