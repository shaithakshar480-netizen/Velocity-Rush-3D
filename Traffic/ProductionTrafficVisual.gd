class_name RushProductionTrafficVisual
extends Node3D
## Render-only NPC model. Shared meshes; no controllers, saves, audio or cameras.
const IDS: Array[String] = ["vortex_s","falcon_s1","apex_rs","inferno_r","phantom_x","titan_v12","tempest_gt","aether_one"]
static var blueprints: Dictionary = {}
var meshes: Array[MeshInstance3D] = []
var materials: Array[StandardMaterial3D] = []
var paint: Array[StandardMaterial3D] = []
var lamps: Dictionary = {}
var spins: Array[Node3D] = []
var radii: Array[float] = []
var detail: int = 2
var applied_quality: int = -1
var last_night: bool = false
var last_brake: bool = false
var lamps_initialized: bool = false

static func prepare(id: String, tree: SceneTree) -> bool:
	if blueprints.has(id): return true
	var ready: bool = await RushVehicleCatalog.request_scene(id,tree)
	if not ready: return false
	var packed: PackedScene = RushVehicleCatalog.scene_for(id)
	if packed==null: return false
	var source: Node3D = packed.instantiate() as Node3D
	if source==null: return false
	var config: Dictionary = RushVehicleCatalog.definition(id).production_visual
	var regex: RegEx = RegEx.new()
	regex.compile("[^a-z0-9]")
	var roles: Dictionary = {}
	for mapping: Dictionary in [config.get("roles",{}),config.get("wheel_roles",{})]:
		for key: String in mapping: roles[regex.sub(key.to_lower(),"",true)] = mapping[key]
	var hidden: Dictionary = {}
	for key: String in config.get("hidden_meshes",[]): hidden[regex.sub(key.to_lower(),"",true)] = true
	var wheel_nodes: Dictionary = {}
	var groups: Array = config.get("wheels",[])
	for index: int in groups.size():
		for key: String in groups[index].get("meshes",[]): wheel_nodes[regex.sub(key.to_lower(),"",true)] = index
	var offset: Array = config.offset
	var normalization: Transform3D = Transform3D(Basis(Vector3.UP,float(config.yaw)).scaled(Vector3.ONE*float(config.scale)),Vector3(float(offset[0]),float(offset[1]),float(offset[2])))
	var entries: Array[Dictionary] = []
	_collect(source,normalization,regex,roles,hidden,wheel_nodes,entries)
	source.free()
	blueprints[id] = {"entries":entries,"wheels":groups,"fallback":config.get("fallback_lamps",[])}
	return true

static func _collect(node: Node, parent_pose: Transform3D, regex: RegEx, roles: Dictionary, hidden: Dictionary, wheels: Dictionary, entries: Array[Dictionary]) -> void:
	var pose: Transform3D = parent_pose
	if node is Node3D:
		if not (node as Node3D).visible: return
		pose = parent_pose*(node as Node3D).transform
	var key: String = regex.sub(String(node.name).to_lower(),"",true)
	if hidden.has(key): return
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node.mesh!=null:
			var sources: Array[Material] = []
			for surface: int in mesh_node.mesh.get_surface_count(): sources.append(mesh_node.get_active_material(surface))
			entries.append({"mesh":mesh_node.mesh,"pose":pose,"materials":sources,"role":String(roles.get(key,"")),"wheel":int(wheels.get(key,-1))})
	for child: Node in node.get_children(): _collect(child,pose,regex,roles,hidden,wheels,entries)

func build(id: String) -> void:
	var data: Dictionary = blueprints[id]
	for group: Dictionary in data.wheels:
		var spin: Node3D = Node3D.new()
		var point: Array = group.center
		spin.position = Vector3(float(point[0]),float(point[1]),float(point[2]))
		add_child(spin)
		spins.append(spin)
		radii.append(maxf(float(group.radius),.1))
	var cache: Dictionary = {}
	for entry: Dictionary in data.entries:
		var node: MeshInstance3D = MeshInstance3D.new()
		node.mesh = entry.mesh # Vertex/index/texture resources remain shared, including imported mesh LODs.
		var wheel: int = int(entry.wheel)
		if wheel>=0:
			spins[wheel].add_child(node)
			node.transform = spins[wheel].transform.affine_inverse()*entry.pose
		else:
			add_child(node)
			node.transform = entry.pose
		meshes.append(node)
		var role: String = String(entry.role)
		for surface: int in entry.materials.size():
			var source: Material = entry.materials[surface]
			if not source is StandardMaterial3D:
				if source!=null: node.set_surface_override_material(surface,source)
				continue
			var key: String = str(source.get_instance_id())+":"+role
			if not cache.has(key):
				var mat: StandardMaterial3D = source.duplicate() as StandardMaterial3D
				cache[key] = mat
				materials.append(mat)
				if role=="Paint" and mat.albedo_texture==null: paint.append(mat)
				if role=="Tyre":
					mat.metallic = 0.0
					mat.roughness = maxf(mat.roughness,.75)
					if mat.albedo_texture==null: mat.albedo_color = Color(.09,.095,.10,mat.albedo_color.a)
				elif role=="Rim":
					mat.metallic = maxf(mat.metallic,.45)
					mat.roughness = clampf(mat.roughness,.25,.48)
				if role in ["Headlight","Taillight","Reverse"]:
					mat.emission_enabled = true
					if not lamps.has(role): lamps[role] = []
					lamps[role].append(mat)
			node.set_surface_override_material(surface,cache[key])
	RushVehicleLights.install_emissive(self,data.fallback,lamps)
	for role: String in lamps:
		for material: StandardMaterial3D in lamps[role]:
			if not material in materials: materials.append(material)
	set_lights(false,false)

func set_paint(color: Color) -> void:
	for mat: StandardMaterial3D in paint:
		mat.albedo_color = color

func set_lights(night: bool, braking: bool) -> void:
	if lamps_initialized and night==last_night and braking==last_brake: return
	last_night = night
	last_brake = braking
	lamps_initialized = true
	for role: String in lamps:
		var color: Color = Color("d4eeff")
		var energy: float = 1.8 if night else .35
		if role=="Taillight":
			color = Color("ff3548")
			energy = 3.5 if braking else (.65 if night else 0.0)
		elif role=="Reverse": energy = 0.0
		for mat: StandardMaterial3D in lamps[role]: mat.emission = color*energy

func animate(delta: float, speed: float) -> void:
	if detail==0: return
	for i: int in spins.size(): spins[i].rotation.x = fposmod(spins[i].rotation.x-speed*delta/radii[i],TAU)

func set_detail(level: int, quality: int) -> void:
	if detail==level and applied_quality==quality:
		return
	detail = level
	applied_quality = quality
	var cast: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if quality == 2 and level >= 1:
		cast = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	elif quality == 1 and level == 2:
		cast = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var biases: Array = [0.2, 0.4, 0.65] if quality == 0 else ([0.28, 0.5, 0.8] if quality == 1 else [0.35, 0.65, 1.0])
	var bias_value: float = float(biases[clampi(level, 0, 2)])
	for mesh: MeshInstance3D in meshes:
		mesh.lod_bias = bias_value
		mesh.cast_shadow = cast
