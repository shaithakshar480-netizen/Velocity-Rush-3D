class_name ArcadeVehicle
extends CharacterBody3D
## Flat-highway constrained arcade model. This body solves X/Z collisions only.
## RoadFrame owns Y; no gravity, floor snap, moving-platform transfer or physical suspension.
signal impact(strength: float)
signal contact_report(relative_speed: float, normal: Vector3, object_type: String)
var transmission := RushTransmission.new()
signal traffic_contact(strength: float)
@export var spec: VehicleSpec = preload("res://Data/VortexS.tres")
var road_center: Callable # Optional multiplayer course; empty retains straight single-player contact.
var course: RushSampledCourse
var turbo: RushTurboController
var finish_coasting: bool = false
var body_collision: CollisionShape3D
var input_source: Node
var signed_speed: float = 0.0
var steering_angle: float = 0.0
var brake_timer: float = 0.0
var driving: bool = false
var visual: VortexVisual
var previous_pose := Transform3D.IDENTITY
var current_pose := Transform3D.IDENTITY
var last_command := Vector2.ZERO
var suspension: Array[float] = [0.34,0.34,0.34,0.34]
var impact_cooldown: float = 0.0
var acceleration_now: float = 0.0
var skid_amount: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	floor_snap_length = 0.0
	platform_floor_layers = 0
	platform_wall_layers = 0
	max_slides = 4
	safe_margin = 0.002
	collision_mask = 6 # Traffic layer 2 and continuous barriers layer 4. No floor contacts.
	var collision := CollisionShape3D.new()
	body_collision = collision
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.88,0.96,3.9)
	collision.shape = shape
	collision.position.y = 0.49
	add_child(collision)
	visual = VortexVisual.new()
	add_child(visual)
	visual.top_level = true
	reset_vehicle()

func reset_vehicle() -> void:
	finish_coasting = false
	transmission.reset()
	global_position = Vector3(0,RushRoadFrame.SURFACE_Y,0)
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	signed_speed = 0.0
	steering_angle = 0.0
	brake_timer = 0.0
	acceleration_now = 0.0
	impact_cooldown = 0.0
	skid_reset()
	last_command = Vector2.ZERO
	previous_pose = global_transform
	current_pose = global_transform
	if is_instance_valid(visual):
		visual.global_transform = current_pose
		if is_instance_valid(visual.body_root):
			visual.body_root.rotation = Vector3.ZERO

func skid_reset() -> void:
	skid_amount = 0.0

func _physics_process(delta: float) -> void:
	previous_pose = current_pose
	# A single explicit road constraint is authoritative even during countdown.
	position.y = RushRoadFrame.SURFACE_Y
	velocity.y = 0.0
	if not driving:
		current_pose = global_transform
		return
	var command := Vector2.ZERO
	if input_source != null:
		command = input_source.sample()
	var previous_speed := signed_speed
	var forward := -global_transform.basis.z
	var grounded := has_road_contact()
	signed_speed = velocity.dot(forward)
	var desired := signed_speed
	var boost := turbo.intensity if turbo != null and not finish_coasting else 0.0
	var speed_cap := lerpf(spec.top_speed_kmh,spec.turbo.top_speed_kmh,boost)/3.6
	if turbo!=null and turbo.multiplayer_local:
		speed_cap = minf(speed_cap,RushTurboController.MULTIPLAYER_CAP_KMH/3.6)
	# Stronger arcade braking preserves per-car brake upgrade differences.
	var brake_deceleration: float = maxf(32.0,spec.braking*1.65)
	var boost_control: float = clampf(boost,0.0,1.0)
	var boost_acceleration := lerpf(1.0,spec.turbo.acceleration_multiplier,boost)
	if boost>0.0 and command.y>=0.0 and signed_speed>0.0:
		command.y = 1.0
	var torque := transmission.tick(delta,signed_speed*3.6,command.y,speed_cap*3.6)
	var mass_factor := 1280.0 / maxf(spec.weight_kg, 400.0)
	if command.y > 0.0:
		brake_timer = 0.0
		if desired < -0.2:
			desired = move_toward(desired,0.0,brake_deceleration*delta)
		else:
			var taper := lerpf(1.0,0.18,pow(clampf(desired/maxf(speed_cap,0.1),0.0,1.0),2.0))
			if desired > speed_cap:
				desired = move_toward(desired,speed_cap,spec.turbo.overspeed_deceleration*delta)
			else:
				desired = minf(desired+spec.acceleration*boost_acceleration*mass_factor*taper*torque*delta,speed_cap)
	elif command.y < 0.0:
		if desired > 0.15:
			brake_timer = 0.0
			desired = move_toward(desired,0.0,brake_deceleration*delta)
		else:
			brake_timer += delta
			desired = move_toward(desired,-spec.reverse_speed_kmh/3.6,spec.reverse_acceleration*delta) if brake_timer > 0.3 else 0.0
	else:
		brake_timer = 0.0
		desired = move_toward(desired,0.0,(spec.rolling_drag+spec.air_drag*desired*desired)*delta)
	if finish_coasting:
		desired = move_toward(signed_speed,0.0,9.0*delta)
	var speed_fraction := clampf(absf(signed_speed)/(spec.top_speed_kmh/3.6),0.0,1.0)
	var limit := deg_to_rad(lerpf(spec.steering_low_degrees,spec.steering_high_degrees,pow(speed_fraction,0.55)))
	var sensitivity := float(SaveService.settings["steering"])
	steering_angle = lerpf(steering_angle,command.x*limit*sensitivity,1.0-exp(-spec.steering_response*lerpf(1.0,1.3,boost_control)*delta))
	if grounded:
		var yaw_rate := clampf(signed_speed/spec.wheelbase*tan(steering_angle),-1.2,1.2)
		# Bounded boost steering support compensates for the higher forward speed.
		var comfort := 9.0 if bool(SaveService.settings["steering_assist"]) else 11.0
		var turbo_speed_ratio: float = clampf(absf(signed_speed)/maxf(spec.top_speed_kmh/3.6,1.0),1.0,1.35)
		comfort *= lerpf(1.0,turbo_speed_ratio,boost_control)
		yaw_rate = clampf(yaw_rate,-comfort/maxf(absf(signed_speed),1.0),comfort/maxf(absf(signed_speed),1.0))
		rotate_y(-yaw_rate*delta)
		forward = -global_transform.basis.z
		var lateral := velocity - forward*velocity.dot(forward)
		lateral.y = 0.0
		# Extra tyre grip reduces sideways drift while boosting or braking.
		var grip_support: float = lerpf(1.0,1.3,boost_control)
		if command.y<0.0: grip_support = maxf(grip_support,1.4)
		lateral *= exp(-spec.grip*grip_support*delta)
		velocity.x = forward.x*desired+lateral.x
		velocity.z = forward.z*desired+lateral.z
	velocity.y = 0.0
	var before := velocity
	move_and_slide()
	position.y = RushRoadFrame.SURFACE_Y
	velocity.y = 0.0
	signed_speed = velocity.dot(-global_transform.basis.z)
	acceleration_now = (signed_speed-previous_speed)/maxf(delta,0.001)
	impact_cooldown = maxf(impact_cooldown-delta,0.0)
	for i: int in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other := collision.get_collider()
		if other is RushTrafficVehicle and not other.was_hit:
			other.mark_collision()
			respond_to_traffic(clampf(absf((before-(-other.global_basis.z*other.speed)).dot(collision.get_normal()))/28.0,0.15,1.0),absf((before-(-other.global_basis.z*other.speed)).dot(collision.get_normal())),collision.get_normal())
		if not other is RushTrafficVehicle and absf(collision.get_normal().y) < 0.6:
			var loss := absf(before.dot(collision.get_normal()))
			if loss > 2.0 and impact_cooldown <= 0.0:
				contact_report.emit(loss,collision.get_normal(),"barrier")
				impact.emit(clampf(loss/20.0,0.1,1.0))
				impact_cooldown = 0.35
			# Retain tangential speed; remove penetration with engine slide solver.
	skid_amount_set(command,grounded)
	last_command = command
	current_pose = global_transform

