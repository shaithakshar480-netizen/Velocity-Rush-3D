class_name RushTrafficMeshLibrary
extends RefCounted
## Shared glTF meshes, authored offline; no procedural mesh work on GO or pool activation.
static var profiles: Array = []
static var scenes: Array[PackedScene] = []
static var low_scenes: Array[PackedScene] = []
static var medium_scenes: Array[PackedScene] = []
const PATHS: Array[String] = ["res://Assets/Traffic/luma_c.glb", "res://Assets/Traffic/meridian_s.glb",
	"res://Assets/Traffic/aero_f.glb", "res://Assets/Traffic/summit_x.glb", "res://Assets/Traffic/forge_u.glb"]

static func prepare() -> void:
	if not scenes.is_empty():
		return
	profiles = JSON.parse_string(FileAccess.get_file_as_string("res://Data/TrafficProfiles.json"))
	for path: String in PATHS:
		scenes.append(load(path) as PackedScene)
		medium_scenes.append(load(path.replace("Assets/Traffic/","Assets/Traffic/Medium/")) as PackedScene)
		low_scenes.append(load(path.replace("Assets/Traffic/","Assets/Traffic/Low/")) as PackedScene)
