class_name RushDuelRace
extends Node
## Isolated unranked mode: never starts RunManager or calls reward/consumable APIs.
var game: Node
var service: RushDuelService
var active: bool = false
var remotes: Dictionary = {}
var clock: float = 0.0
var sequence: int = 0
var hidden_controls: Dictionary = {}
var ticket: int = 0
var course: RushDuelCourse
var local_finished: bool = false
var finish_submitted: bool = false
var go_received: bool = false
var grid_ready: bool = false
var local_grid: Vector3 = Vector3.ZERO
var go_label_until: int = 0

func _ready() -> void:
	process_physics_priority = 10 # Observe the vehicle AFTER its movement step.

func _can_boost() -> bool:
	return active and go_received and not local_finished and service.phase=="RACING" and service.context==SaveService.scope_generation

func _hold_start_grid() -> void:
	game.vehicle.driving = false
	game.vehicle.position = local_grid
	game.vehicle.position.y = RushRoadFrame.SURFACE_Y
	game.vehicle.rotation = Vector3.ZERO
	game.vehicle.velocity = Vector3.ZERO
	game.vehicle.signed_speed = 0.0
	game.vehicle.steering_angle = 0.0
	game.vehicle.last_command = Vector2.ZERO
	# Rebase with ZERO does not update interpolation history after a teleport.
	game.vehicle.previous_pose = game.vehicle.global_transform
	game.vehicle.current_pose = game.vehicle.global_transform
	game.vehicle.visual.global_transform = game.vehicle.global_transform
	for entry: Dictionary in remotes.values():
		entry.ghost.position = entry.grid
		entry.ghost.rotation = Vector3.ZERO
		entry.speed = 0.0

func _physics_process(_delta: float) -> void:
	if active and not go_received:
		_hold_start_grid()
		return
	if not _can_boost(): return
	if game.vehicle.position.z<=-RushDuelCourse.DISTANCE:
		# An inequality catches crossing/overshoot at any physics step; latch once.
		local_finished = true
		game.vehicle.driving = false
		game.vehicle.velocity = Vector3.ZERO
		game.vehicle.signed_speed = 0.0
		game.vehicle.last_command = Vector2.ZERO
		DriveInput.set_enabled(false)
		game.turbo.stop()
		GameAudio.set_driving(false)
func receive(packet: Dictionary) -> void:
	match String(packet.type):
		"countdown": _prepare()
		"tick":
			if active: game.ui.show_countdown(str(int(packet.count)))
		"go":
			if not active or not grid_ready or go_received or local_finished: return
			_hold_start_grid()
			go_label_until = Time.get_ticks_msec()+700
			go_received = true
			game.turbo.start_run()
			GameAudio.set_driving(true)
			game.vehicle.driving = true
			DriveInput.set_enabled(true)
			game.ui.show_countdown("GO!")
		"snapshot":
			if not active or not remotes.has(packet.uid): return
			var entry: Dictionary = remotes[packet.uid]
			var ghost: RushRemoteRacer = entry.ghost
			var model: RushProductionTrafficVisual = entry.model
			var state: RushNetworkRacerState = RushNetworkRacerState.new()
			state.player_id = packet.uid
			state.sequence = int(packet.seq)
			state.position = Vector3(float(packet.position[0]),float(packet.position[1]),float(packet.position[2]))
			state.rotation = Quaternion(Vector3.UP,float(packet.yaw))
			state.velocity = Vector3(float(packet.velocity[0]),float(packet.velocity[1]),float(packet.velocity[2]))
			state.race_progress = float(packet.progress)
			state.finished = packet.finished
			entry.speed = state.velocity.length()
			ghost.accept_snapshot(state)
			for i: int in model.spins.size():
				if i<entry.front.size() and entry.front[i]: model.spins[i].rotation.y = -float(packet.steer)
		"player_left":
			if remotes.has(packet.uid):
				var entry: Dictionary = remotes[packet.uid]
				entry.ghost.queue_free()
				remotes.erase(packet.uid)
		"results":
			if not active: return
			stop()
			service.status = "RACE COMPLETE — %d RACERS. Unranked: no coins or XP awarded."%packet.order.size()
			service.changed.emit()
		"cancelled":
			stop()
			service.status = "Race cancelled. No rewards issued."
			service.changed.emit()
