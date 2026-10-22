class_name RushWetWeather
extends Node3D
## Physically convincing wet-weather water response: falling rain, directional tyre water jets,
## fine low mist wake, and road raindrop impacts. Bounded mobile particle budgets.
var game: Node
var rain: CPUParticles3D
var spray: Array[CPUParticles3D] = []
var mist: Array[CPUParticles3D] = []
var ripples: CPUParticles3D
var quality: int = -1
var enabled: bool = false
var car_id: String = ""
var axle: float = 1.3
var track: float = .8
var previous: Vector3 = Vector3.ZERO
var puddle_spray: Array[CPUParticles3D] = []
var rear_wheels: Array[Node3D] = [null, null]
var puddle_strength: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
# Optional owned/free assets; no speculative resource paths or synthesized water audio.
# Hiss must be a seamless loop configured to loop in its import settings.
@export var wet_hiss_stream: AudioStream
@export var wet_splash_stream: AudioStream
var hiss_player: AudioStreamPlayer
var splash_player: AudioStreamPlayer
var hiss_gain: float = 0.0
var splash_wait: float = 0.0
var puddle_entered: bool = false

func build(owner_game: Node) -> void:
	game = owner_game
	process_mode = Node.PROCESS_MODE_PAUSABLE
	hiss_player = AudioStreamPlayer.new()
	splash_player = AudioStreamPlayer.new()
	add_child(hiss_player)
	add_child(splash_player)
	set_water_audio(wet_hiss_stream, wet_splash_stream)

	# 1. Rain Falling Streaks
	var rain_texture := _make_rain_texture()
	var rain_mat := StandardMaterial3D.new()
	rain_mat.albedo_texture = rain_texture
	# BUG-1 FIX: In Godot, blend_mode = BLEND_MODE_ADD and texture alpha require
	# transparency = TRANSPARENCY_ALPHA. Without it, material renders in opaque pass
	# where blending is ignored. Also disable fog so particles stay visible in dark night/evening fog.
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_mat.albedo_color = Color(0.85, 0.92, 1.0, 0.90)
	rain_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	rain_mat.no_depth_test = false
	rain_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	rain_mat.disable_fog = true
	rain_mat.set_flag(BaseMaterial3D.FLAG_DISABLE_FOG, true)

	rain = CPUParticles3D.new()
	rain.emitting = false
	rain.lifetime = 0.55
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(12, 1, 18)
	rain.direction = Vector3(0.06, -1.0, 0.04)
	rain.spread = 3.0
	rain.gravity = Vector3(0, -12.0, 0)
	rain.initial_velocity_min = 24.0
	rain.initial_velocity_max = 30.0
	# BUG-1 FIX: Use world-space particle simulation (local_coords=false).
	# With local_coords=true, the visibility AABB is treated as a fixed world-space
	# region — as the car moves, the emitter moves but the AABB stays near origin,
	# causing incorrect frustum culling in all non-origin positions. World-space
	# particles let Godot auto-compute a correct AABB from actual live particle positions.
	rain.local_coords = false
	# Auto-computed AABB (zero = Godot computes from live particles in world space).
	# Do NOT set a fixed visibility_aabb or custom_aabb when using world-space particles;
	# the auto-computed one tracks particles correctly as the emitter follows the car.
	rain.visibility_aabb = AABB()

	var rain_streak := QuadMesh.new()
	rain_streak.size = Vector2(0.020, 0.70)
	rain.mesh = rain_streak
	rain.material_override = rain_mat
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)

	# 2. Tyre Water Spray (High-speed directional water droplet roostertail)
	var droplet_texture := _make_droplet_texture()
	var spray_mat := StandardMaterial3D.new()
	spray_mat.albedo_texture = droplet_texture
	spray_mat.albedo_color = Color(0.80, 0.88, 0.96, 0.62)
	spray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spray_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var droplet_mesh := QuadMesh.new()
	droplet_mesh.size = Vector2(0.055, 0.13)

	var spray_ramp := Gradient.new()
	spray_ramp.set_color(0, Color(1, 1, 1, 0.9))
	spray_ramp.set_color(1, Color(0.7, 0.85, 1, 0.0))
	spray_ramp.add_point(0.25, Color(0.95, 0.98, 1, 0.8))
	spray_ramp.add_point(0.65, Color(0.8, 0.9, 1, 0.35))

	for side: int in 2:
		var emitter := CPUParticles3D.new()
		emitter.emitting = false
		emitter.particle_flag_align_y = true
		emitter.local_coords = false
		emitter.lifetime = 0.26
		emitter.lifetime_randomness = 0.25
		emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		emitter.emission_box_extents = Vector3(0.065, 0.006, 0.025)
		emitter.spread = 16.0
		emitter.gravity = Vector3(0, -14.0, 0)
		emitter.scale_amount_min = 0.30
		emitter.scale_amount_max = 0.85
		emitter.color_ramp = spray_ramp
		emitter.mesh = droplet_mesh
		emitter.material_override = spray_mat
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(emitter)
		spray.append(emitter)
		# Reused secondary pool: only emits while this tyre is crossing pooled water.
		var splash := emitter.duplicate() as CPUParticles3D
		splash.emitting = false
		splash.lifetime = 0.32
		splash.lifetime_randomness = 0.30
		add_child(splash)
		puddle_spray.append(splash)

	# 3. Fine Low Water Mist Wake
	var mist_texture := _make_mist_texture()
	var mist_mat := StandardMaterial3D.new()
	mist_mat.albedo_texture = mist_texture
	mist_mat.albedo_color = Color(0.85, 0.92, 1.0, 0.22)
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mist_mesh := QuadMesh.new()
	mist_mesh.size = Vector2.ONE

	var mist_ramp := Gradient.new()
	mist_ramp.set_color(0, Color(1, 1, 1, 0.45))
	mist_ramp.set_color(1, Color(0.7, 0.85, 1, 0.0))
	mist_ramp.add_point(0.40, Color(0.9, 0.95, 1, 0.20))

	for side: int in 2:
		var emitter := CPUParticles3D.new()
		emitter.emitting = false
		emitter.local_coords = false
		emitter.lifetime = 0.22
		emitter.spread = 26.0
		emitter.gravity = Vector3(0, -3.5, 0)
		emitter.scale_amount_min = 0.10
		emitter.scale_amount_max = 0.30
		emitter.color_ramp = mist_ramp
		emitter.mesh = mist_mesh
		emitter.material_override = mist_mat
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(emitter)
		mist.append(emitter)

	# 4. Rain Ground Impact Ripples (subtle water splashes on road deck)
	var ripple_texture := _make_ripple_texture()
	var ripple_mat := StandardMaterial3D.new()
	ripple_mat.albedo_texture = ripple_texture
	ripple_mat.albedo_color = Color(0.88, 0.94, 1.0, 0.38)
	ripple_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ripple_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var ripple_mesh := PlaneMesh.new()
	ripple_mesh.size = Vector2(0.32, 0.32)

	var ripple_ramp := Gradient.new()
	ripple_ramp.set_color(0, Color(1, 1, 1, 0.7))
	ripple_ramp.set_color(1, Color(0.7, 0.85, 1, 0.0))

	ripples = CPUParticles3D.new()
	ripples.emitting = false
	ripples.local_coords = true
	ripples.lifetime = 0.18
	ripples.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ripples.emission_box_extents = Vector3(8.0, 0.01, 12.0)
	ripples.direction = Vector3.UP
	ripples.spread = 0.0
	ripples.gravity = Vector3.ZERO
	ripples.initial_velocity_min = 0.0
	ripples.initial_velocity_max = 0.0
	ripples.scale_amount_min = 0.5
	ripples.scale_amount_max = 1.3
	ripples.color_ramp = ripple_ramp
	ripples.mesh = ripple_mesh
	ripples.material_override = ripple_mat
	ripples.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ripples)

