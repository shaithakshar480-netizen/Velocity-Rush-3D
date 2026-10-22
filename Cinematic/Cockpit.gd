class_name RushCockpit
extends Node3D
## Six prebuilt original interiors. Camera mount leaves road sightlines unobstructed.
var interiors: Dictionary = {}
var current_root: Node3D
var steering: Node3D
var speed: Label3D
var gear: Label3D
var status: Label3D
var navigation: Label3D
var rpm_segments: Array[MeshInstance3D] = []
var ambient: StandardMaterial3D
var accent := Color("61d5e2")
var clock: float = 0.0
var active_id: String = ""
var forearms: Array[MeshInstance3D] = []
var grip_width: float = .108
var wheel_origin: Vector3 = Vector3.ZERO

func _ready() -> void:
	for i: int in RushVehicleCatalog.IDS.size():
		_build_interior(RushVehicleCatalog.IDS[i],int(RushVehicleCatalog.definition(RushVehicleCatalog.IDS[i]).interior.style))
	configure("vortex_s")
	visible = false

func configure(id: String) -> void:
	if active_id==id or not interiors.has(id):
		return
	for item: Dictionary in interiors.values():
		item.root.visible = false
	var selected: Dictionary = interiors[id]
	current_root = selected.root
	current_root.visible = true
	steering = selected.wheel
	steering.rotation.z = 0.0
	speed = selected.speed
	gear = selected.gear
	status = selected.status
	navigation = selected.navigation
	rpm_segments.assign(selected.rpm)
	ambient = selected.ambient
	accent = selected.accent
	active_id = id
	forearms.assign(selected.arms)
	grip_width = float(selected.grip_width)
	wheel_origin = selected.wheel_origin
	clock = .1

