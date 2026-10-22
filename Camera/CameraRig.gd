class_name DriveCameraRig
extends Node3D
const NAMES: Array[String] = ["CHASE", "FAR CHASE", "HOOD", "BUMPER"]
const OFFSETS: Array[Vector3] = [Vector3(0,3.2,7.1),Vector3(0,5.4,11.8),Vector3(0,1.19,-0.85),Vector3(0,0.57,-2.13)]
var effect_quality: int = 1
var camera: Camera3D
var turbo: RushTurboController
var impulse := RushCameraImpulse.new()
var finishing: bool = false
var finish_clock: float = 0.0
var finish_from := Vector3.ZERO
var target: ArcadeVehicle
var mode: int = 0
var showcase: bool = true
var orbit: float = 0.0
var snap_next: bool = true
var local_offset := Vector3.ZERO
var obstruction: float = 1.0
var obstruction_offset: Vector3 = Vector3.ZERO
var rendered_obstruction: float = 1.0
var response := Vector2.ZERO
var response_velocity := Vector2.ZERO
var motion_clock: float = 0.0
var smoothed_speed: float = 0.0
var smoothed_turbo: float = 0.0
var chase_yaw: float = 0.0
var previous_origin: Vector3 = Vector3.ZERO
var pose_initialized: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 100 # Render after the car's visual pose, from the exact same sample.
	process_physics_priority = 40
	camera = Camera3D.new()
	camera.near = 0.08
	camera.far = 900.0
	add_child(camera)
	camera.current = true
	var saved_mode: int = int(SaveService.settings["camera"])
	mode = saved_mode if saved_mode>=0 and saved_mode<NAMES.size() else 0
	local_offset = vehicle_offset()
	obstruction_offset = local_offset
	set_quality(int(SaveService.settings.get("quality", 1)))

func set_quality(level: int) -> void:
	effect_quality = clampi(level, 0, 2)
	if camera != null:
		camera.far = [380.0, 480.0, 650.0][effect_quality]

func cycle() -> void:
	mode = (mode+1)%OFFSETS.size()
	SaveService.set_value("camera",mode)