func _make_rain_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 16
	texture.height = 32
	return texture

func _make_droplet_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.95))
	gradient.set_color(1, Color(0.7, 0.85, 1.0, 0.0))
	gradient.add_point(0.20, Color(0.92, 0.97, 1.0, 0.85))
	gradient.add_point(0.70, Color(0.80, 0.92, 1.0, 0.30))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 16
	texture.height = 32
	return texture

func _make_mist_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.92, 0.96, 1.0, 0.35))
	gradient.set_color(1, Color(0.75, 0.88, 1.0, 0.0))
	gradient.add_point(0.40, Color(0.85, 0.92, 1.0, 0.14))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 32
	texture.height = 32
	return texture

func _make_ripple_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.0))
	gradient.set_color(1, Color(0.7, 0.85, 1.0, 0.0))
	gradient.add_point(0.55, Color(0.90, 0.95, 1.0, 0.60))
	gradient.add_point(0.78, Color(0.80, 0.90, 1.0, 0.25))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 32
	texture.height = 32
	return texture

func _sample_puddle(at_x: float, at_z: float) -> float:
	if absf(at_x) > 8.0:
		return 0.0
	var lane := fposmod(at_x + 8.0, 4.0) - 2.0
	var wear := exp(-pow((absf(lane) - 0.70) * 3.8, 2.0))
	var px := at_x * 0.16
	var pz := at_z * 0.07
	var n: float = _puddle_noise(Vector2(px,pz))*0.70 + _puddle_noise(Vector2(px,pz)*2.4+Vector2(3.8,1.9))*0.30
	var rut := wear * 0.26
	var puddle_mask := smoothstep(0.58 - rut, 0.74 - rut, n)
	var road_bounds := 1.0 - smoothstep(6.2, 8.1, absf(at_x))
	return puddle_mask * road_bounds

