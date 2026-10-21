shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Piso contínuo pensado para VR e compressão do Quest Link: formas grandes,
// transições suaves e animação lenta, sem ruído fino ou cintilação por pixel.
uniform vec3 base_color : source_color = vec3(0.008, 0.014, 0.045);
uniform vec3 grid_color : source_color = vec3(0.02, 0.52, 0.95);
uniform vec3 accent_color : source_color = vec3(0.95, 0.16, 0.82);
uniform float grid_size = 8.0;
uniform float line_width = 0.055;
uniform float emission_energy = 1.65;
uniform float flow_speed = 2.2;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float grid_line(vec2 p, float width) {
	vec2 cell = abs(fract(p) - 0.5);
	vec2 edge = 0.5 - cell;
	vec2 aa = max(fwidth(p), vec2(0.0001));
	vec2 line = 1.0 - smoothstep(vec2(width), vec2(width) + aa * 1.4, edge);
	return max(line.x, line.y);
}

void fragment() {
	vec2 cell_uv = world_xz / grid_size;
	float grid = grid_line(cell_uv, line_width);

	// Faixas largas percorrem o chão sem mover a grade. Assim a imagem mantém
	// referências estáveis entre frames e o encoder só precisa atualizar o brilho.
	float phase = world_xz.y * 0.045 - TIME * flow_speed;
	float wave = pow(max(0.0, 1.0 - abs(sin(phase))), 10.0);
	float cross_wave = pow(max(0.0, 1.0 - abs(sin(world_xz.x * 0.028 + TIME * 0.42))), 18.0);
	float flow = max(wave * 0.55, cross_wave * 0.22);

	// Uma leve vinheta por célula dá volume sem criar detalhes pequenos.
	vec2 center = abs(fract(cell_uv) - 0.5) * 2.0;
	float panel = 1.0 - smoothstep(0.25, 1.0, max(center.x, center.y));
	vec3 color = base_color * (0.78 + panel * 0.22);
	color += grid_color * grid * (0.72 + flow * 0.55);
	color += accent_color * flow * (0.08 + grid * 0.32);

	ALBEDO = color;
	EMISSION = color * emission_energy;
	ROUGHNESS = 0.72;
}