func _physics_process(_delta: float) -> void:
	obstruction = 1.0
	if not is_instance_valid(target) or showcase or mode > 1:
		return
	var origin := target.global_position+Vector3(0,1.2,0)
	var destination := target.global_transform*obstruction_offset
	var query := PhysicsRayQueryParameters3D.create(origin,destination,4,[target.get_rid()])
	var hit := target.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var point: Vector3 = hit["position"]
		obstruction = clampf((origin.distance_to(point)-0.3)/maxf(origin.distance_to(destination),0.1),0.05,1.0)

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var pose := target.render_pose()
	# A revive/teleport must not retain the previous shot's spring or heading.
	if pose_initialized and previous_origin.distance_squared_to(pose.origin)>2025.0 and camera.global_position.distance_squared_to(pose.origin)>2025.0:
		reset_rig()
	previous_origin = pose.origin
	pose_initialized = true
	var speed: float = maxf(target.speed_kmh(),0.0)
	var turbo_amount: float = turbo.intensity if turbo!=null else 0.0
	var telemetry_blend: float = 1.0 if snap_next else 1.0-exp(-6.0*delta)
	smoothed_speed = lerpf(smoothed_speed,speed,telemetry_blend)
	smoothed_turbo = lerpf(smoothed_turbo,turbo_amount,telemetry_blend)
	var vehicle_yaw: float = atan2(pose.basis.z.x,pose.basis.z.z)
	chase_yaw = vehicle_yaw if snap_next else lerp_angle(chase_yaw,vehicle_yaw,1.0-exp(-8.0*delta))
	# Small heading lag only: never let a sweeping bend leave the road off-screen.
	chase_yaw = vehicle_yaw+clampf(wrapf(chase_yaw-vehicle_yaw,-PI,PI),-0.055,0.055)
	var chase_basis: Basis = Basis(Vector3.UP,chase_yaw)
	var blend := 1.0 if snap_next else 1.0-exp(-12.0*delta)
	local_offset = local_offset.lerp(vehicle_offset(),blend)
	var desired: Vector3
	var look: Vector3
	if finishing:
		finish_clock += delta
		var t := smoothstep(0.45,2.6,finish_clock)
		var start_angle := atan2(finish_from.x,finish_from.z)
		var angle := lerp_angle(start_angle,-2.48,t)
		var radius := lerpf(Vector2(finish_from.x,finish_from.z).length(),5.7,smoothstep(0.0,0.45,finish_clock))
		var height := lerpf(finish_from.y,2.5,smoothstep(0.0,0.4,finish_clock))
		desired = pose*Vector3(sin(angle)*radius,height,cos(angle)*radius)
		var road_x: float = target.course.center_x(desired.z) if target.course!=null else 0.0
		desired.x = clampf(desired.x,road_x-8.9,road_x+8.9)
		look = pose.origin+Vector3(0,0.65,0)
	elif showcase:
		orbit += delta*0.12
		desired = pose.origin+Vector3(cos(orbit+0.7)*6.6,2.65,sin(orbit+0.7)*6.6)
		look = pose.origin+Vector3(0,0.65,0)
	else:
		var cinematic_offset := local_offset
		# Scale inertia response with speed; normal braking, deceleration, and stopping
		# must never compress the spring or cause rebound jerks upon halting.
		var speed_scale := clampf(speed / 20.0, 0.0, 1.0)
		var accel_forward := maxf(0.0, target.acceleration_now) * speed_scale
		var lateral_inertia := clampf(target.velocity.dot(pose.basis.x) * .055, -.35, .35) * speed_scale
		var response_target := Vector2(lateral_inertia, clampf(accel_forward, 0.0, 15.0) * .008)
		# Critically damped local response; follow the interpolated physics pose exactly.
		var remaining := minf(delta, .1)
		while remaining > 0.0:
			var step := minf(remaining, 1.0 / 120.0)
			response_velocity += ((response_target - response) * 100.0 - response_velocity * 20.0) * step
			response += response_velocity * step
			remaining -= step
		# Fully settle camera response at low speed / standstill to prevent any idle vibration
		if speed < 0.5:
			response = response.move_toward(Vector2.ZERO, delta * 8.0)
			response_velocity = response_velocity.move_toward(Vector2.ZERO, delta * 30.0)
			if speed < 0.05:
				response = Vector2.ZERO
				response_velocity = Vector2.ZERO
		motion_clock += delta
		if mode < 2:
			# Subtle rear three-quarter framing; preserve each model's own anchors.
			var framing_side: float = 0.32 if mode == 0 else 0.18
			cinematic_offset += Vector3(framing_side - response.x * 0.65, -0.22 - response.y * .2, response.y * 0.7 + clampf(smoothed_speed / 300.0, 0, 1) * 0.9)
			cinematic_offset.y = maxf(cinematic_offset.y, 2.4 if mode == 0 else 3.8)

		if turbo != null and mode < 2:
			cinematic_offset += Vector3(0, -0.10, clampf(turbo.spec.chase_pullback * 1.35, 0.0, 1.35)) * smoothed_turbo
		# No continuous high-frequency camera vibration: speed is conveyed by framing/FOV.
		var view_basis: Basis = chase_basis if mode < 2 else pose.basis
		desired = pose.origin + view_basis * cinematic_offset
		var look_ahead: float = 12.0 if mode > 1 else lerpf(5.5, 10.5, clampf(smoothed_speed / 270.0, 0.0, 1.0))
		look = pose.origin - pose.basis.z * look_ahead + Vector3(0, 0.90, 0)
		if mode < 2 and target.course != null:
			# Smooth forward blend prevents popping when speed crosses zero or during stopping/reversing
			var forward_weight: float = clampf(target.signed_speed / 2.0, 0.0, 1.0)
			if forward_weight > 0.0:
				var lane_offset: float = pose.origin.x - target.course.center_x(pose.origin.z)
				var course_look_x: float = target.course.center_x(look.z) + lane_offset
				look.x = lerpf(look.x, course_look_x, 0.65 * forward_weight)

		obstruction_offset = pose.basis.inverse()*(desired-pose.origin)
		# Pull in immediately for an obstruction, ease back out after it clears.
		rendered_obstruction = obstruction if obstruction<rendered_obstruction else lerpf(rendered_obstruction,obstruction,1.0-exp(-5.0*delta))
		if mode < 2:
			desired = (pose.origin+Vector3(0,1.2,0)).lerp(desired,rendered_obstruction)
	var effect_scale := 0.45 if effect_quality==0 else 0.7
	desired += pose.basis*impulse.tick(delta)*effect_scale*(0.45 if mode>1 and not finishing else 1.0)
	# Interpolate the target, not a lagging world-space chase position.
	camera.global_position = desired
	var wanted_basis := Basis.looking_at(look-desired,Vector3.UP)
	camera.global_basis = camera.global_basis.slerp(wanted_basis,1.0 if snap_next else 1.0-exp(-22.0*delta)).orthonormalized()
	var wanted_fov := 49.0 if showcase else (65.0 if mode==0 else (68.0 if mode==1 else 70.0))+clampf(smoothed_speed/maxf(target.spec.top_speed_kmh,1.0),0.0,1.0)*7.0
	if turbo != null and not showcase:
		wanted_fov += clampf(turbo.spec.fov_degrees*1.2,0.0,11.0)*smoothed_turbo*(0.6 if mode>1 else 1.0)
	if finishing:
		wanted_fov = lerpf(wanted_fov,57.0,smoothstep(0.0,2.5,finish_clock))
	camera.fov = lerpf(camera.fov,wanted_fov,blend)
	snap_next = false

func reset_rig() -> void:
	snap_next = true
	response = Vector2.ZERO
	response_velocity = Vector2.ZERO
	motion_clock = 0
	smoothed_speed = 0.0
	smoothed_turbo = 0.0
	pose_initialized = false
	finishing = false
	finish_clock = 0.0
	impulse.reset()
	local_offset = vehicle_offset()
	obstruction_offset = local_offset
	obstruction = 1.0
	rendered_obstruction = 1.0

func impact_feedback(strength: float) -> void:
	impulse.trigger(strength*0.085,0.35)

func turbo_kick() -> void:
	impulse.trigger(0.055,0.24)

func begin_finish() -> void:
	finishing = true
	showcase = false
	finish_clock = 0.0
	finish_from = target.render_pose().affine_inverse()*camera.global_position
	impulse.reset()

func vehicle_offset() -> Vector3:
	if mode<0 or mode>=NAMES.size(): mode = 0 # Legacy cockpit preference safely falls back to Chase.
	if is_instance_valid(target) and target.visual!=null and target.spec.camera_anchors.size()>=NAMES.size():
		return target.visual.attachment(["camera_chase_anchor","camera_far_anchor","camera_hood_anchor","camera_bumper_anchor"][mode],target.spec.camera_anchors[mode])
	return OFFSETS[mode]