func _build_interior(id: String, style: int) -> void:
	current_root = Node3D.new()
	current_root.name = id+"_Interior"
	add_child(current_root)
	accent = [Color("61d5e2"),Color("9fcbef"),Color("bfe77d"),Color("ff987b"),Color("94a9ff"),Color("eac996")][style]
	accent = Color(String(RushVehicleCatalog.definition(id).interior.get("accent",accent.to_html(false))))
	var leather: StandardMaterial3D = RoadGeometry.material(Color("18212b"),.035,.82)
	var carbon := RoadGeometry.material(Color("17222a"),.45,.37)
	var metal := RoadGeometry.material(Color("7c8c96"),.85,.27)
	ambient = RoadGeometry.material(accent,.1,.35)
	ambient.emission_enabled = true
	ambient.emission = accent*.25
	var screen := RoadGeometry.material(Color("03070d"),.05,.7)
	screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Unique dashboard architecture: shelf, twin pods, narrow race cowl, wing,
	# floating segmented bridge, and a stitched flagship wraparound.
	match style:
		0:
			_box(Vector3(.12,-.46,-1.01),Vector3(1.65,.20,.38),leather,-.10)
			_box(Vector3(.1,-.355,-.79),Vector3(1.60,.027,.045),carbon)
		1:
			_box(Vector3(.15,-.49,-.99),Vector3(1.65,.19,.43),leather,.08)
			for x: float in [-.13,.13]:
				_box(Vector3(x,-.25,-.98),Vector3(.24,.23,.16),carbon,-.13)
		2:
			_box(Vector3(.10,-.48,-1.02),Vector3(1.62,.15,.27),carbon,-.20)
			_box(Vector3(0,-.225,-.99),Vector3(.45,.22,.11),leather,-.10)
		3:
			for side: float in [-1.0,1.0]:
				var wing := _box(Vector3(side*.39,-.44,-.96),Vector3(.83,.17,.35),leather,-.14)
				wing.rotation.z = side*.055
			_box(Vector3(.40,-.49,-.74),Vector3(.23,.33,.19),metal,-.28)
		4:
			_box(Vector3(.1,-.51,-1.02),Vector3(1.64,.13,.32),leather)
			for x: float in [-.33,0.0,.33,.66]:
				_box(Vector3(x,-.36,-.96),Vector3(.28,.042,.22),carbon,-.12)
		5:
			_box(Vector3(.13,-.44,-1.03),Vector3(1.66,.23,.44),leather,-.08)
			_box(Vector3(.12,-.347,-.79),Vector3(1.61,.020,.045),metal)
			for i: int in 30:
				_box(Vector3(-.65+i*.048,-.371,-.791),Vector3(.018,.002,.002),metal)
	var trim_y: float = [-.375,-.39,-.40,-.365,-.40,-.365][style]
	_box(Vector3(.14,trim_y,-.77),Vector3(1.5,.005,.009),ambient)
	# Thin sloped A-pillars remain at screen edges. Each has a different rake.
	for side: float in [-1.0,1.0]:
		var pillar := _box(Vector3(side*.96,.035,-1.14),Vector3(.020+style*.001,.75,.034),leather)
		pillar.rotation.z = side*(.19+style*.022)
		_box(Vector3(side*.86,-.31,-.82),Vector3(.035,.15,.48),carbon)
	_box(Vector3(0,.43,-1.16),Vector3(1.93,.019,.030),leather)
	# Air outlets vary in geometry, count, placement and slat direction.
	for x: float in [-.58,.73]:
		if style in [1,3]:
			_ring(current_root,Vector3(x,-.32,-.81),.030,.041,metal)
			_box(Vector3(x,-.32,-.814),Vector3(.054,.051,.01),screen)
		else:
			_box(Vector3(x,-.32,-.81),Vector3(.15 if style!=4 else .09,.047,.017),metal)
			_box(Vector3(x,-.32,-.798),Vector3(.137 if style!=4 else .078,.035,.006),screen)
		for slit: int in 3:
			var size_value := Vector3(.003,.027,.004) if style in [2,4] else Vector3(.05,.003,.004)
			var offset := Vector3((slit-1)*.016,0,0) if style in [2,4] else Vector3(0,(slit-1)*.008,0)
			_box(Vector3(x,-.32,-.789)+offset,size_value,carbon)
	var cluster_style := int(RushVehicleCatalog.definition(id).interior.cluster_style)
	var width: float = [.46,.43,.43,.58,.52,.57][cluster_style]
	_box(Vector3(0,-.23,-.954),Vector3(width+.025,.19,.055),carbon)
	if cluster_style in [4,5]:
		for panel: int in 3:
			_box(Vector3((panel-1)*width/3,-.23,-.92),Vector3(width/3-.014,.16,.013),screen)
	else:
		_box(Vector3(0,-.23,-.92),Vector3(width,.16,.013),screen)
	var speed_at := Vector3(-.065,-.221,-.905)
	if cluster_style in [1,2,4]:
		speed_at.x = 0.0
	speed = _text("000",speed_at,52 if cluster_style==1 else 60,.00080,Color("e0f3fa"))
	_text("KM/H",speed_at+Vector3(0,-.038,.001),16,.00062,accent)
	gear = _text("G1",Vector3(width*.34,-.223,-.901),31,.00068,accent)
	status = _text("TURBO x2  /  HP 100",Vector3(0,-.291,-.902),15,.00065,Color("bacdd7"))
	var segments: Array[MeshInstance3D] = []
	for i: int in 20:
		var position_value := Vector3(-width*.43+i*width*.86/19,-.166,-.901)
		var dimensions := Vector3(width*.034,.009,.002)
		var angle := 0.0
		match cluster_style:
			1:
				angle = lerpf(PI*.14,PI*.86,float(i)/19)
				position_value = Vector3(-cos(angle)*.118,-.24+sin(angle)*.095,-.899)
				dimensions = Vector3(.008,.014,.002)
			2: dimensions.y = .007+float(i)*.00055
			3: position_value.y += absf(float(i)-9.5)*.0014
			4:
				position_value.y -= float(i%4)*.004
				dimensions.y = .016
			5:
				position_value.x = -.245+float(i%10)*.011 if i<10 else .145+float(i%10)*.011
				position_value.y = -.183
		var material := RoadGeometry.material(accent if i<16 else Color("ff785c"))
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var segment := _box(position_value,dimensions,material)
		if cluster_style==1:
			segment.rotation.z = -angle+PI*.5
		segments.append(segment)
	# Landscape, portrait, compact track and split flagship consoles are distinct.
	var display_size: Vector3 = [Vector3(.33,.18,.022),Vector3(.23,.16,.022),Vector3(.20,.13,.022),Vector3(.22,.27,.022),Vector3(.34,.14,.022),Vector3(.35,.22,.022)][style]
	var display_x: float = [.49,.46,.43,.46,.51,.51][style]
	_box(Vector3(display_x,-.49,-.84),Vector3(display_size.x-.03,.29,.16),carbon,-.22)
	_box(Vector3(display_x,-.27,-.87),display_size,metal)
	_box(Vector3(display_x,-.27,-.854),display_size-Vector3(.016,.016,.01),screen)
	_text(["VORTEX / DRIVE","FALCON / CONNECT","APEX / TELEMETRY","INFERNO / DYNAMICS","PHANTOM / PULSE","TITAN / GRAND TOUR"][style],Vector3(display_x,-.27+display_size.y*.31,-.843),15,.00056,accent)
	navigation = _text("ROUTE  000%",Vector3(display_x,-.278,-.842),22,.00064,Color("c5dce5"))
	for i: int in (3 if style==5 else 2):
		_ring(current_root,Vector3(display_x+(i-1)*.060,-.40,-.76),.009,.014,metal)
	var wheel_mount := Node3D.new()
	wheel_mount.position = Vector3(0,-.345,-.59)
	current_root.add_child(wheel_mount)
	steering = RushSteeringModel.build(wheel_mount,int(RushVehicleCatalog.definition(id).interior.steering_style),leather,carbon,metal,ambient)
	RushInteriorGeometry.merge_direct(steering)
	RushInteriorGeometry.merge_direct(wheel_mount)
	RushInteriorGeometry.merge_direct(current_root,segments)
	# Original seated driver's gloves grip the actual rotating rim. Forearms stay
	# anchored below the eye line; no skeleton/IK solver or runtime mesh creation.
	var driver_arms: Array[MeshInstance3D] = []
	var steering_style: int = int(RushVehicleCatalog.definition(id).interior.steering_style)
	var grip: float = [.108,.101,.106,.116,.113,.115][steering_style]-.003
	var glove_material: StandardMaterial3D = RoadGeometry.material(Color("b9cbd2"),.05,.72)
	for side: float in [-1.0,1.0]:
		var hand: MeshInstance3D = MeshInstance3D.new()
		var glove: SphereMesh = SphereMesh.new()
		glove.radial_segments = 12
		glove.rings = 6
		glove.radius = .5
		glove.height = 1.0
		hand.mesh = glove
		hand.scale = Vector3(.045,.063,.048)
		hand.position = Vector3(side*grip,0,.014)
		hand.material_override = glove_material
		steering.add_child(hand)
		var arm: MeshInstance3D = MeshInstance3D.new()
		var sleeve: CylinderMesh = CylinderMesh.new()
		sleeve.height = 1.0
		sleeve.top_radius = .024
		sleeve.bottom_radius = .041
		sleeve.radial_segments = 10
		sleeve.rings = 1
		arm.mesh = sleeve
		arm.material_override = carbon
		current_root.add_child(arm)
		var elbow: Vector3 = Vector3(side*.23,-.58,-.20)
		var hand_at: Vector3 = wheel_mount.position+Vector3(side*grip,0,.014)
		var direction: Vector3 = (hand_at-elbow).normalized()
		var right: Vector3 = direction.cross(Vector3.FORWARD).normalized()
		arm.transform = Transform3D(Basis(right,direction*elbow.distance_to(hand_at),right.cross(direction)),(hand_at+elbow)*.5)
		driver_arms.append(arm)
	_disable_cabin_shadows(current_root)
	interiors[id] = {"root":current_root,"wheel":steering,"speed":speed,"gear":gear,"status":status,"navigation":navigation,"rpm":segments,"ambient":ambient,"accent":accent,"arms":driver_arms,"grip_width":grip,"wheel_origin":wheel_mount.position}
	current_root.visible = false

