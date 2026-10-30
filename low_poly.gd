class_name LowPoly
## Ajudantes do estilo low poly dos cenários: facetar malhas (normal por face, as
## facetas aparecem com a luz do sol), material liso de cor chapada e material neon
## (emissão sem luz real). Tudo sem textura: nada cintila no headset e o custo fica
## só no número de triângulos.

## Cópia da malha com uma normal por triângulo (sombreamento chapado). Mantém o
## lado de fora de cada face pelo sentido das normais originais
static func facetar(malha: Mesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(malha, 0)
	st.deindex()
	var arrays := st.commit_to_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for k in range(0, v.size(), 3):
		var face := (v[k + 1] - v[k]).cross(v[k + 2] - v[k])
		if face.length_squared() < 1e-12:
			continue
		face = face.normalized()
		if face.dot(n[k] + n[k + 1] + n[k + 2]) < 0.0:
			face = -face
		n[k] = face
		n[k + 1] = face
		n[k + 2] = face
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TANGENT] = null
	var saida := ArrayMesh.new()
	saida.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return saida

## Cor chapada, fosca. `por_instancia`: a cor vem do MultiMesh (set_instance_color)
static func liso(cor: Color, por_instancia := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = cor
	material.roughness = 0.95
	material.metallic_specular = 0.2
	material.vertex_color_use_as_albedo = por_instancia
	return material

## Neon: sem sombreamento, só emissão (o glow do ambiente faz o halo, sem luz real)
static func neon(cor: Color, energia := 2.5) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = cor
	material.emission_enabled = true
	material.emission = cor
	material.emission_energy_multiplier = energia
	return material

## Um MultiMeshInstance3D com a malha em todas as transformações (uma chamada de
## desenho para todas). `cores`: uma por instância, ou vazio
static func espalhar(malha: Mesh, material: Material, transformacoes: Array[Transform3D], cores: Array[Color] = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cores.is_empty()
	mm.mesh = malha
	mm.instance_count = transformacoes.size()
	for k in transformacoes.size():
		mm.set_instance_transform(k, transformacoes[k])
		if mm.use_colors:
			mm.set_instance_color(k, cores[k])
	var no := MultiMeshInstance3D.new()
	no.multimesh = mm
	no.material_override = material
	return no
