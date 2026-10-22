class_name RushRoadCoin
extends Node3D
var active: bool = false
var blocked: bool = false
var attracting: bool = false
var attraction_origin: Vector3 = Vector3.ZERO
var attraction_time: float = 0.0
var attraction_duration: float = 0.4
func begin_attraction(target: Vector3) -> void:
	attracting = true
	attraction_origin = position
	attraction_time = 0.0
	attraction_duration = clampf(position.distance_to(target)/32.0,0.28,0.55)
func tick_attraction(target: Vector3, delta: float) -> bool:
	attraction_time = minf(attraction_time+delta,attraction_duration)
	var t: float = attraction_time/attraction_duration
	var eased: float = t*t*(3.0-2.0*t)
	position = attraction_origin.lerp(target,eased)+Vector3.UP*sin(t*PI)*1.2
	scale = Vector3.ONE*lerpf(1.0,0.55,eased)
	return t>=1.0
var mesh_instance: MeshInstance3D

func build(shared_mesh: Mesh, shared_material: Material, rim: Mesh, badge: Mesh, badge_material: Material) -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = shared_mesh
	mesh_instance.material_override = shared_material
	add_child(mesh_instance)
	mesh_instance.rotation.x = PI/2.0
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var edge := MeshInstance3D.new()
	edge.mesh = rim
	edge.material_override = shared_material
	edge.rotation.x = PI/2.0
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(edge)
	var emblem := MeshInstance3D.new()
	emblem.mesh = badge
	emblem.material_override = badge_material
	emblem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emblem)
	deactivate()

func activate(at: Vector3, _phase_value: float = 0.0) -> void:
	position = at
	position.y = RushRoadFrame.SURFACE_Y+RushRoadFrame.COIN_HEIGHT
	rotation = Vector3.ZERO
	scale = Vector3.ONE
	mesh_instance.position = Vector3.ZERO
	blocked = false
	active = true
	visible = true

func deactivate() -> void:
	attracting = false
	attraction_time = 0.0
	scale = Vector3.ONE
	active = false
	blocked = false
	visible = false
