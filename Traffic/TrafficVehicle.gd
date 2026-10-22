class_name RushTrafficVehicle
extends AnimatableBody3D
var production_id: String = ""
var original_transparency: Dictionary = {}
var original_alpha: Dictionary = {}
var fade_applied: bool = false
var production: RushProductionTrafficVisual
var viewer: Node3D
var forbidden_meshes: Array[MeshInstance3D] = []
var active: bool = false
var course: RushSampledCourse
var lane_offset: float = 0.0
var previous_yaw: float = 0.0
var lane: int = 0
var speed: float = 20.0
var desired_speed: float = 20.0
var half_width: float = 0.95
var half_length: float = 2.2
var body_height: float = 1.3
var wheel_radius: float = 0.34
var was_hit: bool = false
var pass_resolved: bool = false
var minimum_gap: float = INF
var eligible_pass: bool = false
var previous_position := Vector3.ZERO
var materials: Array[StandardMaterial3D] = []
var wheels: Array[Node3D] = []
var kind: int = 0
var fade: float = 0.0
var detail: int = 2
var quality_level: int = 1
var braking: bool = false
var night_mode: int = 0
var horn_left: float = 0.0
var light_materials: Dictionary = {}
var paint_material: StandardMaterial3D
var visual_meshes: Array[MeshInstance3D] = []
var visual_root: Node3D
var visual_variants: Array[Node3D] = []

func _ready() -> void:
	sync_to_physics = false
	collision_layer = 0
	collision_mask = 0
	var profile: Dictionary = RushTrafficMeshLibrary.profiles[kind]
	half_length = float(profile["length"])*0.5+0.07
	half_width = float(profile["width"])*0.5+0.07
	body_height = float(profile["height"])
	wheel_radius = float(profile["wheel_radius"])
	visual_root = Node3D.new()
	add_child(visual_root)
	visual_root.top_level = true
	if not production_id.is_empty():
		production = RushProductionTrafficVisual.new()
		visual_root.add_child(production)
		production.build(production_id)
		materials = production.materials
		for mat: StandardMaterial3D in materials:
			original_transparency[mat.get_instance_id()] = mat.transparency
			original_alpha[mat.get_instance_id()] = mat.albedo_color.a
		visual_meshes = production.meshes
		paint_material = StandardMaterial3D.new() # Retain NPC public paint contract.
	else:
		var material_map: Dictionary = {}
		for scene: PackedScene in [RushTrafficMeshLibrary.low_scenes[kind],RushTrafficMeshLibrary.medium_scenes[kind],RushTrafficMeshLibrary.scenes[kind]]:
			var model := scene.instantiate() as Node3D
			visual_root.add_child(model)
			visual_variants.append(model)
			_prepare_meshes(model,material_map)
		light_materials = material_map
	set_visual_quality(int(SaveService.settings.quality))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(half_width*2.0,body_height,half_length*2.0)
	collision.shape = shape
	collision.position.y = body_height/2.0
	add_child(collision)
	var contact: MeshInstance3D = RushContactShadow.create(visual_root,Vector2(half_width*2.0,half_length*2.0))
	if production!=null: contact.position.y = .001
	deactivate()

func _prepare_meshes(node: Node, cache: Dictionary) -> void:
	if node is MeshInstance3D:
		var node_name := String(node.name).to_lower()
		if "proxy" in node_name or "collision" in node_name or "debug" in node_name:
			forbidden_meshes.append(node)
			node.hide()
			if OS.is_debug_build():
				push_error("TRAFFIC VISUAL SAFETY: forbidden render mesh hidden: "+String(node.name))
			return
		visual_meshes.append(node)
		for surface: int in node.mesh.get_surface_count():
			var source: StandardMaterial3D = node.get_active_material(surface)
			if source == null:
				continue
			var key := RushAutomotiveMaterials.role(source)
			if not cache.has(key):
				var material := RushAutomotiveMaterials.make(key,Color.WHITE)
				if key=="Paint":
					paint_material = material
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				cache[key] = material
				materials.append(material)
			node.set_surface_override_material(surface,cache[key])
	if String(node.name).begins_with("Wheel_") and node is Node3D:
		wheels.append(node)
	for child: Node in node.get_children():
		_prepare_meshes(child,cache)

