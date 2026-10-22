class_name RoadGeometry
extends RefCounted

static func material(color: Color, metallic: float = 0.0, roughness: float = 0.65) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat

static func box(parent: Node3D, at: Vector3, dimensions: Vector3, mat: Material, solid: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	parent.add_child(instance)
	instance.position = at
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = dimensions
		shape.shape = box_shape
		body.add_child(shape)
		instance.add_child(body)
	return instance

static func repeated_boxes(parent: Node3D, transforms: Array[Transform3D], dimensions: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = mat
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i: int in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	parent.add_child(instance)