func _prepare() -> void:
	if active: return
	ticket += 1
	var current: int = ticket
	var generation: int = service.generation
	var roster: Array = service.room.players.duplicate(true)
	var ready: bool = true
	for remote: Dictionary in roster:
		if remote.uid==service.account_id: continue
		ready = await RushProductionTrafficVisual.prepare(String(remote.car),get_tree())
		if current!=ticket or generation!=service.generation or service.context!=SaveService.scope_generation or service.phase!="LOADING": return
		if not ready:
			service._lost()
			return
	local_grid = Vector3.ZERO
	for player: Dictionary in roster:
		if player.uid==service.account_id:
			local_grid = RushDuelService.grid_position(int(player.grid),roster.size())
	active = true
	grid_ready = false
	local_finished = false
	finish_submitted = false
	go_received = false
	game._close_showroom()
	game.run.cancel()
	game.run.suspended = true
	game.traffic.active = false
	game.coins.active = false
	for car: RushTrafficVehicle in game.traffic.pool: car.deactivate()
	game.director.opponents.stop()
	game._reset_turbo()
	game._apply_selected()
	game.director.stop()
	game.turbo.prepare_multiplayer(_can_boost)
	game.director.damage.reset(game.vehicle.spec.vehicle_id)
	game.director.lights.configure()
	game.director.lights.visible = true
	game.vehicle.reset_vehicle()
	for player: Dictionary in roster:
		if player.uid==service.account_id:
			game.vehicle.position = local_grid
	# Rebase with ZERO does not update interpolation history after a teleport.
	game.vehicle.previous_pose = game.vehicle.global_transform
	game.vehicle.current_pose = game.vehicle.global_transform
	game.vehicle.visual.global_transform = game.vehicle.global_transform
	game.vehicle.driving = false
	DriveInput.set_enabled(false)
	game.cameras.showcase = false
	game.cameras.reset_rig()
	game.highway.route_origin = 0.0
	game.highway.last_cell = 999999
	game.highway.update_chunks()
	game.map_dressing.apply(0,4)
	game.finish_gate.enabled = false
	course = RushDuelCourse.new()
	game.world.add_child(course)
	course.build(game.highway)
	game.highway.set_duel_course(true)
	game.vehicle.road_center = RushDuelCourse.center_x
	game.state = game.State.NETWORK
	game.performance.driving = true
	game.ui.show_screen("drive")
	game.ui.rush.leaderboard_panel.hide()
	game.ui.rush.coin_label.text = "—"
	for key: String in ["turbo"]:
		if game.ui.controls.has(key):
			var control: Control = game.ui.controls[key]
			hidden_controls[control] = control.visible
			control.show()
	# No active-run powerup consumption: RunManager remains PREPARING/suspended.
	for remote: Dictionary in roster:
		if remote.uid==service.account_id or service.disconnected_players.has(remote.uid): continue
		var ghost: RushRemoteRacer = RushRemoteRacer.new()
		game.world.add_child(ghost)
		var model: RushProductionTrafficVisual = RushProductionTrafficVisual.new()
		ghost.add_child(model)
		model.build(String(remote.car))
		var front: Array[bool] = []
		for group: Dictionary in RushVehicleCatalog.definition(String(remote.car)).production_visual.wheels:
			front.append(bool(group.front))
		model.set_paint(RushVehicleCatalog.paint_color(int(remote.paint)))
		model.set_detail(2,game.performance.visual_level)
		ghost.position = RushDuelService.grid_position(int(remote.grid),roster.size())
		remotes[remote.uid] = {"ghost":ghost,"model":model,"front":front,"speed":0.0,"grid":ghost.position}
		# Bounded four visual-only remotes; let UI draw between heavier instantiations.
		await get_tree().process_frame
		if current!=ticket: return
		if generation!=service.generation or service.context!=SaveService.scope_generation or service.phase!="LOADING":
			stop()
			return
	# Show the complete grid for a frame before acknowledging that this client loaded.
	_hold_start_grid()
	await get_tree().process_frame
	if current!=ticket: return
	if generation!=service.generation or service.context!=SaveService.scope_generation or service.phase!="LOADING":
		stop()
		return
	grid_ready = true
	sequence = 0
	clock = 0.0
	service.phase = "COUNTDOWN"
	service.status = "Your car is loaded. Waiting for synchronized start…"
	if not service.action("loaded"):
		service._lost()
		return
	game.ui.show_countdown("WAIT FOR START")
