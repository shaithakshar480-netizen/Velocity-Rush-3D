class_name RushDrivingDirector
extends Node3D
## Integrates the driving pass without taking ownership of navigation or persistence.
signal revive_requested # Extension point only: no revive provider or fake reward.
var game: Node
var damage := RushDamageController.new()
var tod := RushTimeOfDay.new()
var audio: RushDrivingAudio
var lights: RushVehicleLights
var opponents: RushRaceOpponents
var effects: RushDamageEffects
var ads: RushRewardedAdService
var store: RushTurboStoreUI
var health_bar: ProgressBar
var condition: Label
var callout: Label
var callout_left: float = 0.0
var crash_left: float = -1.0
var exploded: bool = false
var paint_color := Color.WHITE
# BUG-2 FIX: Track previous gear to distinguish upshifts from downshifts.
# Downshifts fire automatically during braking; must NOT shake the camera.
# Start at 0 (neutral) so any initial 1st-gear engagement is treated as an upshift.
var _previous_gear: int = 0
func build(owner_game: Node) -> void:
	game = owner_game
	process_physics_priority = 10
	audio = RushDrivingAudio.new()
	audio.car = game.vehicle
	add_child(audio)
	lights = RushVehicleLights.new()
	lights.car = game.vehicle
	lights.director = self
	add_child(lights)
	opponents = RushRaceOpponents.new()
	opponents.car = game.vehicle
	opponents.traffic = game.traffic
	opponents.passed.connect(audio.pass_by)
	add_child(opponents)
	game.traffic.opponents = opponents
	game.run.opponents = opponents
	effects = RushDamageEffects.new()
	add_child(effects)
	ads = RushRewardedAdService.new()
	game.ui.add_child(ads)
	store = RushTurboStoreUI.new()
	game.ui.add_child(store)
	store.build(game.ui,ads)
	store.closed.connect(game.close_turbo_store)
	var supply: Button = game.ui._button(game.ui.screens.home,"TURBO SUPPLY",game.open_turbo_store)
	supply.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	supply.offset_left = 14
	supply.offset_right = 214
	supply.offset_top = 124
	supply.offset_bottom = 170
	supply.add_theme_font_size_override("font_size",16)
	var horn := RushHornControl.new()
	game.ui.screens.drive.add_child(horn)
	horn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	horn.offset_left = 360
	horn.offset_right = 444
	horn.offset_top = -104
	horn.offset_bottom = -20
	horn.custom_minimum_size = Vector2(84, 84)
	game.ui.controls.horn = horn
	game.ui.hud_elements["horn"] = horn
	HudLayoutService.apply_control("horn", horn, game.ui.screens.drive.size)
	DriveInput.regions = game.ui.controls
	var hp_card := PanelContainer.new()
	hp_card.name = "HealthCard"
	game.ui.screens.drive.add_child(hp_card)
	hp_card.position = Vector2(0, 70)
	hp_card.custom_minimum_size = Vector2(230, 60)
	hp_card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hp_style := StyleBoxFlat.new()
	hp_style.bg_color = Color("071422f0")
	hp_style.border_color = Color("00e5ffaa")
	hp_style.set_border_width_all(1)
	hp_style.set_corner_radius_all(10)
	hp_style.shadow_color = Color("00e5ff33")
	hp_style.shadow_size = 10
	hp_style.shadow_offset = Vector2(0, 2)
	hp_style.content_margin_left = 10
	hp_style.content_margin_right = 10
	hp_style.content_margin_top = 5
	hp_style.content_margin_bottom = 5
	hp_card.add_theme_stylebox_override("panel", hp_style)

	var hp_root := VBoxContainer.new()
	hp_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_root.add_theme_constant_override("separation", 3)
	hp_card.add_child(hp_root)

	var hp_row := HBoxContainer.new()
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_theme_constant_override("separation", 8)
	hp_root.add_child(hp_row)

	var car_icon := TextureRect.new()
	car_icon.texture = preload("res://Assets/UI/nav_garage.svg")
	car_icon.custom_minimum_size = Vector2(36, 32)
	car_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	car_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	car_icon.modulate = Color("ffffff")
	car_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	car_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(car_icon)

	var hp_col := VBoxContainer.new()
	hp_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_col.add_theme_constant_override("separation", 0)
	hp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(hp_col)

	var tag_label := Label.new()
	tag_label.text = "VEHICLE"
	tag_label.add_theme_font_size_override("font_size", 13)
	tag_label.add_theme_color_override("font_color", Color("00e5ffcc"))
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_col.add_child(tag_label)

	condition = Label.new()
	condition.text = "HP 100"
	condition.add_theme_font_size_override("font_size", 20)
	condition.add_theme_color_override("font_color", Color("f0faff"))
	condition.add_theme_color_override("font_shadow_color", Color("00e5ff44"))
	condition.add_theme_constant_override("shadow_offset_y", 1)
	condition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_col.add_child(condition)

	# Full-width health bar at bottom of the card matching Screenshot B
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size.y = 6
	health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb_bg := StyleBoxFlat.new()
	hb_bg.bg_color = Color("05101ce6")
	hb_bg.border_color = Color("00e5ff26")
	hb_bg.set_border_width_all(1)
	hb_bg.set_corner_radius_all(2)
	health_bar.add_theme_stylebox_override("background", hb_bg)
	var hb_fill := StyleBoxFlat.new()
	hb_fill.bg_color = Color("00e5ff")
	hb_fill.set_corner_radius_all(2)
	hb_fill.shadow_color = Color("00e5ff66")
	hb_fill.shadow_size = 4
	health_bar.add_theme_stylebox_override("fill", hb_fill)
	hp_root.add_child(health_bar)
	callout = game.ui._label(game.ui.screens.drive,"",24,game.ui.ACCENT)
	callout.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	callout.offset_left = -190
	callout.offset_right = 190
	callout.offset_top = -100
	callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var crash_page: Control = game.ui._page("crashed",true)
	crash_page.visible = false
	var column: VBoxContainer = game.ui._center_column(crash_page,410)
	game.ui._label(column,"CAR DESTROYED",34,Color("ff8667"))
	game.ui._label(column,"Repair your car to continue, or start a new race.",17,game.ui.MUTED)
	game.ui._button(column,"REPLAY",game.start_drive,true)
	game.ui._button(column,"MAIN MENU",game.go_home)
	game.vehicle.contact_report.connect(_contact)
	damage.damaged.connect(_damaged)
	damage.restored.connect(_restored)
	damage.destroyed.connect(game.vehicle_destroyed)
	game.vehicle.transmission.shifted.connect(_shifted)
	game.traffic.near_miss_detail.connect(_near_miss)
	game.traffic.passed.connect(audio.pass_by)
	game.turbo.ended.connect(func() -> void: audio.play_effect("blowoff",game.vehicle.position,.45))
	tod.prepare()
	GameAudio.external_engine = true
