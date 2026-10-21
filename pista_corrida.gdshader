shader_type spatial;
render_mode cull_disabled;
// Asfalto da pista do deserto: grão fino, faixas brancas nas bordas, zebra vermelha e
// branca junto delas, linha central amarela tracejada e a linha de largada/chegada
// quadriculada. UV.x = largura (0 a 1), UV.y = metros desde a largada.

uniform float comprimento = 630.0;
uniform vec3 asfalto : source_color = vec3(0.13, 0.13, 0.14);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float x = UV.x;
	float d = UV.y;
	// Grão do asfalto e o "caminho" mais escuro de borracha no meio de cada faixa
	float grao = hash(floor(vec2(x * 240.0, d * 20.0))) * 0.06;
	float borracha = exp(-pow((abs(x - 0.5) - 0.22) / 0.08, 2.0)) * 0.04;
	vec3 cor = asfalto + grao - borracha;
	float rugosidade = 0.85;

	// Zebra nas bordas (blocos de 2 m) e faixa branca logo depois
	float borda = min(x, 1.0 - x);
	if (borda < 0.05) {
		cor = mod(floor(d / 2.0), 2.0) < 1.0 ? vec3(0.75, 0.08, 0.06) : vec3(0.9);
		rugosidade = 0.6;
	} else if (borda < 0.065) {
		cor = vec3(0.9);
	}
	// Linha central amarela tracejada
	if (abs(x - 0.5) < 0.008 && mod(d, 6.0) < 3.0) {
		cor = vec3(0.95, 0.75, 0.1);
	}
	// Largada/chegada: duas fileiras de xadrez
	float largada = min(d, comprimento - d);
	if (largada < 1.6) {
		float casa = mod(floor(x * 16.0) + floor(d / 0.8), 2.0);
		cor = casa < 1.0 ? vec3(0.02) : vec3(0.92);
	}
	ALBEDO = cor;
	ROUGHNESS = rugosidade;
}
