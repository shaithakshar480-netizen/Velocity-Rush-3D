class_name RushShowroom
extends Node3D

var visual: VortexVisual
var camera: Camera3D
var backdrop: Node3D
var backdrop_clearance_scale: float = 1.0
var sky_variants: Array[Sky] = []
var environment: Environment
var active: bool = false
var fit_center: Vector3 = Vector3(0, .7, 0)
var fit_radius: float = 3.0
var fitted_distance: float = 0.0
var fit_points: Array[Vector3] = []
var orbit: float = 2.5
var target_orbit: float = 2.5
var pointer: int = -1
var mouse_drag: bool = false
var interaction: Control
var model_transition: Tween
var displayed_id: String = ""
var selection_ticket: int = 0
var bounds_cache: Dictionary = {}
var bounds_order: Array[String] = []
var studio_clock: float = 0.0
var studio_rims: Array[OmniLight3D] = []

# Cinematic lighting and atmosphere extensions
var studio_key: DirectionalLight3D
var studio_fill: OmniLight3D
var studio_top: SpotLight3D
var platform_ring: MeshInstance3D
var platform_ring_mat: StandardMaterial3D
var dust_particles: GPUParticles3D
var _was_active: bool = false
var _reveal_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	backdrop = Node3D.new()
	backdrop.name = "OrbitClearanceBackdrop"
	add_child(backdrop)
	
	# Premium dark reflective showroom floor
	var floor_mat := RoadGeometry.material(Color("0b1017"), 0.65, 0.16)
	RoadGeometry.box(self, Vector3(0, -0.12, 0), Vector3(36, 0.2, 36), floor_mat)
	
	# 1. Main Platform Base Disc
	var platform := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.3
	disc.bottom_radius = 3.4
	disc.height = 0.12
	disc.radial_segments = 64
	platform.mesh = disc
	platform.material_override = RoadGeometry.material(Color("161f2b"), 0.55, 0.22)
	platform.position.y = -0.055
	add_child(platform)

	# 2. Concentric Inner Turntable Disc
	var inner_platform := MeshInstance3D.new()
	var inner_disc := CylinderMesh.new()
	inner_disc.top_radius = 2.75
	inner_disc.bottom_radius = 2.82
	inner_disc.height = 0.02
	inner_disc.radial_segments = 64
	inner_platform.mesh = inner_disc
	inner_platform.material_override = RoadGeometry.material(Color("0d131b"), 0.72, 0.18)
	inner_platform.position.y = 0.01
	add_child(inner_platform)

	# 3. Illuminated Outer Halo Edge Ring
	platform_ring = MeshInstance3D.new()
	var halo := CylinderMesh.new()
	halo.top_radius = 3.36
	halo.bottom_radius = 3.38
	halo.height = 0.04
	halo.radial_segments = 64
	platform_ring.mesh = halo
	platform_ring_mat = RoadGeometry.material(Color("082530"))
	platform_ring_mat.emission_enabled = true
	platform_ring_mat.emission = Color("00e5ff") * 0.95
	platform_ring.material_override = platform_ring_mat
	platform_ring.position.y = -0.02
	add_child(platform_ring)

	# 4. Concentric Floor Detail (Radial alignment ticks on turntable using repeated_boxes)
	var tick_mat := RoadGeometry.material(Color("00b8d4"))
	tick_mat.emission_enabled = true
	tick_mat.emission = Color("00e5ff") * 0.5
	var tick_xforms: Array[Transform3D] = []
	for i: int in 16:
		var angle: float = float(i) * (TAU / 16.0)
		var t := Transform3D()
		t = t.rotated(Vector3.UP, angle)
		t.origin = Vector3(sin(angle) * 3.05, 0.008, cos(angle) * 3.05)
		tick_xforms.append(t)
	RoadGeometry.repeated_boxes(self, tick_xforms, Vector3(0.04, 0.005, 0.25), tick_mat)

	# 5. Cyan Light Strips & Floor Guide Runners
	var light_mat := RoadGeometry.material(Color("aee9f8"))
	light_mat.emission_enabled = true
	light_mat.emission = Color("00d4ff") * 0.75
	for side: float in [-1.0, 1.0]:
		# Vertical corner light pillars
		RoadGeometry.box(backdrop, Vector3(side * 6.5, 2.5, -6.5), Vector3(0.06, 5.0, 0.06), light_mat)
		# Floor embedded luminous runners
		RoadGeometry.box(backdrop, Vector3(side * 4.8, 0.005, 0), Vector3(0.035, 0.005, 14.0), light_mat)
		# Outer side accent strips
		RoadGeometry.box(backdrop, Vector3(side * 7.2, 0.005, 1.5), Vector3(0.025, 0.005, 8.0), light_mat)

	# 6. Architectural Studio Ribs & Dark Studio Bulkhead
	var architecture := RoadGeometry.material(Color("18202b"), 0.5, 0.35)
	for i: int in 11:
		RoadGeometry.box(backdrop, Vector3(-10 + i * 2, 2.4, -9.5), Vector3(0.12, 5.0, 0.4), architecture)
	
	# Rear ambient back-wall panel with subtle horizontal contrast
	RoadGeometry.box(backdrop, Vector3(0, 2.5, -10.0), Vector3(24.0, 5.2, 0.1), RoadGeometry.material(Color("0d131c"), 0.3, 0.6))
	
	# Overhead studio softboxes & ceiling light trusses
	for side: float in [-1.0, 1.0]:
		RoadGeometry.box(backdrop, Vector3(side * 3.6, 5.0, 0), Vector3(0.9, 0.04, 6.0), light_mat)
		RoadGeometry.box(backdrop, Vector3(side * 6.5, 0.12, 0), Vector3(0.03, 0.02, 16.0), architecture)
	RoadGeometry.box(backdrop, Vector3(0, 5.2, 0), Vector3(2.2, 0.03, 7.5), light_mat)

	_build_workshop()

	# Car Visual Model
	visual = VortexVisual.new()
	add_child(visual)

	# 7. Cinematic 4-Point Lighting Rig
	# A. Key Light (Direct luxury sunbeam highlights car contours and hood lines)
	studio_key = DirectionalLight3D.new()
	studio_key.rotation_degrees = Vector3(-42, -30, 0)
	studio_key.light_energy = 1.15
	studio_key.light_color = Color("fff5e6")
	add_child(studio_key)

	# B. Studio Top Spotlight (Focuses car center from ceiling, dramatic separation from floor)
	studio_top = SpotLight3D.new()
	studio_top.position = Vector3(0, 5.4, 0.2)
	studio_top.rotation_degrees = Vector3(-90, 0, 0)
	studio_top.spot_angle = 32.0
	studio_top.spot_range = 9.0
	studio_top.light_energy = 1.35
	studio_top.light_color = Color("d8f3ff")
	add_child(studio_top)

	# C. Opposite Warm Fill Light (Gentle golden/amber bounce on opposite flank)
	studio_fill = OmniLight3D.new()
	studio_fill.position = Vector3(3.6, 1.2, 2.8)
	studio_fill.omni_range = 8.5
	studio_fill.light_energy = 0.65
	studio_fill.light_color = Color("ffd299")
	add_child(studio_fill)

	# D. Dual Dynamic Rim Lights (Preserved in studio_rims for test & physics compatibility)
	for side: float in [-1.0, 1.0]:
		var rim := OmniLight3D.new()
		rim.position = Vector3(side * 4.2, 2.8, -2.0)
		rim.omni_range = 10.0
		rim.light_energy = 1.7
		rim.light_color = Color("00e5ff") if side < 0 else Color("ffb066")
		add_child(rim)
		studio_rims.append(rim)

	# 8. Environment & Studio Reflections
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("060a10")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a6c4dc")
	environment.ambient_light_energy = 0.52
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var studio := PanoramaSkyMaterial.new()
	studio.panorama = preload("res://Assets/Environment/studio_reflections.hdr")
	for size_value: Sky.RadianceSize in [Sky.RADIANCE_SIZE_64, Sky.RADIANCE_SIZE_128, Sky.RADIANCE_SIZE_512]:
		var sky := Sky.new()
		sky.sky_material = studio
		sky.radiance_size = size_value
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		sky_variants.append(sky)
	environment.sky = sky_variants[int(SaveService.settings.quality)]
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# 9. Subtle Atmosphere Floating Dust Motes (Quality-gated)
	_setup_particles()

	# Camera Setup
	camera = Camera3D.new()
	camera.fov = 43.0
	camera.near = 0.1
	add_child(camera)
	visible = false