func prewarm() -> void:
	audio.prewarm()
	lights.night = 3
	for mode: int in 4:
		tod.mode = mode
		for quality: int in 3:
			tod.apply(game.highway,quality)
			for _frame: int in 6:
				await get_tree().process_frame
	tod.mode = 1
	tod.apply(game.highway,game.performance.visual_level)
	opponents.reset()
	# Render all traffic tiers while the opaque loading screen is still visible.
	for detail: int in 3:
		game.traffic.prewarm_models(1.0)
		for car: RushTrafficVehicle in game.traffic.pool:
			car.detail = detail
			car._apply_detail()
		for racer: RushTrafficVehicle in opponents.racers:
			racer.detail = detail
			racer._apply_detail()
		await get_tree().process_frame
		await get_tree().process_frame
	effects.global_position = game.vehicle.position
	effects.impact(1)
	effects.explode()
	effects.stage = 4
	effects.reset()
	opponents.stop()
func reset_run() -> void:
	stop()
	damage.reset(game.vehicle.spec.vehicle_id)
	effects.configure(game.vehicle.spec.vehicle_id)
	paint_color = game.vehicle.visual.material_sets[game.vehicle.visual.active_index].Paint.albedo_color
	audio.configure(game.vehicle.spec.vehicle_id)
	audio.active = true # Idle during countdown; DriveInput remains locked until GO.
	lights.configure()
	lights.visible = true
	tod.choose(game.run.run_id)
	tod.apply(game.highway,game.performance.visual_level)
	lights.night = tod.mode
	if game.run.race_mode=="five_racer":
		opponents.reset()
	else:
		opponents.stop()
	for car: RushTrafficVehicle in game.traffic.pool:
		car.night_mode = tod.mode
	for car: RushTrafficVehicle in opponents.racers:
		car.night_mode = tod.mode
	apply_quality()
func start_run() -> void:
	damage.enabled = true
	audio.active = true
	opponents.active = game.run.race_mode=="five_racer"
func finish_run() -> void:
	damage.enabled = false
	GameAudio.duck_music(1.5)
func stop() -> void:
	damage.enabled = false
	damage.stage = 0
	audio.silence()
	lights.visible = false
	opponents.stop()
	effects.reset()
	crash_left = -1
	exploded = false
	callout_left = 0
	callout.text = ""
	game.vehicle.visual.body_root.visible = true
	# BUG-2 FIX: Reset gear tracker to neutral on each stop so the NEXT run's
	# first gear engagement is always detected as an upshift (0 -> 1).
	_previous_gear = 0
func crash() -> void:
	damage.enabled = false
	audio.active = false
	opponents.active = false
	effects.destroy()
	crash_left = 2.6
	exploded = false
	GameAudio.duck_music(3)
