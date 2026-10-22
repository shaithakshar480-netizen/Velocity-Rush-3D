class_name RushPowerupService
extends Node
## Optional, bounded offers. Callback captures the race/menu epoch; stale ads cannot affect a new run.
var game: Node
var ads: RushRewardedAdService
var config: Dictionary
var queued: Dictionary = {}
var used: Dictionary = {}
var prepared: bool = false
var epoch: int = 0
var trial_id: String = ""
var repair_available: bool = false
var origin: int = 0
var buttons: Dictionary = {}
var status: Label
var repair_button: Button
var continue_button: Button
var double_button: Button
var revive_button: Button
var claim_button: Button
var crash_stats: Label
var crash_status: Label
var give_up_button: Button
var crash_retry: Button
var result_retry: Button

func build(owner_game: Node, service: RushRewardedAdService) -> void:
	game = owner_game
	ads = service
	process_mode = Node.PROCESS_MODE_ALWAYS
	config = JSON.parse_string(FileAccess.get_file_as_string("res://Data/Powerups.json"))
	ads.turbo_delegate = Callable()
	var page: Control = game.ui._page("powerups",true)
	page.visible = false
	var column: VBoxContainer = game.ui._center_column(page,620)
	game.ui._label(column,"RACE REWARDS",28,game.ui.ACCENT)
	repair_button = game.ui._button(column,"USE REPAIR KIT",use_repair)
	status = game.ui._label(column,"",16,game.ui.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	claim_button = game.ui._button(column,"CLAIM REWARD",ads.retry_pending_reward)
	claim_button.visible = false
	game.ui._button(column,"MAIN MENU",back)
	continue_button = game.ui._button(column,"RACE",close,true)
	ads.status_changed.connect(func(message: String) -> void:
		status.text = message
		if is_instance_valid(crash_status): crash_status.text = message
		if game.state==game.State.RESULTS: game.ui.rush.result_status.text = message
		claim_button.visible = ads.pending!=0 and ads.earned
		refresh())
	double_button = game.ui._button(game.ui.rush.bonus_slot,"DOUBLE RACE COINS  /  WATCH AD",open_results)
	game.ui.rush.bonus_slot.visible = true
	var crash_page: Control = game.ui.screens.crashed
	for child: Node in crash_page.get_children():
		if child is Control: child.hide()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("06101b26")
	crash_page.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var crash_column: VBoxContainer = game.ui._center_column(crash_page,600)
	var center: Node = crash_column.get_parent()
	center.remove_child(crash_column)
	var panel: PanelContainer = PanelContainer.new()
	var glass: StyleBoxFlat = StyleBoxFlat.new()
	glass.bg_color = Color("101c2bf0")
	glass.border_color = game.ui.ACCENT
	glass.set_border_width_all(1)
	glass.set_corner_radius_all(18)
	glass.content_margin_left = 24
	glass.content_margin_right = 24
	glass.content_margin_top = 24
	glass.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel",glass)
	center.add_child(panel)
	panel.add_child(crash_column)
	var crash_heading: Label = game.ui._label(crash_column,"CAR CRASHED",42,Color("e0eef4"))
	game.ui._label(crash_column,"ONE MORE CHANCE",20)
	crash_stats = game.ui._label(crash_column,"",22)
	crash_status = game.ui._label(crash_column,"Watch a rewarded ad to continue this run.\nOr give up and keep the coins you collected.",19,Color("c5d8e2"))
	crash_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	revive_button = game.ui._button(crash_column,"▶  WATCH AD & REVIVE",open_revive,true)
	give_up_button = game.ui._button(crash_column,"▥  GIVE UP — VIEW RESULTS",game.give_up_drive)
	RushCrashPresentation.apply(crash_page,panel,crash_column,crash_heading,revive_button,give_up_button)
	crash_retry = game.ui._button(crash_column,"RETRY SAVING REWARD",ads.retry_pending_reward)
	crash_retry.hide()
	result_retry = game.ui._button(game.ui.rush.bonus_slot,"RETRY SAVING REWARD",ads.retry_pending_reward)
	result_retry.hide()

func _request_ui(kind: String) -> void:
	request(kind,false)

func open_pause() -> void:
	origin = game.State.PAUSED
	game.ui.show_screen("powerups")
	refresh()

func open_results() -> void:
	origin = game.State.RESULTS
	request("double",false)

func open_revive() -> void:
	origin = game.State.CRASHED
	request("revive",false)

func add_end_offers() -> void:
	var parent: Node = status.get_parent()
	for kind: String in ["double","revive"]:
		buttons[kind] = game.ui._button(parent,String(config[kind].label)+"  /  WATCH AD",_request_ui.bind(kind))
		parent.move_child(buttons[kind],2)

func close() -> void:
	if ads.pending!=0:
		status.text = "Complete or close the current ad before continuing."
		return
	if prepared:
		game.start_drive()
	elif origin==game.State.PAUSED:
		game.ui.show_screen("pause")
	elif origin==game.State.RESULTS:
		game.ui.show_screen("results")
	else:
		game.ui.show_screen("crashed")

func begin_run() -> void:
	epoch += 1
	used = queued.duplicate(true) if prepared else {}
	game.trial_vehicle_id = trial_id if prepared and used.has("trial") else ""
	repair_available = used.has("repair")
	queued.clear()
	prepared = false
	trial_id = ""

func apply_run() -> void:
	game.director.damage.shield_ready = used.has("shield")
	game.director.damage.shield_threshold = float(config.shield.minimum_damage)
	game.coins.pickup_radius = float(config.magnet.radius) if used.has("magnet") else 1.45

func discard() -> void:
	epoch += 1
	prepared = false
	queued.clear()
	used.clear()
	repair_available = false
	trial_id = ""
	game.trial_vehicle_id = ""
	game.coins.pickup_radius = 1.45

func eligible(kind: String) -> bool:
	if not config.has(kind):
		return false
	var claims := queued if prepared else used
	if int(claims.get(kind,0))>=int(config[kind].race_limit):
		return false
	match kind:
		"double": return game.state==game.State.RESULTS and game.run.reward_saved and int(game.run.result.get("road_coins",0))>0 and game.run.run_id>int(SaveService.consumables.get("double_reward_run",0))
		"revive": return game.state==game.State.CRASHED and game.run.suspended
		"trial": return prepared and not _trial_candidate().is_empty()
		"turbo": return SaveService.consumables.turbo_inventory<=SaveService.MAX_TURBO-int(config.turbo.charges) and (prepared or game.state in [game.State.HOME,game.State.DRIVING,game.State.PAUSED] or game.ui.screen=="turbo_store")
		_: return prepared or game.state==game.State.PAUSED

func request(kind: String, simulate: bool = false) -> bool:
	if game.run.race_mode in ["multiplayer","tournament"]:
		return false
	if not eligible(kind):
		status.text = "This powerup is already used or unavailable here."
		return false
	var context := {"epoch":epoch,"run":game.run.run_id,"scope":SaveService.scope_generation,"trial":_trial_candidate() if kind=="trial" else ""}
	if kind in ["double","revive"] and simulate: return false
	var requested: bool = ads.request_offer(_grant.bind(kind,context),simulate,"POWERUP_"+kind)
	refresh()
	return requested

func _grant(token: int, kind: String, context: Dictionary) -> bool:
	if int(context.get("scope",-1))!=SaveService.scope_generation: return false
	if int(context.epoch)!=epoch or int(context.run)!=game.run.run_id or not eligible(kind):
		ads.completion_message = "Offer expired; no reward applied to another race."
		# Settle the expired token without granting anything to a different race.
		return SaveService.settle_ad_request(token,false)
	var saved := SaveService.settle_ad_request(token,true) if kind=="turbo" else SaveService.settle_powerup(token,kind,game.run.run_id)
	if not saved:
		return false
	var claims := queued if prepared else used
	claims[kind] = int(claims.get(kind,0))+1
	match kind:
		"trial": trial_id = String(context.trial)
		"repair": repair_available = not prepared
		"shield":
			if not prepared:
				game.director.damage.shield_ready = true
		"magnet":
			if not prepared:
				game.coins.pickup_radius = float(config.magnet.radius)
		"revive": game.revive_drive(float(config.revive.health_fraction))
		"double":
			game.ui.rush.total_label.text = "+%d"%(int(game.run.result.get("total",0))+int(game.run.result.get("road_coins",0)))
			game.ui.rush.result_status.text = "Extra race coins saved."
			RewardService.progression_changed.emit()
			game.ui.rush.result_wallet.text = "WALLET  %d COINS"%SaveService.balance()
	refresh()
	return true

func use_repair() -> void:
	if not repair_available or game.state!=game.State.PAUSED or game.director.damage.health>=game.director.damage.maximum:
		return
	repair_available = false
	game.director.damage.restore_fraction(float(config.repair.health_fraction))
	status.text = "Repair applied."
	refresh()

func _trial_candidate() -> String:
	for id: String in config.trial.eligible:
		if not SaveService.owns(id):
			return id
	return ""

func refresh() -> void:
	if not is_instance_valid(status):
		return
	for kind: String in buttons:
		var button: Button = buttons[kind]
		button.visible = (origin==game.State.RESULTS if kind=="double" else (origin==game.State.CRASHED if kind=="revive" else origin in [game.State.HOME,game.State.PAUSED]))
		button.disabled = not eligible(kind) or ads.pending!=0
		if kind=="trial" and not _trial_candidate().is_empty():
			button.text = String(RushVehicleCatalog.definition(_trial_candidate()).name)+" / WATCH AD"
	repair_button.visible = origin==game.State.PAUSED and repair_available
	continue_button.text = "RACE" if prepared else "BACK"
	double_button.visible = eligible("double")
	double_button.disabled = ads.pending!=0
	result_retry.visible = game.state==game.State.RESULTS and ads.pending!=0 and ads.earned
	var offer_text: String = "WATCH AD — 2× COLLECTED COINS (+%d)"%int(game.run.result.get("road_coins",0))
	double_button.text = offer_text
	if buttons.has("double"):
		buttons.double.text = offer_text
	revive_button.visible = true
	revive_button.disabled = not eligible("revive") or ads.pending!=0
	give_up_button.disabled = ads.pending!=0
	crash_retry.visible = game.state==game.State.CRASHED and ads.pending!=0 and ads.earned
	crash_stats.text = "%.2f KM  •  %d COINS COLLECTED"%[game.run.distance/1000.0,game.run.run_coins]

func _physics_process(delta: float) -> void:
	if game!=null and game.state==game.State.DRIVING and not get_tree().paused:
		game.director.damage.grace_left = maxf(0,game.director.damage.grace_left-delta)

func back() -> void:
	if ads.pending!=0:
		status.text = "Complete or close the current ad before continuing."
		return
	game.go_home()
