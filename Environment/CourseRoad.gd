class_name RushCourseRoad
extends Node3D
signal preparation_progress(fraction: float)
## One-time road baking. Render slots recycle cached meshes; collision never recycles.
var highway: Highway
var course: RushSampledCourse
var cached_tiles: Dictionary = {}
var slots: Array[MeshInstance3D] = []
var sources: Array[Array] = []
var hidden_sources: Array[GeometryInstance3D] = []
var original_visibility: Array[bool] = []
var collision_root: Node3D
var enabled: bool = false
var prepared_length: float = -1.0
var wet_material: ShaderMaterial
var preparing: bool = false
const MARGIN_CELLS: int = 9
# Yield by elapsed work, rather than paying one display frame per tiny tile.
const PREPARE_BUDGET_USEC: int = 4000
const PREPARE_MAX_TILES: int = 4

func capture(owner_highway: Highway) -> void:
	highway = owner_highway
	for chunk: Node3D in highway.chunks:
		var collected: Array = []
		for child: Node in chunk.get_children():
			if child.is_queued_for_deletion(): continue
			if child is MeshInstance3D or child is MultiMeshInstance3D:
				collected.append(child)
				hidden_sources.append(child)
				original_visibility.append(child.visible)
		sources.append(collected)
		var slot := MeshInstance3D.new()
		slot.name = "CachedCourseRoad"
		slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		slot.visible = false
		chunk.add_child(slot)
		slots.append(slot)
	collision_root = Node3D.new()
	collision_root.name = "StationaryCourseCollision"
	add_child(collision_root)

func prepare(value: RushSampledCourse) -> void:
	course = value
	if is_equal_approx(prepared_length,course.length):
		preparation_progress.emit(1.0)
		return
	preparing = true
	preparation_progress.emit(0.0)
	cached_tiles.clear()
	for child: Node in collision_root.get_children():
		collision_root.remove_child(child)
		child.queue_free()
	wet_material = highway.asphalt.duplicate() as ShaderMaterial
	wet_material.set_shader_parameter("course_coordinates",true)
	var last: int = int(ceil(course.length/Highway.LENGTH))+MARGIN_CELLS
	# Present loading UI before the first geometry batch.
	await get_tree().process_frame
	var batch_started: int = Time.get_ticks_usec()
	var batch_tiles: int = 0
	for cell: int in range(-MARGIN_CELLS,last+1):
		var template: int = posmod(-cell,Highway.COUNT)
		cached_tiles[cell] = _bake_tile(sources[template],-float(cell)*Highway.LENGTH)
		_build_collision(-float(cell)*Highway.LENGTH)
		preparation_progress.emit(float(cell+MARGIN_CELLS+1)/float(last+MARGIN_CELLS+1))
		batch_tiles += 1
		# Heavy tiles still yield immediately; cheap tiles share a bounded slice.
		# One tile is indivisible, so its own bake cost can exceed this budget.
		if cell<last and (batch_tiles>=PREPARE_MAX_TILES or Time.get_ticks_usec()-batch_started>=PREPARE_BUDGET_USEC):
			await get_tree().process_frame
			batch_started = Time.get_ticks_usec()
			batch_tiles = 0
	prepared_length = course.length
	preparing = false

func set_enabled(value: bool) -> void:
	enabled = value
	if course!=null: collision_root.position.z = course.origin_z
	for i: int in hidden_sources.size():
		hidden_sources[i].visible = false if value else original_visibility[i]
	for slot: MeshInstance3D in slots: slot.visible = value
	for body: Node in collision_root.get_children():
		(body as StaticBody3D).collision_layer = int(body.get_meta("course_layer")) if value else 0
	if not value:
		for chunk: Node3D in highway.chunks: _dress(chunk,chunk,true)