# Same hash, value-noise blend, rut bias and bounds as asphalt.gdshader.
# Shader floating-point precision can differ slightly at puddle edges.
func _puddle_hash(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(127.1,311.7)))*43758.5453,1.0)

func _puddle_noise(p: Vector2) -> float:
	var cell: Vector2 = p.floor()
	var f: Vector2 = p-cell
	f = f*f*(Vector2(3,3)-2.0*f)
	return lerpf(lerpf(_puddle_hash(cell),_puddle_hash(cell+Vector2.RIGHT),f.x),
		lerpf(_puddle_hash(cell+Vector2.DOWN),_puddle_hash(cell+Vector2.ONE),f.x),f.y)

func set_water_audio(hiss: AudioStream, splash: AudioStream) -> void:
	wet_hiss_stream = hiss
	wet_splash_stream = splash
	if hiss_player==null: return
	hiss_player.stop()
	splash_player.stop()
	hiss_player.stream = hiss
	splash_player.stream = splash
	hiss_gain = 0.0
	hiss_player.volume_db = -60.0
	# Missing SFX bus fails silent rather than bypassing user volume settings.
	if AudioServer.get_bus_index("SFX")>=0:
		hiss_player.bus = &"SFX"
		splash_player.bus = &"SFX"

func _water_audio(delta: float, intensity: float, pool: float) -> void:
	splash_wait = maxf(0.0,splash_wait-delta)
	var target: float = intensity*0.10
	hiss_gain = lerpf(hiss_gain,target,1.0-exp(-delta*5.0))
	var audio_ready: bool = AudioServer.get_bus_index("SFX")>=0
	if hiss_player.stream!=null and audio_ready:
		hiss_player.volume_db = linear_to_db(maxf(hiss_gain,0.001))
		if hiss_gain>0.002 and not hiss_player.playing: hiss_player.play()
		elif hiss_gain<=0.002 and hiss_player.playing: hiss_player.stop()
	if pool<0.28 or intensity<=0.01: puddle_entered = false
	if pool>0.65 and intensity>0.08 and not puddle_entered:
		puddle_entered = true
		if splash_wait<=0.0 and splash_player.stream!=null and audio_ready:
			splash_player.volume_db = lerpf(-32.0,-22.0,intensity)
			splash_player.pitch_scale = randf_range(0.96,1.04)
			splash_player.play()
			splash_wait = 0.65

