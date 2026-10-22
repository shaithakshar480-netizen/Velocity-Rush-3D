class_name VortexVisual
extends Node3D
## Imported production visuals only. Stable slot arrays remain compatible with
## showroom, camera and damage consumers; only the selected model is instantiated.
var lamp_state: Vector4 = Vector4(-1,-1,-1,-1)
var body_root: Node3D
var wheel_pivots: Array[Node3D] = []
var wheel_meshes: Array[Node3D] = []
var brake_mat: StandardMaterial3D
var models: Array[Node3D] = []
var lod_models: Array = []
var body_shells: Array = []
var wheel_sets: Array = []
var material_sets: Array = []
var active_index: int = 0
var quality: int = 1
var attachment_overrides: Dictionary = {}
var radius: float = 0.34
var shadow: MeshInstance3D
var loaded_path: String = ""
var loaded_holder: Node3D
var imported_model: Node3D
var wheel_front: Array[bool] = []
var wheel_radii: Array[float] = []
var role_materials: Dictionary = {}
var material_cache: Dictionary = {}
var mesh_lookup: Dictionary = {}
var role_lookup: Dictionary = {}
var hidden_lookup: Dictionary = {}
var name_filter: RegEx
var prepared_cache: Dictionary = {}
var last_paint: Color = Color(-1,-1,-1,-1)
var last_roughness: float = -1.0
const VENENO_PAINT: Shader = preload("res://Vehicle/VenenoPaint.gdshader")
var is_veneno: bool = false
# Original vertex/index/UV buffers, without auto-generated simplification indices.
# Shared only by this player/showroom visual class; no traffic LOD changes.
static var veneno_full_meshes: Dictionary = {}

func _veneno_full_mesh(source: ArrayMesh, key: String) -> ArrayMesh:
	if veneno_full_meshes.has(key):
		return veneno_full_meshes[key].mesh as ArrayMesh
	var full: ArrayMesh = ArrayMesh.new()
	for surface: int in source.get_surface_count():
		full.add_surface_from_arrays(source.surface_get_primitive_type(surface),source.surface_get_arrays(surface))
		full.surface_set_material(surface,source.surface_get_material(surface))
	# Stable imported node names bound this cache to the 24 supplied Veneno meshes.
	veneno_full_meshes[key] = {"source":source,"mesh":full}
	return full


func _ready() -> void:
	quality = int(SaveService.settings.quality)
	name_filter = RegEx.new()
	name_filter.compile("[^a-z0-9]")
	body_root = Node3D.new()
	add_child(body_root)
	for _i: int in RushVehicleCatalog.IDS.size():
		models.append(null)
		lod_models.append([null,null,null])
		body_shells.append([null,null,null])
		wheel_sets.append([[],[],[]])
		material_sets.append({})
	shadow = RushContactShadow.create(self,Vector2(1.95,4.3))
	shadow.position.y = 0.001 # Below the tyre contact margin, not through its sidewall.
	var id: String = String(SaveService.collection.get("selected","vortex_s"))
	var paints: Dictionary = SaveService.collection.get("paints",{})
	select_model(id,RushVehicleCatalog.paint_color(int(paints.get(id,5))))

func _key(value: String) -> String:
	return name_filter.sub(value.to_lower(),"",true)