func _setup_particles() -> void:
	if int(SaveService.settings.quality) < 1:
		return
	dust_particles = GPUParticles3D.new()
	dust_particles.amount = 28 if int(SaveService.settings.quality) == 1 else 50
	dust_particles.lifetime = 6.0
	dust_particles.preprocess = 3.0
	dust_particles.speed_scale = 0.6
	
	var part_mat := ParticleProcessMaterial.new()
	part_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	part_mat.emission_box_extents = Vector3(3.2, 0.28, 3.2)
	part_mat.gravity = Vector3(0, 0.015, 0)
	part_mat.direction = Vector3(0, 1, 0)
	part_mat.spread = 45.0
	part_mat.initial_velocity_min = 0.05
	part_mat.initial_velocity_max = 0.15
	dust_particles.process_material = part_mat
	
	var pmesh := QuadMesh.new()
	pmesh.size = Vector2(0.012, 0.012)
	var pmat := StandardMaterial3D.new()
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pmat.albedo_color = Color(0.85, 0.95, 1.0, 0.28)
	pmesh.material = pmat
	dust_particles.draw_pass_1 = pmesh
	dust_particles.position = Vector3(0, 0.32, 0)
	add_child(dust_particles)

func show_vehicle(id: String, paint: int) -> void:
	selection_ticket += 1
	var ticket: int = selection_ticket
	var resource_ready: bool = await RushVehicleCatalog.request_scene(id,get_tree())
	if not resource_ready: return
	if not is_inside_tree() or ticket!=selection_ticket: return
	visual.select_model(id, RushVehicleCatalog.paint_color(paint))
	visual.position = Vector3.ZERO
	displayed_id = id
	var path: String = String(RushVehicleCatalog.definition(id).visual_scene_path)
	if bounds_cache.has(path):
		var cached: Dictionary = bounds_cache[path]
		fit_points = cached.points
		fit_center = cached.center
		fit_radius = float(cached.radius)
		return
	var points: Array[Vector3] = []
	_collect_bounds(visual.lod_models[visual.active_index][visual.quality], points)
	if not points.is_empty():
		var bounds: AABB = AABB(points[0], Vector3.ZERO)
		for point: Vector3 in points:
			bounds = bounds.expand(point)
		fit_center = bounds.get_center()
		fit_radius = bounds.size.length() * .5
		fit_points = points
		bounds_cache[path] = {"points":points,"center":fit_center,"radius":fit_radius}
		bounds_order.append(path)
		while bounds_order.size()>3:
			bounds_cache.erase(bounds_order.pop_front())

