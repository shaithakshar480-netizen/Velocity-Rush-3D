class_name RushPresentation
extends Node
## Extends the existing UI using its theme/helpers; no replacement of Phase 1 screens.
var ui: Node
var coin_label: Label
var score_label: Label
var progress_bar: ProgressBar
var countdown: Label
var feedback: Label
var feedback_left: float = 0.0
var combo_pulse: float = 0.0
var displayed_score: float = 0.0
var target_score: float = 0.0
var coin_pulse: float = 0.0
var home_wallet: Label
var home_error: Label
var result_values: Dictionary = {}
var results_fade: Tween
var reward_count: Tween
var rank_title: Label
var total_label: Label
var result_wallet: Label
var result_status: Label
var retry: Button
var again: Button
var home: Button
var result_badge: RushLevelBadge
var xp_label: Label
var mission_summary: Label
var mission_button: Button
var xp_sound_run: int = 0
var leaderboard_panel: PanelContainer
var live_ranking: Label
var final_ranking: Label
var bonus_slot: VBoxContainer

func build(owner_ui: Node) -> void:
	ui = owner_ui
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_hud()
	_build_results()
	leaderboard_panel = PanelContainer.new()
	ui.screens.drive.add_child(leaderboard_panel)
	leaderboard_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	leaderboard_panel.position = Vector2(0,142)
	leaderboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaderboard_panel.add_theme_stylebox_override("panel",ui._style(Color("0b1721c9")))
	live_ranking = ui._label(leaderboard_panel,"",16,ui.ACCENT)
	live_ranking.add_theme_color_override("font_shadow_color",Color("071321"))
	live_ranking.add_theme_constant_override("shadow_offset_x",2)
	live_ranking.add_theme_constant_override("shadow_offset_y",2)
	live_ranking.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ui.home_currency != null and ui.home_currency.get_child_count() > 0:
		var currency_row: HBoxContainer = ui.home_currency.get_child(0) as HBoxContainer
		home_wallet = ui._label(currency_row, "0", 17, Color("ffd360"))
		home_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		home_wallet = ui._label(ui.screens["home"], "", 22, ui.ACCENT)
		home_wallet.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		home_wallet.offset_left = -340
		home_wallet.offset_right = 0
		home_wallet.offset_top = 73
		home_wallet.offset_bottom = 101
		home_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	home_error = ui._label(ui.screens["home"], "", 16, Color("ffad91"))
	home_error.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	home_error.offset_left = -450
	home_error.offset_right = 450
	home_error.offset_top = -88
	home_error.offset_bottom = -72
	home_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SaveService.wallet_changed.connect(_wallet_changed)
	_wallet_changed(SaveService.balance())

var coin_chip: Control
var score_chip: Control
var countdown_tween: Tween
var race_track_title: Label

