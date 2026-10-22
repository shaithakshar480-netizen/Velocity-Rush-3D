extends Node
## Engine integration scenarios; execute only with Tools/run_engine_checks.py (isolated save).
var checks: int = 0
var failures: int = 0
var game: Node
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_migration_and_transactions()
	var gearbox := RushTransmission.new()
	gearbox.configure("vortex_s")
	for speed: int in range(0,300):
		gearbox.tick(.1,float(speed),1,270)
	_check(gearbox.gear==6 and gearbox.rpm>4000,"Transmission reaches sixth with RPM")
	gearbox.reset()
	_check(gearbox.gear==1 and gearbox.rpm==900,"Transmission reset")
	game = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for _frame: int in 15000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame
	_check(game.ready_for_drive,"All driving resources boot/import")
	if not game.ready_for_drive:
		_finish()
		return
	game.start_drive()
	await get_tree().process_frame
	game.run.advance_countdown(4.0)
	_check(DriveInput.enabled and game.director.damage.enabled and game.director.opponents.active,"GO unlocks all run systems")
	var condition: int = game.director.tod.mode
	var car: ArcadeVehicle = game.vehicle
	for mode: int in 5:
		game.cameras.mode = mode
		await get_tree().process_frame
		_check(game.director.cockpit.visible==(mode==4),"Cockpit visibility mode %d"%mode)
		_check(car.visual.body_root.visible==(mode!=4),"Exterior visibility mode %d"%mode)
	game.pause_drive()
	var hp: float = game.director.damage.health
	await get_tree().process_frame
	_check(game.director.damage.health==hp and not DriveInput.enabled,"Pause preserves health and blocks inputs")
	game.resume_drive()
	_check(game.director.tod.mode==condition,"Pause does not reroll time of day")
	# Three touch owners including horn; steering mode uses buttons for this fixture.
	SaveService.set_value("steering_mode",1)
	game.ui.steering_ui._update()
	for pair: Array in [[81,"left"],[82,"accelerate"],[83,"horn"]]:
		var touch := InputEventScreenTouch.new()
		touch.index = int(pair[0])
		touch.pressed = true
		touch.position = DriveInput.regions[String(pair[1])].get_global_rect().get_center()
		DriveInput._input(touch)
	_check(DriveInput.sample()==Vector2(-1,1) and DriveInput.held("horn"),"Horn, steering and gas simultaneous")
	DriveInput.clear()
	game.director.opponents.stop()
	game.traffic.active = false
	game.turbo.set_physics_process(false)
	car.set_physics_process(false)
	SaveService.consumables.turbo_inventory = 3
	for index: int in 3:
		game.turbo.state = RushTurboController.State.READY
		car.signed_speed = 40
		_check(game.turbo.request_activation(),"Eligible activation %d"%index)
		_check(not game.turbo.request_activation(),"Active boost rejects duplicate request")
	_check(SaveService.consumables.turbo_inventory==0,"Three saved charges consumed exactly once")
	game.turbo.state = RushTurboController.State.READY
	_check(not game.turbo.request_activation(),"Empty inventory prevents fourth activation")
	game.close_turbo_store()
	var traffic: RushTrafficVehicle = game.traffic.pool[0]
	traffic.activate(Vector3(6,0,-300),3,20)
	traffic.update_distance_lod(300)
	traffic.update_distance_lod(300)
	_check(traffic.detail==0,"Far traffic selects Low")
	traffic.update_distance_lod(40)
	_check(traffic.detail==2 and traffic.visual_variants[2].visible,"Nearby traffic always High")
	traffic.update_distance_lod(49)
	_check(traffic.detail==2,"LOD hysteresis retains High")
	traffic.deactivate()
	game.director.damage.apply_contact(4,Vector3.BACK,Vector3.FORWARD,"traffic")
	_check(game.director.damage.health>90 and game.state==game.State.DRIVING,"Minor crash survivable")
	for _hit: int in 3:
		game.director.damage.apply_contact(100,Vector3.BACK,Vector3.FORWARD,"traffic")
	_check(game.state==game.State.CRASHED and not car.driving,"Repeated serious impacts destroy and lock driving")
	await get_tree().create_timer(3.0).timeout
	_check(game.ui.screen=="crashed","Destruction reaches failure UI")
	car.set_physics_process(true)
	game.turbo.set_physics_process(true)
	game.start_drive()
	await get_tree().process_frame
	_check(game.director.damage.health==game.director.damage.maximum and SaveService.consumables.turbo_inventory==0,"Replay restores health without granting new boosters")
	game.go_home()
	_check(game.director.effects.stage==0 and not game.director.audio.active,"Home stops damage/audio")
	_finish()
func _migration_and_transactions() -> void:
	for schema: int in [1,2,3,4]:
		var file := FileAccess.open(SaveService.PATH,FileAccess.WRITE)
		file.store_string(JSON.stringify({"schema_version":schema,"settings":{"master":.37,"camera":3},"wallet":{"coins":12000,"issued_run":7,"settled_run":6},"collection":SaveService.collection,"progression":SaveService.progression}))
		file.close()
		SaveService.load_settings()
		_check(SaveService.balance()==12000 and SaveService.settings.master==.37 and SaveService.settings.camera==3,"Old schema %d retains wallet/settings"%schema)
		_check(SaveService.consumables.turbo_inventory==0,"Old schema %d adds empty inventory"%schema)
	_check(SaveService.buy_turbo("boost_2") and SaveService.balance()==11500,"Coin offer atomic purchase")
	SaveService.load_settings()
	_check(SaveService.consumables.turbo_inventory==2,"Inventory survives reload")
	var token := SaveService.reserve_ad_request()
	_check(SaveService.settle_ad_request(token,true),"Verified completed reward settles")
	_check(not SaveService.settle_ad_request(token,true) and SaveService.consumables.turbo_inventory==4,"Duplicate completion cannot reward twice")
	var skipped := SaveService.reserve_ad_request()
	_check(SaveService.settle_ad_request(skipped,false) and SaveService.consumables.turbo_inventory==4,"Skipped ad grants nothing")
	var ads := RushRewardedAdService.new()
	add_child(ads)
	_check(not ads.request_turbo_reward() and SaveService.consumables.turbo_inventory==4,"Missing provider grants nothing")
	ads.queue_free()
	# Force an actual write-open failure using the isolated pending path as a directory.
	DirAccess.make_dir_absolute(SaveService.TEMP)
	var balance := SaveService.balance()
	var inventory: int = SaveService.consumables.turbo_inventory
	_check(not SaveService.buy_turbo("boost_4"),"Write failure rejects purchase")
	_check(SaveService.balance()==balance and SaveService.consumables.turbo_inventory==inventory,"Write failure rolls back both balances")
	DirAccess.remove_absolute(SaveService.TEMP)
	_check(SaveService.commit(),"Storage recovers after failed purchase")
func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)
func _finish() -> void:
	print("DRIVING_PASS_SMOKE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