func _collect_bounds(node: Node3D, points: Array[Vector3]) -> void:
	if not node.visible:
		return
	if node is MeshInstance3D and node.mesh != null:
		var bounds: AABB = node.get_aabb()
		var local_pose: Transform3D = global_transform.affine_inverse() * node.global_transform
		for i: int in 8:
			points.append(local_pose * bounds.get_endpoint(i))
	for child: Node in node.get_children():
		if child is Node3D:
			_collect_bounds(child, points)

func close() -> void:
	selection_ticket += 1 # Invalidate an outstanding preview load.
	active = false
	_was_active = false
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	if model_transition != null and model_transition.is_valid():
		model_transition.kill()
	visual.position.x = 0.0
	visible = false
	pointer = -1
	mouse_drag = false

func set_profile_view() -> void:
	# Hero angle: -0.55 rad (~-31.5°) front 3/4 view.
	# sin(-0.55)=-0.523, cos(-0.55)=+0.852 → camera at positive Z, full car visible.
	target_orbit = -0.55
	orbit = -0.55
	pointer = -1
	mouse_drag = false
	fitted_distance = 0.0

func set_garage_view() -> void:
	target_orbit = 2.5
	orbit = 2.5
	pointer = -1
	mouse_drag = false
	fitted_distance = 0.0

