extends Node
## Run through Tools/run_engine_checks.py in an isolated test profile.
## Targeted scenarios deliberately control coordinates; this is not a device playtest.
var checks: int = 0
var failures: int = 0
var game: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	game.start_drive()
	Input.action_press("accelerate")
	await _frames(30)
	_check(game.vehicle.velocity.length()<0.01 and not DriveInput.enabled,"Countdown blocks throttle")
	game.pause_drive()
	var remaining: float = game.run.countdown_left
	await get_tree().create_timer(0.1,true,false,true).timeout
	_check(is_equal_approx(remaining,game.run.countdown_left),"Pause freezes countdown")
	game.resume_drive()
	await _frames(150)
	Input.action_release("accelerate")
	_check(game.run.state==RushRunManager.RunState.RUNNING and DriveInput.enabled,"GO activates run")
	game.director.opponents.stop()
	game.director.damage.enabled = false
	game.traffic.active = false
	game.coins.active = false
	game.vehicle.driving = false
	game.vehicle.reset_vehicle()
	game.traffic.reset_pool(game.run.run_id)
	game.coins.reset_pool(game.run.run_id)
	var traffic_ids: Array[int] = []
	for item: RushTrafficVehicle in game.traffic.pool:
		traffic_ids.append(item.get_instance_id())
	for i: int in 100:
		game.traffic._try_spawn()
	_check(game.traffic.active_count()>0 and game.traffic.active_count()<=24,"Traffic pool bounded")
	for item: RushTrafficVehicle in game.traffic.pool:
		if item.active:
			_check(item.lane!=game.traffic.escape_lane,"Navigable escape lane")
			_check(item.position.z<-game.run.spec.spawn_min_ahead,"Safe lookahead")
			for other: RushTrafficVehicle in game.traffic.pool:
				if other!=item and other.active and other.lane==item.lane:
					_check(absf(other.position.z-item.position.z)>60.0,"Same-lane spawn spacing")
	_check(not game.traffic.placement_safe(game.traffic.escape_lane,-400.0,20.0),"Reject blocked escape lane")
	_check(not game.traffic.placement_safe((game.traffic.escape_lane+1)%4,-10.0,20.0),"Reject player overlap/unsafe lookahead")
	game.traffic.reset_pool(game.run.run_id)
	for i: int in game.traffic.pool.size():
		_check(game.traffic.pool[i].get_instance_id()==traffic_ids[i],"Pool instance retained")
	game.run.furthest = 0.0
	game.run.distance = 0.0
	game.coins.active = true
	_check(game.coins._spawn_pattern(),"Readable coin pattern spawns")
	_check(game.coins.active_count()==5,"Pattern uses pooled group")
	var first_coin: RushRoadCoin = game.coins.pool[0]
	first_coin.position = game.vehicle.position+Vector3(0,0.9,0)
	game.coins.previous_player = game.vehicle.position
	var coins_before: int = game.run.run_coins
	game.coins.evaluate_pickups()
	game.coins.evaluate_pickups()
	_check(game.run.run_coins==coins_before+1 and not first_coin.active,"Coin picked up exactly once")
	game.coins.active = false
	game.traffic.active = true
	var npc: RushTrafficVehicle = game.traffic.pool[0]
	npc.activate(Vector3.ZERO,1,20.0)
	game.vehicle.position = Vector3(3,0,-7)
	game.vehicle.velocity = Vector3(0,0,-40)
	game.traffic.previous_player = Vector3(3,0,7)
	var near_before: int = game.run.near_misses
	game.traffic.evaluate_passes()
	game.traffic.evaluate_passes()
	_check(game.run.near_misses==near_before+1,"Swept close pass awards once after clearance")
	npc.activate(Vector3.ZERO,1,20.0)
	game.vehicle.position = Vector3(0,0,-7)
	game.vehicle.velocity = Vector3(0,0,-40)
	game.vehicle.impact_cooldown = 0.0
	game.traffic.previous_player = Vector3(0,0,7)
	game.traffic.evaluate_passes()
	_check(npc.was_hit and game.run.combo==0,"Collision cancels combo")
	_check(game.run.near_misses==near_before+1,"Collision cannot award near miss")
	_check(game.vehicle.speed_kmh()<144.0,"Impact slows player")
	npc.activate(Vector3.ZERO,1,20.0)
	game.vehicle.position = Vector3(5,0,-7)
	game.vehicle.velocity = Vector3(0,0,-40)
	game.traffic.previous_player = Vector3(5,0,7)
	game.traffic.evaluate_passes()
	_check(game.run.near_misses==near_before+1,"Distant pass is not a near miss")
	game.director.opponents.stop()
	game.director.damage.enabled = false
	game.traffic.active = false
	game.run.combo = 3
	game.run.combo_left = 0.01
	game.vehicle.velocity = Vector3.ZERO
	game.run._physics_process(0.02)
	_check(game.run.combo==0,"Combo expires")
	game.run.origin_offset = 0.0
	game.run.distance = 2500.0
	game.run.furthest = 2500.0
	game.vehicle.position = Vector3(0,0,-2500)
	game.run.previous_z = -2500.0
	var relative_npc: Vector3 = npc.position-game.vehicle.position
	game._physics_process(0.0)
	_check(is_equal_approx(game.run.origin_offset-game.vehicle.position.z,2500.0),"Rebase preserves route distance")
	_check((npc.position-game.vehicle.position).is_equal_approx(relative_npc),"Rebase preserves traffic offset")
	var score_before: float = game.run.score
	game.vehicle.position.z += 20.0
	game.run._physics_process(0.1)
	game.vehicle.position.z -= 20.0
	game.run._physics_process(0.1)
	_check(is_equal_approx(score_before,game.run.score),"Reverse/retrace cannot farm distance score")
	game.run.distance = game.run.spec.distance_m
	game.run.score = 3000
	game.run.run_coins = 400
	game.run.near_misses = 5
	game.run.high_speed_seconds = 120
	var before_reward := SaveService.balance()
	game.vehicle.position.z = game.run.origin_offset-game.run.spec.distance_m
	game.run.previous_z = game.vehicle.position.z
	game.run.furthest = game.run.spec.distance_m
	game.run._physics_process(0.01)
	_check(game.run.state==RushRunManager.RunState.FINISHED,"Route crossing triggers finish")
	_check(game.run.reward_saved,"Finish saves reward")
	_check(int(game.run.result["total"])==880,"Configured reward arithmetic")
	_check(SaveService.balance()==before_reward+880+int(game.run.result.get("level_coins",0)),"Wallet credited once")
	_check(not SaveService.add_coins(880,game.run.run_id),"Duplicate run ID rejected")
	SaveService.load_settings()
	_check(not SaveService.add_coins(880,game.run.run_id),"Duplicate rejected after reload")
	game.run.retry_reward()
	_check(game.state==game.State.RESULTS and SaveService.balance()==before_reward+880+int(game.run.result.get("level_coins",0)),"Results retry is idempotent")
	game.go_home()
	_check(game.state==game.State.HOME and game.traffic.active_count()==0 and game.coins.active_count()==0,"Results to home clears pools")
	game.start_drive()
	await _frames(2)
	_check(game.run.state==RushRunManager.RunState.COUNTDOWN and game.run.score==0 and game.run.run_coins==0,"Replay resets run")
	game.go_home()
	_check(not SaveService.spend_coins(-1) and not SaveService.spend_coins(SaveService.balance()+1),"Invalid spending rejected")
	_check(SaveService.spend_coins(10),"Valid spending persists")
	var after_spend := SaveService.balance()
	SaveService.load_settings()
	_check(SaveService.balance()==after_spend,"Wallet survives reload")
	# Fail the actual pending-file open by occupying its path with a directory.
	DirAccess.make_dir_absolute(SaveService.TEMP)
	var issued_before: int = SaveService.wallet["issued_run"]
	_check(SaveService.reserve_run()==0 and int(SaveService.wallet["issued_run"])==issued_before,"Failed reservation rolls back")
	_check(not SaveService.spend_coins(1) and SaveService.balance()==after_spend,"Failed spend rolls back")
	DirAccess.remove_absolute(SaveService.TEMP)
	SaveService.commit()
	var old := FileAccess.open(SaveService.PATH,FileAccess.WRITE)
	old.store_string(JSON.stringify({"schema_version":1,"settings":{"master":0.37,"steering":1.14,"camera":2}}))
	old.close()
	SaveService.load_settings()
	_check(SaveService.balance()==0,"Phase 1 migration defaults wallet")
	_check(is_equal_approx(float(SaveService.settings["master"]),0.37) and int(SaveService.settings["camera"])==2,"Phase 1 settings preserved")
	SaveService.commit()
	_check(SaveService._read(SaveService.PATH).get("schema_version")==5,"Migrated save writes schema 5")
	print("PHASE2_SMOKE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)

func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame

func _check(condition: bool, caption: String) -> void:
	checks += 1
	if condition:
		print("PASS: "+caption)
	else:
		failures += 1
		push_error("FAIL: "+caption)
