class_name RushCameraImpulse
extends RefCounted
## Bounded one-shot displacement; no continuous random vibration.
var remaining: float = 0.0
var duration: float = 0.3
var amplitude: float = 0.0
var clock: float = 0.0
func trigger(strength: float, seconds: float = 0.3) -> void:
	amplitude = maxf(amplitude,clampf(strength,0.0,0.10))
	duration = clampf(seconds,0.1,0.6)
	remaining = duration
	clock = 0.0
func tick(delta: float) -> Vector3:
	if remaining <= 0.0:
		return Vector3.ZERO
	remaining = maxf(0.0,remaining-delta)
	clock += delta
	var envelope := pow(remaining/duration,2.0)
	var value := Vector3(sin(clock*TAU*5.0),sin(clock*TAU*4.0)*0.4,0.0)*amplitude*envelope
	if remaining == 0.0:
		amplitude = 0.0
	return value
func reset() -> void:
	remaining = 0.0
	amplitude = 0.0
