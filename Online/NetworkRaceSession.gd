class_name RushNetworkRaceSession
extends RefCounted
const ROOM_SIZE: int = 5
const SNAPSHOT_HZ: int = 15
var match_id: String = ""
var participants: Dictionary = {}
var ready_ids: Array[String] = []
var server_start_confirmed: bool = false
var remote_states: Dictionary = {}
var competitive_powerups_allowed: bool = false
func can_start() -> bool:
	if match_id.is_empty() or participants.size()!=ROOM_SIZE or not server_start_confirmed:
		return false
	for id: String in participants:
		if id not in ready_ids:
			return false
	return true
func receive_vehicle_state(state: RushNetworkRacerState, local_id: String) -> bool:
	if state==null or state.player_id==local_id or not participants.has(state.player_id):
		return false
	var previous: RushNetworkRacerState = remote_states.get(state.player_id)
	if previous!=null and state.sequence<=previous.sequence:
		return false
	remote_states[state.player_id] = state
	return true
