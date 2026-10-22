class_name RushBrakeEffects
extends Node3D
## Bounded rear-tire trails using the constrained flat-road vehicle's traction proxy.
var game: Node
var trail: MultiMeshInstance3D
var mesh: MultiMesh
var ages: PackedFloat32Array = PackedFloat32Array()
var strengths: PackedFloat32Array = PackedFloat32Array()
var cursor: int = 0
var previous: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
var connected: bool = false
var run_id: int = -1
var friction: AudioStreamPlayer
var squeal: AudioStreamPlayer
var smoke: Array[CPUParticles3D] = []
var slip: float = 0.0
var audio_profiles: Dictionary = {}
var brake_banks: Dictionary = {}
var sound_car: String = ""
var brake_gain: float = 0.0
var squeal_gain: float = 0.0
var fade_clock: float = 0.0
const LIFETIME: float = 22.0
func build(owner_game: Node) -> void:
	game = owner_game
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 10
	GameAudio.external_brakes = true
	mesh = MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2.ONE
	mesh.mesh = plane
	mesh.instance_count = 640
	ages.resize(640)
	strengths.resize(640)
	ages.fill(LIFETIME)
	for i: int in 640:
		mesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
	trail = MultiMeshInstance3D.new()
	trail.multimesh = mesh
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://VFX/skid.gdshader")
	trail.material_override = material
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)
	audio_profiles = JSON.parse_string(FileAccess.get_file_as_string("res://Data/VehicleAudioProfiles.json"))
	for id: String in RushVehicleCatalog.IDS:
		var clips: Array[AudioStreamWAV] = []
		for key: String in ["brake_path","tire_path"]:
			var clip: AudioStreamWAV = load(String(audio_profiles[id][key])) as AudioStreamWAV
			clip.loop_mode = AudioStreamWAV.LOOP_FORWARD
			clip.loop_end = int(clip.get_length()*clip.mix_rate)
			clips.append(clip)
		brake_banks[id] = clips
	friction = _loop("brake_friction")
	squeal = _loop("tire_squeal")
	for side: int in 2:
		var puff: CPUParticles3D = CPUParticles3D.new()
		puff.amount = [6,18,30][int(SaveService.settings.quality)]
		puff.lifetime = .6
		puff.emitting = false
		puff.direction = Vector3.UP
		puff.initial_velocity_min = .3
		puff.initial_velocity_max = 1.2
		puff.scale_amount_min = .12
		puff.scale_amount_max = .3
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2.ONE
		puff.mesh = quad
		puff.local_coords = false
		puff.gravity = Vector3(0,.7,0)
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = preload("res://VFX/atmosphere_sprite.gdshader")
		mat.set_shader_parameter("tint",Color(.64,.67,.69,.3))
		puff.material_override = mat
		var fade: Gradient = Gradient.new()
		fade.set_color(0,Color(1,1,1,.6))
		fade.set_color(1,Color(1,1,1,0))
		puff.color_ramp = fade
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)
		smoke.append(puff)
func _loop(name_value: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	var stream: AudioStreamWAV = load("res://Assets/Audio/"+name_value+".wav")
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length()*stream.mix_rate)
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = -80
	add_child(player)
	player.play()
	return player
