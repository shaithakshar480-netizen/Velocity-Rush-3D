extends Node
## Real Godot regression scenarios. NOT executed in the creation environment.
var game: Node
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for i: int in 3000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame
	_check(game.ready_for_drive,"Boot resources prewarmed")
	if not game.ready_for_drive:
		get_tree().quit(1)
		return
	_check(game.traffic.pool.size()==24 and game.coins.pool.size()==40,"Full pools before countdown")
	var road_pose: Transform3D = game.highway.road_collider.global_transform
	game.start_drive()
	await get_tree().process_frame
	var touch := InputEventScreenTouch.new()
	touch.index = 18
	touch.pressed = true
	touch.position = DriveInput.regions["accelerate"].get_global_rect().get_center()
	DriveInput._input(touch)
	for i: int in 30:
		await get_tree().physics_frame
	_check(game.vehicle.speed_kmh()<0.01 and game.vehicle.has_road_contact(),"Countdown holds clean road pose")
	for i: int in 180:
		if game.run.state==RushRunManager.RunState.RUNNING:
			break
		await get_tree().physics_frame
	_check(DriveInput.enabled and DriveInput.held("accelerate"),"Held countdown touch unlocks on GO")
	_check(game.traffic.active_count()==0,"GO does not spawn traffic on activation tick")
	touch.pressed = false
	DriveInput._input(touch)
	game.director.opponents.stop()
	game.director.damage.enabled = false
	game.traffic.reset_pool(0)
	game.coins.reset_pool(0)
	Input.action_press("accelerate")
	var min_y := INF
	var max_y := -INF
	var max_vertical_velocity := 0.0
	for i: int in 4800:
		await get_tree().physics_frame
		min_y = minf(min_y,game.vehicle.position.y)
		max_y = maxf(max_y,game.vehicle.position.y)
		max_vertical_velocity = maxf(max_vertical_velocity,absf(game.vehicle.velocity.y))
	Input.action_release("accelerate")
	_check(absf(min_y)<0.0001 and absf(max_y)<0.0001,"No vertical drift through long straight drive")
	_check(max_vertical_velocity<0.0001,"No vertical oscillation velocity")
	_check(game.run.furthest>2500.0,"Natural driving crosses seams and origin rebase")
	_check(game.highway.road_collider.global_transform.is_equal_approx(road_pose),"Continuous deck never teleports")
	_check(game.vehicle.speed_kmh()>180.0,"High-speed driving preserved")
	game.pause_drive()
	var frozen: Vector3 = game.vehicle.position
	await get_tree().create_timer(0.1,true,false,true).timeout
	_check(frozen.is_equal_approx(game.vehicle.position),"Pause still freezes physics")
	game.resume_drive()
	for lane: int in 4:
		var a := RushRoadFrame.lane_point(lane,0,RushRoadFrame.COIN_HEIGHT)
		var b := RushRoadFrame.lane_point(lane,-12,RushRoadFrame.COIN_HEIGHT)
		_check(a.x==b.x and a.y==b.y and a.z-b.z==12.0,"Exact straight coin lane %d"%lane)
	var coin: RushRoadCoin = game.coins.pool[0]
	coin.rotation = Vector3(1,2,3)
	coin.scale = Vector3.ONE*2
	coin.activate(RushRoadFrame.lane_point(1,game.vehicle.position.z-20,RushRoadFrame.COIN_HEIGHT))
	_check(coin.rotation==Vector3.ZERO and coin.scale==Vector3.ONE,"Coin reuse resets transform")
	_check(coin.position.y==RushRoadFrame.COIN_HEIGHT,"Coin height is authoritative")
	game.highway.set_debug_lanes(false)
	var hidden := true
	for guide: Node3D in game.highway.lane_guides:
		hidden = hidden and not guide.visible
	_check(hidden,"Lane debug is hidden by default")
	game.go_home()
	game.start_drive()
	await get_tree().process_frame
	_check(game.vehicle.position.y==RushRoadFrame.SURFACE_Y and game.vehicle.velocity==Vector3.ZERO,"Replay resets planar pose")
	print("PHASE2_FIX_SMOKE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)

func _check(condition: bool, caption: String) -> void:
	checks += 1
	if condition:
		print("PASS: "+caption)
	else:
		failures += 1
		push_error("FAIL: "+caption)
