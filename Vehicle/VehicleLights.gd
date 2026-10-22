class_name RushVehicleLights
extends Node3D
var car: ArcadeVehicle
var night: int = 0
var beams: Array[SpotLight3D] = []
var brake_glow: float = 0.0
var reverse_nodes: Array[MeshInstance3D] = []
var high_brake: MeshInstance3D
var high_mat: StandardMaterial3D
var reverse_mat: StandardMaterial3D
var director: Node = null
var hazard_timer: float = 0.0
func _ready() -> void:
	for side: float in [-1.0,1.0]:
		var beam := SpotLight3D.new()
		beam.position = Vector3(side*.65,.68,-1.8)
		beam.rotation.x = -.05
		beam.spot_range = 85
		beam.spot_angle = 32
		beam.spot_attenuation = .18
		beam.light_color = Color("dfedff")
		beam.light_energy = 2.5
		beam.shadow_enabled = false
		add_child(beam)
		beams.append(beam)
	reverse_mat = RoadGeometry.material(Color("a8bac6"),.1,.3)
	reverse_mat.emission_enabled = true
	for side: float in [-1.0,1.0]:
		reverse_nodes.append(RoadGeometry.box(self,Vector3(side*.47,.54,2.04),Vector3(.065,.012,.008),reverse_mat))
	high_mat = RoadGeometry.material(Color("671322"),.1,.25)
	high_mat.emission_enabled = true
	high_brake = RoadGeometry.box(self,Vector3(0,.9,2),Vector3(.42,.018,.022),high_mat)
func configure() -> void:
	var data := RushVehicleCatalog.definition(car.spec.vehicle_id)
	# Production GLBs keep their own lamp geometry; hide old add-on light bars.
	var production: bool = data.has("production_visual")
	for node: MeshInstance3D in reverse_nodes:
		node.visible = not production
	high_brake.visible = not production
	var anchors: Dictionary = data.light_anchors
	for i: int in 2:
		var point: Array = anchors["front_left_light_anchor" if i==0 else "front_right_light_anchor"]
		beams[i].position = Vector3(float(point[0]),float(point[1]),float(point[2]))
		point = anchors["reverse_left_anchor" if i==0 else "reverse_right_anchor"]
		reverse_nodes[i].position = Vector3(float(point[0]),float(point[1]),float(point[2]))
	var high: Array = anchors.high_brake_anchor
	high_brake.position = Vector3(float(high[0]),float(high[1]),float(high[2]))
func _process(delta: float) -> void:
	if car==null:
		return
	var body: Node3D = car.visual.body_shells[car.visual.active_index][car.visual.quality]
	global_transform = body.global_transform if body!=null else car.render_pose()
	var braking: bool = car.last_command.y<0 and car.signed_speed>=0
	brake_glow = 1.0 if braking else move_toward(brake_glow,0.0,delta*7.0)
	var is_night: bool = night in [1,2,3]
	for beam: SpotLight3D in beams:
		beam.visible = is_night
		beam.light_energy = [0.0,.85,1.8,2.7,0.0][night]
	var mats: Dictionary = car.visual.material_sets[car.visual.active_index]
	if mats.has("Headlight"):
		mats.Headlight.emission = Color("cce9ff")*(.75 if is_night else 0.0)

	# BUG-3 FIX: Danger / Hazard light logic and daytime rear lights.
	# Hazard mode is active when crashed, destroyed, or in critical damage (stage >= 3).
	var is_hazard: bool = (director != null and (director.crash_left > 0.0 or director.exploded or director.damage.stage >= 3))
	var hazard_mode: int = 0
	if is_hazard:
		hazard_timer += delta
		var flash_on: bool = fmod(hazard_timer, 0.44) < 0.22
		hazard_mode = 1 if flash_on else 2
	else:
		hazard_timer = 0.0

	var tail_color := Color("ff3548")
	var day_base: float = 0.0 # Taillight is OFF by day when not braking
	var night_base: float = 0.40 # Soft running light at night
	var base_emission: float = night_base if is_night else day_base

	if hazard_mode == 1:
		car.visual.brake_mat.emission = Color("ffaa00") * 2.5
		high_mat.emission = Color("ffaa00") * 2.5
	elif hazard_mode == 2:
		car.visual.brake_mat.emission = tail_color * base_emission
		high_mat.emission = Color.BLACK
	else:
		car.visual.brake_mat.emission = tail_color * lerpf(base_emission, 1.2, brake_glow)
		high_mat.emission = tail_color * (1.2 * brake_glow)

	car.visual.update_lamps(is_night, brake_glow, car.signed_speed < -.2, hazard_mode)
	reverse_mat.emission = Color("dceaff") * (.8 if car.signed_speed < -.2 else 0.0)


# Shared by race and showroom VortexVisuals; no extra real-time lights.
static func install_emissive(parent: Node3D, anchors: Array, roles: Dictionary) -> void:
	for anchor: Dictionary in anchors:
		var role: String = String(anchor.role)
		var lamp := MeshInstance3D.new()
		var quad := QuadMesh.new()
		var dimensions: Array = anchor.size
		quad.size = Vector2(float(dimensions[0]),float(dimensions[1]))
		lamp.mesh = quad
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("e6f5ff") if role=="Headlight" else Color("e52b38")
		material.emission_enabled = true
		material.roughness = 0.3
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		lamp.material_override = material
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(lamp)
		var point: Array = anchor.position
		lamp.position = Vector3(float(point[0]),float(point[1]),float(point[2]))
		lamp.rotation.y = PI if bool(anchor.front) else 0.0
		if not roles.has(role): roles[role] = []
		roles[role].append(material)
