shader_type spatial;
// Pintura do Eco Shell 326: fibra azul envernizada, borracha preta em volta dos vidros,
// emenda da tampa traseira, faixa branca baixa, filete prateado no bico e no
// para-lama, filete neon que acende no modo energia e adesivos (SENAI, 326) projetados
// de um atlas gerado em eco_shell_adesivos.gd. Batidas amassam a casca e deixam riscos,
// fibra exposta e fuligem. A geometria vem de eco_shell_casco.gd;
// o mesmo shader pinta o interior (interior = true), fibra azul fosca sem adesivos.

#include "res://eco_shell_aberturas.gdshaderinc"

uniform bool interior = false;
uniform vec3 cor_lataria : source_color = vec3(0.09, 0.42, 0.82);
uniform vec3 cor_interior : source_color = vec3(0.04, 0.13, 0.27);
uniform vec3 cor_filete : source_color = vec3(0.1843, 0.5529, 1.0);
uniform float filete_altura = 0.3;
uniform float filete_largura = 0.012;
uniform float brilho = 3.0;
// 0 = rodando nas rodas, 1 = gerando a pista de energia (acende o filete)
uniform float energia = 0.0;
// Faixa branca: z inicial, z final, y inferior e superior (relativos ao eixo)
uniform vec4 faixa_branca = vec4(-0.45, 0.5, -0.13, -0.05);
uniform float emenda_z = 0.5;

// Preenchidos por eco_shell_adesivos.gd
uniform sampler2D adesivos : source_color, filter_linear_mipmap, repeat_disable;
uniform int qtd_adesivos = 0;
// Retângulo no atlas (u0, v0, u1, v1)
uniform vec4 adesivo_rect[8];
// Centro no plano de projeção, largura e altura (m)
uniform vec4 adesivo_pos[8];
uniform float adesivo_giro[8];
// 0 = nas duas laterais (plano ZY), 1 = no bico (plano XY)
uniform float adesivo_tipo[8];

// Batidas (preenchidas por eco_shell_casco.gd): xyz = ponto, w = intensidade
uniform vec4 marcas[6];
// Raio de uma batida forte (m) e profundidade máxima do amassado
const float RAIO_MARCA = 0.24;
const float FUNDO_AMASSADO = 0.06;

varying vec3 local;
varying vec3 normal_local;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

// Quanto cada ponto foi atingido (0 a 1), somando as batidas com queda suave
float atingido(vec3 p) {
	float total = 0.0;
	for (int i = 0; i < 6; i++) {
		float w = marcas[i].w;
		if (w > 0.0) {
			float r = RAIO_MARCA * (0.5 + 0.5 * w);
			total = max(total, w * (1.0 - smoothstep(0.0, r, distance(p, marcas[i].xyz))));
		}
	}
	return total;
}

void vertex() {
	local = VERTEX;
	normal_local = NORMAL;
	// Amassado: afunda a casca para dentro (no interior a normal já aponta para dentro)
	float a = atingido(VERTEX);
	VERTEX -= NORMAL * a * FUNDO_AMASSADO * (interior ? -1.0 : 1.0);
}

float banda(float v, float centro, float largura) {
	float d = abs(v - centro);
	return 1.0 - smoothstep(largura * 0.6, largura, d);
}

// Anel do lado de fora de uma abertura: d = distância da borda (m)
float contorno(float d, float largura) {
	return 1.0 - smoothstep(largura - 0.003, largura, d);
}

vec4 adesivo(int i, vec3 p, vec3 n) {
	vec4 r = adesivo_rect[i];
	vec4 pos = adesivo_pos[i];
	vec2 q;
	float mascara;
	if (adesivo_tipo[i] < 0.5) {
		// Visto de fora, a direita do observador é o bico no lado direito e a cauda no esquerdo
		q = vec2((p.z - pos.x) * (p.x > 0.0 ? -1.0 : 1.0), p.y - pos.y);
		mascara = smoothstep(0.35, 0.55, abs(n.x));
	} else {
		q = vec2(-p.x - pos.x, p.y - pos.y);
		mascara = smoothstep(0.3, 0.5, -n.z);
	}
	float c = cos(adesivo_giro[i]);
	float s = sin(adesivo_giro[i]);
	q = vec2(c * q.x + s * q.y, -s * q.x + c * q.y);
	vec2 st = q / pos.zw + 0.5;
	float dentro = step(0.0, st.x) * step(st.x, 1.0) * step(0.0, st.y) * step(st.y, 1.0);
	// O atlas sai do SubViewport com alfa pré-multiplicado
	return texture(adesivos, mix(r.xy, r.zw, vec2(clamp(st.x, 0.0, 1.0), 1.0 - clamp(st.y, 0.0, 1.0)))) * dentro * mascara;
}

