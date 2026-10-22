class_name RushContactShadow
extends RefCounted
static var material: ShaderMaterial
static func create(parent: Node3D, dimensions: Vector2) -> MeshInstance3D:
	if material == null:
		material = ShaderMaterial.new()
		material.shader = preload("res://Vehicle/contact_shadow.gdshader")
	var mesh := PlaneMesh.new()
	mesh.size = dimensions
	var shadow := MeshInstance3D.new()
	shadow.mesh = mesh
	shadow.material_override = material
	shadow.position.y = 0.008
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shadow)
	return shadow
