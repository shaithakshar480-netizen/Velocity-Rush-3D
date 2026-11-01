extends Node
## Owns navigation/lifecycle only. Services and gameplay have independent responsibilities.
enum State { SPLASH, HOME, DRIVING, PAUSED, SETTINGS, FINISHING, RESULTS, GARAGE, PROGRESSION, CRASHED, ONBOARDING, NETWORK }
var state: State = State.SPLASH
var pause_exit_dialog: RushRaceExitDialog
var pause_exit_scope: int = -1
var settings_origin: State = State.HOME
var world: Node3D
var highway: Highway
var vehicle: ArcadeVehicle
var cameras: DriveCameraRig
var ui: AutomotiveUI
var performance: PerformanceManager
var last_quality: int = -1
var hud_clock: float = 0.0
var run: RushRunManager
var traffic: RushTrafficSystem
var coins: RushCoinSystem
var course_pickups: RushCoursePickups
var course_preparing: bool = false
var course_generation: int = 0
var finish_gate: RushFinishGate
var turbo: RushTurboController
var turbo_ui: RushTurboPresentation
var exhaust: RushExhaustEffects
var streaks: RushSpeedStreaks
var progression_ui: RushProgressionUI
var map_dressing: RushMapDressing
var brake_effects: RushBrakeEffects
var shop: RushStoreUI
var duel_race: RushDuelRace
var online_ui: RushOnlineUI
var garage_ui: RushGarageUI
var showroom: RushShowroom
var road_environment: Environment
var director: RushDrivingDirector
var ready_for_drive: bool = false
var ad_service: RushAdService
var powerups: RushPowerupService
var trial_vehicle_id: String = ""

var android_back_deadline: int = 0
var exit_dialog: RushAppExitDialog
var exit_notice: Label

func _android_back() -> void:
	if is_instance_valid(pause_exit_dialog) and pause_exit_dialog.visible:
		android_back_deadline = 0
		pause_exit_dialog.cancel()
		return
	if is_instance_valid(exit_dialog) and exit_dialog.visible:
		exit_dialog.hide()
		android_back_deadline = 0
		return
	var now: int = Time.get_ticks_msec()
	if android_back_deadline>0 and now<=android_back_deadline:
		android_back_deadline = 0
		if is_instance_valid(exit_notice): exit_notice.hide()
		if duel_race!=null and duel_race.active:
			online_ui.duel._lost()
		pause_drive()
		if not is_instance_valid(exit_dialog):
			exit_dialog = RushAppExitDialog.new()
			exit_dialog.confirmed.connect(_confirm_exit)
			add_child(exit_dialog)
		exit_dialog.popup_centered(Vector2i(420,190))
		return
	android_back_deadline = now+2000
	_back()
	if not is_instance_valid(exit_notice):
		var layer: CanvasLayer = CanvasLayer.new()
		layer.layer = 120
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(layer)
		exit_notice = Label.new()
		exit_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		exit_notice.text = "Press Back again to exit"
		exit_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		exit_notice.add_theme_font_size_override("font_size",22)
		exit_notice.add_theme_color_override("font_shadow_color",Color.BLACK)
		exit_notice.add_theme_constant_override("shadow_offset_x",2)
		exit_notice.add_theme_constant_override("shadow_offset_y",2)
		layer.add_child(exit_notice)
		exit_notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		exit_notice.offset_top = -100
		exit_notice.offset_bottom = -55
	exit_notice.show()
	_hide_exit_notice(android_back_deadline)

func _hide_exit_notice(ticket: int) -> void:
	await get_tree().create_timer(2.0,true).timeout
	if ticket==android_back_deadline:
		android_back_deadline = 0
		if is_instance_valid(exit_notice): exit_notice.hide()

func _confirm_exit() -> void:
	run.checkpoint()
	if not SaveService.commit():
		exit_dialog.dialog_text = "Progress could not be saved. Please stay in the game and retry."
		exit_dialog.popup_centered(Vector2i(420,190))
		return
	get_tree().quit()

func _enter_tree() -> void:
	# Android Back has its own automatic-quit flag, separate from window-close.
	get_tree().quit_on_go_back = false

