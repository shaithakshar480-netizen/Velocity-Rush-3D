class_name Highway
extends Node3D
const LENGTH: float = 120.0
const COUNT: int = 13
var chunks: Array[Node3D] = []
var target: Node3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var lighting: Environment
var asphalt: ShaderMaterial
var scenery: Array[RushSceneryTile] = []
var route_origin: float = 0.0
var quality: int = 1

var lod_clock: float = 0.0
var shoulder := RoadGeometry.material(Color("65717a"))
var concrete := RoadGeometry.material(Color("929791"))
var stripe := RoadGeometry.material(Color("dbdfc7"))
var cyan := RoadGeometry.material(Color("909a9c"),0.65)
var terrain := RoadGeometry.material(Color("59665f"))
var last_cell: int = 999999
var chunk_cells: Array[int] = []
var lane_guides: Array[Node3D] = []
var ready_for_drive: bool = false
var duel_course_active: bool = false
var duel_collision_layers: Dictionary = {}
var road_collider: StaticBody3D
var sign_material := RoadGeometry.material(Color("164938"))
var lamp_material := RoadGeometry.material(Color("d4dfea"),.1,.4)
var debug_lanes: bool = false
var street_lighting: RushStreetLighting
var course: RushSampledCourse
var course_generation: int = 0
var course_finish_gate: Node3D
var course_run: RushRunManager
var course_road: RushCourseRoad
var straight_collision_layers: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -20
	process_priority = 80
	street_lighting = RushStreetLighting.new()
	add_child(street_lighting)
	_build_continuous_collision()
	asphalt = ShaderMaterial.new()
	asphalt.shader = preload("res://Environment/asphalt.gdshader")
	asphalt.set_shader_parameter("surface_map",preload("res://Assets/Environment/asphalt_surface.png"))
	RushSceneryTile.prepare()
	environment = WorldEnvironment.new()
	var env := Environment.new()
	lighting = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("5a7fa8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_color = Color("bbd4e5")
	env.ambient_light_energy = 0.48
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("869aa9")
	env.fog_density = 0.0018
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-26,-38,0)
	sun.light_color = Color("ffe0b3")
	sun.light_energy = 1.28
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	for i: int in COUNT:
		var chunk := Node3D.new()
		add_child(chunk)
		_build_chunk(chunk,i)
		chunks.append(chunk)
		chunk_cells.append(999999)
		if i%2 == 1:
			await get_tree().process_frame
	course_road = RushCourseRoad.new()
	add_child(course_road)
	course_road.capture(self)
	update_chunks()
	ready_for_drive = true