func _physics_process(delta: float) -> void:
	if game==null:
		return
	if run_id!=game.run.run_id:
		ages.fill(LIFETIME)
		for i: int in 640:
			mesh.set_instance_color(i,Color(0,0,0,0))
		connected = false
		run_id = game.run.run_id
	var car: ArcadeVehicle = game.vehicle
	if sound_car!=car.spec.vehicle_id:
		sound_car = car.spec.vehicle_id
		friction.stream = brake_banks[sound_car][0]
		squeal.stream = brake_banks[sound_car][1]
		friction.play()
		squeal.play()
		brake_gain = 0.0
		squeal_gain = 0.0
		friction.volume_db = -80.0
		squeal.volume_db = -80.0
	var active: bool = game.state==game.State.DRIVING and car.driving
	var speed: float = absf(car.signed_speed)
	var brake: float = maxf(-car.last_command.y,0) if car.signed_speed>1.0 else (maxf(car.last_command.y,0) if car.signed_speed < -1.0 else 0.0)
	var grounded: bool = absf(car.position.y-RushRoadFrame.SURFACE_Y)<.08
	var traction_loss: float = maxf(0.0,absf(car.acceleration_now)/maxf(car.spec.grip*1.6,18.0)-.8)*brake
	var target: float = clampf(maxf(car.skid_amount-.24,traction_loss),0,1) if active and grounded and speed>8 else 0.0
	slip = lerpf(slip,target,1.0-exp(-12.0*delta))
	# Audio follows actual slowing, not steering-derived skid_amount.
	# Signed acceleration must oppose travel (also correct while reversing).
	var slowing: float = maxf(-car.acceleration_now * signf(car.signed_speed),0.0)
	var deceleration: float = smoothstep(0.4,18.0,slowing)
	var throttle: float = maxf(car.last_command.y * signf(car.signed_speed),0.0)
	var coast: float = (1.0-smoothstep(0.0,0.15,throttle))*smoothstep(0.4,4.0,slowing)*0.035
	var grip_sound: float = smoothstep(1.0,38.0,speed)*maxf(pow(brake,1.25)*lerpf(.10,.24,deceleration),coast) if active and grounded and slowing>0.4 else 0.0
	# Reserve the existing squeal for genuine hard-braking traction loss.
	# Steering alone still drives visual skid effects but cannot trigger this sound.
	var tire_sound: float = smoothstep(.55,1.0,brake)*smoothstep(.02,.35,traction_loss)*smoothstep(3.0,14.0,slowing)*smoothstep(8.0,35.0,speed)*.18 if active and grounded else 0.0
	brake_gain = lerpf(brake_gain,grip_sound,1.0-exp(-(14.0 if grip_sound>brake_gain else 6.0)*delta))
	squeal_gain = lerpf(squeal_gain,tire_sound,1.0-exp(-(10.0 if tire_sound>squeal_gain else 4.0)*delta))
	friction.volume_db = linear_to_db(maxf(brake_gain,.0001))
	squeal.volume_db = linear_to_db(maxf(squeal_gain,.0001))
	var pitch: float = float(audio_profiles[sound_car].brake_pitch)
	friction.pitch_scale = lerpf(friction.pitch_scale,pitch*(.82+clampf(speed/70.0,0,1)*.32),1.0-exp(-5.0*delta))
	squeal.pitch_scale = lerpf(squeal.pitch_scale,pitch*(.88+smoothstep(8.0,60.0,speed)*.20+slip*.06),1.0-exp(-5.0*delta))
	var quality: int = clampi(game.performance.effects_level,0,2)
	var limit: int = [160,360,640][quality]
	var definition: Dictionary = RushVehicleCatalog.definition(car.spec.vehicle_id)
	var emitting: bool = active and grounded and speed>8 and slip>.12
	for side: int in 2:
		var contact: Vector3 = car.global_transform*Vector3((-1.0 if side==0 else 1.0)*(float(definition.width)*.5-.055),0,float(definition.wheelbase)*.5)
		contact.y = RushRoadFrame.SURFACE_Y+.008
		if emitting and connected:
			var distance: float = contact.distance_to(previous[side])
			if distance>.12 and distance<8:
				var forward: Vector3 = (contact-previous[side]).normalized()
				var right: Vector3 = Vector3.UP.cross(forward).normalized()
				mesh.set_instance_transform(cursor,Transform3D(Basis(right*.22,Vector3.UP,forward*(distance+.025)),(contact+previous[side])*.5))
				ages[cursor] = 0
				strengths[cursor] = clampf(slip*.8,.10,.55)
				cursor = (cursor+1)%limit
		previous[side] = contact
		var smoke_count: int = [6,18,30][quality]
		if smoke[side].amount!=smoke_count:
			smoke[side].amount = smoke_count
		smoke[side].position = contact+Vector3(0,.06,0)
		smoke[side].emitting = emitting and slip>.27 and quality>0

	connected = emitting
	fade_clock += delta
	# Age all slots (only up to quality limit; unused upper slots stay at LIFETIME).
	for i: int in limit:
		ages[i] += delta
	if fade_clock > .1:
		fade_clock = 0
		for i: int in limit:
			mesh.set_instance_color(i,Color(.025,.027,.03,strengths[i]*clampf(1.0-ages[i]/LIFETIME,0,1)))
	trail.visible = game.state in [game.State.DRIVING,game.State.PAUSED,game.State.FINISHING]
func rebase(shift: Vector3) -> void:
	for i: int in 640:
		var pose: Transform3D = mesh.get_instance_transform(i)
		pose.origin -= shift
		mesh.set_instance_transform(i,pose)
	for i: int in 2:
		previous[i] -= shift