func _build_hud() -> void:
	var page: Control = ui.screens["drive"]

	# 1. Slim cinematic race-status strip at top center
	var status_strip := VBoxContainer.new()
	page.add_child(status_strip)
	status_strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status_strip.offset_left = -188
	status_strip.offset_right = 188
	status_strip.offset_top = -6
	status_strip.offset_bottom = 54
	status_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_strip.add_theme_constant_override("separation", 2)

	race_track_title = ui._label(status_strip, "HIGHWAY RUSH", 23, Color("f0fbff"))
	race_track_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_track_title.add_theme_color_override("font_shadow_color", Color("00e5ff88"))
	race_track_title.add_theme_constant_override("shadow_offset_x", 0)
	race_track_title.add_theme_constant_override("shadow_offset_y", 1)
	race_track_title.add_theme_constant_override("shadow_outline_size", 2)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 5
	progress_bar.show_percentage = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color("05101ce6")
	pb_bg.border_color = Color("00e5ff33")
	pb_bg.set_border_width_all(1)
	pb_bg.set_corner_radius_all(2)
	progress_bar.add_theme_stylebox_override("background", pb_bg)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = Color("00e5ff")
	pb_fill.set_corner_radius_all(2)
	pb_fill.shadow_color = Color("00e5ff77")
	pb_fill.shadow_size = 4
	progress_bar.add_theme_stylebox_override("fill", pb_fill)
	status_strip.add_child(progress_bar)

	# Large distance remaining label (ui.status_label is attached here)
	ui.status_label = ui._label(status_strip, "7.8 KM LEFT", 22, Color("ffffff"))
	ui.status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.status_label.add_theme_color_override("font_shadow_color", Color("00e5ff66"))
	ui.status_label.add_theme_constant_override("shadow_offset_x", 0)
	ui.status_label.add_theme_constant_override("shadow_offset_y", 1)
	ui.status_label.add_theme_constant_override("shadow_outline_size", 2)

	# 2. Telemetry chips for SCORE and COINS below progress line
	var chips_row := HBoxContainer.new()
	page.add_child(chips_row)
	chips_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	chips_row.offset_left = -140
	chips_row.offset_right = 140
	chips_row.offset_top = 60
	chips_row.offset_bottom = 92
	chips_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chips_row.add_theme_constant_override("separation", 10)

	# Score Chip (pill shape with cyan rim glow)
	score_chip = PanelContainer.new()
	score_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var score_style := StyleBoxFlat.new()
	score_style.bg_color = Color("071422f0")
	score_style.border_color = Color("00e5ffaa")
	score_style.set_border_width_all(1)
	score_style.set_corner_radius_all(10)
	score_style.shadow_color = Color("00e5ff33")
	score_style.shadow_size = 6
	score_style.shadow_offset = Vector2(0, 1)
	score_style.content_margin_left = 10
	score_style.content_margin_right = 10
	score_style.content_margin_top = 2
	score_style.content_margin_bottom = 2
	score_chip.add_theme_stylebox_override("panel", score_style)
	chips_row.add_child(score_chip)

	score_label = ui._label(score_chip, "SCORE 0", 17, Color("d0f2ff"))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Coin Chip (pill shape with gold rim glow and coin graphic)
	coin_chip = PanelContainer.new()
	coin_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_style := StyleBoxFlat.new()
	coin_style.bg_color = Color("071422f0")
	coin_style.border_color = Color("ffc838aa")
	coin_style.set_border_width_all(1)
	coin_style.set_corner_radius_all(10)
	coin_style.shadow_color = Color("ffc83833")
	coin_style.shadow_size = 6
	coin_style.shadow_offset = Vector2(0, 1)
	coin_style.content_margin_left = 8
	coin_style.content_margin_right = 10
	coin_style.content_margin_top = 2
	coin_style.content_margin_bottom = 2
	coin_chip.add_theme_stylebox_override("panel", coin_style)
	chips_row.add_child(coin_chip)

	var coin_row := HBoxContainer.new()
	coin_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_row.add_theme_constant_override("separation", 6)
	coin_chip.add_child(coin_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture = preload("res://Assets/UI/icon_coin.svg")
	coin_icon.custom_minimum_size = Vector2(22, 22)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_row.add_child(coin_icon)

	coin_label = ui._label(coin_row, "0", 17, Color("ffd542"))
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# 3. Small localized coin feedback popup near coin chip
	feedback = ui._label(page, "", 13, Color("ffd768"))
	feedback.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	feedback.offset_left = 75
	feedback.offset_right = 175
	feedback.offset_top = 60
	feedback.offset_bottom = 92
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback.add_theme_color_override("font_shadow_color", Color("03090e"))
	feedback.add_theme_constant_override("shadow_offset_y", 1)

	# 4. Cinematic countdown presentation
	countdown = ui._label(page, "", 76, ui.ACCENT)
	countdown.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	countdown.offset_left = -250
	countdown.offset_right = 250
	countdown.offset_top = -90
	countdown.offset_bottom = 15
	countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown.add_theme_color_override("font_shadow_color", Color("071928cc"))
	countdown.add_theme_constant_override("shadow_offset_x", 0)
	countdown.add_theme_constant_override("shadow_offset_y", 3)

func _build_results() -> void:
	var page: Control = ui._page("results",true)
	page.get_child(0).color = Color("080f1c55")
	var scroll := RushTouchScroll.new()
	page.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var shell := PanelContainer.new()
	center.add_child(shell)
	shell.add_theme_stylebox_override("panel",_result_skin("glass",18))
	var column: VBoxContainer = ui._column(shell,760)
	var fit: Callable = func() -> void:
		column.custom_minimum_size.x = minf(760.0,maxf(280.0,page.size.x-80.0))
	page.resized.connect(fit)
	fit.call_deferred()
	column.add_theme_constant_override("separation",4)
	rank_title = ui._label(column,"RUN COMPLETE",36,Color("d9edf2"))
	rank_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui._label(column,"VELOCITY RUSH  /  RACE DEBRIEF",15,ui.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_ranking = ui._label(column,"",17,ui.MUTED)
	var metrics := GridContainer.new()
	metrics.columns = 3
	metrics.add_theme_constant_override("v_separation",8)
	metrics.add_theme_constant_override("h_separation",16)
	column.add_child(metrics)
	for pair: Array in [["Distance","distance"],["Score","score"],["Near Misses","near_misses"],["Best Combo","best_combo"],["Run Time","elapsed"],["Top Speed","highest_speed"]]:
		var tile: PanelContainer = PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_stylebox_override("panel",_result_skin("tile",10))
		metrics.add_child(tile)
		var tile_row := HBoxContainer.new()
		tile.add_child(tile_row)
		var content: VBoxContainer = VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile_row.add_child(content)
		ui._label(content,String(pair[0]).to_upper(),13,ui.MUTED)
		var value: Label = ui._label(content,"—",25,Color("d5f5fb"))
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		result_values[pair[1]] = value
		var symbols: Dictionary = {"distance":"◴","score":"★","near_misses":"⇄","best_combo":"×","elapsed":"◷","highest_speed":"➤"}
		var icon: Label = ui._label(tile_row,String(symbols[pair[1]]),34,Color("abe9ef"))
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(HSeparator.new())
	for pair: Array in [["COINS COLLECTED","road_coins"],["Completion Bonus","completion_bonus"],["Performance Bonus","performance_bonus"]]:
		var row := HBoxContainer.new()
		column.add_child(row)
		ui._label(row,pair[0],20,ui.MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		result_values[pair[1]] = ui._label(row,"0",22)
	var payout: PanelContainer = PanelContainer.new()
	payout.add_theme_stylebox_override("panel",_result_skin("gold",8))
	column.add_child(payout)
	var payout_content: VBoxContainer = VBoxContainer.new()
	payout.add_child(payout_content)
	ui._label(payout_content,"TOTAL COINS EARNED",14,Color("332707")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label = ui._label(payout_content,"+0",34,Color("302304"))
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_wallet = ui._label(column,"",20)
	result_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var progression_row := HBoxContainer.new()
	progression_row.add_theme_constant_override("separation",24)
	column.add_child(progression_row)
	xp_label = ui._label(progression_row,"",20,ui.ACCENT)
	xp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_badge = RushLevelBadge.new()
	progression_row.add_child(result_badge)
	result_badge.build(ui)
	mission_summary = ui._label(column,"",16,ui.MUTED)
	mission_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_status = ui._label(column,"",16,ui.MUTED)
	result_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation",16)
	column.add_child(buttons)
	again = ui._button(buttons,"PLAY AGAIN",func() -> void: ui.play_requested.emit(),true)
	home = ui._button(buttons,"HOME",func() -> void: ui.home_requested.emit())
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_button = ui._button(buttons,"MISSIONS",func() -> void: ui.progression_requested.emit("missions"))
	retry = ui._button(column,"RETRY SAVING REWARD",func() -> void: ui.retry_reward_requested.emit(),true)
	# Layout extension point only. No 2X/ad button or ad behavior in Phase 2.
	bonus_slot = VBoxContainer.new()
	bonus_slot.name = "FutureRewardActionSlot"
	bonus_slot.visible = false
	column.add_child(bonus_slot)
	for button: Button in [again,home,mission_button,retry]:
		_result_button(button,"cyan" if button==again else "silver")
	bonus_slot.child_entered_tree.connect(func(child: Node) -> void:
		if child is Button: _result_button(child as Button,"gold"))

func update_hud(run: RushRunManager) -> void:
	leaderboard_panel.visible = run.race_mode=="five_racer"
	live_ranking.visible = leaderboard_panel.visible
	if live_ranking.visible and run.opponents!=null:
		var order: Array[int] = run.opponents.live_order()
		live_ranking.text = "%d / 5\n"%(order.find(0)+1)
		for i: int in order.size():
			live_ranking.text += "%d  %s\n"%[i+1,run.opponents.racer_name(order[i])]
	coin_label.text = "%d" % run.run_coins
	target_score = run.score
	progress_bar.value = run.progress()*100.0
	var km_left: float = (run.spec.distance_m - run.distance) / 1000.0
	ui.status_label.text = "%.1f KM LEFT" % maxf(km_left, 0.0)

func show_results(summary: Dictionary, saved: bool) -> void:
	final_ranking.text = ""
	for row: Dictionary in summary.get("racers",[]):
		var timing: String = "%.2fs"%float(row.finish_time) if float(row.finish_time)>=0 else "UNFINISHED"
		final_ranking.text += "%d  %s  •  %s  •  %d COINS / %d XP\n"%[int(row.position),String(row.name),timing,int(row.coins),int(row.xp)]
	var rank := int(summary.get("finish_place",0))
	rank_title.text = ["RUN COMPLETE","1ST  /  CHAMPION","2ND  /  PODIUM","3RD  /  PODIUM","4TH  /  FINISH","5TH  /  FINISH"][clampi(rank,0,5)]
	if not bool(summary.get("completed",true)): rank_title.text = "RUN ENDED"
	rank_title.modulate = [Color.WHITE,Color("ffda83"),Color("dcebf5"),Color("d9a77b"),Color.WHITE,Color.WHITE][clampi(rank,0,5)]
	rank_title.add_theme_font_size_override("font_size",46 if rank in [1,2,3] else 38)
	for key: String in result_values:
		var text_value := str(summary.get(key,0))
		match key:
			"distance": text_value = "%.2f KM"%(float(summary.get(key,0.0))/1000.0)
			"elapsed": text_value = "%d:%02d"%[int(float(summary.get(key,0.0))/60.0),int(summary.get(key,0))%60]
			"highest_speed": text_value = "%.0f KM/H"%float(summary[key]) if float(summary.get(key,0))>0 else "—"
			"best_combo": text_value = "x%d"%int(summary.get(key,0))
		result_values[key].text = text_value
	var doubled: bool = int(SaveService.consumables.get("double_reward_run",0))==int(summary.get("run_id",-1))
	var display_total: int = int(summary.get("total",0))+(int(summary.get("road_coins",0)) if doubled else 0)
	total_label.text = "+%d"%display_total
	result_badge.refresh()
	xp_label.text = "+%d XP%s\nLEVEL BONUS  +%d COINS"%[int(summary.get("xp_earned",0)),"  •  NEW BEST" if summary.get("new_best",false) else "",int(summary.get("level_coins",0))]
	var completed_tasks: int = 0
	for task: Dictionary in SaveService.progression.daily.tasks:
		if task.progress>=task.target:
			completed_tasks += 1
	mission_summary.text = "DAILY MISSIONS  %d / 3 COMPLETE   •   %d REWARDS READY"%[completed_tasks,RewardService.claimable_count()]
	mission_button.disabled = not saved
	if saved and xp_sound_run!=int(summary.get("run_id",0)):
		xp_sound_run = int(summary.get("run_id",0))
		GameAudio.event("xp_gain")
	if reward_count!=null and reward_count.is_valid():
		reward_count.kill()
	reward_count = create_tween()
	reward_count.tween_method(func(value: float) -> void: total_label.text = "+%d"%int(value),0.0,float(display_total),.32)
	result_wallet.text = "WALLET  %d COINS"%SaveService.balance()
	result_status.text = "Reward saved to your wallet." if saved else "Reward not saved. "+SaveService.last_error+" Free some storage and retry."
	again.disabled = not saved
	home.disabled = not saved
	retry.visible = not saved
	countdown.text = ""
	ui.show_screen("results")
	if results_fade != null and results_fade.is_valid():
		results_fade.kill()
	var page: Control = ui.screens["results"]
	page.modulate.a = 0.0
	results_fade = create_tween()
	results_fade.tween_property(page,"modulate:a",1.0,0.25)

func show_countdown(text: String) -> void:
	countdown.text = text
	if countdown_tween != null and countdown_tween.is_valid():
		countdown_tween.kill()

	if text == "3":
		displayed_score = 0.0
		target_score = 0.0
		combo_pulse = 0.0
		feedback.text = ""
		feedback_left = 0.0
		coin_pulse = 0.0
		home_error.text = ""

	if text == "":
		return

	countdown.pivot_offset = countdown.size * 0.5
	if text == "GO!":
		countdown.add_theme_font_size_override("font_size", 84)
		countdown.add_theme_color_override("font_color", Color("ffffff"))
		countdown.add_theme_color_override("font_shadow_color", Color("38b8d4ee"))
	elif text in ["3", "2", "1"]:
		countdown.add_theme_font_size_override("font_size", 76)
		countdown.add_theme_color_override("font_color", Color("58eaff"))
		countdown.add_theme_color_override("font_shadow_color", Color("0b1c2acc"))
	elif text == "READY":
		countdown.add_theme_font_size_override("font_size", 54)
		countdown.add_theme_color_override("font_color", Color("ffd152"))
		countdown.add_theme_color_override("font_shadow_color", Color("2a1a06cc"))
	else:
		countdown.add_theme_font_size_override("font_size", 64)
		countdown.add_theme_color_override("font_color", ui.ACCENT)

	countdown.scale = Vector2(1.24, 1.24)
	countdown.modulate.a = 1.0
	countdown_tween = create_tween().set_parallel(true)
	countdown_tween.tween_property(countdown, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if text == "GO!":
		countdown_tween.tween_property(countdown, "modulate:a", 0.0, 0.35).set_delay(0.55)

func coin_feedback(value: int) -> void:
	coin_pulse = 0.35
	feedback.text = "+%d  ◉" % value
	feedback_left = 0.65

func near_miss_feedback(combo: int) -> void:
	combo_pulse = minf(1.0,.55+float(combo)*.05)
	feedback.text = "" # Detailed near-miss callout is owned by DrivingDirector.
	feedback_left = 0.0

func _process(delta: float) -> void:
	displayed_score = lerpf(displayed_score,target_score,1.0-exp(-10.0*delta))
	var sc_int: int = int(round(displayed_score))
	if sc_int >= 1000:
		var sc_str := str(sc_int)
		var fmt := ""
		var c := 0
		for i: int in range(sc_str.length() - 1, -1, -1):
			fmt = sc_str[i] + fmt
			c += 1
			if c % 3 == 0 and i > 0:
				fmt = "," + fmt
		score_label.text = "SCORE  %s" % fmt
	else:
		score_label.text = "SCORE  %d" % sc_int

	combo_pulse = move_toward(combo_pulse,0.0,delta*2.0)
	feedback_left = maxf(feedback_left-delta,0.0)
	feedback.modulate.a = clampf(feedback_left*3.5,0.0,1.0)
	coin_pulse = maxf(coin_pulse-delta,0.0)
	if coin_chip != null and is_instance_valid(coin_chip):
		coin_chip.pivot_offset = coin_chip.size * 0.5
		coin_chip.scale = Vector2.ONE * (1.0 + coin_pulse * 0.15)

func _wallet_changed(balance: int) -> void:
	if ui.home_currency != null:
		# Premium formatted currency display (e.g. 12,450)
		var s := str(balance)
		var formatted := ""
		var count := 0
		for i: int in range(s.length() - 1, -1, -1):
			formatted = s[i] + formatted
			count += 1
			if count % 3 == 0 and i > 0:
				formatted = "," + formatted
		home_wallet.text = formatted
	else:
		home_wallet.text = "WALLET  /  %d COINS"%balance

# Results-only skinning; settlement and callbacks remain owned by existing services.
func _result_skin(kind: String, margin: int) -> StyleBoxTexture:
	var skin := StyleBoxTexture.new()
	skin.texture = load("res://Assets/UI/result_"+kind+".svg") as Texture2D
	skin.texture_margin_left = 20
	skin.texture_margin_right = 20
	skin.texture_margin_top = 20
	skin.texture_margin_bottom = 20
	skin.set_content_margin_all(margin)
	return skin

func _result_button(button: Button, kind: String) -> void:
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size",21)
	button.add_theme_color_override("font_color",Color("15262d"))
	button.add_theme_color_override("font_hover_color",Color("15262d"))
	button.add_theme_color_override("font_pressed_color",Color("ffffff"))
	for state: String in ["normal","hover","pressed","disabled"]:
		var skin: StyleBoxTexture = _result_skin(kind,8)
		if state=="hover": skin.modulate_color = Color(1.08,1.08,1.08)
		elif state=="pressed": skin.modulate_color = Color(0.75,0.82,0.85)
		elif state=="disabled": skin.modulate_color = Color(0.5,0.55,0.6)
		button.add_theme_stylebox_override(state,skin)