func _build_chunk(chunk: Node3D, index: int) -> void:
	# Visual tiles only. Collision support NEVER recycles beneath the vehicle.
	RoadGeometry.box(chunk,Vector3(0,RushRoadFrame.SURFACE_Y-0.2,0),Vector3(16.5,0.4,LENGTH),asphalt)
	RoadGeometry.box(chunk,Vector3(0,-0.8,0),Vector3(500,0.5,LENGTH),terrain)
	var stripes: Array[Transform3D] = []
	var posts: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	for side: float in [-1.0,1.0]:
		RoadGeometry.box(chunk,Vector3(side*9.125,-0.2,0),Vector3(1.75,0.4,LENGTH),shoulder)
		RoadGeometry.box(chunk,Vector3(side*8.13,0.03,0),Vector3(0.12,0.015,LENGTH),stripe)
		RoadGeometry.box(chunk,Vector3(side*RushRoadFrame.BARRIER_X,0.55,0),Vector3(0.4,1.1,LENGTH),concrete)
		RoadGeometry.box(chunk,Vector3(side*9.47,0.91,0),Vector3(0.045,0.1,LENGTH),cyan)
		for z: int in range(-56,60,8):
			posts.append(Transform3D(Basis.IDENTITY,Vector3(side*9.45,1.23,z)))
		for z: int in range(-45,60,60):
			lamps.append(Transform3D(Basis.IDENTITY,Vector3(side*10.5,4.0,z)))
			RoadGeometry.box(chunk,Vector3(side*9.5,7.97,z),Vector3(2.3,0.13,0.18),lamp_material)
	for x: float in [-4.0,0.0,4.0]:
		for z: int in range(-56,60,12):
			stripes.append(Transform3D(Basis.IDENTITY,Vector3(x,0.014,z)))
	RoadGeometry.repeated_boxes(chunk,stripes,Vector3(0.12,0.018,5),stripe)
	RoadGeometry.repeated_boxes(chunk,posts,Vector3(0.13,0.38,0.13),stripe)
	RoadGeometry.repeated_boxes(chunk,lamps,Vector3(0.15,8,0.15),concrete)
	var guide := Node3D.new()
	chunk.add_child(guide)
	var lines: Array[Transform3D] = []
	for x: float in RushRoadFrame.LANE_CENTERS:
		lines.append(Transform3D(Basis.IDENTITY,Vector3(x,0.055,0)))
	RoadGeometry.repeated_boxes(guide,lines,Vector3(0.035,0.01,LENGTH),cyan)
	guide.visible = false
	lane_guides.append(guide)
	var scene := RushSceneryTile.new()
	chunk.add_child(scene)
	scenery.append(scene)
	# Concrete panel joints and metal guardrail caps reuse instanced components.
	var joints: Array[Transform3D] = []
	var reflectors: Array[Transform3D] = []
	var grates: Array[Transform3D] = []
	for side: float in [-1.0,1.0]:
		RoadGeometry.box(chunk,Vector3(side*9.7,1.12,0),Vector3(0.45,0.08,LENGTH),shoulder)
		RoadGeometry.box(chunk,Vector3(side*10.5,0.6,0),Vector3(0.1,0.18,LENGTH),shoulder)
		for z: int in range(-60,60,6):
			joints.append(Transform3D(Basis.IDENTITY,Vector3(side*9.49,0.53,z)))
			reflectors.append(Transform3D(Basis.IDENTITY,Vector3(side*9.46,0.84,z+1)))
		for z: int in range(-52,60,12):
			grates.append(Transform3D(Basis.IDENTITY,Vector3(side*8.8,0.015,z)))
		for z: int in [-45,15]:
			RoadGeometry.box(chunk,Vector3(side*9.1,7.92,z),Vector3(1.1,0.10,0.40),concrete)
			RoadGeometry.box(chunk,Vector3(side*9.1,7.855,z),Vector3(0.8,0.015,0.28),stripe)
	RoadGeometry.repeated_boxes(chunk,joints,Vector3(0.022,0.90,0.035),terrain)
	RoadGeometry.repeated_boxes(chunk,reflectors,Vector3(0.018,0.12,0.22),stripe)
	RoadGeometry.repeated_boxes(chunk,grates,Vector3(0.44,0.012,0.7),terrain)
	if index%3==0:
		for x: float in [-11.2,11.2]:
			RoadGeometry.box(chunk,Vector3(x,4.8,-20),Vector3(0.28,9.6,0.4),shoulder)
		RoadGeometry.box(chunk,Vector3(0,9.3,-20),Vector3(22.5,0.20,0.35),shoulder)
		RoadGeometry.box(chunk,Vector3(0,8.8,-20.35),Vector3(22.5,0.12,0.16),shoulder)
		for x: float in [-4.5,4.5]:
			RoadGeometry.box(chunk,Vector3(x,7.9,-20),Vector3(7.8,1.8,0.14),sign_material)
			var sign := Label3D.new()
			sign.text = ["N04   AURORA CITY\n↓ NORTHLINE", "E17   SUMMIT PASS\nCOAST DISTRICT  ↗", "V01   VELOCITY WAY\n↓ CENTRAL LOOP"][posmod(index+(0 if x<0 else 1),3)]
			sign.font_size = 48
			sign.pixel_size = 0.009
			chunk.add_child(sign)
			sign.position = Vector3(x,7.9,-19.91)

	# Non-colliding edge ribs and reflective studs, one instanced batch each.
	var ribs: Array[Transform3D] = []
	var studs: Array[Transform3D] = []
	for side: float in [-1.0,1.0]:
		for z: int in range(-60,60,2):
			ribs.append(Transform3D(Basis.IDENTITY,Vector3(side*8.42,.021,z)))
	for x: float in [-4.0,0.0,4.0]:
		for z: int in range(-59,60,12):
			studs.append(Transform3D(Basis.IDENTITY,Vector3(x,.035,z)))
	RoadGeometry.repeated_boxes(chunk,ribs,Vector3(.32,.008,.14),shoulder)
	RoadGeometry.repeated_boxes(chunk,studs,Vector3(.12,.025,.16),stripe)
	RushRoadBatcher.merge(chunk)
	for side: float in [-1.0,1.0]:
		for z: float in [-45.0,15.0]:
			street_lighting.fixture(chunk,Vector3(side*9.1,7.84,z))

func _process(delta: float) -> void:
	if course!=null and is_instance_valid(course_finish_gate):
		course_finish_gate.position = course.point(course_run.spec.distance_m)
	if ready_for_drive and not duel_course_active:
		street_lighting.update_nearby(target,quality,delta)