func update_slot(slot: int, route_z: float) -> void:
	if not enabled: return
	var cell: int = int(round((course.origin_z-route_z)/Highway.LENGTH))
	var last: int = int(ceil(course.length/Highway.LENGTH))+MARGIN_CELLS
	# Beyond either end the sampled path extends as a straight, flat road.
	slots[slot].mesh = cached_tiles.get(clampi(cell,-MARGIN_CELLS,last)) as ArrayMesh
	_dress(highway.chunks[slot],highway.chunks[slot],false)

func refresh_dressing() -> void:
	if not enabled: return
	for chunk: Node3D in highway.chunks: _dress(chunk,chunk,false)

func _dress(node: Node, chunk: Node3D, restore: bool) -> void:
	for child: Node in node.get_children():
		if (child is GeometryInstance3D and child in hidden_sources) or (child is MeshInstance3D and child in slots): continue
		if not child is Node3D: continue
		var spatial: Node3D = child as Node3D
		# Place whole lamp assemblies together, and place scenery meshes about their centers.
		var lamp_holder: bool = false
		for part: Node in spatial.get_children():
			if part is Light3D: lamp_holder = true
		if spatial is GeometryInstance3D or lamp_holder:
			if not spatial.has_meta("course_original_transform"):
				spatial.set_meta("course_original_transform",spatial.transform)
			var original: Transform3D = spatial.get_meta("course_original_transform")
			spatial.transform = original
			if spatial is MultiMeshInstance3D and spatial.multimesh!=null:
				if not spatial.has_meta("course_source_multimesh"):
					spatial.set_meta("course_source_multimesh",spatial.multimesh)
					spatial.set_meta("course_bent_multimesh",spatial.multimesh.duplicate())
				var source_batch: MultiMesh = spatial.get_meta("course_source_multimesh")
				spatial.multimesh = source_batch if restore else spatial.get_meta("course_bent_multimesh")
				if restore: continue
				spatial.multimesh.custom_aabb = AABB()
				var batch_pose: Transform3D = spatial.global_transform
				var inverse: Transform3D = batch_pose.affine_inverse()
				for index: int in source_batch.instance_count:
					var authored_instance: Transform3D = batch_pose*source_batch.get_instance_transform(index)
					spatial.multimesh.set_instance_transform(index,inverse*course.pose(authored_instance))
				continue
			if restore: continue
			var authored: Transform3D = chunk.global_transform.affine_inverse()*spatial.global_transform
			var center: Vector3 = Vector3.ZERO
			if spatial is MeshInstance3D and spatial.mesh!=null: center = spatial.mesh.get_aabb().get_center()
			var route_center: Vector3 = authored*center+Vector3(0,0,chunk.position.z)
			var world_center: Vector3 = course.to_world(route_center)
			var turn: Basis = Basis.IDENTITY if spatial is Label3D or lamp_holder else Basis(Vector3.UP,course.heading_at_z(world_center.z))
			spatial.global_transform = Transform3D(turn*authored.basis,world_center-turn*authored.basis*center)
		else:
			_dress(spatial,chunk,restore)

func sync_material() -> void:
	if wet_material==null: return
	for parameter: String in ["wetness","quality","detail_strength"]:
		wet_material.set_shader_parameter(parameter,highway.asphalt.get_shader_parameter(parameter))

func rebase() -> void:
	collision_root.position.z = course.origin_z

func _bake_tile(nodes: Array, base_z: float) -> ArrayMesh:
	var groups: Dictionary = {}
	for node: GeometryInstance3D in nodes:
		if node is MeshInstance3D:
			_append_mesh(node.mesh,node.transform,node,groups,base_z)
		elif node is MultiMeshInstance3D and node.multimesh!=null:
			var batch: MultiMesh = node.multimesh
			for i: int in batch.instance_count:
				_append_mesh(batch.mesh,node.transform*batch.get_instance_transform(i),node,groups,base_z)
	var mesh := ArrayMesh.new()
	for material: Material in groups:
		var surface: SurfaceTool = groups[material]
		surface.generate_normals()
		surface.generate_tangents()
		surface.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count()-1,wet_material if material==highway.asphalt else material)
	return mesh