func _ready() -> void:
	var boot_started := Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -50
	get_tree().auto_accept_quit = false
	ui = AutomotiveUI.new()
	add_child(ui)
	ui.set_boot_status("Preparing highway…")
	await get_tree().process_frame
	await get_tree().process_frame
	# Present the studio ident before heavy scene construction starts.
	if not ui.startup.revealed:
		await ui.startup.brand_finished
	ui.set_boot_status("Loading sports car detail tiers…")
	ui.startup.progress = 0.1
	await RushVehicleCatalog.prewarm_resources(get_tree())
	world = Node3D.new()
	world.name = "DrivingWorld"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	highway = Highway.new()
	world.add_child(highway)
	while not highway.ready_for_drive:
		await get_tree().process_frame
	vehicle = ArcadeVehicle.new()
	vehicle.name = "VortexS"
	world.add_child(vehicle)
	vehicle.reset_vehicle()
	await get_tree().process_frame
	vehicle.input_source = DriveInput
	vehicle.impact.connect(GameAudio.collision)
	highway.target = vehicle
	cameras = DriveCameraRig.new()
	cameras.target = vehicle
	world.add_child(cameras)
	performance = PerformanceManager.new()
	performance.highway = highway
	add_child(performance)
	run = RushRunManager.new()
	run.car = vehicle
	world.add_child(run)
	traffic = RushTrafficSystem.new()
	traffic.car = vehicle
	traffic.run = run
	ui.set_boot_status("Preparing traffic…")
	ui.startup.progress = 0.3
	world.add_child(traffic)
	while not traffic.ready_for_drive:
		await get_tree().process_frame
	coins = RushCoinSystem.new()
	coins.car = vehicle
	coins.run = run
	coins.traffic = traffic
	ui.set_boot_status("Preparing road coins…")
	ui.startup.progress = 0.5
	world.add_child(coins)
	while not coins.ready_for_drive:
		await get_tree().process_frame
	traffic.coins = coins
	run.traffic = traffic
	run.coins = coins
	course_pickups = RushCoursePickups.new()
	world.add_child(course_pickups)
	course_pickups.build(coins,vehicle,traffic)
	run.course_pickups = course_pickups
	_build_turbo()
	finish_gate = RushFinishGate.new()
	finish_gate.car = vehicle
	finish_gate.run = run
	world.add_child(finish_gate)
	finish_gate.process_priority = 10
	highway.course_finish_gate = finish_gate
	highway.course_run = run
	vehicle.impact.connect(run.on_impact)
	vehicle.traffic_contact.connect(run.on_impact)
	vehicle.impact.connect(cameras.impact_feedback)
	_build_garage()
	await get_tree().process_frame
	_build_progression()
	await get_tree().process_frame
	director = RushDrivingDirector.new()
	world.add_child(director)
	director.build(self)
	await get_tree().process_frame
	garage_ui.bind_ads(director.ads)
	powerups = RushPowerupService.new()
	ui.add_child(powerups)
	powerups.build(self,director.ads)
	powerups.add_end_offers()
	var dock: RushRacePowerupDock = RushRacePowerupDock.new()
	ui.add_child(dock)
	dock.build(self)
	brake_effects = RushBrakeEffects.new()
	world.add_child(brake_effects)
	brake_effects.build(self)
	shop = RushStoreUI.new()
	ui.add_child(shop)
	shop.build(ui)
	await get_tree().process_frame
	shop.bind_ads(director.ads)
	ad_service = RushAdService.new()
	add_child(ad_service)
	ad_service.build(self)
	shop.closed.connect(go_home)
	ui.store_requested.connect(func() -> void:
		if state==State.HOME:
			state = State.PROGRESSION
			shop.open())
	ui.garage_requested.connect(open_garage)
	map_dressing = RushMapDressing.new()
	add_child(map_dressing)
	map_dressing.build(self)
	await get_tree().process_frame
	_build_map_selection()
	await get_tree().process_frame
	_build_race_modes()
	await get_tree().process_frame
	online_ui = RushOnlineUI.new()
	ui.add_child(online_ui)
	online_ui.build(ui)
	duel_race = RushDuelRace.new()
	duel_race.game = self
	duel_race.service = online_ui.duel
	add_child(duel_race)
	online_ui.duel.race_event.connect(duel_race.receive)
	ui.play_requested.connect(_play_requested)
	ui.pause_requested.connect(pause_drive)
	ui.resume_requested.connect(resume_drive)
	ui.restart_requested.connect(start_drive)
	ui.home_requested.connect(go_home)
	ui.camera_requested.connect(change_camera)
	ui.settings_requested.connect(open_settings)
	ui.settings_closed.connect(close_settings)
	ui.retry_reward_requested.connect(run.retry_reward)
	run.countdown_changed.connect(ui.show_countdown)
	run.started.connect(_run_started)
	run.finished.connect(_run_finished)
	run.results_ready.connect(_show_results)
	run.coin_awarded.connect(ui.coin_feedback)
	run.near_miss_awarded.connect(ui.near_miss_feedback)
	performance.fallback_changed.connect(_performance_fallback)
	SaveService.changed.connect(_settings_changed)
	_settings_changed()
	ui.set_boot_status("Warming graphics and audio…")
	ui.startup.progress = 0.7
	await director.prewarm()
	await highway.prewarm_sections()
	# Warm the selected car/current profile, rather than rendering all 36 car tiers.
	# Catalog resources remain cached for later garage selection.
	performance.apply_quality()
	_apply_selected()
	await get_tree().process_frame
	await get_tree().process_frame
	cameras.showcase = false
	cameras.reset_rig()
	for car: RushTrafficVehicle in traffic.pool:
		car.set_visual_quality(0)
	traffic.prewarm_models(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	for car: RushTrafficVehicle in traffic.pool:
		car.set_visual_quality(performance.visual_level)
	traffic.prewarm_models(1.0)
	coins.prewarm_visuals()
	GameAudio.prewarm_feedback()
	exhaust.warming = true
	streaks.visible = true
	streaks.intensity = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	traffic.prewarm_models(0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	GameAudio.finish_prewarm()
	exhaust.warming = false
	exhaust.reset()
	streaks.visible = false
	streaks.intensity = 0.0
	traffic.reset_pool(0)
	coins.reset_pool(0)
	var intro_remaining := maxf(0.0,2.9-(Time.get_ticks_msec()-boot_started)*0.001)
	if intro_remaining > 0.0:
		await get_tree().create_timer(intro_remaining).timeout
	ready_for_drive = true
	ui.set_boot_status("Ready")
	ui.startup.progress = 1.0
	await ui.startup.finish()
	var rewards: RushRewardPresentation = RushRewardPresentation.new()
	ui.add_child(rewards)
	if state == State.SPLASH:
		var account: RushAccountUI = RushAccountUI.new()
		ui.add_child(account)
		account.build(self)
		account.launch()

func _settings_changed() -> void:
	var quality := int(SaveService.settings["quality"])
	if quality != last_quality:
		last_quality = quality
		performance.apply_quality()
		if exhaust != null:
			exhaust.quality = quality
			streaks.quality = quality
		if director!=null:
			director.apply_quality()

func start_drive() -> void:
	if not ready_for_drive or director.ads.pending!=0 or course_preparing:
		return
	if run.state == RushRunManager.RunState.FINISHED and not run.reward_saved:
		_show_results(run.result,false)
		return
	_close_showroom()
	run.cancel()
	get_tree().paused = false
	_reset_turbo()
	powerups.begin_run()
	_apply_selected()
	traffic.active = false
	coins.active = false
	director.stop()
	_clear_race_course()
	vehicle.reset_vehicle()
	vehicle.driving = false
	DriveInput.set_enabled(false)
	if not run.prepare():
		go_home()
		ui.show_home_error(SaveService.last_error)
		return
	if run.race_mode=="five_racer":
		course_preparing = true
		if not ui.screens.has("course_loading"):
			var loading_page: Control = ui._page("course_loading")
			var art: RushRaceLoading = RushRaceLoading.new()
			art.name = "RaceLoadingArt"
			loading_page.add_child(art)
		var loading_art: RushRaceLoading = ui.screens["course_loading"].get_node("RaceLoadingArt") as RushRaceLoading
		loading_art.set_stage(0)
		ui.show_countdown("")
		ui.show_screen("course_loading")
		var course_run_id: int = run.run_id
		var course_ticket: int = course_generation
		highway.route_origin = run.origin_offset
		var progress_callback: Callable = loading_art.set_course_progress
		if not highway.course_road.preparation_progress.is_connected(progress_callback):
			highway.course_road.preparation_progress.connect(progress_callback)
		await highway.prepare_sampled_course(run.spec.distance_m)
		if highway.course_road.preparation_progress.is_connected(progress_callback):
			highway.course_road.preparation_progress.disconnect(progress_callback)
		course_preparing = false
		if highway.course==null or course_generation!=course_ticket or run.run_id!=course_run_id or run.state!=RushRunManager.RunState.PREPARING:
			return
		loading_art.set_stage(1)
		vehicle.course = highway.course
		run.course = highway.course
		traffic.course = highway.course
		director.opponents.course = highway.course
		course_pickups.set_course(highway.course)
		finish_gate.car = course_pickups.query_car
	traffic.difficulty = run.difficulty
	director.opponents.difficulty = run.difficulty
	director.reset_run()
	_sanitize_map_settings()
	map_dressing.apply()
	powerups.apply_run()
	traffic.reset_pool(run.run_id)
	coins.reset_pool(run.run_id)
	highway.route_origin = run.origin_offset
	highway.last_cell = 999999
	highway.update_chunks()
	cameras.showcase = false
	cameras.reset_rig()
	if ui.screen == "course_loading":
		(ui.screens["course_loading"].get_node("RaceLoadingArt") as RushRaceLoading).set_stage(2)
	state = State.DRIVING
	GameAudio.set_driving(true)
	GameAudio.set_suspended(false)
	performance.driving = false
	finish_gate.enabled = true
	ui.show_screen("drive")
	ui.update_hud(vehicle,cameras.mode)
	ui.update_run_hud(run)
	ui.show_countdown("READY")
	DriveInput.arm_countdown()
	var prepared_id := run.run_id
	await get_tree().process_frame
	if state == State.DRIVING and run.run_id==prepared_id:
		run.begin_countdown()

func _run_started() -> void:
	director.start_run()
	vehicle.driving = true
	turbo.start_run()
	DriveInput.set_enabled(true)
	traffic.active = true
	coins.active = true
	performance.driving = true

func _run_finished() -> void:
	director.finish_run()
	state = State.FINISHING
	turbo.stop()
	vehicle.finish_coasting = true
	cameras.begin_finish()
	for control: Control in ui.controls.values():
		control.visible = false
	DriveInput.set_enabled(false)
	performance.driving = false
	# Coast briefly through the finish, preserving motion before the results overlay.
	coins.active = false

func _show_results(summary: Dictionary, saved: bool) -> void:
	director.stop()
	state = State.RESULTS
	turbo.stop()
	streaks.visible = false
	DriveInput.set_enabled(false)
	vehicle.driving = false
	traffic.active = false
	coins.active = false
	GameAudio.set_driving(false)
	var presentation_summary := summary.duplicate(true)
	presentation_summary["highest_speed"] = run.highest_speed
	ui.show_results(presentation_summary,saved)
	powerups.refresh()
	if saved:
		progression_ui.present_notices()
	if ad_service!=null: ad_service.on_results(saved)

func pause_drive() -> void:
	if duel_race!=null and duel_race.active:
		online_ui.duel._lost()
		return
	if state != State.DRIVING:
		return
	run.checkpoint()
	state = State.PAUSED
	DriveInput.set_enabled(false)
	GameAudio.set_suspended(true)
	get_tree().paused = true
	ui.show_screen("pause")
	SaveService.commit()

func resume_drive() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	state = State.DRIVING
	if run.state == RushRunManager.RunState.RUNNING:
		DriveInput.set_enabled(true)
	else:
		DriveInput.arm_countdown()
		if run.state == RushRunManager.RunState.PREPARING:
			run.begin_countdown()
	GameAudio.set_suspended(false)
	ui.show_screen("drive")

func go_home() -> void:
	if director!=null and director.ads.pending!=0: return
	if state==State.PAUSED:
		request_pause_exit()
		return
	if state==State.CRASHED:
		give_up_drive()
		return
	if run.state == RushRunManager.RunState.FINISHED and not run.reward_saved:
		_show_results(run.result,false)
		return
	director.stop()
	run.cancel()
	_clear_race_course()
	powerups.discard()
	_close_showroom()
	_reset_turbo()
	_apply_selected()
	traffic.reset_pool(0)
	coins.reset_pool(0)
	finish_gate.enabled = false
	get_tree().paused = false
	state = State.HOME
	DriveInput.set_enabled(false)
	vehicle.driving = false
	vehicle.reset_vehicle()
	highway.route_origin = run.origin_offset
	highway.last_cell = 999999
	highway.update_chunks()
	cameras.showcase = true
	cameras.reset_rig()
	GameAudio.set_driving(false)
	GameAudio.set_suspended(false)
	performance.driving = false
	vehicle.visible = false
	highway.visible = false
	showroom.visible = true
	showroom.active = true
	showroom.camera.h_offset = 0.0
	showroom.show_vehicle(SaveService.collection.selected,int(SaveService.collection.paints[SaveService.collection.selected]))
	highway.environment.environment = showroom.environment
	showroom.camera.make_current()
	ui.show_screen("home")
	progression_ui.refresh_home()
	if not bool(SaveService.onboarding.completed):
		SaveService.confirm_starter()
	progression_ui.present_notices()

func open_settings() -> void:
	if state != State.HOME and state != State.PAUSED:
		return
	settings_origin = state
	state = State.SETTINGS
	DriveInput.clear()
	ui.show_screen("settings")

func close_settings() -> void:
	if state != State.SETTINGS:
		return
	SaveService.commit()
	state = settings_origin
	ui.show_screen("pause" if state == State.PAUSED else "home")

func change_camera() -> void:
	if state == State.DRIVING:
		cameras.cycle()
		ui.show_camera_name(cameras.mode)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	if is_instance_valid(pause_exit_dialog) and pause_exit_dialog.visible:
		if event.is_action_pressed("pause"): pause_exit_dialog.cancel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		_back()
	elif event.is_action_pressed("camera"):
		change_camera()
	elif event.is_action_pressed("restart") and state in [State.DRIVING,State.PAUSED]:
		start_drive()

func _back() -> void:
	if is_instance_valid(pause_exit_dialog) and pause_exit_dialog.visible:
		pause_exit_dialog.cancel()
		return
	if duel_race!=null and duel_race.active:
		online_ui.duel.leave()
		duel_race.stop()
		return
	if ui.screen in ["multiplayer","tournaments"]:
		online_ui._back()
		return
	if ui.screen=="powerups":
		if powerups.prepared:
			powerups.back()
		else:
			powerups.close()
		return
	if ui.screen=="turbo_store":
		close_turbo_store()
		return
	match state:
		State.DRIVING: pause_drive()
		State.PAUSED: resume_drive()
		State.SETTINGS: close_settings()
		State.RESULTS: go_home()
		State.CRASHED: go_home()
		State.GARAGE: go_home()
		State.PROGRESSION: go_home()

func _notification(what: int) -> void:
	if not ready_for_drive:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		android_back_deadline = 0
		if is_instance_valid(exit_notice): exit_notice.hide()
		if duel_race!=null and duel_race.active:
			online_ui.duel._lost()
		pause_drive()
		SaveService.commit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_android_back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		run.checkpoint()
		SaveService.commit()
		get_tree().quit()

func _physics_process(delta: float) -> void:
	if state not in [State.DRIVING,State.FINISHING]:
		return
	if state == State.DRIVING:
		run.advance_countdown(delta)
	# Rebase before precision loss; recycle existing segments without allocations.
	if absf(vehicle.position.z) > 2400.0:
		# A complete pool period preserves each segment's signs and hill variation.
		var period := Highway.LENGTH*Highway.COUNT
		var shift := Vector3(0,0,roundf(vehicle.position.z/period)*period)
		if highway.course!=null:
			highway.course.origin_z -= shift.z
			highway.course_road.rebase()
		run.rebase(shift)
		director.opponents.rebase(shift)
		traffic.rebase(shift)
		coins.rebase(shift)
		brake_effects.rebase(shift)
		vehicle.position -= shift
		vehicle.rebase_render_pose(shift)
		cameras.camera.global_position -= shift
		highway.route_origin = run.origin_offset
		highway.last_cell = 999999
		highway.update_chunks()

func _process(delta: float) -> void:
	if state in [State.DRIVING,State.FINISHING]:
		GameAudio.update_vehicle(delta,vehicle.speed_kmh(),DriveInput.sample().y,vehicle.skid_amount,turbo.intensity,vehicle.acceleration_now,turbo.spec.top_speed_kmh)
		streaks.visible = true
		var streak_target := clampf((vehicle.speed_kmh()-135.0)/160.0,0.0,0.55)+turbo.intensity*0.4
		if state==State.FINISHING:
			streak_target *= clampf(run.finish_left/run.spec.finish_seconds,0.0,1.0)
		streaks.intensity = lerpf(streaks.intensity,streak_target,1.0-exp(-8.0*delta))
		hud_clock += delta
		if hud_clock >= 0.05:
			hud_clock = 0.0
			ui.update_hud(vehicle,cameras.mode)
			ui.update_run_hud(run)

func diagnostics() -> Dictionary:
	# For the remote inspector/tests only; never attached to the player HUD.
	return {"run": run.diagnostics(), "traffic": traffic.diagnostics(), "coins": coins.diagnostics()}

func _build_turbo() -> void:
	turbo = RushTurboController.new()
	turbo.spec = vehicle.spec.turbo
	turbo.car = vehicle
	turbo.run = run
	world.add_child(turbo)
	vehicle.turbo = turbo
	cameras.turbo = turbo
	turbo.reset()
	turbo_ui = RushTurboPresentation.new()
	ui.add_child(turbo_ui)
	turbo_ui.build(ui,turbo)
	exhaust = RushExhaustEffects.new()
	exhaust.car = vehicle
	exhaust.turbo = turbo
	world.add_child(exhaust)
	var effects_layer := CanvasLayer.new()
	effects_layer.layer = 0
	world.add_child(effects_layer)
	streaks = RushSpeedStreaks.new()
	effects_layer.add_child(streaks)
	streaks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	streaks.visible = false
	turbo.became_ready.connect(_turbo_ready)
	turbo.activated.connect(_turbo_started)
	turbo.ended.connect(_turbo_ended)
	turbo.empty_requested.connect(func() -> void:
		director.callout.text = "TURBO x0"
		director.callout_left = .9)
	vehicle.impact.connect(_turbo_collision)

func _reset_turbo() -> void:
	GameAudio.reset_turbo()
	for control: Control in ui.controls.values():
		control.visible = true
	turbo.reset()
	turbo_ui.reset()
	exhaust.reset()
	streaks.intensity = 0.0
	streaks.impact = 0.0
	streaks.visible = false

func _turbo_ready() -> void:
	GameAudio.event("turbo_ready")

func _turbo_started() -> void:
	cameras.turbo_kick()
	exhaust.ignition()
	turbo_ui.kick()
	GameAudio.event("turbo_ignition")
	GameAudio.event("turbo_flare")
	RushHaptics.pulse(45)

func _turbo_ended() -> void:
	GameAudio.event("turbo_end")

func _turbo_collision(strength: float) -> void:
	turbo.on_collision(strength)
	streaks.impact = maxf(streaks.impact,strength)
	exhaust.flare = 0.0

func _build_garage() -> void:
	road_environment = highway.environment.environment
	showroom = RushShowroom.new()
	world.add_child(showroom)
	garage_ui = RushGarageUI.new()
	ui.add_child(garage_ui)
	garage_ui.build(ui)
	showroom.interaction = garage_ui.interaction
	garage_ui.closed.connect(go_home)
	garage_ui.play_requested.connect(func() -> void:
		go_home()
		_play_requested())
	garage_ui.vehicle_previewed.connect(showroom.show_vehicle)

func _apply_selected() -> void:
	var id: String = trial_vehicle_id if not trial_vehicle_id.is_empty() else SaveService.collection["selected"]
	var spec := RushVehicleCatalog.effective(id,SaveService.collection["upgrades"][id])
	vehicle.apply_configuration(spec,RushVehicleCatalog.paint_color(int(SaveService.collection["paints"][id])))
	turbo.spec = spec.turbo
	turbo.reset()
	ui.car_info.text = "%s\n%.0f KM/H   /   SELECTED"%[SaveService.car_name(id).to_upper(),spec.top_speed_kmh]

func open_garage() -> void:
	if state != State.HOME:
		return
	state = State.GARAGE
	showroom.camera.h_offset = 0.0
	DriveInput.set_enabled(false)
	vehicle.visible = false
	highway.visible = false
	showroom.visible = true
	showroom.active = true
	showroom.set_garage_view()
	highway.environment.environment = showroom.environment
	showroom.camera.make_current()
	garage_ui.open()
	ui.show_screen("garage")
	GameAudio.set_garage(true)

func _close_showroom() -> void:
	if showroom == null:
		return
	showroom.close()
	showroom.camera.h_offset = 0.0
	showroom.interaction = garage_ui.interaction
	vehicle.visible = true
	highway.visible = true
	highway.environment.environment = road_environment
	cameras.camera.make_current()
	GameAudio.set_garage(false)

func _performance_fallback(_fallback: bool) -> void:
	if director!=null:
		director.apply_quality()
	var level := performance.effects_level
	exhaust.quality = level
	streaks.quality = level
	cameras.set_quality(performance.visual_level)
	vehicle.visual.set_quality(performance.visual_level)
	if showroom!=null:
		showroom.set_quality(performance.visual_level)
	var traffic_quality: int = 0 if performance.degrade_stage>=5 else performance.visual_level
	if traffic!=null:
		for car: RushTrafficVehicle in traffic.pool:
			car.set_visual_quality(traffic_quality)
	if director!=null and director.opponents!=null:
		for racer: RushTrafficVehicle in director.opponents.racers:
			racer.set_visual_quality(traffic_quality)

func _build_progression() -> void:
	RewardService.bind_run(run)
	turbo.activated.connect(run.record_turbo)
	# Subscribe to the debounced impact, not the second traffic contact signal.
	vehicle.impact.connect(run.record_collision)
	progression_ui = RushProgressionUI.new()
	ui.add_child(progression_ui)
	progression_ui.build(ui)
	ui.progression_requested.connect(open_progression)

func open_progression(page: String) -> void:
	if state not in [State.HOME,State.RESULTS,State.PROGRESSION] or page not in ["missions","profile","daily"]:
		return
	if run.state==RushRunManager.RunState.FINISHED and not run.reward_saved:
		return
	state = State.PROGRESSION
	DriveInput.set_enabled(false)
	if page=="profile":
		vehicle.visible = false
		highway.visible = false
		showroom.visible = true
		showroom.active = true
		showroom.interaction = progression_ui.profile_interaction
		showroom.set_profile_view()
		showroom.show_vehicle(SaveService.collection.selected,int(SaveService.collection.paints[SaveService.collection.selected]))
		highway.environment.environment = showroom.environment
		showroom.camera.make_current()
		GameAudio.set_garage(true)
	progression_ui.open(page)

var turbo_store_from_race: bool = false
func open_turbo_store() -> void:
	if state not in [State.HOME,State.DRIVING]:
		return
	turbo_store_from_race = state==State.DRIVING
	if turbo_store_from_race:
		pause_drive()
	state = State.PROGRESSION
	director.store.refresh()
	ui.show_screen("turbo_store")

func vehicle_destroyed() -> void:
	if state!=State.DRIVING:
		return
	state = State.CRASHED
	run.checkpoint()
	run.suspended = true
	turbo.stop()
	DriveInput.set_enabled(false)
	vehicle.driving = false
	vehicle.velocity = Vector3.ZERO
	vehicle.signed_speed = 0
	traffic.active = false
	coins.active = false
	finish_gate.enabled = false
	performance.driving = false
	streaks.visible = false
	GameAudio.set_driving(false)
	for control: Control in ui.controls.values():
		control.visible = false
	director.crash()
	powerups.refresh()

func close_turbo_store() -> void:
	if turbo_store_from_race:
		state = State.PAUSED
		resume_drive()
	else:
		go_home()

## Frosted-glass backing for the Choose Your Race panel. Set to false to fall back
## to the plain translucent panel (no screen-texture blur) if it costs too much on a device.
const RACE_GLASS_BLUR: bool = true
const RACE_GLASS_SHADER: String = """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 rect_size = vec2(600.0, 400.0);
uniform float corner_radius = 20.0;
uniform float blur_lod : hint_range(0.0, 6.0) = 2.6;
uniform float blur_spread = 2.0;
uniform vec4 glass_tint : source_color = vec4(0.03, 0.08, 0.13, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	vec2 spread = SCREEN_PIXEL_SIZE * blur_spread * exp2(blur_lod);
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb * 0.4;
	c += textureLod(screen_tex, SCREEN_UV + vec2(spread.x, 0.0), blur_lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV - vec2(spread.x, 0.0), blur_lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV + vec2(0.0, spread.y), blur_lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV - vec2(0.0, spread.y), blur_lod).rgb * 0.15;
	c = mix(c, glass_tint.rgb, tint_amount);
	c += vec3(0.10, 0.20, 0.28) * (1.0 - UV.y) * 0.16;
	vec2 p = (UV - vec2(0.5)) * rect_size;
	vec2 d = abs(p) - (rect_size * 0.5 - vec2(corner_radius));
	float dist = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - corner_radius;
	COLOR = vec4(c, 1.0 - smoothstep(-1.0, 1.0, dist));
}
"""

func _build_race_modes() -> void:
	var page := ui._page("race_modes",true)
	page.visible = false
	# Remove the default dark backdrop so only the glass panel is visible.
	var backdrop: Node = page.get_child(0)
	if backdrop is ColorRect:
		(backdrop as ColorRect).color = Color(0.0, 0.0, 0.0, 0.0)
	var screen: Vector2 = Vector2(1280.0, 720.0)
	if is_inside_tree():
		screen = get_viewport().get_visible_rect().size
	var compact: bool = screen.y < 600.0 or screen.x < 900.0
	# Preferred 440-740 px on wide screens, never wider than ~92% of the screen.
	var panel_width: float = minf(clampf(screen.x * 0.6, 440.0, 740.0), screen.x * 0.92)
	var gap: int = 10 if compact else 14
	var pad_x: int = 18 if compact else 30
	var pad_y: int = 14 if compact else 22
	var inner_width: float = panel_width - float(pad_x * 2)
	var title_size: int = 24 if compact else 32
	var note_size: int = 13 if compact else 15
	var button_font: int = 17 if compact else 20
	var tab_height: float = 54.0 if compact else 66.0
	var mode_height: float = 46.0 if compact else 56.0
	var ice: Color = Color(0.92, 0.97, 1.0)
	var steel: Color = Color(0.75, 0.85, 0.95)

	var column := ui._center_column(page, int(panel_width))
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# With glass on, the panel fill is light so the blurred backing shows through,
	# and the outer glow moves to its own layer underneath the glass.
	var panel_fill: Color = Color(0.035, 0.075, 0.12, 0.26) if RACE_GLASS_BLUR else Color(0.035, 0.075, 0.12, 0.84)
	var panel_glow: Color = Color(0.0, 0.0, 0.0, 0.0) if RACE_GLASS_BLUR else Color(0.15, 0.65, 1.0, 0.35)
	var panel_style: StyleBoxFlat = _race_ui_style(panel_fill, Color(0.28, 0.78, 1.0, 0.95), 2, 20, panel_glow, 18)
	panel_style.content_margin_left = pad_x
	panel_style.content_margin_right = pad_x
	panel_style.content_margin_top = pad_y
	panel_style.content_margin_bottom = pad_y
	panel.add_theme_stylebox_override("panel", panel_style)
	if RACE_GLASS_BLUR:
		var holder: MarginContainer = MarginContainer.new()
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(holder)
		var glow_layer: Panel = Panel.new()
		glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow_layer.add_theme_stylebox_override("panel", _race_ui_style(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, 20, Color(0.15, 0.65, 1.0, 0.35), 18))
		holder.add_child(glow_layer)
		_race_ui_glass(holder)
		holder.add_child(panel)
	else:
		column.add_child(panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", gap)
	panel.add_child(body)

	# Title (font size shrinks if the panel is very narrow)
	var title: Label = _race_ui_label(body, "CHOOSE YOUR RACE", title_size, ui.ACCENT)
	var ui_font: Font = title.get_theme_font("font")
	title.add_theme_font_size_override("font_size", _race_ui_fit_font(ui_font, ["CHOOSE YOUR RACE"], title_size, 14, inner_width))
	var underline: ColorRect = ColorRect.new()
	underline.color = Color(0.28, 0.78, 1.0, 0.45)
	underline.custom_minimum_size = Vector2(0.0, 2.0)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(underline)

	# Difficulty tabs (same callbacks / ButtonGroup behaviour as before)
	var tab_width: float = (inner_width - 16.0) / 3.0
	var tab_font: int = _race_ui_fit_font(ui_font, ["EASY", "NORMAL", "HARD"], button_font, 12, tab_width - 20.0)
	var difficulty_row: HBoxContainer = HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 8)
	body.add_child(difficulty_row)
	var difficulty_group: ButtonGroup = ButtonGroup.new()
	for index: int in 3:
		var option: Button = ui._button(difficulty_row,["EASY","NORMAL","HARD"][index],func() -> void: run.difficulty = index)
		option.toggle_mode = true
		option.button_group = difficulty_group
		option.button_pressed = index==run.difficulty
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.custom_minimum_size = Vector2(0.0, tab_height)
		var tab_off: StyleBoxFlat = _race_ui_style(Color(0.13, 0.16, 0.21, 0.95), Color(0.35, 0.42, 0.50, 0.9), 2, 12)
		var tab_hover: StyleBoxFlat = _race_ui_style(Color(0.17, 0.21, 0.27, 0.95), Color(0.50, 0.62, 0.74, 1.0), 2, 12)
		var tab_on: StyleBoxFlat = _race_ui_style(Color(0.04, 0.28, 0.42, 0.97), Color(0.35, 0.92, 1.0, 1.0), 2, 12, Color(0.2, 0.8, 1.0, 0.45), 10)
		for tab_style: StyleBoxFlat in [tab_off, tab_hover, tab_on]:
			tab_style.content_margin_top = 6
			tab_style.content_margin_bottom = 20
		_race_ui_apply_button(option, tab_off, tab_hover, tab_on, ice, tab_font, 12)
		_race_ui_stars(option, index + 1)
	var note: Label = _race_ui_label(body, "Difficulty applies to solo and 5-racer races only.", note_size, ui.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Race card: ONE Button is the outer tap target; the visual card is its own
	# stylebox and its content is an overlay that ignores the mouse.
	var card_pad_x: int = 14 if compact else 18
	var card_pad_y: int = 10 if compact else 12
	var card_gap: int = 8 if compact else 10
	var stat_gap: int = 6
	var card_inner: float = inner_width - float(card_pad_x * 2)
	var cell_width: float = (card_inner - 2.0) / 3.0
	var card_title_size: int = _race_ui_fit_font(ui_font, ["5-RACER HIGHWAY RACE"], 20 if compact else 24, 12, card_inner)
	var stat_size: int = _race_ui_fit_font(ui_font, ["YOU + 4 RIVALS", "8 KM", "POSITION REWARDS"], 12 if compact else 14, 9, cell_width - 8.0)
	var icon_height: float = 30.0 if compact else 34.0
	var stats_height: float = icon_height + float(stat_gap) + ui_font.get_height(stat_size)
	var card_height: float = float(card_pad_y * 2) + ui_font.get_height(card_title_size) + float(card_gap) + stats_height + 4.0
	var race_button: Button = ui._button(body,"",_select_race.bind("five_racer"),true)
	race_button.text = ""
	race_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_button.custom_minimum_size = Vector2(0.0, card_height)
	var card_normal: StyleBoxFlat = _race_ui_style(Color(0.10, 0.20, 0.30, 0.78), Color(0.55, 0.85, 1.0, 0.85), 2, 14, Color(0.2, 0.7, 1.0, 0.22), 8)
	var card_hover: StyleBoxFlat = _race_ui_style(Color(0.14, 0.28, 0.40, 0.85), Color(0.75, 0.95, 1.0, 1.0), 2, 14, Color(0.2, 0.75, 1.0, 0.35), 10)
	var card_down: StyleBoxFlat = _race_ui_style(Color(0.08, 0.17, 0.26, 0.90), Color(0.45, 0.90, 1.0, 1.0), 2, 14)
	_race_ui_apply_button(race_button, card_normal, card_hover, card_down, ice, card_title_size, 14)
	var card_content: VBoxContainer = VBoxContainer.new()
	card_content.alignment = BoxContainer.ALIGNMENT_CENTER
	card_content.add_theme_constant_override("separation", card_gap)
	card_content.anchor_left = 0.0
	card_content.anchor_top = 0.0
	card_content.anchor_right = 1.0
	card_content.anchor_bottom = 1.0
	card_content.offset_left = card_pad_x
	card_content.offset_right = -card_pad_x
	card_content.offset_top = card_pad_y
	card_content.offset_bottom = -card_pad_y
	race_button.add_child(card_content)
	_race_ui_label(card_content, "5-RACER HIGHWAY RACE", card_title_size, ice, HORIZONTAL_ALIGNMENT_CENTER)
	var stats: HBoxContainer = HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 0)
	stats.custom_minimum_size = Vector2(0.0, stats_height)
	card_content.add_child(stats)
	_race_ui_stat(stats, "rivals", "YOU + 4 RIVALS", Vector2(minf(100.0, cell_width - 10.0), icon_height), stat_size, stat_gap, steel)
	_race_ui_divider(stats, stats_height * 0.8)
	_race_ui_stat(stats, "road", "8 KM", Vector2(34.0, icon_height), stat_size, stat_gap, steel)
	_race_ui_divider(stats, stats_height * 0.8)
	_race_ui_stat(stats, "trophy", "POSITION REWARDS", Vector2(32.0, icon_height), stat_size, stat_gap, steel)
	_race_ui_ignore_mouse(race_button)

	# Mode buttons (same callbacks as before); font is fitted so labels never clip.
	var mode_gap: float = 12.0
	var mode_width: float = (inner_width - mode_gap) / 2.0
	var mode_pad: int = 38 if compact else 44
	var mode_size: int = _race_ui_fit_font(ui_font, ["HIGHWAY RUSH", "MULTIPLAYER"], button_font, 11, mode_width - float(mode_pad) - 16.0)
	var mode_row: HBoxContainer = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", int(mode_gap))
	body.add_child(mode_row)
	var rush_button: Button = ui._button(mode_row,"HIGHWAY RUSH",_select_race.bind("highway_rush"))
	_race_ui_metal_button(rush_button, "gauge", mode_height, mode_size, ice, mode_pad)
	var multi_button: Button = ui._button(mode_row,"MULTIPLAYER",func() -> void: online_ui.open("multiplayer"))
	_race_ui_metal_button(multi_button, "network", mode_height, mode_size, ice, mode_pad)
	var mode_note: Label = _race_ui_label(body, "HIGHWAY RUSH: SOLO / TRAFFIC / SCORE + COINS", note_size - 1, ui.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Back
	var back_button: Button = ui._button(body,"BACK",go_home)
	_race_ui_metal_button(back_button, "arrow", mode_height - 6.0, button_font, ice, mode_pad)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.custom_minimum_size = Vector2(minf(190.0, inner_width), mode_height - 6.0)


func _race_ui_glass(parent: Control) -> ColorRect:
	var shader: Shader = Shader.new()
	shader.code = RACE_GLASS_SHADER
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	var glass: ColorRect = ColorRect.new()
	glass.color = Color.WHITE
	glass.material = material
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(glass)
	glass.resized.connect(func() -> void: material.set_shader_parameter("rect_size", glass.size))
	return glass


func _race_ui_fit_font(font: Font, texts: Array, start_size: int, min_size: int, max_width: float) -> int:
	var fitted: int = start_size
	while fitted > min_size:
		var widest: float = 0.0
		for text in texts:
			widest = maxf(widest, font.get_string_size(String(text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fitted).x)
		if widest <= max_width:
			break
		fitted -= 1
	return fitted


func _race_ui_ignore_mouse(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_race_ui_ignore_mouse(child)


func _race_ui_style(fill: Color, border: Color, border_width: int, radius: int, glow: Color = Color(0, 0, 0, 0), glow_size: int = 0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	style.shadow_color = glow
	style.shadow_size = glow_size
	return style


func _race_ui_apply_button(button: Button, normal: StyleBoxFlat, hover: StyleBoxFlat, pressed: StyleBoxFlat, font_color: Color, font_size: int, radius: int) -> void:
	var focus: StyleBoxFlat = _race_ui_style(Color(0, 0, 0, 0), Color(0.65, 0.95, 1.0, 0.95), 2, radius)
	focus.draw_center = false
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_stylebox_override("focus", focus)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(color_name, font_color)
	button.add_theme_font_size_override("font_size", font_size)


func _race_ui_metal_button(button: Button, icon_kind: String, height: float, font_size: int, font_color: Color, left_pad: int) -> void:
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, height)
	var steel_off: StyleBoxFlat = _race_ui_style(Color(0.22, 0.26, 0.31, 0.97), Color(0.66, 0.73, 0.80, 0.95), 2, 12, Color(0, 0, 0, 0.35), 4)
	var steel_hover: StyleBoxFlat = _race_ui_style(Color(0.29, 0.34, 0.40, 0.97), Color(0.80, 0.92, 1.0, 1.0), 2, 12, Color(0.2, 0.7, 1.0, 0.30), 8)
	var steel_down: StyleBoxFlat = _race_ui_style(Color(0.15, 0.18, 0.22, 0.97), Color(0.45, 0.85, 1.0, 1.0), 2, 12)
	for steel_style: StyleBoxFlat in [steel_off, steel_hover, steel_down]:
		steel_style.content_margin_left = left_pad
		steel_style.content_margin_right = 14
	_race_ui_apply_button(button, steel_off, steel_hover, steel_down, font_color, font_size, 12)
	var sheen: ColorRect = ColorRect.new()
	sheen.color = Color(1, 1, 1, 0.12)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sheen.offset_left = 12
	sheen.offset_right = -12
	sheen.offset_top = 4
	sheen.offset_bottom = 5
	button.add_child(sheen)
	var icon: Control = _race_ui_icon(button, icon_kind, Color(0.80, 0.92, 1.0), Vector2(24.0, 24.0))
	icon.anchor_left = 0.0
	icon.anchor_right = 0.0
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = 10
	icon.offset_right = 34
	icon.offset_top = -12
	icon.offset_bottom = 12


func _race_ui_label(parent: Control, text: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _race_ui_divider(parent: HBoxContainer, height: float) -> void:
	var line: ColorRect = ColorRect.new()
	line.color = Color(0.5, 0.75, 1.0, 0.45)
	line.custom_minimum_size = Vector2(1.0, height)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _race_ui_stat(parent: HBoxContainer, kind: String, caption: String, icon_size: Vector2, font_size: int, spacing: int, color: Color) -> void:
	var cell: VBoxContainer = VBoxContainer.new()
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_theme_constant_override("separation", spacing)
	parent.add_child(cell)
	var icon: Control = _race_ui_icon(cell, kind, Color(0.62, 0.86, 1.0), icon_size)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var text: Label = _race_ui_label(cell, caption, font_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _race_ui_stars(button: Button, count: int) -> void:
	var star_width: float = 14.0
	var star_gap: float = 4.0
	var total: float = star_width * float(count) + star_gap * float(count - 1)
	var stars: Control = Control.new()
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.anchor_left = 0.5
	stars.anchor_right = 0.5
	stars.anchor_top = 1.0
	stars.anchor_bottom = 1.0
	stars.offset_left = -total * 0.5
	stars.offset_right = total * 0.5
	stars.offset_top = -19
	stars.offset_bottom = -6
	button.add_child(stars)
	stars.draw.connect(func() -> void: _race_ui_draw_stars(stars, count, button.button_pressed))
	button.toggled.connect(func(_on: bool) -> void: stars.queue_redraw())


func _race_ui_draw_stars(canvas: Control, count: int, selected: bool) -> void:
	var tone: Color = Color(1.0, 0.80, 0.30) if selected else Color(0.60, 0.68, 0.78, 0.75)
	var radius: float = 6.5
	for i: int in count:
		var center: Vector2 = Vector2(7.0 + 18.0 * float(i), canvas.size.y * 0.5)
		var points: PackedVector2Array = PackedVector2Array()
		for p: int in 10:
			var r: float = radius if p % 2 == 0 else radius * 0.45
			var angle: float = -PI * 0.5 + float(p) * PI / 5.0
			points.append(center + Vector2(cos(angle), sin(angle)) * r)
		canvas.draw_colored_polygon(points, tone)


func _race_ui_icon(parent: Control, kind: String, color: Color, icon_size: Vector2) -> Control:
	var icon: Control = Control.new()
	icon.custom_minimum_size = icon_size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	icon.draw.connect(func() -> void: _race_ui_draw_icon(icon, kind, color))
	return icon


func _race_ui_draw_icon(canvas: Control, kind: String, color: Color) -> void:
	var w: float = canvas.size.x
	var h: float = canvas.size.y
	match kind:
		"rivals":
			var slot: float = w / 5.0
			for i: int in 5:
				var tone: Color = color if i == 0 else Color(color.r, color.g, color.b, color.a * 0.6)
				var cx: float = slot * (float(i) + 0.5)
				canvas.draw_circle(Vector2(cx, h * 0.26), slot * 0.2, tone)
				canvas.draw_colored_polygon(PackedVector2Array([
					Vector2(cx - slot * 0.38, h), Vector2(cx - slot * 0.26, h * 0.5),
					Vector2(cx + slot * 0.26, h * 0.5), Vector2(cx + slot * 0.38, h)]), tone)
		"road":
			canvas.draw_line(Vector2(w * 0.32, 0.0), Vector2(w * 0.04, h), color, 2.5, true)
			canvas.draw_line(Vector2(w * 0.68, 0.0), Vector2(w * 0.96, h), color, 2.5, true)
			for i: int in 4:
				var y0: float = h * (0.08 + 0.24 * float(i))
				canvas.draw_line(Vector2(w * 0.5, y0), Vector2(w * 0.5, y0 + h * 0.13), color, 2.5)
		"trophy":
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(w * 0.25, h * 0.05), Vector2(w * 0.75, h * 0.05), Vector2(w * 0.68, h * 0.45),
				Vector2(w * 0.58, h * 0.62), Vector2(w * 0.42, h * 0.62), Vector2(w * 0.32, h * 0.45)]), color)
			canvas.draw_rect(Rect2(w * 0.45, h * 0.62, w * 0.10, h * 0.18), color)
			canvas.draw_rect(Rect2(w * 0.30, h * 0.82, w * 0.40, h * 0.12), color)
			canvas.draw_arc(Vector2(w * 0.22, h * 0.28), w * 0.12, PI * 0.5, PI * 1.5, 12, color, 2.0, true)
			canvas.draw_arc(Vector2(w * 0.78, h * 0.28), w * 0.12, -PI * 0.5, PI * 0.5, 12, color, 2.0, true)
		"gauge":
			var center: Vector2 = Vector2(w * 0.5, h * 0.58)
			var r: float = minf(w, h) * 0.44
			canvas.draw_arc(center, r, PI * 0.8, PI * 2.2, 28, color, 2.5, true)
			canvas.draw_line(center, center + Vector2(cos(-0.75), sin(-0.75)) * r * 0.8, color, 2.5, true)
			canvas.draw_circle(center, 2.5, color)
		"network":
			var hub: Vector2 = Vector2(w * 0.5, h * 0.5)
			var nodes: Array[Vector2] = [Vector2(w * 0.15, h * 0.2), Vector2(w * 0.85, h * 0.2), Vector2(w * 0.5, h * 0.92)]
			for node: Vector2 in nodes:
				canvas.draw_line(hub, node, color, 2.0, true)
				canvas.draw_circle(node, 3.5, color)
			canvas.draw_circle(hub, 5.0, color)
		"arrow":
			canvas.draw_line(Vector2(w, h * 0.5), Vector2(0.0, h * 0.5), color, 2.5, true)
			canvas.draw_polyline(PackedVector2Array([Vector2(w * 0.42, h * 0.12), Vector2(0.0, h * 0.5), Vector2(w * 0.42, h * 0.88)]), color, 2.5, true)

func _play_requested() -> void:
	if state==State.RESULTS:
		start_drive()
	elif state==State.HOME:
		state = State.PROGRESSION
		ui.show_screen("race_modes")

func _select_race(mode: String) -> void:
	if state!=State.PROGRESSION or ui.screen!="race_modes":
		return
	run.race_mode = mode
	ui.show_screen("map_selection")

func request_pause_exit() -> void:
	if state!=State.PAUSED: return
	if pause_exit_dialog==null:
		pause_exit_dialog = RushRaceExitDialog.new()
		add_child(pause_exit_dialog)
		pause_exit_dialog.confirmed.connect(func() -> void:
			if state!=State.PAUSED or pause_exit_scope!=SaveService.scope_generation: return
			run.cancel()
			state = State.HOME
			go_home())
		pause_exit_dialog.canceled.connect(func() -> void:
			if pause_exit_scope==SaveService.scope_generation: resume_drive())
	pause_exit_scope = SaveService.scope_generation
	android_back_deadline = 0
	if is_instance_valid(exit_notice): exit_notice.hide()
	if ui.screens.has("pause"): ui.screens["pause"].hide()
	pause_exit_dialog.popup_centered(Vector2i(620,240))

func give_up_drive() -> void:
	if state!=State.CRASHED or director.ads.pending!=0: return
	if ad_service!=null and ad_service.fullscreen: return
	run.give_up() # Existing atomic race receipt settles base road coins once.

func revive_drive(fraction: float) -> void:
	if state!=State.CRASHED or not run.suspended:
		return
	# Choose a clear lane at the crash or at most 18 m behind; never advance for free.
	var route_at: Vector3 = highway.course.to_route(vehicle.position) if highway.course!=null else vehicle.position
	var best_x: float = route_at.x
	var best_z: float = route_at.z
	var best_gap: float = -INF
	for setback: float in [0.0,6.0,12.0,18.0]:
		var z: float = route_at.z+setback
		for lane_x: float in RushRoadFrame.LANE_CENTERS:
			var gap: float = 1000.0
			for npc: RushTrafficVehicle in traffic.pool+director.opponents.racers:
				var npc_at: Vector3 = highway.course.to_route(npc.position) if highway.course!=null else npc.position
				if npc.active and absf(npc_at.x-lane_x)<3.0:
					gap = minf(gap,absf(npc_at.z-z)-npc.half_length-vehicle.half_length())
			var safety: float = minf(gap,30.0)-setback*.1
			if safety>best_gap:
				best_gap = safety
				best_x = lane_x
				best_z = z
	vehicle.position.x = best_x
	vehicle.position.z = best_z
	vehicle.position.y = RushRoadFrame.SURFACE_Y
	vehicle.rotation = Vector3.ZERO
	if highway.course!=null:
		vehicle.position = highway.course.to_world(vehicle.position)
		vehicle.rotation.y = highway.course.heading_at_z(vehicle.position.z)
	vehicle.velocity = Vector3.ZERO
	vehicle.signed_speed = 0.0
	vehicle.last_command = Vector2.ZERO
	vehicle.previous_pose = vehicle.global_transform
	vehicle.current_pose = vehicle.global_transform
	vehicle.visual.global_transform = vehicle.global_transform
	run.previous_x = vehicle.position.x
	run.previous_z = vehicle.position.z
	traffic.previous_player = vehicle.position
	director.opponents.previous_player = vehicle.position
	director.effects.reset()
	cameras.reset_rig()
	director.damage.restore_fraction(fraction)
	director.damage.grace_left = 2.0
	director.damage.enabled = true
	director.crash_left = -1
	director.exploded = false
	director.audio.active = true
	director.opponents.active = run.race_mode=="five_racer"
	run.suspended = false
	state = State.DRIVING
	get_tree().paused = false
	vehicle.driving = true
	turbo.start_run()
	traffic.active = true
	coins.active = true
	finish_gate.enabled = true
	performance.driving = true
	GameAudio.set_driving(true)
	GameAudio.set_suspended(false)
	DriveInput.set_enabled(true)
	for control: Control in ui.controls.values():
		control.visible = true
	ui.steering_ui._update()
	ui.show_screen("drive")

## Maps shown on the Choose Your Map screen, in display order. Other maps stay in
## Maps.json and the game; they are only hidden from this picker.
const SELECTABLE_MAP_IDS: Array[String] = ["rain","neon","metro"]

## Original indices (into map_dressing.maps) of the selectable maps, in display order.
func _selectable_map_indices() -> Array[int]:
	var found: Array[int] = []
	for wanted: String in SELECTABLE_MAP_IDS:
		var index: int = -1
		for i: int in map_dressing.maps.size():
			if String(map_dressing.maps[i].id)==wanted:
				index = i
				break
		if index>=0: found.append(index)
		else: push_warning("Selectable map id not found in Maps.json: "+wanted)
	if found.is_empty():
		# Never leave the picker empty if the catalog ids ever change.
		for i: int in map_dressing.maps.size(): found.append(i)
	return found

## Old saves may hold a hidden map index or the retired RANDOM value (== maps.size()).
## Fall back to the first selectable map; in memory only, so nothing is rewritten here.
func _sanitize_map_settings() -> void:
	var allowed: Array[int] = _selectable_map_indices()
	if int(SaveService.settings.get("map",0)) not in allowed:
		SaveService.settings.map = allowed[0]

func _build_map_selection() -> void:
	var page: Control = ui._page("map_selection",true)
	page.visible = false
	page.get_child(0).color = Color("06101b44")
	var column: VBoxContainer = ui._center_column(page,1000)
	ui._label(column,"CHOOSE YOUR MAP",30,ui.ACCENT)
	var scroll: ScrollContainer = RushTouchScroll.new()
	scroll.custom_minimum_size = Vector2(0,180)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var row: HBoxContainer = HBoxContainer.new()
	scroll.add_child(row)
	row.add_theme_constant_override("separation",16)
	_sanitize_map_settings()
	var selected_map: int = int(SaveService.settings.get("map",0))
	var selection: Label = ui._label(column,"SELECTED: "+String(map_dressing.maps[selected_map].title),19,ui.ACCENT)
	var map_group: ButtonGroup = ButtonGroup.new()
	# Only the allowed maps are shown; `i` stays the ORIGINAL index into map_dressing.maps.
	for i: int in _selectable_map_indices():
		var label: String = String(map_dressing.maps[i].title)
		var button: Button = ui._button(row,label,func() -> void:
			SaveService.settings.map = i
			SaveService.commit()
			selection.text = "SELECTED: "+label)
		button.toggle_mode = true
		button.button_group = map_group
		button.button_pressed = i==selected_map
		button.custom_minimum_size = Vector2(220,140)
		var map_id: String = String(map_dressing.maps[i].id)
		# A bundled real in-game capture wins over the SVG placeholder when it exists;
		# a newer capture saved by MapPreview still replaces it through bind_button.
		var bundled_preview: String = "res://Assets/UI/map_"+map_id+"_preview.png"
		button.icon = load(bundled_preview) if ResourceLoader.exists(bundled_preview) else load("res://Assets/UI/map_"+map_id+".svg")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",90)
		map_dressing.previews.bind_button(map_id,button)
		RushMapSelectionStyle.card(button,label)
		if i==selected_map: scroll.ensure_control_visible.call_deferred(button)
	# Display names for the three real presets: DAY=MORNING, DUSK=EVENING, NIGHT=NIGHT.
	var presets: Array[int] = [RushTimeOfDay.Preset.MORNING,RushTimeOfDay.Preset.EVENING,RushTimeOfDay.Preset.NIGHT]
	var time: OptionButton = OptionButton.new()
	for name_value: String in ["DAY","DUSK","NIGHT"]:
		time.add_item(name_value)
	time.selected = maxi(0,presets.find(RushTimeOfDay.normalize_preset(SaveService.settings.get("map_time",0))))
	time.item_selected.connect(func(value: int) -> void:
		SaveService.settings.map_time = presets[value]
		SaveService.commit())
	column.add_child(time)
	ui._button(column,"RACE",start_drive,true)
	ui._button(column,"BACK",func() -> void: ui.show_screen("race_modes"))
	RushMapSelectionStyle.panel(page,column,scroll)

func _clear_race_course() -> void:
	course_generation += 1
	vehicle.course = null
	if finish_gate!=null: finish_gate.car = vehicle
	run.course = null
	traffic.course = null
	if director!=null: director.opponents.course = null
	if course_pickups!=null: course_pickups.set_course(null)
	highway.clear_sampled_course()