func _input(event: InputEvent) -> void:
	if not active or not is_instance_valid(interaction):
		return
	if event is InputEventScreenTouch:
		if event.pressed and pointer < 0 and interaction.get_global_rect().has_point(event.position):
			pointer = event.index
		elif event.index == pointer and not event.pressed:
			pointer = -1
	elif event is InputEventScreenDrag and event.index == pointer:
		target_orbit -= event.relative.x * 0.006
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_drag = event.pressed and interaction.get_global_rect().has_point(event.position)
	elif event is InputEventMouseMotion and mouse_drag:
		target_orbit -= event.relative.x * 0.006

func _trigger_reveal() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = create_tween().set_parallel(true)
	
	# 1. Subtle camera FOV reveal (smooth settle into standard 43.0 FOV)
	camera.fov = 46.5
	_reveal_tween.tween_property(camera, "fov", 43.0, 1.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# 2. Key light power rise
	if is_instance_valid(studio_key):
		studio_key.light_energy = 0.25
		_reveal_tween.tween_property(studio_key, "light_energy", 1.15, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# 3. Studio top light reveal
	if is_instance_valid(studio_top):
		studio_top.light_energy = 0.0
		_reveal_tween.tween_property(studio_top, "light_energy", 1.35, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# 4. Fill light rise
	if is_instance_valid(studio_fill):
		studio_fill.light_energy = 0.1
		_reveal_tween.tween_property(studio_fill, "light_energy", 0.65, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if not active:
		_was_active = false
		return
	
	# Entrance reveal trigger detection
	if not _was_active:
		_was_active = true
		_trigger_reveal()

	studio_clock += delta
	
	# Animate dynamic rim lights
	for i: int in studio_rims.size():
		studio_rims[i].position.z = -2.0 + sin(studio_clock * 0.35 + float(i) * PI) * 1.3
		studio_rims[i].light_energy = 1.6 + sin(studio_clock * 0.4 + float(i)) * 0.16

	# Subtle top light breathing effect
	if is_instance_valid(studio_top):
		studio_top.light_energy = 1.35 + sin(studio_clock * 0.5) * 0.08

	# Platform neon halo breathing pulse
	if is_instance_valid(platform_ring_mat):
		var pulse: float = 0.95 + sin(studio_clock * 1.2) * 0.18
		platform_ring_mat.emission = Color("00e5ff") * pulse

	# Slow premium idle camera orbit (smooth, non-intrusive)
	if pointer < 0 and not mouse_drag:
		target_orbit += delta * 0.055
	
	orbit = lerp_angle(orbit, target_orbit, 1.0 - exp(-10.0 * delta))
	
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var usable: Rect2 = Rect2(Vector2.ZERO, viewport_size)
	if is_instance_valid(interaction) and interaction.is_visible_in_tree():
		usable = interaction.get_global_rect()

	# Godot KEEP_HEIGHT makes fov vertical. Fit a bounding sphere at every orbit.
	var tangent: float = tan(deg_to_rad(camera.fov) * .5)
	var direction: Vector3 = Vector3(sin(orbit), .32, cos(orbit)).normalized()
	var horizontal: float = tangent * maxf(usable.size.x / viewport_size.y, .03)
	var vertical: float = tangent * maxf(usable.size.y / viewport_size.y, .03)
	var distance: float = 1.0
	for point: Vector3 in fit_points:
		var local: Vector3 = point - fit_center
		var radial: float = Vector2(local.x, local.z).length()
		var depth: float = radial * .953 + absf(local.y) * .305
		distance = maxf(distance, depth + 1.15 * maxf(radial / horizontal, (radial * .305 + absf(local.y) * .953) / vertical))
	
	# Keep the bounds-derived fit even for a narrow showroom region.
	
	fitted_distance = distance if distance > fitted_distance else lerpf(fitted_distance, distance, 1.0 - exp(-7.0 * delta))
	distance = fitted_distance
	
	# Tiny organic camera breathing drift for extra luxury automotive showroom realism
	var framing_drift: Vector3 = Vector3(
		sin(studio_clock * 0.4) * 0.018,
		cos(studio_clock * 0.3) * 0.012,
		sin(studio_clock * 0.35) * 0.018
	)
	camera.position = fit_center + direction * distance + framing_drift
	camera.look_at(fit_center)
	camera.v_offset = (usable.get_center().y / viewport_size.y - .5) * 2.0 * distance * tangent
	camera.h_offset = (.5 - usable.get_center().x / viewport_size.x) * 2.0 * distance * tangent
	# The old 6–8 m enclosure cut through the bounds-fitted camera orbit.
	# Include the optical frustum offsets, not just Camera3D.position.
	# 4.8 m is below the nearest ceiling/wall solid's original inner radius.
	var optical_radius: float = camera.position.length()+absf(camera.h_offset)+absf(camera.v_offset)
	var required_scale: float = maxf(1.0,(optical_radius+2.0)/4.8)
	# Grow only during this showroom session: no breathing walls while dragging.
	if required_scale>backdrop_clearance_scale:
		backdrop_clearance_scale = required_scale
		backdrop.scale = Vector3.ONE*backdrop_clearance_scale


func set_quality(level: int) -> void:
	visual.set_quality(level)
	if not sky_variants.is_empty():
		environment.sky = sky_variants[clampi(level, 0, 2)]
	
	# Scalable quality settings for mobile optimization
	if level == 0:
		if is_instance_valid(studio_top):
			studio_top.visible = false
		if is_instance_valid(studio_fill):
			studio_fill.visible = false
		if is_instance_valid(dust_particles):
			dust_particles.emitting = false
	elif level == 1:
		if is_instance_valid(studio_top):
			studio_top.visible = true
			studio_top.light_energy = 0.9
		if is_instance_valid(studio_fill):
			studio_fill.visible = true
			studio_fill.light_energy = 0.45
		if is_instance_valid(dust_particles):
			dust_particles.emitting = true
			dust_particles.amount = 25
	else:
		if is_instance_valid(studio_top):
			studio_top.visible = true
			studio_top.light_energy = 1.35
		if is_instance_valid(studio_fill):
			studio_fill.visible = true
			studio_fill.light_energy = 0.65
		if is_instance_valid(dust_particles):
			dust_particles.emitting = true
			dust_particles.amount = 50

# Static workshop architecture around the live car, shared materials and no extra lights.
func _build_workshop() -> void:
	var metal: StandardMaterial3D = RoadGeometry.material(Color("465263"),0.55,0.4)
	var inset: StandardMaterial3D = RoadGeometry.material(Color("202d3b"),0.35,0.55)
	var trim: StandardMaterial3D = RoadGeometry.material(Color("778999"),0.65,0.32)
	var black: StandardMaterial3D = RoadGeometry.material(Color("0c1822"),0.15,0.6)
	var cyan: StandardMaterial3D = RoadGeometry.material(Color("77c9df"))
	cyan.emission_enabled = true
	cyan.emission = Color("50badd")*0.7
	var screen_mat: StandardMaterial3D = RoadGeometry.material(Color("16364b"))
	screen_mat.emission_enabled = true
	screen_mat.emission = Color("225b76")*0.6
	# Four bays keep the backdrop complete throughout the existing orbit/drag.
	for side: int in 4:
		var bay := Node3D.new()
		add_child(bay)
		bay.rotation.y = side*PI*0.5
		_workshop_box(bay,Vector3(0,2.8,-8.5),Vector3(17,5.6,.2),inset)
		for column: int in 4:
			var x: float = -6.0+column*4.0
			_workshop_box(bay,Vector3(x,2.9,-8.25),Vector3(3.7,4.9,.18),metal)
			_workshop_box(bay,Vector3(x,2.9,-8.12),Vector3(3.25,4.35,.08),inset)
			for edge: float in [-1.0,1.0]:
				_workshop_box(bay,Vector3(x+edge*1.73,2.9,-8.02),Vector3(.055,4.7,.04),cyan)
			_workshop_box(bay,Vector3(x,1.45,-8.02),Vector3(3.35,.045,.04),cyan)
			_workshop_box(bay,Vector3(x,4.65,-8.02),Vector3(3.35,.045,.04),cyan)
			# Recessed diagnostics console, backed by physical wall panels.
			_workshop_box(bay,Vector3(x,1.1,-7.95),Vector3(2.8,.62,.35),black)
			for monitor: int in 3:
				var mx: float = x+(monitor-1)*.84
				_workshop_box(bay,Vector3(mx,1.15,-7.75),Vector3(.7,.38,.025),screen_mat)
				for line: int in 3:
					_workshop_box(bay,Vector3(mx-.08,1.05+line*.085,-7.725),Vector3(.38+line*.045,.013,.008),cyan)
		# Raised maintenance walkway and railing.
		_workshop_box(bay,Vector3(0,3.15,-7.0),Vector3(15,.16,1.2),metal)
		_workshop_box(bay,Vector3(0,3.95,-6.42),Vector3(15,.045,.045),trim)
		for post: int in 11:
			_workshop_box(bay,Vector3(-7.2+post*1.44,3.57,-6.42),Vector3(.035,.85,.035),trim)
		# Open floor-level tools replace the tall drawer cabinets.
		for x: float in [-6.4,6.4]:
			# Low workshop jack: twin runners, lifting arm and saddle.
			for rail: float in [-.22,.22]:
				_workshop_box(bay,Vector3(x+rail,.065,-6.6),Vector3(.08,.17,1.05),metal)
			_workshop_box(bay,Vector3(x,.18,-6.65),Vector3(.12,.12,.7),trim)
			_workshop_box(bay,Vector3(x,.3,-6.95),Vector3(.3,.08,.28),black)
			_workshop_box(bay,Vector3(x,.5,-6.1),Vector3(.035,.9,.035),trim)
			_workshop_box(bay,Vector3(x,.96,-6.1),Vector3(.28,.04,.04),black)
			# Three open-ended spanners resting on the floor, with visible split jaws.
			for tool: int in 3:
				var tx: float = x-.55+tool*.2
				var tz: float = -5.9+tool*.08
				_workshop_box(bay,Vector3(tx,.005,tz),Vector3(.055,.035,.42),trim)
				_workshop_box(bay,Vector3(tx,.005,tz-.23),Vector3(.14,.035,.055),trim)
				for jaw: float in [-.055,.055]:
					_workshop_box(bay,Vector3(tx+jaw,.005,tz-.28),Vector3(.035,.035,.1),trim)
		_workshop_box(bay,Vector3(0,5.35,-5.8),Vector3(15,.18,.22),trim)
	_flush_workshop_boxes()
	# True thin rings, rather than luminous filled discs over the car footprint.
	for radius: float in [2.65,2.86,3.52,3.9]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius-.014
		torus.outer_radius = radius+.014
		torus.rings = 64
		torus.ring_segments = 6
		ring.mesh = torus
		ring.material_override = cyan
		ring.position.y = .018 if radius<3.3 else -.008
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)

var workshop_batches: Dictionary = {}
func _workshop_box(parent: Node3D, at: Vector3, dimensions: Vector3, material: StandardMaterial3D) -> void:
	var key: String = str(material.get_instance_id())+":"+str(dimensions)
	if not workshop_batches.has(key):
		workshop_batches[key] = {"poses":[],"size":dimensions,"material":material}
	var pose: Transform3D = parent.transform
	pose.origin = parent.transform*at
	workshop_batches[key].poses.append(pose)

func _flush_workshop_boxes() -> void:
	for batch: Dictionary in workshop_batches.values():
		var poses: Array[Transform3D] = []
		poses.assign(batch.poses)
		RoadGeometry.repeated_boxes(backdrop,poses,batch.size,batch.material)
	workshop_batches.clear()
