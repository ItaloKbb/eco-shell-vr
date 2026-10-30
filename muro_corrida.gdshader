shader_type spatial;
render_mode cull_disabled;
// Muro de proteção da pista, na paleta de cada mapa (PistaCorrida.paleta): corpo liso,
// rodapé mais escuro, filete neon perto do alto e o topo todo em neon (o contorno do
// circuito fica legível de longe e à noite). Sem blocos alternados: listras de alto
// contraste passando rápido ao lado enjoam em VR. Só aritmética (impacto baixo).
// UV.x = 0 em baixo a 1 em cima, UV.y = metros ao longo da pista.

uniform vec3 corpo : source_color = vec3(0.95, 0.92, 0.86);
uniform vec3 neon : source_color = vec3(0.18, 0.9, 1.0);

varying vec3 normal_mundo;

void vertex() {
	normal_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float w = fwidth(UV.x) + 0.0001;
	// Rodapé escuro (onde o pneu raspa), com transição suave
	vec3 cor = mix(corpo * 0.45, corpo, smoothstep(0.12, 0.2, UV.x));
	// Filete neon nas faces de lado, logo abaixo do topo
	float filete = smoothstep(0.78 - w, 0.78 + w, UV.x) * (1.0 - smoothstep(0.9 - w, 0.9 + w, UV.x));
	// Topo do muro inteiro aceso
	float topo = smoothstep(0.6, 0.8, normalize(normal_mundo).y);
	float aceso = max(filete, topo);
	ALBEDO = mix(cor, neon, aceso);
	ROUGHNESS = 0.7;
	EMISSION = neon * aceso * 1.6;
}
