extends Node

var checks: int = 0
var failures: int = 0

func _check(condition: bool, caption: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + caption)
		push_error("FAIL: " + caption)
	else:
		print("PASS: " + caption)

func _ready() -> void:
	print("--- MAP PRESET TEST SUITE START ---")
	test_migration_and_normalization()
	await test_ui_and_maps()
	print("--- MAP PRESET TEST SUITE END ---")
	print("CHECKS: %d, FAILURES: %d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func test_migration_and_normalization() -> void:
	print(">>> Testing Save/Load migration & Preset normalization...")
	_check(RushTimeOfDay.Preset.MORNING == 0, "Preset.MORNING is 0")
	_check(RushTimeOfDay.Preset.EVENING == 1, "Preset.EVENING is 1")
	_check(RushTimeOfDay.Preset.NIGHT == 2, "Preset.NIGHT is 2")

	# Mode mappings
	_check(RushTimeOfDay.preset_to_mode(RushTimeOfDay.Preset.MORNING) == 0, "preset_to_mode MORNING -> 0")
	_check(RushTimeOfDay.preset_to_mode(RushTimeOfDay.Preset.EVENING) == 1, "preset_to_mode EVENING -> 1")
	_check(RushTimeOfDay.preset_to_mode(RushTimeOfDay.Preset.NIGHT) == 3, "preset_to_mode NIGHT -> 3")

	# Obsolete integers migrate to MORNING
	_check(RushTimeOfDay.normalize_preset(-1) == RushTimeOfDay.Preset.MORNING, "Old placeholder (-1) -> MORNING")
	_check(RushTimeOfDay.normalize_preset(3) == RushTimeOfDay.Preset.NIGHT, "Old NIGHT (3) -> NIGHT (2)")
	_check(RushTimeOfDay.normalize_preset(4) == RushTimeOfDay.Preset.MORNING, "Old DAY (4) -> MORNING")
	_check(RushTimeOfDay.normalize_preset(5) == RushTimeOfDay.Preset.MORNING, "Old RANDOM (5) -> MORNING")
	_check(RushTimeOfDay.normalize_preset(99) == RushTimeOfDay.Preset.MORNING, "Out of bounds (99) -> MORNING")

	# Valid integers
	_check(RushTimeOfDay.normalize_preset(0) == RushTimeOfDay.Preset.MORNING, "Int 0 -> MORNING")
	_check(RushTimeOfDay.normalize_preset(1) == RushTimeOfDay.Preset.EVENING, "Int 1 -> EVENING")
	_check(RushTimeOfDay.normalize_preset(2) == RushTimeOfDay.Preset.NIGHT, "Int 2 -> NIGHT")

	# String values
	_check(RushTimeOfDay.normalize_preset("MORNING") == RushTimeOfDay.Preset.MORNING, "String 'MORNING' -> MORNING")
	_check(RushTimeOfDay.normalize_preset("EVENING") == RushTimeOfDay.Preset.EVENING, "String 'EVENING' -> EVENING")
	_check(RushTimeOfDay.normalize_preset("NIGHT") == RushTimeOfDay.Preset.NIGHT, "String 'NIGHT' -> NIGHT")
	_check(RushTimeOfDay.normalize_preset("SUNSET") == RushTimeOfDay.Preset.MORNING, "String 'SUNSET' -> MORNING")
	_check(RushTimeOfDay.normalize_preset("DUSK") == RushTimeOfDay.Preset.MORNING, "String 'DUSK' -> MORNING")
	_check(RushTimeOfDay.normalize_preset("DAY") == RushTimeOfDay.Preset.MORNING, "String 'DAY' -> MORNING")
	_check(RushTimeOfDay.normalize_preset("RANDOM") == RushTimeOfDay.Preset.MORNING, "String 'RANDOM' -> MORNING")
	_check(RushTimeOfDay.normalize_preset("RANDOM TIME") == RushTimeOfDay.Preset.MORNING, "String 'RANDOM TIME' -> MORNING")
	_check(RushTimeOfDay.normalize_preset("MAP PRESET") == RushTimeOfDay.Preset.MORNING, "String 'MAP PRESET' -> MORNING")
	_check(RushTimeOfDay.normalize_preset(null) == RushTimeOfDay.Preset.MORNING, "Null -> MORNING")

	# SaveService _validated checks
	_check(SaveService._validated("map_time", -1) == 0, "SaveService validates -1 -> 0")
	_check(SaveService._validated("map_time", "SUNSET") == 0, "SaveService validates 'SUNSET' -> 0")
	_check(SaveService._validated("map_time", "DUSK") == 0, "SaveService validates 'DUSK' -> 0")
	_check(SaveService._validated("map_time", "DAY") == 0, "SaveService validates 'DAY' -> 0")
	_check(SaveService._validated("map_time", "RANDOM") == 0, "SaveService validates 'RANDOM' -> 0")
	_check(SaveService._validated("map_time", 1) == 1, "SaveService validates 1 -> 1 (EVENING)")
	_check(SaveService._validated("map_time", 2) == 2, "SaveService validates 2 -> 2 (NIGHT)")
	_check(SaveService.DEFAULTS["map_time"] == 0, "SaveService DEFAULTS['map_time'] is 0 (MORNING)")

func test_ui_and_maps() -> void:
	print(">>> Testing Map Selection UI & Map environments...")
	var game: Node = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for _frame: int in 15000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame

	_check(game.ready_for_drive, "Game initialized ready_for_drive")
	if not game.ready_for_drive:
		return

	# Find OptionButton in map_selection screen
	var map_screen: Control = game.ui.screens.get("map_selection")
	_check(map_screen != null, "map_selection screen exists")

	var option_button: OptionButton = null
	for node: Node in map_screen.find_children("*", "OptionButton", true, false):
		option_button = node as OptionButton
		break

	_check(option_button != null, "OptionButton found in map_selection")
	if option_button == null:
		return

	# Verify EXACTLY 3 items in dropdown
	_check(option_button.item_count == 3, "OptionButton contains exactly 3 options (got %d)" % option_button.item_count)

	var items: Array[String] = []
	var ids: Array[int] = []
	for idx: int in option_button.item_count:
		items.append(option_button.get_item_text(idx))
		ids.append(option_button.get_item_id(idx))

	_check(items == ["MORNING", "EVENING", "NIGHT"], "Items are exactly ['MORNING', 'EVENING', 'NIGHT'] (got %s)" % str(items))
	_check(ids == [0, 1, 2], "Item IDs are [0, 1, 2] matching RushTimeOfDay.Preset (got %s)" % str(ids))

	# Explicitly verify absence of obsolete items
	_check(not items.has("MAP PRESET"), "No 'MAP PRESET' placeholder item in dropdown")
	_check(not items.has("SUNSET"), "No 'SUNSET' option in dropdown")
	_check(not items.has("DUSK"), "No 'DUSK' option in dropdown")
	_check(not items.has("DAY"), "No 'DAY' option in dropdown")
	_check(not items.has("RANDOM"), "No 'RANDOM' option in dropdown")
	_check(not items.has("RANDOM TIME"), "No 'RANDOM TIME' option in dropdown")

	# Find map index for each required map
	var map_indices: Dictionary = {}
	for idx: int in game.map_dressing.maps.size():
		var id: String = String(game.map_dressing.maps[idx].id)
		map_indices[id] = idx

	for required_id: String in ["rain", "neon", "metro", "highway"]:
		_check(map_indices.has(required_id), "Map '%s' exists in Maps.json" % required_id)

	# ========================================================
	# 1. TEST RAIN CITY (id: "rain")
	# ========================================================
	var rain_idx: int = map_indices["rain"]
	print(">>> Testing RAIN CITY (map %d)..." % rain_idx)

	# Rain City + MORNING
	game.map_dressing.apply(rain_idx, RushTimeOfDay.Preset.MORNING)
	_check(game.director.tod.mode == 0, "Rain City + MORNING -> tod.mode == 0")
	_check(game.map_dressing.weather.enabled == true, "Rain City + MORNING -> weather.enabled == true (Rain ON)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 1.0, "Rain City + MORNING -> wetness == 1.0")

	# Rain City + EVENING
	game.map_dressing.apply(rain_idx, RushTimeOfDay.Preset.EVENING)
	_check(game.director.tod.mode == 1, "Rain City + EVENING -> tod.mode == 1")
	_check(game.map_dressing.weather.enabled == true, "Rain City + EVENING -> weather.enabled == true (Rain ON)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 1.0, "Rain City + EVENING -> wetness == 1.0")

	# Rain City + NIGHT
	game.map_dressing.apply(rain_idx, RushTimeOfDay.Preset.NIGHT)
	_check(game.director.tod.mode == 3, "Rain City + NIGHT -> tod.mode == 3")
	_check(game.map_dressing.weather.enabled == true, "Rain City + NIGHT -> weather.enabled == true (Rain ON)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 1.0, "Rain City + NIGHT -> wetness == 1.0")

	# ========================================================
	# 2. TEST NEON CITY (id: "neon")
	# ========================================================
	var neon_idx: int = map_indices["neon"]
	print(">>> Testing NEON CITY (map %d)..." % neon_idx)

	# Neon City + MORNING
	game.map_dressing.apply(neon_idx, RushTimeOfDay.Preset.MORNING)
	_check(game.director.tod.mode == 0, "Neon City + MORNING -> tod.mode == 0")
	_check(game.map_dressing.weather.enabled == false, "Neon City + MORNING -> weather.enabled == false (No rain)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 0.0, "Neon City + MORNING -> wetness == 0.0")

	# Neon City + EVENING
	game.map_dressing.apply(neon_idx, RushTimeOfDay.Preset.EVENING)
	_check(game.director.tod.mode == 1, "Neon City + EVENING -> tod.mode == 1")
	_check(game.map_dressing.weather.enabled == false, "Neon City + EVENING -> weather.enabled == false (No rain)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 0.0, "Neon City + EVENING -> wetness == 0.0")

	# Neon City + NIGHT
	game.map_dressing.apply(neon_idx, RushTimeOfDay.Preset.NIGHT)
	_check(game.director.tod.mode == 3, "Neon City + NIGHT -> tod.mode == 3")
	_check(game.map_dressing.weather.enabled == false, "Neon City + NIGHT -> weather.enabled == false (No rain)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 0.0, "Neon City + NIGHT -> wetness == 0.0")

	# ========================================================
	# 3. TEST METRO NIGHT EXPRESSWAY (id: "metro")
	# ========================================================
	var metro_idx: int = map_indices["metro"]
	print(">>> Testing METRO NIGHT EXPRESSWAY (map %d)..." % metro_idx)

	# Metro + MORNING
	game.map_dressing.apply(metro_idx, RushTimeOfDay.Preset.MORNING)
	_check(game.director.tod.mode == 0, "Metro + MORNING -> tod.mode == 0")
	_check(game.map_dressing.weather.enabled == false, "Metro + MORNING -> weather.enabled == false (No rain)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 0.0, "Metro + MORNING -> wetness == 0.0")

	# Metro + EVENING
	game.map_dressing.apply(metro_idx, RushTimeOfDay.Preset.EVENING)
	_check(game.director.tod.mode == 1, "Metro + EVENING -> tod.mode == 1")
	_check(game.map_dressing.weather.enabled == false, "Metro + EVENING -> weather.enabled == false (No rain)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 0.0, "Metro + EVENING -> wetness == 0.0")

	# Metro + NIGHT
	game.map_dressing.apply(metro_idx, RushTimeOfDay.Preset.NIGHT)
	_check(game.director.tod.mode == 3, "Metro + NIGHT -> tod.mode == 3")
	_check(game.map_dressing.weather.enabled == false, "Metro + NIGHT -> weather.enabled == false (No rain)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 0.0, "Metro + NIGHT -> wetness == 0.0")

	# ========================================================
	# 4. TEST HIGHWAY RUSH (id: "highway")
	# ========================================================
	var highway_idx: int = map_indices["highway"]
	print(">>> Testing HIGHWAY RUSH (map %d)..." % highway_idx)

	# Highway + MORNING
	game.map_dressing.apply(highway_idx, RushTimeOfDay.Preset.MORNING)
	_check(game.director.tod.mode == 0, "Highway + MORNING -> tod.mode == 0")
	_check(game.map_dressing.weather.enabled == false, "Highway + MORNING -> weather.enabled == false (No rain)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 0.0, "Highway + MORNING -> wetness == 0.0")

	# Highway + EVENING
	game.map_dressing.apply(highway_idx, RushTimeOfDay.Preset.EVENING)
	_check(game.director.tod.mode == 1, "Highway + EVENING -> tod.mode == 1")
	_check(game.map_dressing.weather.enabled == false, "Highway + EVENING -> weather.enabled == false (No rain)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 0.0, "Highway + EVENING -> wetness == 0.0")

	# Highway + NIGHT
	game.map_dressing.apply(highway_idx, RushTimeOfDay.Preset.NIGHT)
	_check(game.director.tod.mode == 3, "Highway + NIGHT -> tod.mode == 3")
	_check(game.map_dressing.weather.enabled == false, "Highway + NIGHT -> weather.enabled == false (No rain)")
	_check(float(game.highway.asphalt.get_shader_parameter("wetness")) == 0.0, "Highway + NIGHT -> wetness == 0.0")

	# ========================================================
	# 5. SWITCHING MAPS & RETURNING TO RAIN CITY
	# ========================================================
	print(">>> Testing Map Switching...")
	# Return to Rain City with MORNING
	game.map_dressing.apply(rain_idx, RushTimeOfDay.Preset.MORNING)
	_check(game.map_dressing.weather.enabled == true, "Returning to Rain City restores rain (MORNING)")

	# Switch to Neon City
	game.map_dressing.apply(neon_idx, RushTimeOfDay.Preset.NIGHT)
	_check(game.map_dressing.weather.enabled == false, "Switching to Neon City disables rain")

	# Return to Rain City with NIGHT
	game.map_dressing.apply(rain_idx, RushTimeOfDay.Preset.NIGHT)
	_check(game.map_dressing.weather.enabled == true, "Returning to Rain City preserves rain (NIGHT)")

	# Replay / ensure_weather invariant check
	game.map_dressing.ensure_weather()
	_check(game.map_dressing.weather.enabled == true, "ensure_weather preserves Rain City rain")

	# Switching to Highway Rush
	game.map_dressing.apply(highway_idx, RushTimeOfDay.Preset.EVENING)
	game.map_dressing.ensure_weather()
	_check(game.map_dressing.weather.enabled == false, "ensure_weather preserves Highway dry state")