func stop() -> void:
	ticket += 1
	if not active: return
	active = false
	go_received = false
	grid_ready = false
	go_label_until = 0
	local_finished = false
	finish_submitted = false
	game.turbo.reset()
	game.vehicle.road_center = Callable()
	if is_instance_valid(course):
		game.world.remove_child(course)
		course.queue_free()
	course = null
	game.highway.set_duel_course(false)
	GameAudio.set_driving(false)
	game.streaks.visible = false
	game.vehicle.driving = false
	DriveInput.set_enabled(false)
	for entry: Dictionary in remotes.values():
		if is_instance_valid(entry.ghost): entry.ghost.queue_free()
	remotes.clear()
	for control: Control in hidden_controls:
		if is_instance_valid(control): control.visible = bool(hidden_controls[control])
	hidden_controls.clear()
	game.director.audio.active = false
	game.run.suspended = false
	game.go_home()
	game.online_ui.open("multiplayer")
func _process(delta: float) -> void:
	if not active: return
	if service.context!=SaveService.scope_generation or service.phase in ["OFFLINE","CANCELLED"]:
		stop()
		return
	for id: String in remotes:
		var entry: Dictionary = remotes[id]
		entry.model.animate(delta,float(entry.speed))
	var running: bool = _can_boost()
	game.director.audio.active = running
	GameAudio.update_vehicle(delta,game.vehicle.speed_kmh(),DriveInput.sample().y if running else 0.0,game.vehicle.skid_amount if running else 0.0,game.turbo.intensity,game.vehicle.acceleration_now,RushTurboController.MULTIPLAYER_CAP_KMH)
	game.streaks.visible = running
	game.streaks.intensity = lerpf(game.streaks.intensity,game.turbo.intensity*.4 if running else 0.0,1.0-exp(-10.0*delta))
	clock += delta
	if clock<1.0/15.0: return
	clock = 0.0 # No catch-up burst after a stall.
	game.ui.update_hud(game.vehicle,game.cameras.mode)
	if DriveInput.held("horn"): game.director.audio.horn()
	var progress: float = 1.0 if local_finished else clampf(-game.vehicle.position.z/RushDuelCourse.DISTANCE,0,1)
	game.ui.rush.progress_bar.value = progress*100.0
	game.ui.status_label.text = "FINISHED • WAITING FOR RESULTS" if local_finished else "ONLINE • %.2f KM LEFT"%(RushDuelCourse.DISTANCE*.001*(1-progress))
	game.ui.status_label.text += " • "+service.latency_text()
	if service.phase!="RACING": return
	if Time.get_ticks_msec()>=go_label_until: game.ui.show_countdown("")
	var pose: Transform3D = game.vehicle.global_transform # Physics pose agrees with finish/progress on this tick.
	var velocity: Vector3 = game.vehicle.velocity
	sequence += 1
	service.action("snapshot",{"seq":sequence,"position":[pose.origin.x,pose.origin.y,pose.origin.z],"yaw":wrapf(pose.basis.get_euler().y,-PI,PI),"velocity":[velocity.x,velocity.y,velocity.z],"steer":game.vehicle.steering_angle,"progress":progress,"finished":local_finished})
	if local_finished and not finish_submitted:
		# Service also guards duplicate submission. Retry only a send that was rejected.
		finish_submitted = service.action("finish")