func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	if not value:
		if rain != null: rain.emitting = false
		for emitter: CPUParticles3D in spray: emitter.emitting = false
		for emitter: CPUParticles3D in mist: emitter.emitting = false
		for emitter: CPUParticles3D in puddle_spray: emitter.emitting = false
		puddle_strength.fill(0.0)
		puddle_entered = false
		if ripples != null: ripples.emitting = false
	else:
		# BUG-1 FIX: Restart the rain emitter whenever weather is enabled so the particle
		# pool is seeded fresh and does not leave a stale one-frame empty AABB that
		# Godot might use for an incorrect frustum cull on the very first rendered frame.
		if rain != null: rain.restart()

func _process(delta: float) -> void:
	if game == null: return
	if not enabled:
		_water_audio(delta,0.0,0.0)
		return
	var car: ArcadeVehicle = game.vehicle
	var next_quality: int = clampi(game.performance.effects_level, 0, 2)
	if next_quality != quality:
		quality = next_quality
		# Fixed pools; changing wetness never reallocates/restarts live particles.
		rain.amount = [50, 110, 220][quality]
		for emitter: CPUParticles3D in spray:
			emitter.amount = [24, 90, 160][quality]
		for emitter: CPUParticles3D in puddle_spray:
			emitter.amount = [12, 52, 92][quality]
		for emitter: CPUParticles3D in mist:
			emitter.amount = [1, 8, 14][quality]
		ripples.amount = [1, 14, 24][quality]

	if car_id != car.spec.vehicle_id:
		car_id = car.spec.vehicle_id
		var definition: Dictionary = RushVehicleCatalog.definition(car_id)
		axle = float(definition.wheelbase) * 0.5
		track = float(definition.width) * 0.5 - 0.055
		rear_wheels.fill(null)
		# Actual imported rear-wheel centres, without hierarchy scans per frame.
		for i: int in car.visual.wheel_pivots.size():
			if car.visual.wheel_front[i]: continue
			var wheel: Node3D = car.visual.wheel_pivots[i]
			var local_center: Vector3 = car.to_local(wheel.global_position)
			rear_wheels[0 if local_center.x<0.0 else 1] = wheel

	var active: bool = game.state in [game.State.DRIVING, game.State.FINISHING, game.State.NETWORK]
	# BUG-1 FIX: Emit rain whenever active regardless of quality tier. The particle
	# count (rain.amount) is already 1/110/220 for LOW/MED/HIGH — LOW is intentionally
	# sparse but should still emit. The previous `quality > 0` guard silently stopped
	# all rain on LOW-quality devices, which was unintentional for Rain City.
	rain.emitting = active
	rain.global_position = car.global_position + Vector3(0, 9, -10)

	var speed: float = absf(car.signed_speed)
	var grounded: bool = car.has_road_contact()
	var wetness: float = clampf(float(game.highway.asphalt.get_shader_parameter("wetness")),0.0,1.0)
	var in_motion: bool = active and car.driving and grounded and speed > 2.0 and wetness>0.01
	var speed_response: float = smoothstep(2.0,65.0,speed)
	var strongest_pool: float = 0.0

	# Rebase/restart jumps discard old world-space spray
	if previous.distance_squared_to(car.global_position) > 400.0:
		for emitter: CPUParticles3D in spray: emitter.restart()
		for emitter: CPUParticles3D in mist: emitter.restart()
		for emitter: CPUParticles3D in puddle_spray: emitter.restart()
		puddle_strength.fill(0.0)
		puddle_entered = false
	previous = car.global_position

	# Update tyre water spray & mist
	for side: int in 2:
		var side_sign: float = -1.0 if side == 0 else 1.0
		var contact: Vector3 = car.global_transform * Vector3(side_sign * track, 0.04, axle)
		if is_instance_valid(rear_wheels[side]): contact = rear_wheels[side].global_position
		contact.y = RushRoadFrame.SURFACE_Y+0.025
		var road_contact: Vector3 = car.course.to_route(contact) if car.course!=null else contact
		var puddle_factor: float = _sample_puddle(road_contact.x, road_contact.z-(car.course.origin_z if car.course!=null else 0.0))*wetness
		puddle_strength[side] = lerpf(puddle_strength[side],puddle_factor,1.0-exp(-delta*18.0))
		puddle_factor = puddle_strength[side]
		strongest_pool = maxf(strongest_pool,puddle_factor)

		var spray_emitter: CPUParticles3D = spray[side]
		spray_emitter.global_position = contact
		var rear: Vector3 = car.global_basis.z * (1.0 if car.signed_speed >= 0.0 else -1.0)
		var outward: Vector3 = car.global_basis.x*side_sign
		# Partial chassis velocity + tyre-relative ejection. World-space droplets
		# retain their launch motion after turning; they do not stick to the vehicle.
		var inherited: Vector3 = car.velocity*0.14
		inherited.y = 0.0
		var launch: Vector3 = inherited+rear*(2.0+speed*0.12)+outward*(0.65+speed_response*1.0)+Vector3.UP*(0.7+puddle_factor*0.45)
		spray_emitter.direction = launch.normalized()
		spray_emitter.initial_velocity_min = launch.length()*0.75
		spray_emitter.initial_velocity_max = launch.length()*1.20
		spray_emitter.spread = 10.0+puddle_factor*8.0
		spray_emitter.color = Color(1,1,1,wetness*(0.18+0.58*speed_response))
		spray_emitter.emitting = in_motion and absf(road_contact.x)<8.1

		var splash: CPUParticles3D = puddle_spray[side]
		splash.global_position = contact
		var splash_launch: Vector3 = inherited+rear*(3.0+speed*0.14)+outward*(1.4+speed_response*1.8)+Vector3.UP*(1.5+speed_response*0.9)
		splash.direction = splash_launch.normalized()
		splash.initial_velocity_min = splash_launch.length()*0.75
		splash.initial_velocity_max = splash_launch.length()*1.15
		splash.spread = 14.0+puddle_factor*9.0
		splash.color = Color(1,1,1,puddle_factor*(0.25+speed_response*0.60))
		splash.emitting = in_motion and absf(road_contact.x)<8.1 and speed>6.0 and puddle_factor>0.40

		var mist_emitter: CPUParticles3D = mist[side]
		mist_emitter.global_position = contact+Vector3(0.0,0.04,0.0)
		var mist_launch: Vector3 = inherited+rear*1.5+outward*0.45+Vector3.UP*0.35
		mist_emitter.direction = mist_launch.normalized()
		mist_emitter.initial_velocity_min = mist_launch.length()*0.8
		mist_emitter.initial_velocity_max = mist_launch.length()
		mist_emitter.color = Color(1,1,1,wetness*speed_response*(0.2+puddle_factor*0.5))
		mist_emitter.emitting = in_motion and absf(road_contact.x)<8.1 and quality>0 and speed>12.0

	_water_audio(delta, speed_response*wetness if in_motion else 0.0,strongest_pool)

	# Rain road surface impact ripples
	ripples.global_position = Vector3(car.global_position.x, RushRoadFrame.SURFACE_Y + 0.015, car.global_position.z - 8.0)
	ripples.rotation.y = 0.0
	if car.course!=null:
		var ahead: Vector3 = car.course.to_route(car.global_position)
		ahead.z -= 8.0
		ahead.y = RushRoadFrame.SURFACE_Y+.015
		ripples.global_position = car.course.to_world(ahead)
		ripples.rotation.y = car.course.heading_at_z(ripples.global_position.z)
	ripples.emitting = active and quality > 0
