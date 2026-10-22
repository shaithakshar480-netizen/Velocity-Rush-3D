class_name RushHaptics
extends RefCounted
static var last_event_ms: int = -1000
static func pulse(milliseconds: int) -> void:
	if not OS.has_feature("android") or not bool(SaveService.settings["vibration"]):
		return
	var now := Time.get_ticks_msec()
	if now-last_event_ms < 180:
		return
	last_event_ms = now
	Input.vibrate_handheld(clampi(milliseconds,15,100))
