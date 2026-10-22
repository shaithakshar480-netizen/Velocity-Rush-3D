class_name RushCoursePickups
extends Node3D
## Adapter for the existing pooled pickup system (not supplied in this overlay).
## Its authoritative pool/reward/magnet logic stays in route coordinates. Read-only
## vehicle/NPC queries and shared render instances bridge it to the curved world.
class QueryCar extends ArcadeVehicle:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_DISABLED
		collision_layer = 0
		collision_mask = 0
		visible = false

class QueryVisual extends VortexVisual:
	var source_visual: VortexVisual
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_DISABLED
		visible = false
		body_root = Node3D.new()
		add_child(body_root)
	func attachment(name_value: String, fallback: Vector3) -> Vector3:
		return source_visual.attachment(name_value,fallback)

class QueryNPC extends RushTrafficVehicle:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_DISABLED
		collision_layer = 0
		collision_mask = 0
		visible = false

class QueryTraffic extends RushTrafficSystem:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_DISABLED
	var source: RushTrafficSystem
	func placement_safe(lane_index: int, z: float, speed_value: float) -> bool:
		return source.placement_safe(lane_index,z,speed_value)

var course: RushSampledCourse
var system: RushCoinSystem
var player: ArcadeVehicle
var traffic: RushTrafficSystem
var query_car: ArcadeVehicle
var query_visual: QueryVisual
var query_traffic: QueryTraffic
var source_meshes: Array[GeometryInstance3D] = []
var render_meshes: Array[GeometryInstance3D] = []
var saved_layers: Array[int] = []

func build(pickups: RushCoinSystem, car: ArcadeVehicle, npcs: RushTrafficSystem) -> void:
	system = pickups
	player = car
	traffic = npcs
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -25
	process_priority = 90 # After pooled coin bob/spin/magnet flight, before camera.
	# Disabled, shapeless query nodes: global/local transforms work without running
	# any inherited controller, visual initialization, input or save callback.
	query_car = QueryCar.new()
	add_child(query_car)
	query_visual = QueryVisual.new()
	query_visual.source_visual = player.visual
	add_child(query_visual)
	query_car.visual = query_visual
	query_traffic = QueryTraffic.new()
	add_child(query_traffic)
	query_traffic.source = traffic
	query_traffic.car = query_car
	query_traffic.run = traffic.run
	for npc: RushTrafficVehicle in traffic.pool:
		var mirror := QueryNPC.new()
		query_traffic.add_child(mirror)
		mirror.half_width = npc.half_width
		mirror.half_length = npc.half_length
		query_traffic.pool.append(mirror)
	_capture(system)

func _capture(node: Node) -> void:
	for child: Node in node.get_children():
		if child.is_queued_for_deletion(): continue
		var copy: GeometryInstance3D = null
		if child is GeometryInstance3D and source_meshes.has(child):
			_capture(child)
			continue
		if child is MeshInstance3D:
			var mesh_copy := MeshInstance3D.new()
			mesh_copy.mesh = child.mesh
			if child.mesh!=null:
				for surface: int in child.mesh.get_surface_count():
					mesh_copy.set_surface_override_material(surface,child.get_surface_override_material(surface))
			copy = mesh_copy
		elif child is MultiMeshInstance3D and child.multimesh!=null:
			var batch_copy := MultiMeshInstance3D.new()
			batch_copy.multimesh = child.multimesh.duplicate() as MultiMesh
			batch_copy.multimesh.custom_aabb = AABB()
			copy = batch_copy
		elif child is SpriteBase3D or child is Label3D:
			copy = child.duplicate(0) as GeometryInstance3D
			copy.set_script(null)
			for descendant: Node in copy.get_children(): descendant.free()
		if copy!=null:
			copy.material_override = child.material_override
			copy.material_overlay = child.material_overlay
			copy.cast_shadow = child.cast_shadow
			copy.layers = child.layers
			copy.visibility_range_begin = child.visibility_range_begin
			copy.visibility_range_end = child.visibility_range_end
			copy.visible = false
			add_child(copy)
			source_meshes.append(child)
			render_meshes.append(copy)
			saved_layers.append(child.layers)
		_capture(child)

func set_course(value: RushSampledCourse) -> void:
	if value!=null: _capture(system) # Include any effects created during boot prewarming.
	course = value
	system.car = query_car if course!=null else player
	system.traffic = query_traffic if course!=null else traffic
	for i: int in source_meshes.size():
		source_meshes[i].layers = 0 if course!=null else saved_layers[i]
		render_meshes[i].visible = false
	refresh_queries()

func refresh_queries() -> void:
	if course==null: return
	query_car.spec = player.spec
	query_car.body_collision = player.body_collision
	query_visual.global_transform = _route_pose(player.visual.global_transform)
	query_visual.body_root.transform = player.visual.body_root.transform
	query_car.driving = player.driving
	query_car.position = course.to_route(player.position)
	query_car.rotation = Vector3(0,player.rotation.y-course.heading_at_z(player.position.z),0)
	query_car.velocity = course.route_velocity(player.position,player.velocity)
	query_car.signed_speed = player.signed_speed
	query_car.previous_pose = _route_pose(player.previous_pose)
	query_car.current_pose = _route_pose(player.current_pose)
	query_traffic.ready_for_drive = traffic.ready_for_drive
	query_traffic.active = traffic.active
	query_traffic.escape_lane = traffic.escape_lane
	query_traffic.opponents = traffic.opponents
	for i: int in traffic.pool.size():
		var source: RushTrafficVehicle = traffic.pool[i]
		var mirror: RushTrafficVehicle = query_traffic.pool[i]
		mirror.active = source.active
		mirror.lane = source.lane
		mirror.position = course.to_route(source.position)
		mirror.previous_position = course.to_route(source.previous_position)
		mirror.speed = source.speed
		mirror.desired_speed = source.desired_speed

func _route_pose(pose: Transform3D) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,-course.heading_at_z(pose.origin.z))*pose.basis,course.to_route(pose.origin))

func _physics_process(_delta: float) -> void:
	refresh_queries()

func _process(_delta: float) -> void:
	if course==null: return
	for i: int in source_meshes.size():
		var source: GeometryInstance3D = source_meshes[i]
		var copy: GeometryInstance3D = render_meshes[i]
		copy.visible = source.is_visible_in_tree()
		if not copy.visible: continue
		copy.transparency = source.transparency
		copy.material_override = source.material_override
		copy.material_overlay = source.material_overlay
		if source is MultiMeshInstance3D:
			var input: MultiMesh = source.multimesh
			var output: MultiMesh = (copy as MultiMeshInstance3D).multimesh
			var count: int = input.instance_count if input.visible_instance_count<0 else input.visible_instance_count
			output.visible_instance_count = count
			for instance: int in count:
				output.set_instance_transform(instance,course.pose(source.global_transform*input.get_instance_transform(instance)))
				if input.use_colors: output.set_instance_color(instance,input.get_instance_color(instance))
				if input.use_custom_data: output.set_instance_custom_data(instance,input.get_instance_custom_data(instance))
		else:
			copy.global_transform = course.pose(source.global_transform)

func _exit_tree() -> void:
	if is_instance_valid(system):
		system.car = player
		system.traffic = traffic
