shader_type spatial;
render_mode cull_disabled;
// Roda de bicicleta do Eco Shell: pneu preto, faixa branca no aro, aro preto e raios
// finos vazados (dá para ver através da roda). Desenhada nas tampas do CylinderMesh,
// cujo eixo é o Y local. No modo planador (led = 1) vira disco de levitação: anel de
// LED tracejado no aro (gira junto), faixa acesa no meio do pneu e raios iluminados.

uniform float raio = 0.245;
uniform int raios = 24;
// Largura dos raios (m)
uniform float espessura = 0.004;
uniform float led = 0.0;
uniform vec3 cor_led : source_color = vec3(0.1843, 0.5529, 1.0);
uniform float brilho = 4.0;

varying vec3 local;
varying vec3 normal_local;

void vertex() {
	local = VERTEX;
	normal_local = NORMAL;
}

void fragment() {
	float r = length(local.xz) / raio;
	float ang = atan(local.z, local.x);
	vec3 cor = vec3(0.02);
	float rugosidade = 0.85;
	float metal = 0.0;
	float luz = 0.0;
	if (abs(normal_local.y) > 0.5) {
		if (r < 0.8 && r > 0.13) {
			// Distância (m) até o raio mais próximo
			float setor = TAU / float(raios);
			float d = abs(fract(ang / setor + 0.5) - 0.5) * setor * length(local.xz);
			if (d > espessura) {
				discard;
			}
			cor = vec3(0.6, 0.62, 0.65);
			metal = 0.9;
			rugosidade = 0.3;
			luz = 0.25;
		} else if (r <= 0.13) {
			cor = vec3(0.15, 0.15, 0.17);
			metal = 0.8;
			rugosidade = 0.4;
			luz = 0.6 * step(r, 0.07);
		} else if (r < 0.88) {
			// Aro preto; aceso, vira um anel tracejado
			cor = vec3(0.03);
			rugosidade = 0.4;
			luz = step(0.45, fract(ang / TAU * 16.0)) * smoothstep(0.81, 0.83, r) * (1.0 - smoothstep(0.86, 0.875, r));
		} else if (r < 0.905) {
			cor = vec3(0.85);
			rugosidade = 0.5;
			luz = 1.0;
		}
	} else {
		// Banda de rodagem: faixa de LED no meio
		luz = 1.0 - smoothstep(0.003, 0.006, abs(local.y));
	}
	ALBEDO = cor;
	METALLIC = metal;
	ROUGHNESS = rugosidade;
	EMISSION = cor_led * luz * led * brilho;
}
