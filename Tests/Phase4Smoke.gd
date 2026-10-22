extends Node
## Real Godot assertions, only execute in the isolated engine-check profile.
var checks: int = 0
var failures: int = 0
var game: Node
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Fixture seeds version 2 through the actual file loader; not a gameplay reward API.
	var file := FileAccess.open(SaveService.PATH,FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":2,"settings":{"master":0.37,"steering":1.1},"wallet":{"coins":600000,"issued_run":7,"settled_run":6}}))
	file.close()
	SaveService.load_settings()
	_check(SaveService.balance()==600000 and SaveService.owns("vortex_s"),"Schema 2 migration preserves wallet and grants starter")
	_check(SaveService.collection["selected"]=="vortex_s" and SaveService.settings["steering_mode"]==0,"Migration defaults selected car and steering wheel")
	_check(SaveService.settings["master"]==0.37,"Migration preserves settings")
	_check(not SaveService.select_vehicle("falcon_s1"),"Unowned selection rejected")
	var balance := SaveService.balance()
	_check(SaveService.buy_vehicle("falcon_s1"),"Buy with enough coins")
	_check(SaveService.balance()==balance-15000 and SaveService.owns("falcon_s1"),"Debit and ownership atomic")
	_check(not SaveService.buy_vehicle("falcon_s1") and SaveService.balance()==balance-15000,"Duplicate purchase no debit")
	_check(SaveService.select_vehicle("falcon_s1"),"Select owned car")
	_check(SaveService.set_paint("falcon_s1",0),"Set owned paint")
	balance = SaveService.balance()
	_check(SaveService.buy_upgrade("falcon_s1","engine",0),"Upgrade affordable")
	_check(not SaveService.buy_upgrade("falcon_s1","engine",0) and SaveService.balance()==balance-500,"Rapid duplicate expected-level request rejected")
	for level: int in range(1,10):
		_check(SaveService.buy_upgrade("falcon_s1","engine",level),"Upgrade step %d"%level)
	balance = SaveService.balance()
	_check(not SaveService.buy_upgrade("falcon_s1","engine",10) and SaveService.balance()==balance,"Level 10 cannot buy again")
	SaveService.load_settings()
	_check(SaveService.collection["selected"]=="falcon_s1" and SaveService.collection["paints"]["falcon_s1"]==0,"Selected car and paint survive reload")
	_check(SaveService.collection["upgrades"]["falcon_s1"]["engine"]==10,"Upgrades survive reload")
	_check(SaveService._read(SaveService.PATH)["schema_version"]==5,"Writes schema 5")
	var base := RushVehicleCatalog.effective("falcon_s1",{})
	var improved := RushVehicleCatalog.effective("falcon_s1",SaveService.collection["upgrades"]["falcon_s1"])
	_check(improved.top_speed_kmh>base.top_speed_kmh and improved.acceleration>base.acceleration,"Upgrade affects actual vehicle spec")
	_check(RushVehicleCatalog.effective("falcon_s1",{}).acceleration==base.acceleration,"Base resources not mutated")
	SaveService.wallet["coins"] = 0
	_check(not SaveService.buy_vehicle("apex_rs") and not SaveService.buy_upgrade("falcon_s1","tires",0),"Insufficient car and upgrade funds rejected")
	SaveService.wallet["coins"] = balance
	# A failed pending open must roll back both ownership/upgrade and debit.
	DirAccess.make_dir_absolute(SaveService.TEMP)
	_check(not SaveService.buy_vehicle("apex_rs") and not SaveService.owns("apex_rs") and SaveService.balance()==balance,"Failed purchase write rolls back")
	_check(not SaveService.buy_upgrade("falcon_s1","tires",0) and SaveService.collection["upgrades"]["falcon_s1"]["tires"]==0,"Failed upgrade write rolls back")
	DirAccess.remove_absolute(SaveService.TEMP)
	SaveService.commit()
	game = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for i: int in 4000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame
	_check(game.ready_for_drive,"Boot and prewarm")
	if not game.ready_for_drive:
		get_tree().quit(1)
		return
	game.open_garage()
	_check(game.state==game.State.GARAGE and game.showroom.camera.current,"Garage has dedicated current camera")
	game.go_home()
	game.start_drive()
	await _frames(165)
	game.director.opponents.stop()
	game.director.damage.enabled = false
	game.traffic.reset_pool(0)
	game.coins.reset_pool(0)
	_check(game.vehicle.spec.vehicle_id=="falcon_s1" and game.vehicle.spec.top_speed_kmh==improved.top_speed_kmh,"Race uses selected upgraded car")
	_check(game.vehicle.visual.active_index==1 and game.turbo.spec.top_speed_kmh>game.vehicle.spec.top_speed_kmh,"Selected visual and Turbo integrated")
	_touch(11,"wheel",true)
	var drag := InputEventScreenDrag.new()
	drag.index = 11
	for degrees: float in [20.0,40.0,60.0]:
		drag.position = DriveInput.regions.wheel.get_global_rect().get_center()+Vector2.from_angle(deg_to_rad(degrees))*90
		DriveInput._input(drag)
	_touch(12,"accelerate",true)
	SaveService.consumables.turbo_inventory = 1 # Isolated test fixture.
	game.vehicle.velocity = Vector3(0,0,-30)
	game.vehicle.signed_speed = 30
	_touch(13,"turbo",true)
	await _frames(4)
	_check(DriveInput.sample().x>0.1 and DriveInput.held("accelerate") and game.turbo.state==RushTurboController.State.ACTIVE,"Wheel plus throttle plus Turbo")
	_touch(11,"wheel",false)
	_touch(12,"accelerate",false)
	_touch(13,"turbo",false)
	await _frames(100)
	_check(absf(DriveInput.wheel_angle)<0.05,"Wheel returns to center")
	SaveService.set_value("steering_mode",1)
	await get_tree().process_frame
	_touch(14,"left",true)
	_check(DriveInput.sample().x<0,"Button mode remains functional")
	_touch(14,"left",false)
	SaveService.set_value("steering_mode",2)
	_check(DriveInput.effective_mode()==1 if not OS.has_feature("android") else true,"Unsupported tilt falls back to buttons")
	Input.action_press("right")
	_check(DriveInput.sample().x>0,"Keyboard independent of steering mode")
	Input.action_release("right")
	game.go_home()
	for id: String in RushVehicleCatalog.IDS:
		var spec := RushVehicleCatalog.effective(id,{})
		game.vehicle.apply_configuration(spec,RushVehicleCatalog.paint_color(0))
		_check(game.vehicle.visual.wheel_meshes.size()==4 and spec.exhaust_points.size()>0 and spec.turbo.top_speed_kmh>spec.top_speed_kmh,"Car model and Turbo: "+id)
	var traffic: RushTrafficVehicle = game.traffic.pool[0]
	traffic.activate(Vector3(-6,0,-300),0,20)
	_check(traffic.paint_material != null and not traffic.paint_material.vertex_color_use_as_albedo,"Explicit traffic paint does not depend on vertex color")
	var fixed_pose: Transform3D = game.highway.road_collider.global_transform
	game.highway.route_origin = 6200
	game.highway.last_cell = 999999
	game.highway.update_chunks()
	_check(game.highway.road_collider.global_transform==fixed_pose,"Scenery section changes never move road collider")
	# Malformed collection fields sanitize safely; wallet stays outside this normalization.
	SaveService._load_collection({"owned":["bogus",123],"selected":"bogus","paints":{"vortex_s":"bad"},"upgrades":{"vortex_s":{"engine":999}}})
	_check(SaveService.owns("vortex_s") and SaveService.collection["selected"]=="vortex_s" and SaveService.collection["upgrades"]["vortex_s"]["engine"]==10,"Corrupt IDs and levels sanitize")
	print("PHASE4_SMOKE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
func _touch(id: int, action: String, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.pressed = pressed
	event.position = DriveInput.regions[action].get_global_rect().get_center()
	if action=="wheel":
		event.position += Vector2(90,0) # Center is now the horn.
	DriveInput._input(event)
func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
func _check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+caption)
	else:
		print("PASS: "+caption)