func _physics_process(delta: float) -> void:
	if duel_course_active: return
	update_chunks()
	lod_clock += delta
	if lod_clock>=0.2 and is_instance_valid(target):
		lod_clock = 0.0
		for i: int in scenery.size():
			scenery[i].update_lod(absf(chunks[i].position.z-(course.to_route(target.position).z if course!=null else target.position.z)),quality)

func update_chunks() -> void:
	if duel_course_active: return
	if chunks.size() != COUNT:
		return
	var center := 0
	if is_instance_valid(target):
		center = int(floor((course.to_route(target.global_position).z if course!=null else target.global_position.z)/LENGTH))
	if center == last_cell:
		return
	last_cell = center
	for i: int in COUNT:
		var cell := center-7+i
		var slot := posmod(cell,COUNT)
		if chunk_cells[slot] != cell:
			chunk_cells[slot] = cell
			chunks[slot].position.z = cell*LENGTH
			var route_distance := route_origin-cell*LENGTH
			scenery[slot].configure(clampi(int(route_distance/2000.0),0,3),int(floor(-route_distance/LENGTH)))
			if course!=null: course_road.update_slot(slot,float(cell)*LENGTH)
			scenery[slot].update_lod(absf(cell*LENGTH-((course.to_route(target.position).z if course!=null else target.position.z) if is_instance_valid(target) else 0.0)),quality)

func _build_continuous_collision() -> void:
	# Player remains within +/-2401 m before rebasing; the deck covers +/-10000 m.
	road_collider = _static_box(Vector3(0,-0.5,0),Vector3(20,1,RushRoadFrame.COLLISION_LENGTH),1)
	for side: float in [-1.0,1.0]:
		_static_box(Vector3(side*RushRoadFrame.BARRIER_X,0.55,0),Vector3(0.4,1.1,RushRoadFrame.COLLISION_LENGTH),4)

func _static_box(at: Vector3, size_value: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size_value
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	body.position = at
	return body

func set_debug_lanes(value: bool) -> void:
	debug_lanes = value and OS.is_debug_build()
	for guide: Node3D in lane_guides:
		guide.visible = debug_lanes

func set_quality(level: int) -> void:
	quality = level
	asphalt.set_shader_parameter("detail_strength",0.45 if level==0 else 1.0)
	asphalt.set_shader_parameter("quality", level)
	sun.shadow_enabled = level > 0
	sun.directional_shadow_max_distance = [25.0, 55.0, 90.0][level]

	lighting.fog_density = [0.0022,0.0018,0.0015][level]
	if course_road!=null: course_road.sync_material()

	for i: int in scenery.size():
		scenery[i].distance_bucket = -1
		scenery[i].update_lod(absf(chunks[i].position.z-((course.to_route(target.position).z if course!=null else target.position.z) if is_instance_valid(target) else 0.0)),level)

func prewarm_sections() -> void:
	for section: int in 4:
		for tile: RushSceneryTile in scenery:
			tile.configure(section,3)
			tile.update_lod(0.0,2)
		await get_tree().process_frame
	last_cell = 999999
	update_chunks()

func set_duel_course(value: bool) -> void:
	if value: clear_sampled_course() # Existing Duel geometry/protocol owns its road.
	if duel_course_active==value: return
	duel_course_active = value
	for chunk: Node3D in chunks: chunk.visible = not value
	street_lighting.visible = not value
	if value:
		for child: Node in get_children():
			if child is StaticBody3D:
				var body: StaticBody3D = child as StaticBody3D
				duel_collision_layers[body] = body.collision_layer
				body.collision_layer = 0
	else:
		for body: StaticBody3D in duel_collision_layers:
			if is_instance_valid(body): body.collision_layer = int(duel_collision_layers[body])
		duel_collision_layers.clear()
		last_cell = 999999
		update_chunks()

func prepare_sampled_course(meters: float) -> void:
	clear_sampled_course()
	var sampled := RushSampledCourse.new()
	sampled.build(meters)
	var ticket: int = course_generation
	await course_road.prepare(sampled)
	if ticket!=course_generation: return
	course = sampled
	course_road.set_enabled(true)
	chunk_cells.fill(999999)
	course_road.sync_material()
	for child: Node in get_children():
		if child is StaticBody3D:
			straight_collision_layers[child] = child.collision_layer
			child.collision_layer = 0
	last_cell = 999999
	update_chunks()

func clear_sampled_course() -> void:
	course_generation += 1
	course = null
	if course_road==null: return
	course_road.set_enabled(false)
	chunk_cells.fill(999999)
	for body: StaticBody3D in straight_collision_layers:
		if is_instance_valid(body): body.collision_layer = int(straight_collision_layers[body])
	straight_collision_layers.clear()
	last_cell = 999999