void fragment() {
	vec3 p = local;
	float d_vidro = borda_vidro(p);
	float d_janela = borda_janela(p);
	float d_roda = borda_para_lama(p);
	if (d_vidro < 0.0 || d_janela < 0.0 || d_roda < 0.0) {
		discard;
	}
	vec3 n = normalize(normal_local);
	float y = p.y - centro_y;
	float laterais = smoothstep(0.35, 0.55, abs(n.x));

	// Borracha preta em volta do vidro do teto e das janelas; emenda da tampa traseira
	float borracha = max(contorno(d_vidro, 0.022), contorno(d_janela, 0.016));
	borracha = max(borracha, banda(p.z, emenda_z, 0.008) * step(faixa_branca.w, y));

	float branca = step(faixa_branca.x, p.z) * step(p.z, faixa_branca.y)
		* smoothstep(faixa_branca.z - 0.004, faixa_branca.z, y) * (1.0 - smoothstep(faixa_branca.w, faixa_branca.w + 0.004, y))
		* laterais;

	// Filete prateado: em volta do bico até o para-lama, e na borda do recorte da roda
	float prata = banda(y, -0.02, 0.008) * (1.0 - smoothstep(para_lama.x - para_lama.z * 0.6, para_lama.x - para_lama.z * 0.4, p.z));
	prata = max(prata, contorno(d_roda, 0.014));

	float corpo = smoothstep(0.06, 0.14, UV.x) * (1.0 - smoothstep(0.82, 0.92, UV.x));
	float filete = banda(UV.y, filete_altura, filete_largura) * corpo;
	float lanterna = smoothstep(0.993, 0.997, UV.x) * banda(UV.y, 0.0, 0.3);

	vec3 cor = cor_lataria;
	float metal = 0.05;
	float rugosidade = 0.3;
	cor = mix(cor, vec3(0.92), branca);
	cor = mix(cor, vec3(0.78, 0.8, 0.83), prata);
	metal = mix(metal, 0.9, prata);
	rugosidade = mix(rugosidade, 0.25, prata);
	// Filete apagado é um risco azul-escuro; com energia vira neon
	cor = mix(cor, mix(cor_lataria * 0.5, cor_filete, energia), filete);

	for (int i = 0; i < qtd_adesivos; i++) {
		vec4 a = adesivo(i, p, n);
		cor = cor * (1.0 - a.a) + a.rgb;
	}

	cor = mix(cor, vec3(0.015), borracha);
	rugosidade = mix(rugosidade, 0.8, borracha);

	// Batidas: riscos finos na direção do arrasto, fibra cinza exposta e fuligem no centro
	float riscos = 0.0;
	float estrago = 0.0;
	for (int i = 0; i < 6; i++) {
		float w = marcas[i].w;
		if (w > 0.0) {
			float r = RAIO_MARCA * (0.5 + 0.5 * w);
			float k = (1.0 - smoothstep(0.0, r, distance(p, marcas[i].xyz))) * w;
			estrago = max(estrago, k);
			float ang = hash(float(i) * 7.13 + marcas[i].x * 31.0) * PI;
			float coord = dot(p.zy + p.xx * 0.5, vec2(cos(ang), sin(ang))) * 140.0;
			float sorte = hash(floor(coord) + float(i) * 17.0);
			float linha = 1.0 - smoothstep(0.15, 0.35, abs(fract(coord) - 0.5));
			riscos = max(riscos, step(0.6, sorte) * linha * smoothstep(0.02, 0.25, k));
		}
	}
	cor = mix(cor, vec3(0.55, 0.56, 0.58), riscos * 0.85);
	cor = mix(cor, vec3(0.02, 0.018, 0.015), smoothstep(0.2, 0.7, estrago) * 0.9);
	rugosidade = mix(rugosidade, 0.85, estrago);
	float verniz = (1.0 - borracha) * (1.0 - estrago);

	vec3 luz_traseira = vec3(1.0, 0.05, 0.05) * lanterna;
	cor = mix(cor, luz_traseira, lanterna);

	if (interior) {
		ALBEDO = mix(cor_interior, vec3(0.015), borracha);
		ROUGHNESS = 0.8;
	} else {
		ALBEDO = cor;
		METALLIC = metal;
		ROUGHNESS = rugosidade;
		CLEARCOAT = verniz;
		CLEARCOAT_ROUGHNESS = 0.08;
		EMISSION = (luz_traseira + cor_filete * filete * energia) * brilho;
	}
}
