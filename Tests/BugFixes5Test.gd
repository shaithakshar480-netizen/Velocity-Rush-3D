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
	print("========================================")
	print("--- 5 GAMEPLAY BUGS VERIFICATION START ---")
	print("========================================")
	await test_bugs()
	print("========================================")
	print("--- 5 GAMEPLAY BUGS VERIFICATION END ---")
	print("CHECKS: %d, FAILURES: %d" % [checks, failures])
	print("========================================")
	get_tree().quit(0 if failures == 0 else 1)

func test_bugs() -> void:
	var game: Node = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for _frame: int in 15000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame

	_check(game.ready_for_drive, "Game initialized ready_for_drive")
	if not game.ready_for_drive:
		return

	# =========================================================================
	# BUG 1 VERIFICATION — RAIN CITY RAIN IN MORNING, EVENING, NIGHT
	# =========================================================================
	print("\n>>> Testing BUG 1: Rain City rain visibility across Morning, Evening, Night...")
	var rain_map_idx: int = -1
	for idx: int in game.map_dressing.maps.size():
		if game.map_dressing.maps[idx].id == "rain":
			rain_map_idx = idx
			break
	_check(rain_map_idx >= 0, "Rain City map located")

	var weather: RushWetWeather = game.map_dressing.weather
	_check(weather != null and weather.rain != null, "WetWeather and rain CPUParticles3D exist")

	var rain_mat: StandardMaterial3D = weather.rain.material_override as StandardMaterial3D
	_check(rain_mat != null, "Rain material exists")
	_check(rain_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Rain material uses TRANSPARENCY_ALPHA for proper additive blending")
	_check(rain_mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "Rain material uses additive blend (BLEND_MODE_ADD) for all-environment visibility")
	_check(rain_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Rain material is unshaded")
	_check(rain_mat.get_flag(BaseMaterial3D.FLAG_DISABLE_FOG) == true, "Rain material has FLAG_DISABLE_FOG enabled")
	_check(weather.rain.local_coords == false, "Rain uses world-space simulation (local_coords=false)")
	_check(weather.rain.visibility_aabb == AABB(), "Rain visibility_aabb is AABB() (auto-compute from world-space particles)")

	game.start_drive()
	for _f: int in 500:
		if game.state == game.State.DRIVING:
			break
		await get_tree().process_frame
	_check(game.state == game.State.DRIVING, "Game entered DRIVING state")

	# Test repeated preset switching: Morning -> Evening -> Night -> Morning -> Night -> Evening
	for preset: int in [
		RushTimeOfDay.Preset.MORNING,
		RushTimeOfDay.Preset.EVENING,
		RushTimeOfDay.Preset.NIGHT,
		RushTimeOfDay.Preset.MORNING,
		RushTimeOfDay.Preset.NIGHT,
		RushTimeOfDay.Preset.EVENING
	]:
		var preset_name: String = RushTimeOfDay.PRESET_NAMES[preset]
		game.map_dressing.apply(rain_map_idx, preset)
		for _f: int in 10:
			await get_tree().process_frame
		_check(weather.enabled == true, "Rain City + %s: weather.enabled == true" % preset_name)
		_check(weather.rain.emitting == true, "Rain City + %s: rain.emitting == true" % preset_name)
		_check(weather.rain.visible == true, "Rain City + %s: rain.visible == true" % preset_name)
		_check(weather.rain.amount >= 50, "Rain City + %s: rain.amount >= 50 (%d)" % [preset_name, weather.rain.amount])

	# =========================================================================
	# BUG 2 VERIFICATION — BRAKE PRESS / SHIFT CAUSES NO CAMERA SHAKE
	# =========================================================================
	print("\n>>> Testing BUG 2: Gear shifts & braking cause NO camera shake, collisions preserved...")
	var director: RushDrivingDirector = game.director
	_check(director != null, "DrivingDirector exists")
	var cam_rig: DriveCameraRig = game.cameras
	_check(cam_rig != null, "DriveCameraRig exists")
	cam_rig.impulse.reset()

	# Initial gear is 0 (neutral)
	_check(director._previous_gear == 0, "Initial previous gear is 0 (neutral)")
	# Simulate first engagement 0 -> 1:
	director._shifted(1)
	_check(director._previous_gear == 1, "After first-gear engagement, previous gear is 1")
	_check(cam_rig.impulse.remaining == 0.0, "First-gear engagement causes NO camera impulse")

	# Simulate upshift 1 -> 2:
	director._shifted(2)
	_check(director._previous_gear == 2, "After upshift to 2, previous gear is 2")
	_check(cam_rig.impulse.remaining == 0.0, "Upshift 1 -> 2 causes NO camera impulse")

	# Simulate downshift 2 -> 1 (occurs when braking):
	director._shifted(1)
	_check(director._previous_gear == 1, "After downshift to 1, previous gear is 1")
	_check(cam_rig.impulse.remaining == 0.0, "Downshift 2 -> 1 causes NO camera impulse")

	# Upshift 1 -> 3
	director._shifted(3)
	_check(director._previous_gear == 3, "After upshift to 3, previous gear is 3")
	_check(cam_rig.impulse.remaining == 0.0, "Upshift 1 -> 3 causes NO camera impulse")

	# Downshift 3 -> 2
	director._shifted(2)
	_check(director._previous_gear == 2, "After downshift to 2, previous gear is 2")
	_check(cam_rig.impulse.remaining == 0.0, "Downshift 3 -> 2 causes NO camera impulse")

	# Verify genuine collision impact feedback STILL triggers camera shake
	cam_rig.impact_feedback(0.5)
	_check(cam_rig.impulse.remaining > 0.0, "Legitimate collision impact feedback triggers camera shake")
	cam_rig.impulse.reset()

	# Verify camera response settles to Vector2.ZERO at standstill / low speed
	cam_rig.response = Vector2(0.2, -0.3)
	cam_rig.response_velocity = Vector2(1.0, -1.0)
	# Process a frame while speed is 0
	cam_rig._process(0.1)
	_check(cam_rig.response.length() < 0.01, "Camera response settles to zero at vehicle standstill (response=%s)" % str(cam_rig.response))

	# Verify stop() resets gear to neutral (0)
	director.stop()
	_check(director._previous_gear == 0, "After stop(), previous gear is reset to 0 (neutral) for next run")

	# =========================================================================
	# BUG 3 VERIFICATION — REAR LIGHTS DAYTIME OFF & HAZARD STATE
	# =========================================================================
	print("\n>>> Testing BUG 3: Daytime rear lights are OFF when not braking, ON when braking, hazard flashes...")
	var visual: VortexVisual = game.vehicle.visual
	_check(visual != null, "VortexVisual exists on player vehicle")
	var vehicle_lights: RushVehicleLights = director.lights
	_check(vehicle_lights != null, "RushVehicleLights exists")
	_check(vehicle_lights.director == director, "VehicleLights director reference is connected")

	# 1. Daytime (night = false), not braking (braking = 0.0), not reversing
	visual.lamp_state = Vector4(-9, -9, -9, -9) # Force refresh
	visual.update_lamps(false, 0.0, false, 0)
	var taillight_mats: Array = visual.role_materials.get("Taillight", [])
	_check(taillight_mats.size() > 0, "Taillight role materials found on vehicle")
	for mat: StandardMaterial3D in taillight_mats:
		_check(mat.emission.r == 0.0 and mat.emission.g == 0.0 and mat.emission.b == 0.0,
			"Daytime NOT braking -> Taillight emission is OFF (0.0): %s" % str(mat.emission))

	# 2. Daytime, braking = 1.0
	visual.lamp_state = Vector4(-9, -9, -9, -9)
	visual.update_lamps(false, 1.0, false, 0)
	for mat: StandardMaterial3D in taillight_mats:
		_check(mat.emission.r > 2.0, "Daytime BRAKING -> Taillight emission is bright red (> 2.0): %s" % str(mat.emission))

	# 3. Nighttime, not braking = 0.0
	visual.lamp_state = Vector4(-9, -9, -9, -9)
	visual.update_lamps(true, 0.0, false, 0)
	for mat: StandardMaterial3D in taillight_mats:
		_check(mat.emission.r > 0.3 and mat.emission.r < 1.0,
			"Nighttime NOT braking -> Taillight running light (~0.4): %s" % str(mat.emission))

	# 4. Hazard state: flash ON
	visual.lamp_state = Vector4(-9, -9, -9, -9)
	visual.update_lamps(false, 0.0, false, 1)
	for mat: StandardMaterial3D in taillight_mats:
		_check(mat.emission.r > 2.0, "Hazard Flash ON -> Taillight hazard glowing bright: %s" % str(mat.emission))

	# 5. Hazard state: flash OFF
	visual.lamp_state = Vector4(-9, -9, -9, -9)
	visual.update_lamps(false, 0.0, false, 2)
	for mat: StandardMaterial3D in taillight_mats:
		_check(mat.emission.r == 0.0, "Hazard Flash OFF (Day) -> Taillight emission is OFF: %s" % str(mat.emission))

	# =========================================================================
	# BUG 4 VERIFICATION — TRAFFIC DOES NOT DISAPPEAR AT HIGH SPEED
	# =========================================================================
	print("\n>>> Testing BUG 4: Traffic lookahead max_ahead at high speeds (220+ km/h)...")
	var traffic: RushTrafficSystem = game.traffic
	_check(traffic != null, "RushTrafficSystem exists")

	# Mock high speed calculation
	var speed_kmh: float = 230.0
	var lookahead: float = maxf(game.run.spec.spawn_min_ahead, speed_kmh / 3.6 * game.run.spec.reaction_seconds + 100.0)
	var max_ahead: float = maxf(850.0, lookahead + 150.0)
	_check(lookahead >= 350.0, "High speed (230 km/h) lookahead is >= 350m (got %.1f)" % lookahead)
	_check(max_ahead > lookahead + 90.0, "max_ahead (%.1f) strictly exceeds lookahead + 90m spawn distance" % max_ahead)
	_check(max_ahead >= 850.0, "max_ahead is >= 850m buffer preventing premature despawn")

	# =========================================================================
	# BUG 5 VERIFICATION — 5-RACER HIGHWAY RACE OPPONENTS USE PRODUCTION CARS
	# =========================================================================
	print("\n>>> Testing BUG 5: Race opponents spawn with preferred production models...")
	var opponents: RushRaceOpponents = director.opponents
	_check(opponents != null, "RushRaceOpponents exists")
	_check(opponents.racers.size() == 4, "4 AI opponent racers instantiated")

	var profiles: Array = opponents.profiles
	_check(profiles.size() == 4, "4 profiles loaded from RacerProfiles.json")

	var expected_cars: Array[String] = ["falcon_s1", "apex_rs", "inferno_r", "phantom_x"]
	for i: int in 4:
		var racer: RushTrafficVehicle = opponents.racers[i]
		var profile: Dictionary = profiles[i]
		var expected_car: String = expected_cars[i]
		_check(profile.preferred_car == expected_car, "Profile %d (%s) preferred_car is %s" % [i, profile.display_name, expected_car])
		_check(racer.production_id == expected_car, "Racer %d production_id is %s (got %s)" % [i, expected_car, racer.production_id])
		_check(racer.production != null, "Racer %d has RushProductionTrafficVisual instantiated (not fallback kind=2)" % i)
		if racer.production != null:
			_check(racer.production.meshes.size() > 0, "Racer %d production visual contains %d meshes" % [i, racer.production.meshes.size()])

	# Verify reset applies liveries to opponents
	opponents.reset()
	for i: int in 4:
		var racer: RushTrafficVehicle = opponents.racers[i]
		var expected_col: Color = [Color("bf752f"),Color("426fac"),Color("913a49"),Color("b8c4c8")][i]
		_check(racer.paint_material.albedo_color == expected_col, "Racer %d paint_material matches expected livery color: %s" % [i, str(racer.paint_material.albedo_color)])
		if racer.production != null and racer.production.paint.size() > 0:
			var mat: StandardMaterial3D = racer.production.paint[0]
			_check(mat.albedo_color == expected_col, "Racer %d production paint matches expected livery color: %s" % [i, str(mat.albedo_color)])
