class_name RushRoadBatcher
extends RefCounted
## Boot-only consolidation: varied static boxes become unit-box instances per material.
static var unit_box: BoxMesh
static func merge(parent: Node3D) -> void:
	if unit_box==null:
		unit_box = BoxMesh.new()
		unit_box.size = Vector3.ONE
	var batches: Dictionary = {}
	var materials: Dictionary = {}
	var obsolete: Array[Node] = []
	for child: Node in parent.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and child.get_child_count()==0:
			var mat: Material = child.material_override
			if mat == null:
				continue
			var key := mat.get_instance_id()
			if not batches.has(key):
				batches[key] = []
				materials[key] = mat
			var box := child.mesh as BoxMesh
			var pose: Transform3D = child.transform
			pose.basis = pose.basis.scaled(box.size)
			batches[key].append(pose)
			obsolete.append(child)
	for key: int in batches:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = unit_box
		multi.instance_count = batches[key].size()
		for i: int in multi.instance_count:
			multi.set_instance_transform(i,batches[key][i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.material_override = materials[key]
		parent.add_child(node)
	for child: Node in obsolete:
		child.free()
