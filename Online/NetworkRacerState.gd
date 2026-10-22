class_name RushNetworkRacerState
extends RefCounted
## One essential-state snapshot; cosmetic nodes are never synchronized.
var player_id: String = ""
var display_name: String = ""
var car_id: String = "vortex_s"
var paint: int = 0
var position: Vector3 = Vector3.ZERO
var rotation: Quaternion = Quaternion.IDENTITY
var velocity: Vector3 = Vector3.ZERO
var speed: float = 0.0
var lap: int = 0
var checkpoint: int = 0
var race_progress: float = 0.0
var finished: bool = false
var finish_time: float = -1.0
var sequence: int = 0
func interpolate(other: RushNetworkRacerState, weight: float) -> Transform3D:
	return Transform3D(Basis(rotation.slerp(other.rotation,clampf(weight,0,1))),position.lerp(other.position,clampf(weight,0,1)))
func packet() -> Array:
	return [sequence,player_id,position.snapped(Vector3.ONE*.01),rotation,velocity.snapped(Vector3.ONE*.1),speed,lap,checkpoint,race_progress,finished,finish_time]
