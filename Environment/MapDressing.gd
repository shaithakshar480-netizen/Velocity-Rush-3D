class_name RushMapDressing
extends Node
var game: Node
var maps: Array = []
var roots: Array[Node3D] = []
var rain: CPUParticles3D # Legacy field retained; weather owns the emitters.
var weather: RushWetWeather
var previews: RushMapPreview
var built_key: String = ""
var facade: ShaderMaterial
var selected: int = 0
func build(owner_game: Node) -> void:
	game = owner_game
	weather = RushWetWeather.new()
	game.world.add_child(weather)
	weather.build(game)
	previews = RushMapPreview.new()
	add_child(previews)
	previews.build(game)
	maps = JSON.parse_string(FileAccess.get_file_as_string("res://Data/Maps.json"))
func apply(map_override: int = -1, time_override: int = -2) -> void:
	selected = map_override if map_override>=0 else int(SaveService.settings.get("map",0))
	if selected==maps.size():
		selected = randi_range(0,maps.size()-1)
	selected = clampi(selected,0,maps.size()-1)
	var config: Dictionary = maps[selected]
	var id: String = String(config.id)
	var raw_time: Variant = time_override if time_override >= 0 else SaveService.settings.get("map_time", RushTimeOfDay.Preset.MORNING)
	var preset: int = RushTimeOfDay.normalize_preset(raw_time)
	game.director.tod.mode = RushTimeOfDay.preset_to_mode(preset)
	# Reset night-only ambient overrides before the normal time-of-day setup.
	game.highway.lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	game.highway.lighting.ambient_light_sky_contribution = 0.0
	game.director.tod.apply(game.highway,game.performance.visual_level)
	# Stable indirect fill for ALL vehicles, including dark paint between street lamps.
	# A dark sky must not erase body silhouettes; keep sky/reflections and lamp accents.
	if game.director.tod.mode in [2,3]:
		var lighting: Environment = game.highway.lighting
		lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		lighting.ambient_light_sky_contribution = 0.0
		lighting.ambient_light_color = Color("b1c6df")
		lighting.ambient_light_energy = maxf(lighting.ambient_light_energy,0.65)
		# Existing directional moon/key supplies readable contour highlights, no new lights.
		game.highway.sun.light_energy = maxf(game.highway.sun.light_energy,0.32)
	game.director.lights.night = game.director.tod.mode
	for traffic_car: RushTrafficVehicle in game.traffic.pool:
		traffic_car.night_mode = 0 if game.director.tod.mode==4 else game.director.tod.mode
	for racer: RushTrafficVehicle in game.director.opponents.racers:
		racer.night_mode = 0 if game.director.tod.mode==4 else game.director.tod.mode
	game.highway.terrain.albedo_color = Color(String(config.terrain))
	game.highway.asphalt.set_shader_parameter("wetness",1.0 if id=="rain" else 0.0)
	# Dry dusk asphalt should not amplify the low sun like the night city finish.
	var city_sheen: float = 0.0
	if id in ["metro","neon"]:
		city_sheen = 0.22 if game.director.tod.mode==2 else (0.75 if game.director.tod.mode==3 else 0.0)
	game.highway.asphalt.set_shader_parameter("city_sheen",city_sheen)
	game.highway.course_road.sync_material()
	for tile: RushSceneryTile in game.highway.scenery:
		tile.visible = id=="highway"
	weather.set_enabled(id=="rain")
	if facade!=null:
		facade.set_shader_parameter("night",1.0 if game.director.tod.mode in [2,3] else .05)
	var next_key: String = id+":"+str(game.performance.visual_level)
	if built_key==next_key:
		if game.highway.course!=null: game.highway.course_road.refresh_dressing()
		game.highway.course_road.sync_material()
		return # Reuse batched geometry on replay; never rebuild identical maps.
	built_key = next_key
	for root: Node3D in roots:
		root.get_parent().remove_child(root)
		root.queue_free()
	roots.clear()
	if rain!=null:
		rain.queue_free()
		rain = null
	if id=="highway":
		return
	facade = ShaderMaterial.new()
	facade.shader = preload("res://Environment/city_facade.gdshader")
	facade.set_shader_parameter("night",1.0 if game.director.tod.mode in [2,3] else .05)
	var stone: StandardMaterial3D = RoadGeometry.material(Color(String(config.terrain)),.1,.85)
	var dark: StandardMaterial3D = RoadGeometry.material(Color("24303d"),.25,.4)
	var neon: StandardMaterial3D = RoadGeometry.material(Color("39738c"),.2,.3)
	neon.emission_enabled = true
	neon.emission = Color("6a40cb") if id=="neon" else Color("39849b")
	var billboard := ShaderMaterial.new()
	billboard.shader = preload("res://Environment/neon_billboard.gdshader")
	var pink: StandardMaterial3D = RoadGeometry.material(Color("572c63"),.15,.4)
	pink.emission_enabled = true
	pink.emission = Color("e54dae")
	pink.emission_energy_multiplier = 1.5
	neon.emission = Color("32cde5")
	neon.emission_energy_multiplier = 1.4
	var green: StandardMaterial3D = RoadGeometry.material(Color("234837"))
	var water: StandardMaterial3D = RoadGeometry.material(Color("31546a"),.35,.24)
	for chunk: Node3D in game.highway.chunks:
		var root: Node3D = Node3D.new()
		chunk.add_child(root)
		roots.append(root)
		var density: int = [2, 4, 7][game.performance.visual_level]
		for i: int in density:
			var z: float = -float(i)*120.0/float(density)
			for side: float in [-1.0,1.0]:
				var x: float = side*(24.0+float(i%3)*9.0)
				if id in ["metro","neon","rain"]:
					var height: float = 24.0+float((i*7)%5)*12.0 if id in ["metro","neon"] else 12.0+float((i*7)%5)*9.0
					RoadGeometry.box(root,Vector3(x,height*.5,z),Vector3(12,height,16),facade)
					# Setback podiums, roof trim and sidewalks share a handful of instanced materials.
					RoadGeometry.box(root,Vector3(x,1.8,z),Vector3(14,3.6,18),dark)
					RoadGeometry.box(root,Vector3(x,height+.18,z),Vector3(12.5,.36,16.5),stone)
					RoadGeometry.box(root,Vector3(side*16,.10,z),Vector3(8,.2,120.0/float(density)),stone)
					if game.performance.visual_level>0:
						RoadGeometry.box(root,Vector3(x+side*2,height+1,z-3),Vector3(3,2,4),dark)
					RoadGeometry.box(root,Vector3(x-side*6.05,height*.6,z),Vector3(.05,1.1,14),neon)
					if id in ["metro","neon"]:
						# Fixed, batched emissive architecture: no additional dynamic lights.
						RoadGeometry.box(root,Vector3(x-side*6.09,height*.55,z),Vector3(.07,height*.68,5.5),billboard)
						RoadGeometry.box(root,Vector3(x-side*6.13,height*.5,z-7),Vector3(.06,height*.92,.18),pink if i%2==0 else neon)
						if game.performance.visual_level>0:
							RoadGeometry.box(root,Vector3(x+side*18,height*.68,z-9),Vector3(10,height*1.36,12),facade)
					# Neon extra strip: HIGH only (emissive fragment cost).
					if id=="neon" and game.performance.visual_level==2:
						RoadGeometry.box(root,Vector3(x-side*6.1,height*.35,z),Vector3(.08,4,8),neon)
				else:
					var rock: MeshInstance3D = MeshInstance3D.new()
					var shape: SphereMesh = SphereMesh.new()
					# LOW: fewer sphere segments to reduce vertex count.
					shape.radial_segments = 6 if game.performance.visual_level == 0 else 8
					shape.rings = 3 if game.performance.visual_level == 0 else 4
					rock.mesh = shape
					rock.material_override = stone
					rock.position = Vector3(x+side*15,4,z)
					rock.scale = Vector3(25,18+float(i%3)*9,24)
					root.add_child(rock)
					if id!="desert":
						RoadGeometry.box(root,Vector3(side*15,2.5,z),Vector3(.4,5,.4),stone)
						var tree: MeshInstance3D = MeshInstance3D.new()
						var foliage: CylinderMesh = CylinderMesh.new()
						foliage.top_radius = 0
						foliage.bottom_radius = 2.5
						foliage.height = 6 if id=="alpine" else .6
						foliage.radial_segments = 6
						tree.mesh = foliage
						tree.material_override = green
						tree.position = Vector3(side*15,5,z)
						root.add_child(tree)
		if id=="coastal":
			RoadGeometry.box(root,Vector3(-160,-.4,-60),Vector3(260,.1,120),water)
		if id=="alpine" and game.highway.chunks.find(chunk)%3==0:
			RoadGeometry.box(root,Vector3(0,8,-45),Vector3(24,1,24),dark)
			for side: float in [-1.0,1.0]:
				RoadGeometry.box(root,Vector3(side*11,4,-45),Vector3(1,8,24),dark)
	for root: Node3D in roots:
		RushRoadBatcher.merge(root)
	if game.highway.course!=null: game.highway.course_road.refresh_dressing()
	game.highway.course_road.sync_material()
	# Rain/spray are precreated once, not reconstructed on every race.
	ensure_weather()

func ensure_weather() -> void:
	if maps.is_empty(): return
	var config: Dictionary = maps[clampi(selected,0,maps.size()-1)]
	var is_rain: bool = String(config.id)=="rain"
	if weather!=null: weather.set_enabled(is_rain)
	if game!=null and game.highway!=null and game.highway.asphalt!=null:
		game.highway.asphalt.set_shader_parameter("wetness",1.0 if is_rain else 0.0)
