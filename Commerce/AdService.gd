class_name RushAdService
extends Node
## Policy/receipt boundary. Existing RewardedAdService owns atomic Save settlement.
const REWARDED: PackedStringArray = ["TURBO_REFILL","STORE_turbo","STORE_repair","STORE_magnet","STORE_shield","POWERUP_turbo","POWERUP_repair","POWERUP_magnet","POWERUP_shield","POWERUP_double","POWERUP_revive","POWERUP_trial","GARAGE_UPGRADE"]
const SAFE_SCREENS: PackedStringArray = ["home","store","garage","results","powerups","turbo_store","pause","crashed"]
var game: Node
var provider: RushAdProvider
var config: Dictionary = {}
var attempted: bool = false
var sdk_ready: bool = false
var reward_ready: bool = false
var interstitial_ready: bool = false
var foreground: bool = true
static var ticket_counter: int = 0
var active: Dictionary = {}
var fullscreen: bool = false
var fullscreen_ticket: int = 0
var shield: Control
var privacy_started: int = 0
var audio_owned: bool = false
var previous_mute: bool = false
var next_preload: int = 0
var next_initialize: int = 0
var clock: float = 0.0
var completed: int = 0
var last_result_key: String = ""
var last_interstitial: int = 0
var privacy_button: Button

func build(owner_game: Node) -> void:
	game = owner_game
	process_mode = Node.PROCESS_MODE_ALWAYS
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://Data/AdsConfig.json"))
	if not decoded is Dictionary: return
	var mode: String = String(decoded.get("mode",""))
	if mode not in ["TEST","PRODUCTION"]: return
	var selected: Variant = decoded.get("test" if mode=="TEST" else "production",{})
	if not selected is Dictionary: return
	if mode=="PRODUCTION" and selected.get("privacy_setup_complete",false)!=true: return
	config = selected.duplicate(true)
	config.mode = mode
	config.cooldown = maxi(120,int(decoded.get("interstitial_cooldown_seconds",120)))*1000
	config.min_races = maxi(2,int(decoded.get("interstitial_min_completed_races",2)))
	for key: String in ["app_id","rewarded_id","interstitial_id"]:
		if not config.get(key) is String or String(config[key]).is_empty():
			config.clear()
			return
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	shield = Control.new()
	layer.add_child(shield)
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	shield.hide()
	provider = RushAdProvider.new()
	add_child(provider)
	provider.event.connect(_event)
	game.director.ads.provider = self
	# Required UMP withdrawal entry; no debug controls or Store redesign.
	privacy_button = Button.new()
	privacy_button.text = "AD PRIVACY"
	privacy_button.visible = false
	game.shop.header_panel.get_child(0).add_child(privacy_button)
	privacy_button.pressed.connect(_privacy)

func _safe() -> bool:
	if not is_instance_valid(game) or not game.ready_for_drive or not foreground or AuthService.busy or SaveService.transaction_busy: return false
	if game.state in [game.State.SPLASH,game.State.DRIVING,game.State.FINISHING,game.State.NETWORK,game.State.ONBOARDING]: return false
	if game.ui.screen not in SAFE_SCREENS: return false
	if game.online_ui!=null and game.online_ui.duel.phase!="OFFLINE": return false
	if not game.shop.purchases.pending.is_empty() or game.shop.purchases.settling or game.shop.membership.pending: return false
	return true

func _process(delta: float) -> void:
	clock += delta
	if clock<0.2: return
	clock = 0.0
	var now: int = Time.get_ticks_msec()
	if privacy_started>0 and now-privacy_started>180000:
		privacy_started = 0
		fullscreen = false
		shield.hide()
		_restore_audio()
	if not active.is_empty():
		if not _context_valid() or now-int(active.started)>180000:
			_cancel()
	if config.is_empty() or not _safe() or fullscreen or not active.is_empty(): return
	if not attempted or (not sdk_ready and now>=next_initialize):
		attempted = true
		next_initialize = now+60000
		if config.mode=="PRODUCTION":
			fullscreen = true
			privacy_started = now
			shield.show()
		if not provider.initialize(config):
			fullscreen = false
			privacy_started = 0
			shield.hide()
		return
	if sdk_ready and now>=next_preload:
		next_preload = now+60000
		provider.preload_ads()

func can_request_rewarded(placement: String) -> bool:
	return placement in REWARDED and _placement_allowed(placement) and _safe() and not fullscreen and active.is_empty() and reward_ready

func availability() -> String:
	if config.is_empty() or not sdk_ready: return "UNAVAILABLE"
	if fullscreen or not active.is_empty(): return "BUSY"
	return "READY" if reward_ready else "LOADING"

func request_rewarded(receipt: int, earned_callback: Callable, closed_callback: Callable, placement: String = "TURBO_REFILL") -> void:
	if placement not in REWARDED or not _placement_allowed(placement) or receipt<=0 or not earned_callback.is_valid() or not closed_callback.is_valid() or not _safe() or fullscreen or not active.is_empty() or not reward_ready:
		if closed_callback.is_valid(): closed_callback.call(receipt)
		return
	_start(placement,true,receipt,earned_callback,closed_callback)

func _placement_allowed(placement: String) -> bool:
	if not is_instance_valid(game): return false
	var screen: String = game.ui.screen
	if placement=="POWERUP_revive": return screen=="crashed" and game.state==game.State.CRASHED
	if placement=="POWERUP_double": return screen=="results" and game.state==game.State.RESULTS
	if placement.begins_with("STORE_"): return screen=="store"
	if placement=="GARAGE_UPGRADE": return screen=="garage"
	if placement=="TURBO_REFILL": return screen=="turbo_store"
	return placement.begins_with("POWERUP_") and screen=="powerups"

