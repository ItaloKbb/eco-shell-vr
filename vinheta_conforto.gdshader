shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, blend_mix, fog_disabled;

uniform float intensidade : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// VIEW é calculado separadamente para cada olho: o centro fica alinhado à visão.
	float borda = 1.0 - smoothstep(0.68, 0.88, VIEW.z);
	ALBEDO = vec3(0.0);
	ALPHA = borda * intensidade * 0.85;
}
