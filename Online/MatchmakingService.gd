class_name RushMatchmakingService
extends RefCounted
var online: RushOnlineService
var searching: bool = false
func quick_match() -> bool:
	if online==null or searching or not online.is_online():
		return false
	searching = online.request("quick_match",{"room_size":5,"display_name":online.display_name()})
	return searching
func cancel_search() -> void:
	if online!=null:
		online.request("cancel_search")
		online.leave_match()
	searching = false
func status_text() -> String:
	if online==null or not online.is_online():
		return "Online service not connected yet."
	if online.session.can_start():
		return "READY"
	return "SEARCHING FOR RACERS  %d / 5"%online.session.participants.size() if searching else "QUICK MATCH"
