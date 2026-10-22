class_name RushDuelCourse
extends Node3D
## Fixed multiplayer-only geometry. Network coordinates remain world X/Y/Z.
const DISTANCE: float = 2000.0
const STEP: float = 10.0
const STATIONS: Array[float] = [0.0,150.0,450.0,650.0,1050.0,1250.0,1550.0,1800.0,2000.0]
const OFFSETS: Array[float] = [0.0,0.0,-2.4,-2.4,2.4,2.4,-1.8,0.0,0.0]

static func center_x(z: float) -> float:
	var distance: float = clampf(-z,0.0,DISTANCE)
	for i: int in STATIONS.size()-1:
		if distance<=STATIONS[i+1]:
			var t: float = (distance-STATIONS[i])/(STATIONS[i+1]-STATIONS[i])
			var eased: float = t*t*t*(t*(t*6.0-15.0)+10.0)
			return lerpf(OFFSETS[i],OFFSETS[i+1],eased)
	return 0.0

func build(highway: Highway) -> void:
	# Continuous shared edges, no recycling, no transforms rewritten during racing.
	_strip(-8.25,8.25,0.0,highway.asphalt,0)
	_strip(-10.0,-8.25,0.0,highway.shoulder,0)
	_strip(8.25,10.0,0.0,highway.shoulder,0)
	_strip(-10.0,10.0,0.0,null,1)
	for side: float in [-1.0,1.0]:
		_strip(side*8.13-.06,side*8.13+.06,.015,highway.stripe,0)
		_wall(side*9.7,highway.concrete)
	var markings: Array[Transform3D] = []
	var posts: Array[Transform3D] = []
	var fixtures: Array[Transform3D] = []
	for distance: int in range(-12,2040,12):
		var z: float = -float(distance)
		# Short dashes follow the same centerline; yaw wraps to the forward road direction.
		var yaw: float = -atan((center_x(z-1.0)-center_x(z+1.0))/2.0)
		for x: float in [-4.0,0.0,4.0]:
			markings.append(Transform3D(Basis(Vector3.UP,yaw),Vector3(center_x(z)+x,.022,z)))
		for side: float in [-1.0,1.0]:
			posts.append(Transform3D(Basis.IDENTITY,Vector3(center_x(z)+side*9.45,1.22,z)))
		# No dynamic traffic lights; small shared emissive roadside reflectors.
		if distance%60==0:
			for side: float in [-1.0,1.0]:
				fixtures.append(Transform3D(Basis.IDENTITY,Vector3(center_x(z)+side*10.8,3.0,z)))
	RoadGeometry.repeated_boxes(self,markings,Vector3(.12,.012,5.0),highway.stripe)
	RoadGeometry.repeated_boxes(self,posts,Vector3(.10,.24,.12),highway.stripe)
	RoadGeometry.repeated_boxes(self,fixtures,Vector3(.16,6.0,.16),highway.concrete)
	RoadGeometry.box(self,Vector3(0,-.8,-1000),Vector3(500,.5,2200),highway.terrain)
	# Reuse low-cost landscape shapes, placed relative to the course (not a fake visual bend).
	var hills: Array[Transform3D] = []
	for distance: int in range(0,2200,160):
		for side: float in [-1.0,1.0]:
			var z: float = -float(distance)
			hills.append(Transform3D(Basis.IDENTITY.scaled(Vector3(35,12+distance%3*3,65)),Vector3(center_x(z)+side*65,2,z)))
	var hill_mesh: SphereMesh = SphereMesh.new()
	hill_mesh.radial_segments = 12
	hill_mesh.rings = 6
	var hill_batch: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var instances: MultiMesh = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = hill_mesh
	instances.instance_count = hills.size()
	for i: int in hills.size(): instances.set_instance_transform(i,hills[i])
	hill_batch.multimesh = instances
	hill_batch.material_override = highway.terrain
	hill_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hill_batch)
	_finish(highway)

func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal: Vector3 = (b-a).cross(c-a).normalized()
	for point: Vector3 in [a,c,b,a,d,c]:
		surface.set_normal(normal)
		surface.set_uv(Vector2(point.x*.08,-point.z*.08))
		surface.add_vertex(point)

