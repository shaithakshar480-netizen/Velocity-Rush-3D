class_name RushInteriorGeometry
extends RefCounted
## Rounded lofts and ergonomic sweeps, built once before driving. No physics bodies.
static func shell(parent: Node3D, at: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	var outline := PackedVector2Array()
	var radius := minf(size_value.x,size_value.y)*.23
	for corner: int in 4:
		var angle := float(corner)*PI*.5
		var center := Vector2((1.0 if corner in [0,3] else -1.0)*(size_value.x*.5-radius),(1.0 if corner<2 else -1.0)*(size_value.y*.5-radius))
		for step: int in 4:
			var arc := angle+float(step)/3.0*PI*.5
			outline.append(center+Vector2(cos(arc),sin(arc))*radius)
	return panel(parent,at,outline,size_value.z,material)

static func panel(parent: Node3D, at: Vector3, outline: PackedVector2Array, depth: float, material: Material) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := outline.size()
	# Beveled face, shoulder, rounded sidewall, back. Clockwise front winding.
	var scales: Array[float] = [.91,1.0,1.0,.91]
	var zs: Array[float] = [depth*.5,depth*.30,-depth*.30,-depth*.5]
	for ring: int in 3:
		for i: int in n:
			var j := (i+1)%n
			var a := Vector3(outline[i].x*scales[ring],outline[i].y*scales[ring],zs[ring])
			var b := Vector3(outline[j].x*scales[ring],outline[j].y*scales[ring],zs[ring])
			var c := Vector3(outline[j].x*scales[ring+1],outline[j].y*scales[ring+1],zs[ring+1])
			var d := Vector3(outline[i].x*scales[ring+1],outline[i].y*scales[ring+1],zs[ring+1])
			var normal := Vector3(outline[i].x+outline[j].x,outline[i].y+outline[j].y,depth*(1-ring)*2).normalized()
			_triangle(surface,a,b,c,normal)
			_triangle(surface,a,c,d,normal)
	for i: int in n:
		var j := (i+1)%n
		_triangle(surface,Vector3(0,0,depth*.5),Vector3(outline[j].x*.91,outline[j].y*.91,depth*.5),Vector3(outline[i].x*.91,outline[i].y*.91,depth*.5),Vector3.BACK)
		_triangle(surface,Vector3(0,0,-depth*.5),Vector3(outline[i].x*.91,outline[i].y*.91,-depth*.5),Vector3(outline[j].x*.91,outline[j].y*.91,-depth*.5),Vector3.FORWARD)
	return _instance(parent,at,surface.commit(),material)

static func sweep(parent: Node3D, path: PackedVector3Array, radii: PackedFloat32Array, material: Material, closed: bool = false) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in (path.size() if closed else path.size()-1):
		var next := (i+1)%path.size()
		var tangent := (path[next]-path[i]).normalized()
		var across := Vector3(-tangent.y,tangent.x,0).normalized()
		for side: int in 10:
			var angle := TAU*float(side)/10.0
			var angle_next := TAU*float(side+1)/10.0
			var na := across*cos(angle)+Vector3.BACK*sin(angle)
			var nb := across*cos(angle_next)+Vector3.BACK*sin(angle_next)
			var a := path[i]+na*radii[i]
			var b := path[next]+na*radii[next]
			var c := path[next]+nb*radii[next]
			var d := path[i]+nb*radii[i]
			_triangle(surface,a,b,c,(na+nb).normalized())
			_triangle(surface,a,c,d,(na+nb).normalized())
	return _instance(parent,Vector3.ZERO,surface.commit(),material)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	surface.set_normal(normal)
	for point: Vector3 in [a,b,c]:
		surface.set_uv(Vector2(point.x,point.y)*8.0)
		surface.add_vertex(point)

static func _instance(parent: Node3D, at: Vector3, mesh: ArrayMesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	instance.position = at
	return instance

static func merge_direct(parent: Node3D, excluded: Array[MeshInstance3D] = []) -> void:
	var groups: Dictionary = {}
	var originals: Array[MeshInstance3D] = []
	for child: Node in parent.get_children():
		if child is MeshInstance3D and child.mesh is ArrayMesh and child not in excluded:
			var material: Material = child.material_override
			if not groups.has(material):
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[material] = surface
			var builder: SurfaceTool = groups[material]
			builder.append_from(child.mesh,0,child.transform)
			originals.append(child)
	for material: Material in groups:
		var builder: SurfaceTool = groups[material]
		_instance(parent,Vector3.ZERO,builder.commit(),material)
	for original: MeshInstance3D in originals:
		parent.remove_child(original)
		original.free()
