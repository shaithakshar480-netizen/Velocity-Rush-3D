class_name RushTransmission
extends RefCounted
signal shifted(gear: int)
var gear: int = 1
var rpm: float = 900.0
var shift_left: float = 0.0
var hold: float = 0.0
var config: Dictionary
func _init() -> void:
	config = RushDrivingData.get_data().transmission
func configure(id: String) -> void:
	config = RushDrivingData.get_data().transmission.duplicate(true)
	var overrides: Dictionary = RushDrivingData.get_data().get("vehicle_transmissions",{}).get(id,{})
	config.merge(overrides,true)
	reset()
func reset() -> void:
	gear = 1
	rpm = float(config.idle_rpm)
	shift_left = 0.0
	hold = 0.0
func tick(delta: float, speed: float, throttle: float, ceiling: float) -> float:
	shift_left = maxf(0,shift_left-delta)
	hold = maxf(0,hold-delta)
	var caps: Array = config.speed_fractions
	var upper := maxf(ceiling*float(caps[gear-1]),1)
	if shift_left<=0 and hold<=0:
		if speed>upper*.94 and gear<caps.size():
			_change(gear+1)
		elif gear>1 and speed<ceiling*float(caps[gear-2])*.64:
			_change(gear-1)
	var target := lerpf(float(config.idle_rpm),float(config.redline_rpm),clampf(maxf(speed,0)/maxf(ceiling*float(caps[gear-1]),1),0,1))
	if speed<2 and throttle>0:
		target = 1800.0
	rpm = lerpf(rpm,target,1-exp(-12*delta))
	return float(config.torque[gear-1])*(0.15 if shift_left>0 else 1.0)
func _change(next: int) -> void:
	gear = next
	shift_left = float(config.shift_seconds)
	hold = float(config.minimum_hold)
	rpm *= .69
	shifted.emit(gear)
