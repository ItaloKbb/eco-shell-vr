shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
// Casca da esfera de nascimento, vista por dentro: grade hexagonal escura (a mesma
// linguagem do mundo) com ondas de energia correndo para a saída, que brilha como uma
// porta. `carga` (0 a 1) acelera as ondas e esquenta as linhas de ciano para âmbar a
// partir da saída. `ruptura` (0 a 1) estilhaça a casca célula por célula, abrindo da
// saída para trás, com as bordas em brasa.

uniform float carga : hint_range(0.0, 1.0) = 0.0;
uniform float ruptura : hint_range(0.0, 1.0) = 0.0;
// VR: menos brilho e sem cintilação rápida
uniform float intensidade = 1.0;
uniform float cintilar = 1.0;
uniform vec3 cor_fundo : source_color = vec3(0.012, 0.025, 0.07);
uniform vec3 cor_linha : source_color = vec3(0.15, 0.62, 1.0);
uniform vec3 cor_quente : source_color = vec3(1.0, 0.6, 0.22);
// Direção da saída no espaço local da esfera
uniform vec3 saida = vec3(0.0, 0.0, -1.0);

// Colunas de hexágonos na volta do equador (inteiro: sem emenda no atan)
const float COLUNAS = 44.0;
const vec2 PASSO = vec2(1.0, 1.7320508);

varying vec3 local;

void vertex() {
	local = VERTEX;
}

float sorteio(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Longitude/latitude da grade de volta para uma direção na esfera
vec3 direcao(vec2 uv) {
	vec2 ang = uv * (TAU / COLUNAS);
	return vec3(cos(ang.y) * cos(ang.x), sin(ang.y), cos(ang.y) * sin(ang.x));
}

void fragment() {
	vec3 p = normalize(local);
	vec3 s = normalize(saida);
	float t = TIME;
	vec2 uv = vec2(atan(p.z, p.x), asin(clamp(p.y, -1.0, 1.0))) * (COLUNAS / TAU);

	// Grade hexagonal: centro mais próximo entre as duas redes deslocadas
	vec2 a = mod(uv, PASSO) - PASSO * 0.5;
	vec2 b = mod(uv - PASSO * 0.5, PASSO) - PASSO * 0.5;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	vec2 id = uv - gv;
	vec2 q = abs(gv);
	float ate_borda = 0.5 - max(dot(q, normalize(PASSO)), q.x);
	float w = fwidth(uv.y);
	// Nos polos as células espremem: a grade some suavemente
	float polo = 1.0 - smoothstep(0.7, 0.92, abs(p.y));
	float linha = (1.0 - smoothstep(0.012, 0.035 + w, ate_borda)) * polo;
	float sorte = sorteio(id);

	float ate_saida = acos(clamp(dot(p, s), -1.0, 1.0));
	float celula_saida = acos(clamp(dot(direcao(id), s), -1.0, 1.0));

	// Fundo: mais claro no horizonte, dá volume à casca
	float horizonte = 1.0 - abs(p.y);
	vec3 cor = cor_fundo * (0.5 + 0.9 * horizonte * horizonte);
	// Algumas células acendem devagar, ao acaso
	float acesa = smoothstep(0.93, 1.0, 0.5 + 0.5 * sin(t * 0.6 + sorte * 60.0)) * polo;
	cor += cor_linha * acesa * 0.06 * (1.0 - smoothstep(0.0, 1.0, ate_borda * 4.0) * 0.5);

	// Ondas viajando para a saída (fase cresce com o tempo: a frente anda até ela)
	float vel = 1.0 + carga * 5.0;
	float onda = pow(0.5 + 0.5 * sin(ate_saida * 7.0 + t * vel), 8.0);
	float calor = clamp(carga * 2.4 - ate_saida * 1.1, 0.0, 1.0) * smoothstep(0.2, 0.6, carga);
	vec3 cor_l = mix(cor_linha, cor_quente, calor);
	cor += cor_l * linha * (0.22 + onda * (0.35 + carga * 1.2));

	// A porta: halo na saída que abre e esquenta com a carga
	float porta = exp(-ate_saida * ate_saida * mix(30.0, 7.0, carga));
	cor += mix(cor_linha, vec3(1.0, 0.82, 0.55), carga) * porta * (0.2 + carga * 0.9);

	// Perto do fim, células em volta da porta trincam e piscam
	float trinca = smoothstep(0.75, 1.0, carga) * step(sorte, 0.4) * (1.0 - smoothstep(0.4, 1.0, celula_saida));
	trinca *= mix(1.0, 0.65 + 0.35 * sin(t * 28.0 + sorte * 12.0), cintilar);
	cor += cor_quente * trinca * (0.25 + linha);

	// Ruptura: cada célula cai inteira, da saída para trás
	if (ruptura > 0.0) {
		float ordem = celula_saida + sorte * 0.5;
		float limiar = ruptura * (PI + 0.9) - 0.2;
		if (ordem < limiar) {
			discard;
		}
		float brasa = 1.0 - smoothstep(0.0, 0.45, ordem - limiar);
		cor += vec3(1.0, 0.72, 0.4) * brasa * (0.6 + 2.0 * linha);
	}

	ALBEDO = cor * intensidade;
}
