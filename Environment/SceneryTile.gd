class_name RushSceneryTile
extends Node3D
## Four section variants precreated at boot. Only visibility changes while driving.
const PATHS: Array[String] = ["res://Assets/Environment/open_mountain.glb","res://Assets/Environment/rock_cut.glb","res://Assets/Environment/city_approach.glb","res://Assets/Environment/outskirts.glb"]
static var scenes: Array[PackedScene] = []
var variants: Array[Node3D] = []
var details: Array = []
var active_section: int = 0
var cell: int = 0
var quality: int = 1
var distance_bucket: int = -1
var window_materials: Array[StandardMaterial3D] = []
static func prepare() -> void:
	if scenes.is_empty():
		for path: String in PATHS:
			scenes.append(load(path) as PackedScene)
func _ready() -> void:
	prepare()
	for scene: PackedScene in scenes:
		var root := scene.instantiate() as Node3D
		add_child(root)
		variants.append(root)
		var nodes: Dictionary = {}
		_cache(root,nodes)
		details.append(nodes)
		root.visible = false
func _cache(node: Node, nodes: Dictionary) -> void:
	if node is MeshInstance3D:
		nodes[String(node.name)] = node
		for surface: int in node.mesh.get_surface_count():
			var original: Material = node.get_active_material(surface)
			if original is StandardMaterial3D and original.resource_name in ["Earth","Rock","Distant"]:
				var terrain_mat := original.duplicate() as StandardMaterial3D
				var role_name := original.resource_name
				terrain_mat.albedo_color = Color("394330") if role_name=="Earth" else (Color("514e46") if role_name=="Rock" else Color("465c72"))
				node.set_surface_override_material(surface,terrain_mat)
			if original is StandardMaterial3D and original.resource_name=="Glass":
				var mat := original.duplicate() as StandardMaterial3D
				mat.emission_enabled = true
				node.set_surface_override_material(surface,mat)
				window_materials.append(mat)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_cache(child,nodes)
func configure(section: int, cell_value: int) -> void:
	active_section = clampi(section,0,3)
	cell = cell_value
	for i: int in variants.size():
		variants[i].visible = i==active_section
	distance_bucket = -1
func update_lod(distance: float, level: int) -> void:
	# Bucket distances scale with quality: LOW uses tighter cutoffs to reduce draw calls.
	# LOW   (0): near<120, mid<260, far>=260
	# MEDIUM(1): near<160, mid<320, far>=320
	# HIGH  (2): near<200, mid<420, far>=420  (original values)
	var near_dist: float = [120.0, 160.0, 200.0][clampi(level,0,2)]
	var far_dist: float  = [260.0, 320.0, 420.0][clampi(level,0,2)]
	var bucket := 0 if distance < near_dist else (1 if distance < far_dist else 2)
	if bucket==distance_bucket and quality==level:
		return
	distance_bucket = bucket
	quality = level
	var nodes: Dictionary = details[active_section]
	for name_value: String in nodes:
		var shown := true
		match name_value:
			# Details: HIGH only at close range. MEDIUM/LOW never.
			"Details": shown = quality == 2 and bucket == 0
			# Vegetation: hidden on LOW entirely (high overdraw cost for foliage).
			"Vegetation": shown = quality > 0 and bucket < 2
			# Rocks: close+mid only on HIGH; close only on MEDIUM; never on LOW.
			"Rocks": shown = (quality == 2 and bucket <= 1) or (quality == 1 and bucket == 0)
			"RidgeNear": shown = bucket < 2
			# Structures: always on HIGH; skip mid/far on MEDIUM; skip all on LOW.
			"Structures": shown = quality == 2 or (quality == 1 and bucket == 0)
			"StructuresFar": shown = bucket == 2 or quality == 0
			"Overpass": shown = posmod(cell,7)==3
		nodes[name_value].visible = shown
		nodes[name_value].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if name_value=="Overpass" and quality>0 and bucket==0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func set_night(value: bool) -> void:
	for material: StandardMaterial3D in window_materials:
		material.emission = Color("b3c2db")*(.35 if value else 0.0)
