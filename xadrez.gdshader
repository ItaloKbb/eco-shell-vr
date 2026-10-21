shader_type spatial;
// Bandeira quadriculada do pórtico de largada

void fragment() {
	float casa = mod(floor(UV.x * 24.0) + floor(UV.y * 6.0), 2.0);
	ALBEDO = casa < 1.0 ? vec3(0.02) : vec3(0.95);
	ROUGHNESS = 0.5;
}