func _collect(node: Node, config: Dictionary) -> void:
	if node is AnimationPlayer:
		(node as AnimationPlayer).stop()
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if is_veneno and mesh_node.mesh is ArrayMesh:
			mesh_node.mesh = _veneno_full_mesh(mesh_node.mesh as ArrayMesh,String(node.name))
		var key: String = _key(String(node.name))
		mesh_lookup[key] = mesh_node
		if hidden_lookup.has(key):
			mesh_node.visible = false
			return
		var role: String = String(role_lookup.get(key,""))
		if mesh_node.mesh!=null:
			for surface: int in mesh_node.mesh.get_surface_count():
				var source: Material = mesh_node.get_active_material(surface)
				if not source is StandardMaterial3D:
					continue
				# This exact supplied material is the textured body atlas, not glass/rims.
				if is_veneno and _key(source.resource_name)=="material24001":
					var paint_key: String = "veneno_atlas:"+str(source.get_instance_id())
					if not material_cache.has(paint_key):
						var atlas_paint: ShaderMaterial = ShaderMaterial.new()
						atlas_paint.shader = VENENO_PAINT
						atlas_paint.set_shader_parameter("body_atlas",(source as StandardMaterial3D).albedo_texture)
						material_cache[paint_key] = atlas_paint
					mesh_node.set_surface_override_material(surface,material_cache[paint_key])
					continue
				# Duplicate imported material resources, preserving every texture/channel.
				var cache_key: String = str(source.get_instance_id())+":"+role
				if not material_cache.has(cache_key):
					var mat: StandardMaterial3D = source.duplicate() as StandardMaterial3D
					material_cache[cache_key] = mat
					if not role.is_empty():
						if not role_materials.has(role): role_materials[role] = []
						role_materials[role].append(mat)
					if role=="Paint" and mat.albedo_texture==null:
						mat.metallic = maxf(mat.metallic,0.4)
						mat.roughness = minf(mat.roughness,0.32)
					elif role=="Tyre":
						mat.metallic = 0.0
						mat.roughness = maxf(mat.roughness,0.75)
						if mat.albedo_texture==null:
							mat.albedo_color = Color(0.09,0.095,0.10,mat.albedo_color.a)
					elif role=="Rim":
						mat.metallic = maxf(mat.metallic,0.45)
						mat.roughness = clampf(mat.roughness,0.25,0.48)
						if mat.albedo_texture==null and mat.albedo_color.get_luminance()<0.04:
							mat.albedo_color = Color(0.12,0.13,0.14,mat.albedo_color.a)
					elif role in ["Headlight","Taillight","Reverse"]:
						mat.emission_enabled = true
				mesh_node.set_surface_override_material(surface,material_cache[cache_key])
	for child: Node in node.get_children():
		_collect(child,config)

func _install_wheels(config: Dictionary) -> void:
	for group: Dictionary in config.get("wheels",[]):
		var targets: Array[Node3D] = []
		for source_name: String in group.get("meshes",[]):
			var key: String = _key(source_name)
			if mesh_lookup.has(key): targets.append(mesh_lookup[key] as Node3D)
		if targets.is_empty():
			push_warning("Production wheel mapping did not resolve")
			continue
		var point: Array = group.center
		var steer := Node3D.new()
		loaded_holder.add_child(steer)
		steer.position = Vector3(float(point[0]),float(point[1]),float(point[2]))
		var spin := Node3D.new()
		steer.add_child(spin)
		for target: Node3D in targets:
			# Imported vertex buffers stay untouched; retain the full world transform.
			target.reparent(spin,true)
		wheel_pivots.append(steer)
		wheel_meshes.append(spin)
		wheel_front.append(bool(group.front))
		wheel_radii.append(maxf(float(group.radius),0.1))

func _stash_model() -> void:
	if loaded_holder==null: return
	for cached: Dictionary in prepared_cache.values():
		var holder: Node3D = cached.holder
		holder.queue_free()
	prepared_cache.clear()
	loaded_holder.visible = false
	prepared_cache[loaded_path] = {"holder":loaded_holder,"model":imported_model,
		"pivots":wheel_pivots,"spins":wheel_meshes,"front":wheel_front,"radii":wheel_radii,
		"roles":role_materials,"materials":material_cache,"lookup":mesh_lookup}

