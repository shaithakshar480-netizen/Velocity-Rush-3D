class_name RushAutomotiveMaterials
extends RefCounted
## Material roles are explicit. No dependency on glTF vertex-color import switches.
const TRAFFIC_PAINTS: Array[Color] = [Color("dfded5"),Color("20242d"),Color("909ca4"),Color("545b63"),Color("203f65"),Color("832735"),Color("314d40"),Color("80674b")]
static func role(source: Material) -> String:
	if source == null:
		return "Trim"
	for name_value: String in ["Paint","Glass","Trim","Rubber","Alloy","Headlight","Taillight","Carbon","Housing","BrakeDisc","BrakeCaliper","Lens","LightInternals"]:
		if source.resource_name.begins_with(name_value):
			return name_value
	return "Trim"
static func make(role_name: String, paint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = role_name
	mat.vertex_color_use_as_albedo = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	match role_name:
		"Paint":
			mat.albedo_color = paint
			mat.metallic = 0.68
			mat.roughness = 0.23
		"Glass":
			mat.albedo_color = Color("234353")
			mat.metallic = 0.42
			mat.roughness = 0.12
		"Rubber":
			mat.albedo_color = Color("101218")
			mat.roughness = 0.92
		"Alloy":
			mat.albedo_color = Color("a4b3bf")
			mat.metallic = 0.8
			mat.roughness = 0.25
		"Carbon":
			mat.albedo_color = Color("172025")
			mat.metallic = 0.32
			mat.roughness = 0.38
		"Housing":
			mat.albedo_color = Color("252b32")
			mat.metallic = 0.62
			mat.roughness = 0.23
		"BrakeCaliper":
			mat.albedo_color = Color("b34931")
			mat.metallic = 0.45
			mat.roughness = 0.30
		"Lens":
			mat.albedo_color = Color("7896ac")
			mat.metallic = 0.55
			mat.roughness = 0.09
		"LightInternals":
			mat.albedo_color = Color("bbc9d5")
			mat.metallic = 0.85
			mat.roughness = 0.16
		"BrakeDisc":
			mat.albedo_color = Color("737b83")
			mat.metallic = 0.75
			mat.roughness = 0.48
		"Headlight","Taillight":
			mat.albedo_color = Color("b9e5ee") if role_name=="Headlight" else Color("a70e22")
			mat.emission_enabled = true
			mat.emission = mat.albedo_color*0.16
			mat.roughness = 0.3
		_:
			mat.albedo_color = Color("141e29")
			mat.roughness = 0.6
	return mat

static var shared_player: Dictionary = {}
static func player_material(role_name: String) -> StandardMaterial3D:
	if role_name in ["Paint","Taillight","Headlight"]:
		return make(role_name,Color.WHITE)
	if not shared_player.has(role_name):
		shared_player[role_name] = make(role_name,Color.WHITE)
	return shared_player[role_name]

static func paint_quality(mat: StandardMaterial3D, level: int) -> void:
	mat.metallic = [0.55,0.72,0.78][clampi(level,0,2)]
	mat.roughness = [0.32,0.25,0.20][clampi(level,0,2)]
	# Compatibility deliberately uses the cheaper base PBR highlight path.
	mat.clearcoat_enabled = level==2 and RenderingServer.get_current_rendering_method()!="gl_compatibility"
	mat.clearcoat = 0.6
	mat.clearcoat_roughness = 0.18
