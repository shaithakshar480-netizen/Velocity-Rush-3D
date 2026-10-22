class_name RushRaceDifficulty
extends RefCounted
## No reward multiplier, player-stat mutation, teleporting or persistent AI inventory.
static func profile(level: int) -> Dictionary:
	return [
		{"pace":.86,"decision":1.5,"headway":1.3,"gap":1.2,"acceleration":.82,"mistake":.24,"recovery":2.0,"density":.72,"boosts":1,"boost_after":28.0,"boost_duration":2.2,"lane_time":2.2},
		{"pace":.96,"decision":1.0,"headway":1.1,"gap":1.1,"acceleration":.95,"mistake":.12,"recovery":1.2,"density":1.0,"boosts":2,"boost_after":20.0,"boost_duration":3.0,"lane_time":1.9},
		{"pace":1.0,"decision":.72,"headway":1.0,"gap":1.0,"acceleration":1.0,"mistake":.035,"recovery":.7,"density":1.12,"boosts":2,"boost_after":14.0,"boost_duration":3.8,"lane_time":1.6}
	][clampi(level,0,2)]
