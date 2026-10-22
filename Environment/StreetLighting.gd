class_name RushStreetLighting
extends Node3D
## Fixed fixtures follow recycled visual chunks. Only nearby lights reach the GPU.
var lamps: Array[SpotLight3D] = []
var lenses: Array[StandardMaterial3D] = []
var levels: Array[float] = []
var night: bool = false
func fixture(chunk: Node3D, at: Vector3) -> void:
	var holder: Node3D = Node3D.new()
	chunk.add_child(holder)
	holder.position = at
	var lens: StandardMaterial3D = RoadGeometry.material(Color("c5d0d4"),.25,.32)
	lens.emission_enabled = true
	lens.emission = Color("ffdfab")
	lens.emission_energy_multiplier = 0.0
	RoadGeometry.box(holder,Vector3.ZERO,Vector3(.82,.025,.30),lens)
	var light: SpotLight3D = SpotLight3D.new()
	holder.add_child(light)
	light.rotation_degrees.x = -90.0
	light.spot_range = 22.0
	light.spot_angle = 66.0
	light.spot_attenuation = 1.1
	light.light_color = Color("fff0d8")
	light.shadow_enabled = false
	light.visible = false
	lamps.append(light)
	lenses.append(lens)
	levels.append(0.0)
func update_nearby(target: Node3D, quality: int, delta: float) -> void:
	# LOW quality: street lights are completely disabled; skip the whole loop.
	if quality == 0:
		for i: int in lamps.size():
			if lamps[i].visible:
				lamps[i].visible = false
		return
	var enabled: bool = night and is_instance_valid(target)
	if not enabled:
		# Fast path: fade all lamps to dark without distance queries.
		for i: int in lamps.size():
			levels[i] = lerpf(levels[i], 0.0, 1.0 - exp(-7.0 * delta))
			lamps[i].visible = levels[i] > .015
			lamps[i].light_energy = levels[i] * [0.0, 1.4, 1.75][clampi(quality,0,2)]
			lenses[i].emission_energy_multiplier = levels[i] * 2.8
		return
	# MEDIUM: 50 m radius. HIGH: 65 m radius (tighter than before to reduce overlap cost).
	var radius: float = [0.0, 50.0, 65.0][clampi(quality, 0, 2)]
	for i: int in lamps.size():
		var gain: float = 1.0 - smoothstep(radius * .60, radius, lamps[i].global_position.distance_to(target.global_position))
		levels[i] = lerpf(levels[i], gain, 1.0 - exp(-7.0 * delta))
		lamps[i].visible = levels[i] > .015
		lamps[i].light_energy = levels[i] * [0.0, 1.4, 1.75][clampi(quality,0,2)]
		lenses[i].emission_energy_multiplier = levels[i] * 2.8
