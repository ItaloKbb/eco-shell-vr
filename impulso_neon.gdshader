shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Placa de turbo: setas (chevrons) correndo no sentido do impulso (-V do UV).
uniform vec3 base_color : source_color = vec3(0.03, 0.02, 0.06);
uniform vec3 arrow_color : source_color = vec3(1.0, 0.75, 0.1);
uniform float arrows = 4.0;
uniform float speed = 1.6;
uniform float emission_energy = 2.4;

void fragment() {
	vec2 uv = UV;
	float x = abs(uv.x - 0.5) * 2.0;
	// V invertido: a ponta aponta para a frente da placa
	float fase = fract(uv.y * arrows + x * 0.6 + TIME * speed);
	float seta = (1.0 - smoothstep(0.0, 0.05, abs(fase - 0.5) - 0.12)) * (1.0 - smoothstep(0.85, 0.95, x));
	float borda = 1.0 - smoothstep(0.9, 0.96, max(x, abs(uv.y - 0.5) * 2.0));
	vec3 color = base_color + arrow_color * seta + arrow_color * (1.0 - borda) * 0.6;
	ALBEDO = color;
	EMISSION = color * emission_energy;
}
