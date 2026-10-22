extends Node

class MockInput extends Node:
	var cmd := Vector2.ZERO
	func sample() -> Vector2:
		return cmd

var failures: int = 0
var checks: int = 0

func _check(condition: bool, caption: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", caption)
		push_error("FAIL: " + caption)
	else:
		print("PASS: ", caption)

func _ready() -> void:
	print("========================================")
	print("--- CAMERA SHAKE 6-TEST SUITE START ---")
	print("========================================")
	var game = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for i in 15000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame

	_check(game.ready_for_drive, "Game ready_for_drive initialized")
	if not game.ready_for_drive:
		get_tree().quit(1)
		return

	var car: ArcadeVehicle = game.vehicle
	var cam_rig: DriveCameraRig = game.cameras
	var director: RushDrivingDirector = game.director

	var mock = MockInput.new()
	add_child(mock)
	car.input_source = mock

	game.start_drive()
	for i in 500:
		if game.state == game.State.DRIVING:
			break
		await get_tree().process_frame

	car.driving = true
	DriveInput.set_enabled(true)
	_check(game.state == game.State.DRIVING, "Game state is DRIVING")

	# =========================================================================
	# TEST 1: Drive -> release accelerator -> naturally coast to stop -> NO camera shake
	# =========================================================================
	print("\n>>> TEST 1: Coast to stop (natural deceleration)")
	cam_rig.impulse.reset()
	mock.cmd = Vector2(0, 1.0)
	for i in 60:
		await get_tree().physics_frame
		if car.speed_kmh() > 20.0:
			break
	_check(car.speed_kmh() > 15.0, "Car accelerated to > 15 km/h: %.1f km/h" % car.speed_kmh())
	
	# Release accelerator and coast to stop
	mock.cmd = Vector2.ZERO
	for i in 800:
		await get_tree().physics_frame
		if car.speed_kmh() < 0.2:
			break
	_check(car.speed_kmh() < 0.5, "Car stopped naturally: %.2f km/h" % car.speed_kmh())
	_check(cam_rig.impulse.remaining == 0.0, "Coast to stop: NO camera shake impulse (remaining=%.3f)" % cam_rig.impulse.remaining)
	_check(cam_rig.response.length() < 0.02, "Coast to stop: Camera response settled: %s" % str(cam_rig.response))

	# =========================================================================
	# TEST 2: Drive -> normal brake -> stop -> NO camera shake
	# =========================================================================
	print("\n>>> TEST 2: Normal drive and brake to stop")
	cam_rig.impulse.reset()
	mock.cmd = Vector2(0, 1.0)
	for i in 150:
		await get_tree().physics_frame
		if car.speed_kmh() > 80.0:
			break
	_check(car.speed_kmh() > 50.0, "Car accelerated: %.1f km/h" % car.speed_kmh())

	# Brake with command.y = -0.6
	mock.cmd = Vector2(0, -0.6)
	for i in 250:
		await get_tree().physics_frame
		if car.speed_kmh() < 0.2:
			break
	mock.cmd = Vector2.ZERO
	_check(car.speed_kmh() < 0.5, "Car stopped with normal brake: %.2f km/h" % car.speed_kmh())
	_check(cam_rig.impulse.remaining == 0.0, "Normal brake: NO camera shake impulse (remaining=%.3f)" % cam_rig.impulse.remaining)
	_check(cam_rig.response.length() < 0.02, "Normal brake: Camera response settled: %s" % str(cam_rig.response))

	# =========================================================================
	# TEST 3: Drive fast -> hard brake -> stop -> NO camera shake
	# =========================================================================
	print("\n>>> TEST 3: Drive fast -> hard brake -> stop")
	cam_rig.impulse.reset()
	mock.cmd = Vector2(0, 1.0)
	for i in 300:
		await get_tree().physics_frame
		if car.speed_kmh() > 140.0:
			break
	_check(car.speed_kmh() > 100.0, "Car reached high speed: %.1f km/h" % car.speed_kmh())

	# Hard brake with command.y = -1.0
	mock.cmd = Vector2(0, -1.0)
	for i in 300:
		await get_tree().physics_frame
		if car.speed_kmh() < 0.2:
			break
	mock.cmd = Vector2.ZERO
	_check(car.speed_kmh() < 0.5, "Car stopped with hard brake: %.2f km/h" % car.speed_kmh())
	_check(cam_rig.impulse.remaining == 0.0, "Hard brake: NO camera shake impulse (remaining=%.3f)" % cam_rig.impulse.remaining)
	_check(cam_rig.response.length() < 0.02, "Hard brake: Camera response settled: %s" % str(cam_rig.response))

	# =========================================================================
	# TEST 4: Brake repeatedly -> stop -> wait at standstill -> camera stable
	# =========================================================================
	print("\n>>> TEST 4: Repeated brake pulses -> stop -> wait at standstill")
	for pulse in 3:
		mock.cmd = Vector2(0, 1.0)
		for i in 30:
			await get_tree().physics_frame
		mock.cmd = Vector2(0, -1.0)
		for i in 30:
			await get_tree().physics_frame

	mock.cmd = Vector2.ZERO
	for i in 120:
		await get_tree().physics_frame
		if car.speed_kmh() < 0.2:
			break

	# Measure camera stability for 60 frames at standstill
	var prev_pos := cam_rig.camera.global_position
	var max_jitter := 0.0
	for f in 60:
		await get_tree().physics_frame
		var pos := cam_rig.camera.global_position
		var delta_pos := (pos - prev_pos).length()
		prev_pos = pos
		if delta_pos > max_jitter:
			max_jitter = delta_pos

	_check(max_jitter < 0.001, "Standstill camera remains completely stable (max_jitter=%.6f m)" % max_jitter)
	_check(cam_rig.impulse.remaining == 0.0, "Standstill: impulse.remaining == 0.0")

	# =========================================================================
	# TEST 5: Multiple downshifts during braking -> NO camera shake
	# =========================================================================
	print("\n>>> TEST 5: Downshifts during braking produce NO camera shake")
	cam_rig.impulse.reset()
	# Simulate all downshift transitions: 5->4, 4->3, 3->2, 2->1
	director._shifted(5)
	director._shifted(4)
	director._shifted(3)
	director._shifted(2)
	director._shifted(1)
	_check(cam_rig.impulse.remaining == 0.0, "Downshifts 5->4->3->2->1 caused NO camera shake impulse")

	# =========================================================================
	# TEST 6: Actual crash/collision -> legitimate crash camera shake works
	# =========================================================================
	print("\n>>> TEST 6: Legitimate collision impact feedback triggers camera shake")
	cam_rig.impulse.reset()
	cam_rig.impact_feedback(0.6)
	_check(cam_rig.impulse.remaining > 0.15, "Major collision impact triggers camera shake (remaining=%.3f, amp=%.3f)" % [
		cam_rig.impulse.remaining, cam_rig.impulse.amplitude
	])
	var shake_offset := cam_rig.impulse.tick(0.016)
	_check(shake_offset.length() > 0.001, "Collision shake produces visible displacement: %s" % str(shake_offset))
	cam_rig.impulse.reset()

	print("========================================")
	print("--- CAMERA SHAKE 6-TEST SUITE END ---")
	print("CHECKS: %d, FAILURES: %d" % [checks, failures])
	print("========================================")
	get_tree().quit(0 if failures == 0 else 1)