func select_model(id: String, paint: Color) -> void:
	var next_is_veneno: bool = RushVehicleCatalog.canonical_id(id)=="aether_one"
	var data: Dictionary = RushVehicleCatalog.definition(id)
	var path: String = String(data.visual_scene_path)
	var next_index: int = maxi(RushVehicleCatalog.IDS.find(id),0)
	if loaded_holder==null or loaded_path!=path:
		var cached: Dictionary = prepared_cache.get(path,{})
		prepared_cache.erase(path)
		var next_model: Node3D = null
		if cached.is_empty():
			var packed: PackedScene = RushVehicleCatalog.scene_for(id)
			if packed==null: return
			next_model = packed.instantiate() as Node3D
			if next_model==null: return
		is_veneno = next_is_veneno
		_stash_model()
		if not cached.is_empty():
			loaded_holder = cached.holder
			imported_model = cached.model
			wheel_pivots = cached.pivots
			wheel_meshes = cached.spins
			wheel_front = cached.front
			wheel_radii = cached.radii
			role_materials = cached.roles
			material_cache = cached.materials
			mesh_lookup = cached.lookup
			loaded_holder.visible = true
		else:
			wheel_pivots = []
			wheel_meshes = []
			wheel_front = []
			wheel_radii = []
			mesh_lookup = {}
			material_cache = {}
			role_materials = {}
			role_lookup = {}
			hidden_lookup = {}
			loaded_holder = Node3D.new()
			body_root.add_child(loaded_holder)
			imported_model = next_model
			var normalization := Node3D.new()
			loaded_holder.add_child(normalization)
			var config: Dictionary = data.production_visual
			for role_map: Dictionary in [config.get("roles",{}),config.get("wheel_roles",{})]:
				for source_name: String in role_map:
					role_lookup[_key(source_name)] = role_map[source_name]
			for source_name: String in config.get("hidden_meshes",[]):
				hidden_lookup[_key(source_name)] = true
			var offset: Array = config.offset
			normalization.position = Vector3(float(offset[0]),float(offset[1]),float(offset[2]))
			normalization.rotation.y = float(config.yaw)
			normalization.scale = Vector3.ONE*float(config.scale)
			normalization.add_child(imported_model)
			_collect(imported_model,config)
			_install_wheels(config)
			RushVehicleLights.install_emissive(loaded_holder,config.get("fallback_lamps",[]),role_materials)
		loaded_path = path
	is_veneno = next_is_veneno
	# Clear only references, never free the selected instance on an alias change.
	for i: int in models.size():
		models[i] = null
		lod_models[i] = [null,null,null]
		body_shells[i] = [null,null,null]
		wheel_sets[i] = [[],[],[]]
		material_sets[i] = {}
	active_index = next_index
	models[active_index] = loaded_holder
	# No fabricated low-poly substitution: all quality levels use this one GLB.
	lod_models[active_index] = [loaded_holder,loaded_holder,loaded_holder]
	body_shells[active_index] = [loaded_holder,loaded_holder,loaded_holder]
	wheel_sets[active_index] = [wheel_pivots,wheel_pivots,wheel_pivots]
	var mats: Dictionary = {}
	for role: String in ["Paint","Headlight","Taillight"]:
		mats[role] = StandardMaterial3D.new()
		mats[role].emission_enabled = true
	mats.Paint.albedo_color = paint
	mats.Paint.roughness = 0.28
	mats.Taillight.emission = Color("ff3548")*0.16
	material_sets[active_index] = mats
	brake_mat = mats.Taillight
	attachment_overrides.clear()
	for name_value: String in data.attachment_markers:
		var p: Array = data.attachment_markers[name_value]
		attachment_overrides[name_value] = Vector3(float(p[0]),float(p[1]),float(p[2]))
	radius = float(data.wheel_radius)
	shadow.scale = Vector3(float(data.width)/1.95,1,float(data.length)/4.3)
	body_root.rotation = Vector3.ZERO
	last_roughness = -1.0
	_apply_paint()
	lamp_state = Vector4(-1,-1,-1,-1)
	update_lamps(false,0.0,false)
	set_quality(quality)

