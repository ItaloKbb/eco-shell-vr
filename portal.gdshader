shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Vórtice do portal, desenhado num quad (plano XY local, meia largura = `tamanho`).
// Borda: anel brilhante com chamas girando para fora. Dentro: um túnel em três camadas
// de profundidade, cada uma vista pela posição da câmera no espaço do portal (paralaxe
// de verdade: em VR cada olho vê o túnel de um ângulo e ele tem fundo). Nas camadas,
// faixas em espiral e estrelas correm para o centro, que é escuro (o "horizonte").

uniform vec3 cor : source_color = vec3(0.1, 0.85, 1.0);
uniform float tamanho = 6.0;
// Borda do vórtice, em fração da meia largura
uniform float raio = 0.75;
uniform float intensidade = 1.0;

varying vec3 local;
varying vec3 camera_local;

void vertex() {
	local = VERTEX;
	camera_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Ruído de valor periódico em x (período n): não emenda ao dar a volta no ângulo
float ruido(vec2 p, float n) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(vec2(mod(i.x, n), i.y));
	float b = hash(vec2(mod(i.x + 1.0, n), i.y));
	float c = hash(vec2(mod(i.x, n), i.y + 1.0));
	float d = hash(vec2(mod(i.x + 1.0, n), i.y + 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, float n) {
	return 0.62 * ruido(p, n) + 0.38 * ruido(p * 2.0 + vec2(0.0, 7.3), n * 2.0);
}

// Camada do túnel a `fundo` metros atrás do plano: onde o raio de visão desta câmera,
// passando pelo ponto do quad, chega naquela profundidade
vec3 camada(vec2 plano, float fundo, float t) {
	// Deslocamento da paralaxe, limitado: visto de lado ele cresce sem fim e o padrão tremeria
	vec2 desloca = (plano - camera_local.xy) * fundo / max(abs(camera_local.z), 0.05);
	desloca *= min(1.0, tamanho * 1.5 / max(length(desloca), 0.001));
	vec2 xy = plano + desloca;
	vec2 q = xy / tamanho;
	float r = length(q) / raio;
	float a = atan(q.y, q.x) / TAU + 0.5;
	float v = log(max(r, 0.001));
	// Espiral logarítmica girando e escorrendo para dentro
	float giro = a + v * 0.35 - t * 0.07;
	float n = fbm(vec2(giro * 12.0, v * 3.0 - t * 1.1), 12.0);
	float faixas = smoothstep(0.42, 0.92, n);
	// Estrelas sendo sugadas
	vec2 c = vec2(giro * 40.0, v * 6.0 - t * 1.6);
	vec2 id = floor(c);
	float estrela = step(0.94, hash(vec2(mod(id.x, 40.0), id.y))) * (1.0 - smoothstep(0.0, 0.14, length(fract(c) - 0.5)));
	float escuro = smoothstep(0.08, 0.95, r);
	return (cor * faixas + vec3(0.9, 0.95, 1.0) * estrela) * escuro;
}

void fragment() {
	vec2 plano = local.xy;
	vec2 q = plano / tamanho;
	float r = length(q) / raio;
	float a = atan(q.y, q.x) / TAU + 0.5;
	float t = TIME;

	// Borda: anel fino e chamas lambendo para fora, girando devagar
	float n = fbm(vec2((a + t * 0.03) * 16.0, r * 4.0 - t * 1.4), 16.0);
	float fora = r - 1.0;
	float chama = fora > 0.0 ? (1.0 - smoothstep(0.0, 0.05 + 0.32 * n, fora)) * smoothstep(0.25, 0.65, n) : 0.0;
	float anel = exp(-pow(fora / 0.035, 2.0));

	vec3 luz = vec3(0.0);
	if (r < 1.0) {
		// Quanto de frente a câmera está: de lado, as camadas fundas somem suavemente
		vec3 olhar = camera_local - local;
		float frente = smoothstep(0.08, 0.35, abs(olhar.z) / max(length(olhar), 0.001));
		luz += camada(plano, 1.0, t) * mix(0.6, 1.0, frente);
		luz += camada(plano, 3.5, t) * 0.55 * frente;
		luz += camada(plano, 9.0, t) * 0.3 * frente;
		// Brilho rodando por dentro da borda
		float dentro = fbm(vec2((a - t * 0.06) * 16.0, r * 6.0 + t * 0.8), 16.0);
		luz += cor * pow(smoothstep(0.5, 1.0, r), 3.0) * (0.5 + 1.2 * dentro);
	}
	luz += cor * (anel * 2.6 + chama * 1.7) + vec3(1.0) * anel * 0.5;

	float alfa = r < 1.0 ? 1.0 : clamp(chama * 0.9 + anel, 0.0, 1.0);
	if (alfa < 0.01) {
		discard;
	}
	ALBEDO = luz * intensidade;
	ALPHA = alfa;
}
