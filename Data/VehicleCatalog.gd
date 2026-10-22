class_name RushVehicleCatalog
extends RefCounted
const IDS: Array[String] = ["vortex_s","falcon_s1","apex_rs","inferno_r","phantom_x","titan_v12","tempest_gt","nebula_r","razor_x","solaris_v","cyclone_rs","aether_one"]
const CATEGORIES: Array[String] = ["engine","handling","brakes","tires","transmission"]
static var data: Dictionary = {}
# Stable IDS above remain the save/cloud contract. Only these eight appear in Garage.
const PLAYABLE_IDS: Array[String] = ["vortex_s","falcon_s1","apex_rs","inferno_r","phantom_x","titan_v12","tempest_gt","aether_one"]
const ALIASES: Dictionary = {"nebula_r":"aether_one","razor_x":"phantom_x","solaris_v":"tempest_gt","cyclone_rs":"aether_one"}
static var scene_cache: Dictionary = {}
static var cache_order: Array[String] = []
static func prepare() -> void:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string("res://Data/VehicleCatalog.json"))
static func canonical_id(id: String) -> String:
	return String(ALIASES.get(id,id)) if id in IDS else "vortex_s"
static func garage_slot(id: String, collection: Dictionary) -> String:
	# Preserve the selected legacy purchase, its name, paint and upgrades verbatim.
	var selected: String = String(collection.get("selected","vortex_s"))
	if canonical_id(selected)==id and selected in collection.get("owned",[]):
		return selected
	var best: String = id
	var best_level: int = -1
	for candidate: String in IDS:
		if canonical_id(candidate)!=id or candidate not in collection.get("owned",[]):
			continue
		var levels: Dictionary = collection.get("upgrades",{}).get(candidate,{})
		var total: int = 0
		for category: String in CATEGORIES:
			total += int(levels.get(category,0))
		if total>best_level:
			best = candidate
			best_level = total
	return best
static func visual_paths(id: String) -> Array[String]:
	return [String(definition(id).visual_scene_path)]
static func prepare_models() -> void:
	prepare()
static func scene_for(id: String) -> PackedScene:
	var path: String = String(definition(id).visual_scene_path)
	if not scene_cache.has(path):
		var scene: PackedScene = load(path) as PackedScene
		if scene==null:
			push_error("Production vehicle resource could not be loaded")
			return null
		scene_cache[path] = scene
		cache_order.append(path)
		while cache_order.size()>3:
			scene_cache.erase(cache_order.pop_front())
	return scene_cache[path] as PackedScene
static func request_scene(id: String, tree: SceneTree) -> bool:
	var path: String = String(definition(id).visual_scene_path)
	if scene_cache.has(path): return true
	var status: int = ResourceLoader.load_threaded_get_status(path)
	if status==ResourceLoader.THREAD_LOAD_INVALID_RESOURCE or status==ResourceLoader.THREAD_LOAD_FAILED:
		if ResourceLoader.load_threaded_request(path,"PackedScene")!=OK: return false
	while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame
	if ResourceLoader.load_threaded_get_status(path)!=ResourceLoader.THREAD_LOAD_LOADED: return false
	if not scene_cache.has(path):
		scene_cache[path] = ResourceLoader.load_threaded_get(path)
		cache_order.append(path)
		while cache_order.size()>3:
			scene_cache.erase(cache_order.pop_front())
	return scene_cache[path]!=null
static func prewarm_resources(tree: SceneTree) -> void:
	prepare()
	await request_scene(String(SaveService.collection.get("selected","vortex_s")),tree)

static func definition(id: String) -> Dictionary:
	prepare()
	return data["cars"][maxi(IDS.find(id),0)]
static func price(id: String) -> int:
	return int(definition(id)["price"])
static func upgrade_cost(level: int) -> int:
	prepare()
	return int(data["upgrade_costs"][level]) if level>=0 and level<10 else -1
static func paint_color(index: int) -> Color:
	prepare()
	return Color(data["paints"][clampi(index,0,data["paints"].size()-1)]["hex"])
static func effective(id: String, upgrades: Dictionary) -> VehicleSpec:
	var d := definition(id)
	var s := VehicleSpec.new()
	s.vehicle_id = id
	s.display_name = d["name"]
	for key: String in ["top_speed_kmh","acceleration","steering_response","braking","grip","weight_kg","wheelbase","wheel_radius"]:
		s.set(key,float(d[key]))
	var e := clampi(int(upgrades.get("engine",0)),0,10)
	var h := clampi(int(upgrades.get("handling",0)),0,10)
	var b := clampi(int(upgrades.get("brakes",0)),0,10)
	var t := clampi(int(upgrades.get("tires",0)),0,10)
	var g := clampi(int(upgrades.get("transmission",0)),0,10)
	var m: Dictionary = data["upgrade_modifiers"]
	s.acceleration *= 1.0+e*float(m["engine_acceleration"])+g*float(m["transmission_acceleration"])
	s.top_speed_kmh *= 1.0+e*float(m["engine_speed"])+g*float(m["transmission_speed"])
	s.steering_response *= 1.0+h*float(m["handling_response"])
	s.grip *= 1.0+h*float(m["handling_grip"])+t*float(m["tires_grip"])
	s.braking *= 1.0+b*float(m["brakes"])
	s.turbo = load("res://Data/VortexTurbo.tres").duplicate(true) as RushTurboSpec
	s.turbo.top_speed_kmh = float(d["turbo_speed"])+(s.top_speed_kmh-float(d["top_speed_kmh"]))
	s.turbo.acceleration_multiplier = float(d["turbo_acceleration"])
	s.turbo.charge_multiplier = float(d["turbo_charge"])
	s.camera_anchors.clear()
	for point: Array in d["camera_anchors"]:
		s.camera_anchors.append(Vector3(float(point[0]),float(point[1]),float(point[2])))
	s.exhaust_points.clear()
	for point: Array in d["exhaust_points"]:
		s.exhaust_points.append(Vector3(float(point[0]),float(point[1]),float(point[2])))
	return s

static func upgrade_ad_requirement(target: int) -> int:
	prepare()
	return int(data.upgrade_ad_requirements[clampi(target,1,10)-1])

static func paint_count() -> int:
	prepare()
	return data.paints.size()
