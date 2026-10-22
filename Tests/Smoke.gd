extends Node
## Execute using an isolated user-data directory, never a real player's profile.
## godot --headless --path . res://Tests/Smoke.tscn
var failures: int = 0
var checks: int = 0
var game: Node
var saved_settings: Dictionary

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	saved_settings = SaveService.settings.duplicate(true)
	SaveService.set_value("steering_mode",1)
	game = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for boot_frame: int in 3000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame
	_check(game.ready_for_drive,"Prewarm finishes before play")
	if not game.ready_for_drive:
		get_tree().quit(1)
		return
	_check(game.state == game.State.HOME,"Splash reaches home")
	game.start_drive()
	await _frames(165)
	game.director.opponents.stop()
	game.director.damage.enabled = false
	game.traffic.reset_pool(0)
	game.coins.reset_pool(0)
	_check(game.vehicle.has_road_contact(),"Ground contact")
	Input.action_press("accelerate")
	await _frames(240)
	_check(game.vehicle.speed_kmh()>70.0,"Acceleration")
	var previous: float = game.vehicle.speed_kmh()
	Input.action_release("accelerate")
	Input.action_press("brake")
	await _frames(30)
	_check(game.vehicle.speed_kmh()<previous,"Braking")
	await _frames(240)
	_check(game.vehicle.signed_speed < -1.0,"Brake transitions to reverse")
	Input.action_release("brake")
	game.start_drive()
	await _frames(165)
	game.director.opponents.stop()
	game.director.damage.enabled = false
	game.traffic.reset_pool(0)
	game.coins.reset_pool(0)
	Input.action_press("accelerate")
	await _frames(720)
	_check(game.vehicle.speed_kmh()<=game.vehicle.spec.top_speed_kmh+1.0,"Top speed cap")
	_check(game.vehicle.speed_kmh()>130.0,"High-speed driving")
	Input.action_press("right")
	await _frames(30)
	_check(absf(game.vehicle.rotation.y)>0.01,"Steering")
	_check(absf(game.vehicle.rotation.z)<0.001,"No rollover torque")
	Input.action_release("right")
	Input.action_release("accelerate")
	for i: int in 5:
		game.change_camera()
		await _frames(12)
		_check(game.cameras.mode==(i+1+int(saved_settings["camera"]))%4,"Camera cycle %d"%i)
	game.pause_drive()
	var position: Vector3 = game.vehicle.position
	await get_tree().create_timer(0.1,true,false,true).timeout
	_check(game.vehicle.position.is_equal_approx(position),"Pause freezes physics")
	game.open_settings()
	_check(game.state == game.State.SETTINGS and get_tree().paused,"Pause settings preserves freeze")
	game.close_settings()
	game.resume_drive()
	_check(not get_tree().paused and DriveInput.enabled,"Resume")
	game.start_drive()
	_check(game.vehicle.velocity.length()<0.01,"Restart clears momentum")
	await _frames(165)
	# Real InputEventScreenTouch routing with distinct IDs and independent release.
	_touch(3,"accelerate",true)
	_touch(8,"left",true)
	_check(DriveInput.sample()==Vector2(-1,1),"Two-finger throttle and steering")
	_touch(8,"left",false)
	_check(DriveInput.sample()==Vector2(0,1),"One finger release preserves other")
	_touch(9,"brake",true)
	_check(DriveInput.sample().y == -1.0,"Brake wins simultaneous pedals")
	_touch(9,"brake",false)
	_touch(3,"accelerate",false)
	_check(DriveInput.sample()==Vector2.ZERO,"All fingers released")
	_touch(11,"accelerate",true)
	game.pause_drive()
	_check(DriveInput.pointers.is_empty(),"Pause clears active touches")
	game.go_home()
	_check(game.state==game.State.HOME and not get_tree().paused,"Return home")
	SaveService.set_value("steering",1.23)
	SaveService.load_settings()
	_check(is_equal_approx(float(SaveService.settings["steering"]),1.23),"Settings round trip")
	SaveService.set_value("steering",999)
	_check(float(SaveService.settings["steering"])==1.5,"Settings clamps bad ranges")
	_check(SaveService._read("user://does_not_exist.json").is_empty(),"Missing save safe")
	# Corrupt primary with a known-good backup: load must recover, not crash.
	SaveService.set_value("steering",1.1)
	SaveService.set_value("steering",1.2)
	var corrupt := FileAccess.open(SaveService.PATH,FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	SaveService.load_settings()
	_check(is_equal_approx(float(SaveService.settings["steering"]),1.1),"Corrupt save backup recovery")
	SaveService.settings = saved_settings
	SaveService.commit()
	print("PHASE1_SMOKE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)

func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame

func _touch(id: int, action: String, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.pressed = pressed
	event.position = DriveInput.regions[action].get_global_rect().get_center()
	DriveInput._input(event)

func _check(condition: bool, caption: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+caption)
	else:
		print("PASS: "+caption)