func _apply_paint() -> void:
	var proxy: StandardMaterial3D = material_sets[active_index].Paint
	if last_paint==proxy.albedo_color and last_roughness==proxy.roughness:
		return
	last_paint = proxy.albedo_color
	last_roughness = proxy.roughness
	if is_veneno:
		for key: String in material_cache:
			if key.begins_with("veneno_atlas:"):
				var atlas_paint: ShaderMaterial = material_cache[key] as ShaderMaterial
				atlas_paint.set_shader_parameter("paint_color",proxy.albedo_color)
				atlas_paint.set_shader_parameter("paint_roughness",proxy.roughness)
	for mat: StandardMaterial3D in role_materials.get("Paint",[]):
		# Never tint a textured livery, decals, or baked body atlas.
		if mat.albedo_texture==null:
			mat.albedo_color = proxy.albedo_color
			mat.roughness = proxy.roughness

func set_quality(level: int) -> void:
	quality = clampi(level,0,2)
	# Player car lod_bias policy — intentionally higher than traffic.
	# The local player car occupies the centre of the screen and sits only
	# 7–12 m from the race camera; a bias >= 1.0 is NOT enough to guarantee
	# LOD-0 (highest detail) under Godot 4's GL-Compatibility LOD selection.
	#   HIGH   → 3.0 : LOD-0 forced at any practical race-camera distance.
	#   MEDIUM → 2.0 : LOD-0 preserved up to ~18 m; crisp close-up view.
	#   LOW    → 1.2 : visibly clean; minor saving only at long viewing angles.
	# Traffic/opponents are NOT affected — they use ProductionTrafficVisual.
	const PLAYER_LOD_BIAS: Array[float] = [1.2, 2.0, 3.0]
	for mesh: MeshInstance3D in mesh_lookup.values():
		mesh.lod_bias = PLAYER_LOD_BIAS[quality]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if quality==0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Original meshes remain intact; use imported LODs where available.

func _apply_lod() -> void:
	if loaded_holder!=null: loaded_holder.visible = true

func animate(delta: float, speed: float, steering: float, _brake: bool, _suspension: Array[float], _longitudinal: float) -> void:
	for i: int in wheel_pivots.size():
		wheel_pivots[i].rotation.y = -steering if wheel_front[i] else 0.0
		wheel_meshes[i].rotation.x = fposmod(wheel_meshes[i].rotation.x-speed*delta/wheel_radii[i],TAU)
	_apply_paint()

func update_lamps(night: bool, braking: float, reversing: bool, hazard_state: int = 0) -> void:
	var state := Vector4(float(night), snappedf(braking, .025), float(reversing), float(hazard_state))
	if state == lamp_state: return
	lamp_state = state
	for role: String in ["Headlight","Taillight","Reverse"]:
		var color: Color = Color("d4eeff")
		var energy: float = 0.0 if not night else 1.8
		if role == "Taillight":
			color = Color("ff3548")
			if hazard_state == 1:
				color = Color("ff9900")
				energy = 3.5
			elif hazard_state == 2:
				energy = 0.40 if night else 0.0
			else:
				# BUG-3 FIX: In daytime, taillights are completely OFF (0.0 energy) when not braking.
				# At night, they have a soft running light baseline (0.40).
				# When braking, they glow bright red (3.5).
				var base_energy: float = 0.40 if night else 0.0
				energy = lerpf(base_energy, 3.5, braking)
		elif role == "Reverse":
			energy = 1.5 if reversing else 0.0
		elif role == "Headlight":
			if hazard_state == 1:
				color = Color("ffaa22")
				energy = 2.5
			elif hazard_state == 2:
				energy = 1.8 if night else 0.0
		for mat: StandardMaterial3D in role_materials.get(role, []):
			mat.emission = color * energy

func attachment(name_value: String, fallback: Vector3) -> Vector3:
	return attachment_overrides.get(name_value,fallback)
