shader_type fog;

#include "res://fog_noise.gdshaderinc"

// Névoa de tempestade de luz: névoa rasteira + camada de nuvens baixas,
// com regiões coloridas na paleta e clarões que acendem a névoa por dentro.
// O ruído é ancorado no mundo, então a névoa não "anda junto" com o jogador.

uniform vec3 mist_color : source_color = vec3(0.35, 0.4, 0.75);
uniform vec3 color_warm : source_color = vec3(0.92, 0.36, 0.18); // #EB5C2E
uniform vec3 color_gold : source_color = vec3(0.96, 0.62, 0.2);  // #F59E33
uniform vec3 color_cold : source_color = vec3(0.18, 0.55, 1.0);  // #2F8DFF

uniform float mist_density = 0.3;
uniform float mist_height = 2.5;
uniform float cloud_density = 0.22;
uniform float cloud_base = 9.0;
uniform float cloud_top = 22.0;
uniform vec3 wind = vec3(0.6, 0.0, 0.35);

// Brilho constante da névoa e força dos clarões
uniform float glow = 0.3;
uniform float storm_energy = 5.0;
// Tamanho de cada célula de tempestade e frequência média dos clarões
uniform float storm_cell = 22.0;
uniform float storm_rate = 0.1;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Soma dos clarões das células vizinhas: sobe rápido, apaga suave
float storm(vec2 xz) {
	vec2 cell = floor(xz / storm_cell);
	float total = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 c = cell + vec2(float(x), float(y));
			float h = hash2(c);
			if (hash2(c + 11.0) < 0.45) {
				continue; // nem toda célula tem tempestade
			}
			vec2 center = (c + 0.25 + 0.5 * vec2(h, hash2(c + 3.7))) * storm_cell;
			float t = fract(TIME * storm_rate * (0.6 + h) + h * 7.0);
			float flash = smoothstep(0.0, 0.03, t) * exp(-t * 9.0);
			flash += 0.5 * smoothstep(0.07, 0.1, t) * exp(-max(t - 0.07, 0.0) * 12.0);
			float dist = length(xz - center) / (storm_cell * 0.6);
			total += flash * exp(-dist * dist * 2.0);
		}
	}
	return total;
}

void fog() {
	vec3 wp = WORLD_POSITION;

	float mist_n = fbm3((wp - wind * TIME) * vec3(0.07, 0.18, 0.07));
	float mist = mist_density * smoothstep(0.3, 0.8, mist_n) * exp(-max(wp.y, 0.0) / mist_height);

	float band = smoothstep(cloud_base, cloud_base + 3.0, wp.y) * (1.0 - smoothstep(cloud_top - 5.0, cloud_top, wp.y));
	float cloud_n = fbm3((wp - wind * TIME * 1.5) * 0.045 + vec3(5.0));
	float cloud = cloud_density * band * smoothstep(0.35, 0.75, cloud_n);

	float dens = mist + cloud;

	// Regiões de cor em grande escala, mudando devagar
	float region = fbm3(vec3(wp.xz * 0.015, TIME * 0.02));
	vec3 tint = mix(color_cold, color_warm, smoothstep(0.35, 0.6, region));
	tint = mix(tint, color_gold, smoothstep(0.65, 0.85, region));

	DENSITY = dens;
	ALBEDO = mist_color;
	EMISSION = tint * (glow + storm(wp.xz) * storm_energy) * clamp(dens * 4.0, 0.0, 1.0);
}