func _process(delta: float) -> void:
	if not is_instance_valid(visual):
		return
	visual.global_transform = render_pose()
	visual.animate(delta,signed_speed,steering_angle,last_command.y<0.0,suspension,acceleration_now)

func render_pose() -> Transform3D:
	return previous_pose.interpolate_with(current_pose,Engine.get_physics_interpolation_fraction())

func rebase_render_pose(shift: Vector3) -> void:
	previous_pose.origin -= shift
	current_pose.origin -= shift
	visual.global_position -= shift

func has_road_contact() -> bool:
	var center: float = course.center_x(position.z) if course!=null else (float(road_center.call(position.z)) if road_center.is_valid() else 0.0)
	return absf(position.y-RushRoadFrame.SURFACE_Y)<0.001 and absf(position.x-center)<RushRoadFrame.ROAD_HALF_WIDTH

func skid_amount_set(command: Vector2, grounded: bool) -> void:
	skid_amount = clampf(absf(steering_angle*signed_speed)*0.12+ (0.25 if command.y<0.0 and signed_speed>12.0 else 0.0),0.0,0.65) if grounded else 0.0

func speed_kmh() -> float:
	return Vector2(velocity.x,velocity.z).length()*3.6

func respond_to_traffic(strength: float, relative_speed: float = -1.0, normal: Vector3 = Vector3.BACK) -> void:
	traffic_contact.emit(strength)
	if impact_cooldown > 0.0:
		return
	velocity.x *= lerpf(0.85,0.45,strength)
	velocity.z *= lerpf(0.85,0.45,strength)
	signed_speed = velocity.dot(-global_transform.basis.z)
	impact_cooldown = 0.6
	contact_report.emit(relative_speed if relative_speed>=0 else strength*28.0,normal,"traffic")
	impact.emit(strength)

func apply_configuration(value: VehicleSpec, paint: Color) -> void:
	transmission.configure(value.vehicle_id)
	spec = value
	var d := RushVehicleCatalog.definition(spec.vehicle_id)
	var shape := body_collision.shape as BoxShape3D
	shape.size = Vector3(float(d["width"])*0.98,float(d["height"])*0.78,float(d["length"])*0.93)
	body_collision.position.y = shape.size.y*0.5+0.01
	visual.select_model(spec.vehicle_id,paint)

func half_width() -> float:
	return (body_collision.shape as BoxShape3D).size.x*0.5

func half_length() -> float:
	return (body_collision.shape as BoxShape3D).size.z*0.5