func activate(at: Vector3, lane_index: int, velocity_value: float) -> void:
	position = at
	braking = false
	horn_left = 0.0
	detail = 2
	if is_instance_valid(viewer):
		var distance := at.distance_to(viewer.position)
		detail = 2 if distance<=45.0 else (1 if distance<=100.0 else 0)
	_apply_detail()
	position.y = RushRoadFrame.SURFACE_Y
	previous_position = position
	rotation = Vector3.ZERO
	lane_offset = RushRoadFrame.LANE_CENTERS[lane_index]
	if course!=null: rotation.y = course.heading_at_z(position.z)
	previous_yaw = rotation.y
	lane = lane_index
	desired_speed = velocity_value
	speed = velocity_value
	was_hit = false
	pass_resolved = false
	minimum_gap = INF
	eligible_pass = false
	var paint_index := posmod(int(absf(at.z)/17.0)+lane_index*3+kind*5,8)
	paint_material.albedo_color = RushAutomotiveMaterials.TRAFFIC_PAINTS[paint_index]
	if production!=null: production.set_paint(paint_material.albedo_color)
	if production!=null or quality_level == 0:
		set_fade(1.0)
	else:
		fade = 0.0
		fade_applied = false
		set_fade(1.0 if is_instance_valid(viewer) and at.distance_to(viewer.position)<=45.0 else 0.0)
	active = true
	visible = true
	visual_root.global_transform = global_transform
	for wheel: Node3D in wheels:
		wheel.rotation = Vector3.ZERO
	collision_layer = 2

func deactivate() -> void:
	active = false
	visible = false
	collision_layer = 0

func set_fade(value: float) -> void:
	# Production cars spawn ahead of the player. Keep body depth/sorting intact:
	# alpha-fading every GLB surface causes ghosting and expensive transparent draws.
	var next_fade: float = 1.0 if production!=null or quality_level==0 else clampf(value,0.0,1.0)
	if fade_applied and is_equal_approx(fade,next_fade):
		return
	fade = next_fade
	fade_applied = true
	for material: StandardMaterial3D in materials:
		var color := material.albedo_color
		color.a = fade*float(original_alpha.get(material.get_instance_id(),1.0))
		material.albedo_color = color
		# Opaque bodies must not enter transparent triangle sorting at close range.
		material.transparency = int(original_transparency.get(material.get_instance_id(),BaseMaterial3D.TRANSPARENCY_DISABLED)) if fade>=1.0 else BaseMaterial3D.TRANSPARENCY_ALPHA

func _process(delta: float) -> void:
	# Forbidden-mesh safety guard: debug builds only; not worth the loop cost in release.
	if OS.is_debug_build():
		for mesh: MeshInstance3D in forbidden_meshes:
			if mesh.visible:
				mesh.hide()
				push_error("TRAFFIC VISUAL SAFETY: forbidden mesh was made visible")
	if not active:
		return
	visual_root.global_position = previous_position.lerp(position,Engine.get_physics_interpolation_fraction())
	visual_root.global_basis = Basis(Vector3.UP,lerp_angle(previous_yaw,rotation.y,Engine.get_physics_interpolation_fraction()))
	if production!=null:
		# Lamps are cached by state and remain readable before the car reaches near LOD.
		production.set_lights(night_mode>0,braking)
		if detail > 0:
			production.animate(delta,speed)
	else:
		# Generic LOD model: only animate wheels when close enough to notice.
		if detail > 0:
			for wheel: Node3D in wheels:
				wheel.rotate_x(-speed*delta/wheel_radius)
	if light_materials.has("Headlight"):
		light_materials.Headlight.emission = Color("d1e5fc")*(.6 if night_mode>0 else .12)
	if light_materials.has("Taillight"):
		light_materials.Taillight.emission = Color("ed2637")*(.9 if braking else (.42 if night_mode>=2 else 0.0))

func mark_collision() -> void:
	was_hit = true
	pass_resolved = true

func set_visual_quality(level: int) -> void:
	quality_level = clampi(level,0,2)
	set_fade(fade)
	# Quality may reduce shadow cost, never force a crude model beside the player.
	if production==null:
		for mesh: MeshInstance3D in visual_meshes:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if level==0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_apply_detail()
func update_distance_lod(distance: float) -> void:
	# LOD thresholds scale with quality_level so LOW devices get cheaper meshes sooner.
	# quality 0 (LOW):    close<30, mid<70,  far>=70
	# quality 1 (MEDIUM): close<40, mid<90,  far>=90
	# quality 2 (HIGH):   close<45, mid<108, far>=108
	var close_thresh: float = [30.0, 40.0, 45.0][clampi(quality_level,0,2)]
	var far_thresh: float   = [70.0, 90.0, 108.0][clampi(quality_level,0,2)]
	var mid_enter: float    = close_thresh + 7.0  # hysteresis gap
	var mid_exit: float     = far_thresh - 16.0
	var next := detail
	if distance <= close_thresh:
		next = 2
	elif distance > far_thresh:
		next = 0
	elif detail == 2 and distance > mid_enter:
		next = 1
	elif detail == 0 and distance < mid_exit:
		next = 1
	if next != detail:
		detail = next
		_apply_detail()
	if distance <= close_thresh and fade < 1.0:
		set_fade(1.0)
func _apply_detail() -> void:
	if production!=null:
		production.set_detail(detail,quality_level)
		production.set_lights(night_mode>0,braking)
		return
	for i: int in visual_variants.size():
		visual_variants[i].visible = i==detail
	if OS.is_debug_build() and active:
		assert(visual_variants[detail].visible,"TRAFFIC LOD: selected visible mesh missing")
