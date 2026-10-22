class_name RushRoadFrame
extends RefCounted
## Authoritative straight-highway coordinates. All contact/coin heights use this frame.
const SURFACE_Y: float = 0.0
const LANE_WIDTH: float = 4.0
const LANE_CENTERS: Array[float] = [-6.0,-2.0,2.0,6.0]
const ROAD_HALF_WIDTH: float = 10.0
const BARRIER_X: float = 9.7
const COIN_HEIGHT: float = 1.15
const COLLISION_LENGTH: float = 20000.0

static func lane_point(lane: int, z: float, height: float = 0.0) -> Vector3:
	return Vector3(LANE_CENTERS[clampi(lane,0,3)],SURFACE_Y+height,z)

static func transition_point(from_lane: int, to_lane: int, t: float, z: float) -> Vector3:
	var u := clampf(t,0.0,1.0)
	var eased := u*u*(3.0-2.0*u)
	return Vector3(lerpf(LANE_CENTERS[from_lane],LANE_CENTERS[to_lane],eased),SURFACE_Y+COIN_HEIGHT,z)
