extends Node
## Godot integration assertions. Unexecuted until a Godot binary is supplied.
var checks: int = 0
var failures: int = 0
var game: Node
var events := {"ready":0,"active":0,"end":0}
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveService.set_value("steering_mode",1)
	game = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for i: int in 3000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame
	_check(game.ready_for_drive,"Boot and prewarm complete")
	if not game.ready_for_drive:
		get_tree().quit(1)
		return
	var turbo: RushTurboController = game.turbo
	var wallet := SaveService.balance()
	SaveService.consumables.turbo_inventory = 2 # Isolated integration-test fixture.
	turbo.became_ready.connect(func() -> void: events["ready"] += 1)
	turbo.activated.connect(func() -> void: events["active"] += 1)
	turbo.ended.connect(func() -> void: events["end"] += 1)
	_check(not turbo.request_activation(),"Home blocks activation")
	game.start_drive()
	await get_tree().process_frame
	_check(turbo.active_left==0.0 and not turbo.request_activation(),"Countdown blocks activation")
	await _frames(165)
	game.director.opponents.stop()
	game.director.damage.enabled = false
	game.traffic.reset_pool(0)
	game.coins.reset_pool(0)
	turbo.set_physics_process(false)
	game.vehicle.driving = false
	game.vehicle.velocity = Vector3.ZERO
	game.vehicle.signed_speed = 0.0
	_check(turbo.active_left==0.0,"Countdown has no active boost duration")
	game.run.award_near_miss()
	_check(turbo.active_left==0 and game.run.near_misses==1,"Near miss preserves scoring without refilling Turbo")
	game.run.collect_coin()
	_check(turbo.active_left==0 and game.run.run_coins==10,"Coin rewards do not refill boosters")
	_check(turbo.state==RushTurboController.State.READY and events["ready"]==1,"Saved inventory enables READY without charge meter")
	_check(not turbo.request_activation(),"Stationary activation rejected without charge loss")
	game.vehicle.velocity = Vector3(0,0,-210.0/3.6)
	game.vehicle.signed_speed = 210.0/3.6
	game.vehicle.driving = true
	# Three simultaneous touch IDs exercise steer + throttle + Turbo.
	_touch(2,"accelerate",true)
	_touch(3,"left",true)
	_touch(4,"turbo",true)
	_check(DriveInput.held("left") and DriveInput.held("accelerate"),"Turbo touch preserves independent steering/pedal")
	turbo._physics_process(1.0/60.0)
	_touch(3,"left",false)
	_touch(4,"turbo",false)
	_check(turbo.state==RushTurboController.State.ACTIVE and events["active"]==1,"Touch activates once")
	_check(not turbo.request_activation(),"Activation spam rejected")
	_check(game.cameras.impulse.remaining>0 and game.exhaust.flare>0 and GameAudio.players["turbo_ignition"].playing,"Activation reaches camera VFX and audio")
	turbo.set_physics_process(true)
	await _frames(120)
	_check(game.vehicle.speed_kmh()>215.0 and game.vehicle.speed_kmh()<=271.0,"Boost accelerates beyond normal cap without teleport")
	_check(game.vehicle.position.y==0.0 and game.vehicle.velocity.y==0.0,"Boost retains planar stability")
	var charge_before := turbo.active_left
	var effect_clock: float = game.exhaust.clock
	game.pause_drive()
	_check(not turbo.request_activation(),"Pause rejects activation")
	await get_tree().create_timer(0.15,true,false,true).timeout
	_check(turbo.active_left==charge_before and game.exhaust.clock==effect_clock,"Pause freezes drain and effects")
	_check(GameAudio.players["turbo_spool"].stream_paused and GameAudio.players["wind"].stream_paused,"Pause freezes audio layers")
	game.resume_drive()
	_check(not GameAudio.players["turbo_spool"].stream_paused,"Resume continues audio")
	game.vehicle.respond_to_traffic(0.8)
	_check(turbo.state==RushTurboController.State.COOLDOWN and turbo.intensity<=0.15,"Collision ends boost and relieves cinematics")
	_check(game.vehicle.speed_kmh()<210.0 and game.vehicle.velocity.y==0.0,"Traffic impact remains meaningful")
	turbo.set_physics_process(false)
	game.vehicle.driving = false
	turbo._physics_process(4.0)
	game.vehicle.signed_speed = 30.0
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = true
	DriveInput._input(shift)
	turbo._physics_process(0.01)
	_check(turbo.state==RushTurboController.State.ACTIVE,"SHIFT uses input abstraction")
	Input.action_press("brake")
	turbo._physics_process(0.01)
	Input.action_release("brake")
	_check(turbo.state==RushTurboController.State.COOLDOWN,"Brake cancels boost")
	turbo._physics_process(4.0)
	SaveService.consumables.turbo_inventory = 1 # Third activation explicitly exercises a saved extra.
	turbo.request_activation()
	turbo._physics_process(20.0)
	_check(turbo.active_left==0.0 and turbo.state==RushTurboController.State.COOLDOWN,"Long timestep drains without negative charge")
	_check(events["active"]==3 and events["end"]==3,"Exactly one start/end cue per activation")
	_check(SaveService.balance()==wallet,"Turbo never changes persistent wallet")
	game.run._finish()
	_check(not turbo.enabled and not turbo.request_activation() and game.cameras.finishing,"Finish locks Turbo and starts hero camera")
	var stopped_charge := turbo.active_left
	turbo._physics_process(1.0)
	_check(turbo.active_left==stopped_charge,"No drain after finish")
	await _frames(180)
	_check(game.state==game.State.RESULTS and Engine.time_scale==1.0,"Results follows cinematic with normal time scale")
	game.start_drive()
	await get_tree().process_frame
	_check(turbo.active_left==0 and turbo.intensity==0 and turbo.activations==0,"Replay clears duration and effects, not saved boosters")
	_check(not game.cameras.finishing and not GameAudio.players["turbo_ignition"].playing,"Replay clears cinematic and ignition")
	_check(turbo.activated.get_connections().size()==2,"Signals are not duplicated on replay")
	print("PHASE3_SMOKE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)

func _touch(id: int, action: String, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.pressed = pressed
	event.position = DriveInput.regions[action].get_global_rect().get_center()
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
