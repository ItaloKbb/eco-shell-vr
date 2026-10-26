shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

// Túnel de energia do loading (transicao.gd): um funil visto por dentro, com braços em
// espiral girando, filetes correndo na direção do piloto, anéis passando e um núcleo
// branco no fundo. O script integra `fluxo` (distância percorrida) e `giro`, então
// mudar a velocidade nunca dá salto na imagem. UV.y: 0 = fundo do túnel, 1 = perto.
uniform vec3 cor : source_color = vec3(0.3, 0.8, 1.0);
uniform float intensidade = 0.0;
uniform float fluxo = 0.0;
uniform float giro = 0.0;
// Quantos braços de espiral, quanto eles torcem ao longo do túnel e a densidade de filetes
uniform float bracos = 3.0;
uniform float torcao = 2.5;
uniform float colunas = 56.0;
// Clarão da saída (0 a 1): tudo puxa para o branco
uniform float clarao = 0.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	float a = UV.x;
	float z = UV.y;
	// Braços em espiral: faixas largas e suaves girando
	float espiral = fract(a * bracos + z * torcao + giro);
	float braco = smoothstep(0.0, 0.08, espiral) * (1.0 - smoothstep(0.14, 0.34, espiral));
	// Filetes: cada coluna com sua fase e velocidade, correndo para perto (z crescendo)
	float coluna = floor(a * colunas);
	float fase = hash(coluna);
	float rapidez = 0.7 + 0.6 * hash(coluna + 17.0);
	float corrida = fract(z * 2.0 - fluxo * rapidez + fase);
	float centro = abs(fract(a * colunas) - 0.5) * 2.0;
	float filete = smoothstep(0.75, 1.0, corrida) * (1.0 - smoothstep(0.15, 0.5, centro)) * step(0.45, hash(coluna + 3.0));
	// Anéis passando
	float anel = pow(abs(sin((z * 6.0 - fluxo * 0.8) * 3.14159)), 40.0);
	// Fundo brilhante (núcleo) e a boca do túnel some suave perto do piloto
	float nucleo = 1.0 - smoothstep(0.0, 0.22, z);
	float boca = 1.0 - smoothstep(0.75, 1.0, z);
	// Escuro entre os braços: o contraste é o que dá a sensação de velocidade
	vec3 c = cor * (braco * 0.32 + anel * 0.18 + 0.01) + mix(cor, vec3(1.0), 0.5) * filete * 0.9;
	c += mix(cor, vec3(1.0), 0.75) * pow(nucleo, 3.0) * 1.4;
	c = mix(c, vec3(1.0), clarao * (0.4 + 0.6 * (1.0 - z)));
	ALBEDO = c * boca * intensidade;
}
