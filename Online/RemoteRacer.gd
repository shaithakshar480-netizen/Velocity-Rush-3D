class_name RushRemoteRacer
extends Node3D
## Visual-only interpolation target. No local input or vehicle physics applied here.
var before: RushNetworkRacerState
var after: RushNetworkRacerState
var blend_time: float = 0.0
var snapshot_interval: float = 1.0/15.0
func accept_snapshot(state: RushNetworkRacerState) -> void:
	if state==null or (after!=null and state.sequence<=after.sequence):
		return
	before = after if after!=null else state
	after = state
	blend_time = 0.0
func _process(delta: float) -> void:
	if before==null or after==null:
		return
	blend_time = minf(blend_time+delta,snapshot_interval)
	global_transform = before.interpolate(after,blend_time/snapshot_interval)