func _box(at: Vector3, dimensions: Vector3, material: Material, pitch: float = 0.0) -> MeshInstance3D:
	var mesh := RushInteriorGeometry.shell(current_root,at,dimensions,material)
	mesh.rotation.x = pitch
	return mesh

func _ring(parent: Node3D, at: Vector3, inner: float, outer: float, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 32
	torus.ring_segments = 8
	mesh.mesh = torus
	mesh.material_override = material
	mesh.rotation.x = PI*.5
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func _text(value: String, at: Vector3, font_size_value: int, pixels: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.position = at
	label.font_size = font_size_value
	label.pixel_size = pixels
	label.modulate = color
	label.outline_size = 0
	current_root.add_child(label)
	return label

func update_instruments(delta: float, car: ArcadeVehicle, _turbo: RushTurboController, health: float, progress: float, night: bool) -> void:
	steering.rotation.z = lerpf(steering.rotation.z,clampf(-car.steering_angle*2.0,-1.15,1.15),1-exp(-12*delta))
	for i: int in forearms.size():
		var side: float = -1.0 if i==0 else 1.0
		var elbow: Vector3 = Vector3(side*.23,-.58,-.20)
		var hand: Vector3 = wheel_origin+steering.basis*Vector3(side*grip_width,0,.014)
		var direction: Vector3 = (hand-elbow).normalized()
		var right: Vector3 = direction.cross(Vector3.FORWARD).normalized()
		forearms[i].transform = Transform3D(Basis(right,direction*elbow.distance_to(hand),right.cross(direction)),(hand+elbow)*.5)
	clock += delta
	if clock<.1:
		return
	clock = 0
	_set_text(speed,"%03d"%roundi(car.speed_kmh()))
	_set_text(gear,"R" if car.signed_speed<-.2 else "G%d"%car.transmission.gear)
	_set_text(status,"TURBO x%d  /  HP %03d"%[int(SaveService.consumables.turbo_inventory),roundi(health)])
	_set_text(navigation,"ROUTE  %03d%%"%roundi(progress*100))
	for i: int in rpm_segments.size():
		rpm_segments[i].visible = float(i)/float(rpm_segments.size())<car.transmission.rpm/float(car.transmission.config.redline_rpm)
	ambient.emission = accent*(.45 if night else .20)

func _set_text(label: Label3D, value: String) -> void:
	if label.text!=value: label.text = value

func _disable_cabin_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_disable_cabin_shadows(child)
