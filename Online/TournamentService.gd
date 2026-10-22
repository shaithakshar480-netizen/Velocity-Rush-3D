class_name RushTournamentService
extends RefCounted
const STATUSES: Array[String] = ["UPCOMING","OPEN","IN_PROGRESS","FINISHED","CLAIMED"]
var online: RushOnlineService
var server_events: Array[Dictionary] = []
## Never expose template data as active events or grant local wallet rewards.
func refresh() -> bool:
	return online!=null and online.request("list_tournaments")
func enter(tournament_id: String) -> bool:
	return online!=null and online.request("enter_tournament",{"tournament_id":tournament_id})
func claim(tournament_id: String, result_id: String) -> bool:
	if online==null or tournament_id.is_empty() or result_id.is_empty():
		return false
	# Trusted backend verifies account, placement, result ownership and idempotent claim.
	# No placement supplied by UI; no local currency/XP grant path.
	return online.request("claim_tournament",{"tournament_id":tournament_id,"player_id":online.account_id,"result_id":result_id})
static func event_template() -> Dictionary:
	return {"tournament_id":"","title":"","start_time":0,"end_time":0,"entry_requirement":{},"race_rules":{},"leaderboard":[],"reward_table":[],"status":"UPCOMING","current_round":0,"placement":0,"qualified":false}
func accept_events(sender: Object, events: Array[Dictionary]) -> bool:
	if online==null or not online.is_online() or sender!=online.provider:
		return false
	var accepted: Array[Dictionary] = []
	for event: Dictionary in events:
		if String(event.get("tournament_id","")).is_empty() or String(event.get("status","")) not in STATUSES or bool(event.get("template_only",false)):
			continue
		accepted.append(event.duplicate(true))
	server_events = accepted
	return true
