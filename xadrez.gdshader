shader_type spatial;
// Bandeira quadriculada do pórtico de largada: casas grandes com filtro de caixa
// (de longe viram cinza em vez de moiré) e borda neon na cor da pista

uniform vec3 neon : source_color = vec3(0.18, 0.9, 1.0);

float xadrez(vec2 q, vec2 w) {
	vec2 i = 2.0 * (abs(fract((q - 0.5 * w) * 0.5) - 0.5) - abs(fract((q + 0.5 * w) * 0.5) - 0.5)) / w;
	return 0.5 - 0.5 * i.x * i.y;
}

void fragment() {
	vec2 q = vec2(UV.x * 12.0, UV.y * 3.0);
	float casa = xadrez(q, fwidth(q) + 0.0001);
	vec3 cor = mix(vec3(0.05, 0.05, 0.07), vec3(0.95), casa);
	// Filete aceso em cima e embaixo da viga
	float w = fwidth(UV.y) + 0.0001;
	float borda = 1.0 - smoothstep(0.06 - w, 0.06 + w, min(UV.y, 1.0 - UV.y));
	ALBEDO = mix(cor, neon, borda);
	ROUGHNESS = 0.5;
	EMISSION = neon * borda * 1.6;
}
