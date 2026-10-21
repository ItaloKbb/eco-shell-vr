shader_type spatial;
// Areia do deserto: ondulações finas do vento, tons mais escuros nos vales das dunas e
// um brilho de grão de quartzo que pisca conforme se move.

uniform vec3 areia : source_color = vec3(0.86, 0.66, 0.42);
uniform vec3 sombra : source_color = vec3(0.7, 0.48, 0.3);

varying vec3 mundo;

void vertex() {
	mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = mundo.xz;
	// Ondulações do vento: listras finas tortas
	float onda = sin(p.x * 1.7 + p.y * 0.6 + sin(p.y * 0.15) * 3.0) * 0.5 + 0.5;
	float vale = smoothstep(0.0, 6.0, mundo.y);
	vec3 cor = mix(sombra, areia, 0.55 + 0.45 * vale);
	cor *= 0.92 + 0.08 * onda;
	// Brilho de grão
	float brilho = step(0.995, hash(floor(p * 18.0))) * 0.5;
	ALBEDO = cor + brilho;
	ROUGHNESS = 0.95;
}