func _append_mesh(mesh: Mesh, pose: Transform3D, source: GeometryInstance3D, groups: Dictionary, base_z: float) -> void:
	if mesh==null: return
	for surface_index: int in mesh.get_surface_count():
		var material: Material = source.material_override
		if material==null and source is MeshInstance3D: material = source.get_active_material(surface_index)
		if material==null: material = mesh.surface_get_material(surface_index)
		if not groups.has(material):
			var builder := SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[material] = builder
		var builder: SurfaceTool = groups[material]
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count: int = vertices.size() if indices.is_empty() else indices.size()
		for triangle: int in range(0,count,3):
			var polygon: Array[Vector3] = []
			for corner: int in 3:
				var index: int = triangle+corner if indices.is_empty() else indices[triangle+corner]
				polygon.append(pose*vertices[index])
			var low: float = minf(polygon[0].z,minf(polygon[1].z,polygon[2].z))
			var high: float = maxf(polygon[0].z,maxf(polygon[1].z,polygon[2].z))
			if high-low<4.0:
				_emit(builder,polygon,base_z)
			else:
				for slice_index: int in range(int(floor(low/4.0)),int(floor(high/4.0))+1):
					var clipped: Array[Vector3] = _clip(polygon,float(slice_index)*4.0,true)
					clipped = _clip(clipped,float(slice_index+1)*4.0,false)
					_emit(builder,clipped,base_z)

func _clip(input: Array[Vector3], plane: float, above: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if input.is_empty(): return result
	var previous: Vector3 = input[input.size()-1]
	var was_inside: bool = previous.z>=plane if above else previous.z<=plane
	for current: Vector3 in input:
		var inside: bool = current.z>=plane if above else current.z<=plane
		if inside!=was_inside:
			result.append(previous.lerp(current,(plane-previous.z)/(current.z-previous.z)))
		if inside: result.append(current)
		previous = current
		was_inside = inside
	return result

func _emit(surface: SurfaceTool, polygon: Array[Vector3], base_z: float) -> void:
	for i: int in range(1,polygon.size()-1):
		if (polygon[i]-polygon[0]).cross(polygon[i+1]-polygon[0]).length_squared()<0.00000001: continue
		for vertex: Vector3 in [polygon[0],polygon[i],polygon[i+1]]:
			var route: Vector3 = vertex+Vector3(0,0,base_z)
			surface.set_uv(Vector2(route.x,route.z)*.08)
			surface.set_uv2(Vector2(route.x,route.z))
			surface.add_vertex(course.to_world(route)-Vector3(0,0,base_z))

func _build_collision(base_z: float) -> void:
	var floor_faces := PackedVector3Array()
	var wall_faces := PackedVector3Array()
	for step: int in 30:
		var z0: float = base_z+60.0-float(step)*4.0
		var z1: float = z0-4.0
		_quad(floor_faces,_point(-10,0,z0),_point(10,0,z0),_point(10,0,z1),_point(-10,0,z1))
		for side: float in [-1.0,1.0]:
			var x: float = side*RushRoadFrame.BARRIER_X
			var a: Vector3 = _point(x-.2,0,z0)
			var b: Vector3 = _point(x+.2,0,z0)
			var c: Vector3 = _point(x+.2,0,z1)
			var d: Vector3 = _point(x-.2,0,z1)
			var up: Vector3 = Vector3.UP*1.1
			_quad(wall_faces,a,a+up,d+up,d)
			_quad(wall_faces,b,c,c+up,b+up)
			_quad(wall_faces,a+up,b+up,c+up,d+up)
	_install_collision(floor_faces,1)
	_install_collision(wall_faces,4)

func _point(x: float, y: float, z: float) -> Vector3:
	return course.to_world(Vector3(x,y+RushRoadFrame.SURFACE_Y,z))

func _quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append_array(PackedVector3Array([a,b,c,a,c,d]))

func _install_collision(faces: PackedVector3Array, layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_meta("course_layer",layer)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	collision_root.add_child(body)
