class_name RushAdProvider
extends Node
## Native events contain identity/state only. Never quantities or save data.
signal event(ticket: int, placement: String, state: String)
const CONTRACT: String = "rushads:v1:initialize,preload,showAd,invalidate,showPrivacyOptions,ad_event"
var native: Object
var configured: bool = false

func initialize(config: Dictionary) -> bool:
	if configured:
		native.call("initialize",String(config.mode),String(config.app_id),String(config.rewarded_id),String(config.interstitial_id))
		return true
	if OS.get_name()!="Android" or not Engine.has_singleton("RushAdsBridge"): return false
	native = Engine.get_singleton("RushAdsBridge")
	# JNI plugin dispatch is not represented by Object.has_method().
	var capabilities: Variant = native.call("getBridgeCapabilities")
	if not capabilities is String or capabilities!=CONTRACT: return false
	if not native.has_signal("ad_event"): return false
	if not native.is_connected("ad_event",_native_event):
		native.connect("ad_event",_native_event)
	configured = true
	native.call("initialize",String(config.mode),String(config.app_id),String(config.rewarded_id),String(config.interstitial_id))
	return true

func preload_ads() -> void:
	if configured: native.call("preload")
func show_ad(ticket: int, placement: String, rewarded: bool) -> void:
	if configured: native.call("showAd",ticket,placement,rewarded)
func invalidate(ticket: int) -> void:
	if configured: native.call("invalidate",ticket)
func privacy() -> void:
	if configured: native.call("showPrivacyOptions")
func _native_event(ticket: int, placement: String, state: String) -> void:
	event.emit(ticket,placement,state)
func _exit_tree() -> void:
	if is_instance_valid(native) and native.is_connected("ad_event",_native_event):
		native.disconnect("ad_event",_native_event)
