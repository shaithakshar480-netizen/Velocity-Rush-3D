class_name RushOnlineService
extends RefCounted
## Provider must own authentication, transport validation and server authority.
## Node.connect/disconnect names are intentionally not overridden.
var provider: Object
var account_id: String = ""
var session: RushNetworkRaceSession = RushNetworkRaceSession.new()
func is_online() -> bool:
	return is_instance_valid(provider) and provider.has_method("is_online") and bool(provider.call("is_online")) and not account_id.is_empty()
func connect_service() -> bool:
	return is_instance_valid(provider) and provider.has_method("connect_service") and bool(provider.call("connect_service"))
func disconnect_service() -> void:
	leave_match()
	if is_instance_valid(provider) and provider.has_method("disconnect_service"):
		provider.call("disconnect_service")
	account_id = ""
func request(method: String, payload: Dictionary = {}) -> bool:
	return is_online() and provider.has_method(method) and bool(provider.call(method,payload))
func create_match() -> bool:
	return request("create_match",{"room_size":5})
func join_match(match_id: String) -> bool:
	return request("join_match",{"match_id":match_id})
func leave_match() -> void:
	request("leave_match")
	session = RushNetworkRaceSession.new()
func start_match() -> bool:
	return session.can_start() and request("start_match",{"match_id":session.match_id})
func send_player_input(input: Dictionary) -> bool:
	return session.can_start() and request("send_player_input",input)
func send_vehicle_state(state: RushNetworkRacerState) -> bool:
	return state!=null and state.player_id==account_id and session.can_start() and request("send_vehicle_state",{"state":state.packet()})
func receive_vehicle_state(state: RushNetworkRacerState) -> bool:
	return is_online() and session.receive_vehicle_state(state,account_id)
func report_finish() -> bool:
	return session.can_start() and request("report_finish",{"match_id":session.match_id})
func display_name() -> String:
	var value: String = String(SaveService.progression.get("name","")).strip_edges()
	return "YOU" if value.is_empty() else value
func accept_session(sender: Object, match_id: String, participants: Dictionary, ready: Array[String], confirmed: bool) -> bool:
	if sender!=provider or not is_online() or match_id.is_empty() or participants.size()>5 or not participants.has(account_id):
		return false
	for id: Variant in participants:
		if not id is String or String(id).is_empty() or not participants[id] is Dictionary:
			return false
	session.match_id = match_id
	session.participants = participants.duplicate(true)
	session.ready_ids = ready.duplicate()
	session.server_start_confirmed = confirmed
	return true