func _strip(left: float, right: float, y: float, material: Material, layer: int) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in 206:
		var z0: float = 20.0-i*STEP
		var z1: float = z0-STEP
		_quad(surface,Vector3(center_x(z0)+left,y,z0),Vector3(center_x(z0)+right,y,z0),Vector3(center_x(z1)+right,y,z1),Vector3(center_x(z1)+left,y,z1))
	surface.generate_tangents()
	_install(surface.commit(),material,layer)

func _wall(x: float, material: Material) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in 206:
		var z0: float = 20.0-i*STEP
		var z1: float = z0-STEP
		var a: Vector3 = Vector3(center_x(z0)+x-.2,0,z0)
		var b: Vector3 = Vector3(center_x(z0)+x+.2,0,z0)
		var c: Vector3 = Vector3(center_x(z1)+x+.2,0,z1)
		var d: Vector3 = Vector3(center_x(z1)+x-.2,0,z1)
		var up: Vector3 = Vector3.UP*1.1
		_quad(surface,a,a+up,d+up,d)
		_quad(surface,b,c,c+up,b+up)
		_quad(surface,a+up,b+up,c+up,d+up)
	_install(surface.commit(),material,4)

func _install(mesh: ArrayMesh, material: Material, layer: int) -> void:
	if material!=null:
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	if layer!=0:
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = layer
		body.collision_mask = 0
		var shape: CollisionShape3D = CollisionShape3D.new()
		var triangles: ConcavePolygonShape3D = mesh.create_trimesh_shape()
		triangles.backface_collision = true
		shape.shape = triangles
		body.add_child(shape)
		add_child(body)

func _finish(highway: Highway) -> void:
	var gate: Node3D = Node3D.new()
	gate.position = Vector3(center_x(-DISTANCE),0,-DISTANCE)
	add_child(gate)
	var dark: StandardMaterial3D = RoadGeometry.material(Color("0b1724"),.35,.45)
	var accent: StandardMaterial3D = RoadGeometry.material(Color("38e4e8"),.2,.35)
	accent.emission_enabled = true
	accent.emission = Color("24a5b0")
	for x: float in [-9.0,9.0]:
		RoadGeometry.box(gate,Vector3(x,3.6,0),Vector3(.45,7.2,.65),dark)
		RoadGeometry.box(gate,Vector3(x,3.6,.34),Vector3(.12,6.8,.025),accent)
	RoadGeometry.box(gate,Vector3(0,7.1,0),Vector3(18.5,1.5,.65),dark)
	RoadGeometry.box(gate,Vector3(0,6.35,.35),Vector3(18.0,.10,.04),accent)
	var label: Label3D = Label3D.new()
	label.text = "FINISH"
	label.font_size = 112
	label.pixel_size = .028
	label.position = Vector3(0,7.1,.34)
	label.outline_size = 0
	label.no_depth_test = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(label)
	var white_cells: Array[Transform3D] = []
	var dark_cells: Array[Transform3D] = []
	for x: int in range(-8,8):
		for row: int in 2:
			var cell: Transform3D = Transform3D(Basis.IDENTITY,Vector3(x+.5,.025,row-.5))
			if (x+row)%2==0: white_cells.append(cell)
			else: dark_cells.append(cell)
	RoadGeometry.repeated_boxes(gate,white_cells,Vector3(1,.012,1),highway.stripe)
	RoadGeometry.repeated_boxes(gate,dark_cells,Vector3(1,.012,1),dark)
	for distance: int in [300,150,50]:
		for side: float in [-1.0,1.0]:
			var marker: Node3D = Node3D.new()
			marker.position = Vector3(center_x(-DISTANCE+distance)+side*10.8,0,-DISTANCE+distance)
			add_child(marker)
			RoadGeometry.box(marker,Vector3(0,1.8,0),Vector3(.13,3.6,.13),highway.concrete)
			RoadGeometry.box(marker,Vector3(0,3.2,0),Vector3(2.2,1.1,.12),dark)
			var sign: Label3D = Label3D.new()
			sign.text = "FINISH\n%d m"%distance
			sign.font_size = 48
			sign.pixel_size = .012
			sign.position = Vector3(0,3.2,.07)
			sign.outline_size = 0
			sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			marker.add_child(sign)