func apply_quality() -> void:
	effects.quality = game.performance.effects_level
	for beam: SpotLight3D in lights.beams:
		beam.spot_range = [85.0,105.0,130.0][game.performance.visual_level]
	for car: RushTrafficVehicle in opponents.racers:
		car.set_visual_quality(game.performance.visual_level)
func _contact(speed: float, normal: Vector3, kind: String) -> void:
	damage.apply_contact(speed,normal,-game.vehicle.global_basis.z,kind)
func _damaged(amount: float, stage: int) -> void:
	effects.stage = stage
	effects.impact(clampf(amount/40,0,1))
	game.vehicle.visual.material_sets[game.vehicle.visual.active_index].Paint.albedo_color = paint_color.darkened(stage*.09)
	game.vehicle.visual.material_sets[game.vehicle.visual.active_index].Paint.roughness = .24+stage*.12
	if amount>15:
		audio.play_effect("heavy_impact",game.vehicle.position,clampf(amount/30,.35,1))
		audio.play_effect("scrape",game.vehicle.position,.22)
	elif amount>6:
		audio.play_effect("heavy_impact",game.vehicle.position,.35)
	else:
		audio.play_effect("scrape",game.vehicle.position,clampf(amount/12,.15,.5))
	if stage==3:
		audio.play_effect("damage_warning",game.vehicle.position,.5)
	if amount>15:
		GameAudio.duck_music(.7)
func _shifted(_gear: int) -> void:
	if audio.active:
		audio.play_effect("shift",game.vehicle.position,.32)
	_previous_gear = _gear
func _near_miss(gap: float, speed: float, at: Vector3) -> void:
	var rules: Dictionary = RushDrivingData.get_data().near_miss
	var insane := gap<=float(rules.insane_gap) and speed>=float(rules.insane_kmh)
	var close := gap<=float(rules.close_gap) and speed>=float(rules.close_kmh)
	callout.text = "INSANE NEAR MISS" if insane else ("CLOSE CALL" if close else "NEAR MISS")
	game.cameras.impact_feedback(.09 if insane else .04)
	callout.text += " x%d\n+%d"%[maxi(1,game.run.combo),game.run.spec.near_miss_score*maxi(1,game.run.combo)]
	callout_left = 1.1
	game.streaks.impact = maxf(game.streaks.impact,.15 if insane else .07)
	audio.play_effect("passby",at,1 if insane else .65)
func _process(delta: float) -> void:
	if game==null:
		return
	effects.global_transform = game.vehicle.render_pose()
	audio.damage_stage = damage.stage
	var driving: bool = game.state in [game.State.DRIVING,game.State.FINISHING]
	game.vehicle.visual.body_root.visible = true
	game.ui.screens.drive.get_node("SpeedGlass").visible = true
	game.turbo_ui.meter_box.offset_top = 136
	game.turbo_ui.meter_box.offset_bottom = 162
	game.ui.screens.drive.get_node("SpeedDial").visible = true
	game.ui.screens.drive.get_node("SpeedReadout").visible = true
	if driving:
		health_bar.value = damage.health/damage.maximum*100
		condition.text = "HP %03d"%roundi(damage.health/damage.maximum*100)
		if game.run.race_mode=="five_racer":
			condition.text += "   /   POS %d/5"%(opponents.live_order().find(0)+1)
		if DriveInput.held("horn") and audio.horn():
			game.traffic.react_to_horn()
	callout_left = maxf(0,callout_left-delta)
	callout.visible = callout_left>0 and driving
	var age: float = 1.1-callout_left
	callout.scale = Vector2.ONE*(1.0+.16*sin(clampf(age/.2,0,1)*PI))
	callout.modulate.a = clampf(callout_left*3,0,1)
	condition.modulate = Color("ff937b") if damage.stage>=3 else Color.WHITE
	if crash_left>=0:
		crash_left -= delta
		if crash_left<2.0 and not exploded:
			exploded = true
			effects.explode()
			audio.play_effect("explosion",game.vehicle.position,1)
			game.cameras.impact_feedback(.55)
		if crash_left<=0:
			crash_left = -1
			game.ui.show_screen("crashed")

func _physics_process(delta: float) -> void:
	if game!=null and opponents!=null:
		if game.run.state==RushRunManager.RunState.RUNNING:
			opponents.record_finishes(delta,game.run.origin_offset-game.run.spec.distance_m)
		opponents.evaluate_contacts()

func _restored() -> void:
	effects.reset()
	effects.stage = damage.stage
	audio.damage_stage = damage.stage
	var paint: StandardMaterial3D = game.vehicle.visual.material_sets[game.vehicle.visual.active_index].Paint
	paint.albedo_color = paint_color.darkened(damage.stage*.09)
	paint.roughness = .24+damage.stage*.12