func _input(_event_input: InputEvent) -> void:
	if fullscreen: get_viewport().set_input_as_handled()

func _start(placement: String, rewarded: bool, receipt: int = 0, earned_callback: Callable = Callable(), closed_callback: Callable = Callable()) -> void:
	ticket_counter += 1
	active = {"ticket":ticket_counter,"scope":SaveService.scope_generation,"placement":placement,"scene":game.ui.screen,"receipt":receipt,"earned":false,"rewarded":rewarded,"success":earned_callback,"failure":closed_callback,"started":Time.get_ticks_msec()}
	if rewarded: reward_ready = false
	else: interstitial_ready = false
	fullscreen_ticket = ticket_counter
	shield.show()
	fullscreen = true # includes the asynchronous show request, prevents overlapping taps.
	provider.show_ad(ticket_counter,placement,rewarded)

func on_results(saved: bool) -> void:
	if not saved or game.run.race_mode in ["multiplayer","tournament"]: return
	var key: String = "%d:%d"%[SaveService.scope_generation,game.run.run_id]
	if key==last_result_key: return
	last_result_key = key
	completed += 1
	call_deferred("_results_ad",key)

func _results_ad(key: String) -> void:
	if key!=last_result_key or not _safe() or game.ui.screen!="results" or not game.run.reward_saved: return
	if config.is_empty() or completed<int(config.min_races) or Time.get_ticks_msec()-last_interstitial<int(config.cooldown): return
	if not active.is_empty() or fullscreen or not interstitial_ready or game.director.ads.pending!=0: return
	# Conservative: even cached active/grace metadata suppresses forced ads.
	# This does not grant valuable entitlements or pretend to verify a purchase.
	if game.shop.membership.entitlement_state() in ["ACTIVE","GRACE_PERIOD"]: return
	last_interstitial = Time.get_ticks_msec()
	_start("RESULTS_INTERSTITIAL",false)

func _context_valid() -> bool:
	return not active.is_empty() and int(active.scope)==SaveService.scope_generation and not AuthService.busy and game.ui.screen==String(active.scene) and (game.online_ui==null or game.online_ui.duel.phase=="OFFLINE")

func _event(ticket: int, placement: String, state: String) -> void:
	if ticket==0:
		match state:
			"READY":
				sdk_ready = true
				next_preload = 0
				if privacy_started>0:
					privacy_started = 0
					fullscreen = false
					shield.hide()
					_restore_audio()
			"REWARDED_READY": reward_ready = true
			"INTERSTITIAL_READY": interstitial_ready = true
			"REWARDED_UNAVAILABLE": reward_ready = false
			"INTERSTITIAL_UNAVAILABLE": interstitial_ready = false
			"PRIVACY_REQUIRED": privacy_button.visible = true
			"PRIVACY_NOT_REQUIRED": privacy_button.visible = false
			"PRIVACY_OPENED": fullscreen = true; privacy_started = Time.get_ticks_msec(); shield.show(); _mute()
			"PRIVACY_CLOSED": fullscreen = false; privacy_started = 0; shield.hide(); _restore_audio(); next_preload = 0
			"UNAVAILABLE":
				sdk_ready = false
				reward_ready = false
				interstitial_ready = false
				if privacy_started>0:
					privacy_started = 0
					fullscreen = false
					shield.hide()
					_restore_audio()
		return
	if active.is_empty() or ticket!=int(active.ticket) or placement!=String(active.placement):
		if state in ["CLOSED","SHOW_FAILED"] and ticket==fullscreen_ticket:
			fullscreen = false
			fullscreen_ticket = 0
			shield.hide()
			_restore_audio()
		return
	match state:
		"OPENED": _mute()
		"EARNED":
			if _context_valid() and bool(active.rewarded): active.earned = true
		"CLOSED", "SHOW_FAILED":
			var context: Dictionary = active
			var deliver: bool = state=="CLOSED" and _context_valid() and bool(active.earned)
			active = {}
			fullscreen = false
			fullscreen_ticket = 0
			shield.hide()
			_restore_audio()
			next_preload = Time.get_ticks_msec()+30000
			if int(context.scope)==SaveService.scope_generation:
				var callback: Callable = context.success if deliver else context.failure
				if callback.is_valid(): callback.call(int(context.receipt))

func _cancel() -> void:
	var context: Dictionary = active
	active = {}
	provider.invalidate(int(context.ticket))
	# Native retains its fullscreen lock until actual dismissal. No second show.
	fullscreen = false
	shield.hide()
	_restore_audio()
	if int(context.scope)==SaveService.scope_generation:
		var callback: Callable = context.failure
		if callback.is_valid(): callback.call(int(context.receipt))

func _mute() -> void:
	if audio_owned: return
	previous_mute = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0,true)
	audio_owned = true
func _restore_audio() -> void:
	if audio_owned: AudioServer.set_bus_mute(0,previous_mute)
	audio_owned = false
func _privacy() -> void:
	if not _safe() or fullscreen or not active.is_empty(): return
	reward_ready = false
	interstitial_ready = false
	fullscreen = true
	privacy_started = Time.get_ticks_msec()
	shield.show()
	provider.privacy()
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_PAUSED:
		foreground = false
	elif what==NOTIFICATION_APPLICATION_RESUMED:
		foreground = true
		next_preload = 0
func _exit_tree() -> void:
	if not active.is_empty(): _cancel()
	_restore_audio()
