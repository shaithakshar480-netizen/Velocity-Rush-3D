class_name RushTimeOfDay
extends RefCounted
enum Preset {
	MORNING = 0,
	EVENING = 1,
	NIGHT = 2,
}
const PRESET_NAMES: Array[String] = ["MORNING", "EVENING", "NIGHT"]
const NAMES: Array[String] = ["MORNING", "EVENING", "NIGHT"]
var mode: int = 0


static func preset_to_mode(preset: int) -> int:
	match preset:
		Preset.MORNING:
			return 0
		Preset.EVENING:
			return 1
		Preset.NIGHT:
			return 3
		_:
			return 0

static func mode_to_preset(tod_mode: int) -> int:
	match tod_mode:
		0, 4:
			return Preset.MORNING
		1:
			return Preset.EVENING
		2, 3:
			return Preset.NIGHT
		_:
			return Preset.MORNING

static func normalize_preset(raw: Variant) -> int:
	if raw is String:
		var s: String = (raw as String).strip_edges().to_upper()
		match s:
			"MORNING":
				return Preset.MORNING
			"EVENING":
				return Preset.EVENING
			"NIGHT":
				return Preset.NIGHT
			_:
				return Preset.MORNING
	if (raw is int or raw is float) and is_finite(float(raw)):
		var val: int = int(raw)
		match val:
			Preset.MORNING:
				return Preset.MORNING
			Preset.EVENING:
				return Preset.EVENING
			Preset.NIGHT:
				return Preset.NIGHT
			3:
				return Preset.NIGHT
			_:
				return Preset.MORNING
	return Preset.MORNING

func prepare() -> void:
	pass

func choose(_run_id: int = 0) -> void:
	# Random time-of-day is obsolete; active preset is preserved.
	pass
func apply(highway: Highway, quality: int) -> void:
	var light_index: int = 0 if mode==4 else mode

	highway.sun.rotation_degrees = [Vector3(-21,35,0),Vector3(-26,-38,0),Vector3(-8,-45,0),Vector3(-34,20,0)][light_index]
	highway.sun.light_color = [Color("ffe8d0"),Color("ffe0b3"),Color("f5ad87"),Color("adc6eb")][light_index]
	highway.sun.light_energy = [1.28,1.40,.67,.34][light_index]
	highway.lighting.ambient_light_energy = [.32,.32,.38,.36][light_index]
	highway.lighting.fog_light_color = [Color("8faabd"),Color("869aa9"),Color("535b7c"),Color("24334c")][light_index]
	highway.stripe.emission_enabled = true
	highway.stripe.emission = Color("b9c8d1")*(.13 if mode in [2,3] else 0.0)
	highway.lamp_material.emission_enabled = true
	highway.lamp_material.emission = Color.BLACK
	if highway.street_lighting!=null: highway.street_lighting.night = mode in [2,3]
	for tile: RushSceneryTile in highway.scenery:
		tile.set_night(mode in [2,3])
