class_name RushDamageController
extends RefCounted
signal damaged(amount: float, stage: int)
signal restored
signal destroyed
var shield_ready: bool = false
var shield_threshold: float = 8.0
var grace_left: float = 0.0
var health: float = 100.0
var maximum: float = 100.0
var resistance: float = 1.0
var stage: int = 0
var enabled: bool = false
func reset(id: String) -> void:
	shield_ready = false
	grace_left = 0.0
	maximum = 100.0
	resistance = clampf(float(RushVehicleCatalog.definition(id).get("durability_multiplier",1.0)),1.0,1.75)
	health = maximum
	stage = 0
	enabled = false
func apply_contact(relative_speed: float, normal: Vector3, forward: Vector3, object_type: String) -> void:
	if not enabled or grace_left>0 or health<=0 or relative_speed<2.0:
		return
	var frontal: float = absf(normal.normalized().dot(forward.normalized()))
	# Normal major impacts (~45 m/s normal closing speed) cost ~19 HP before resistance.
	# Extreme impacts still hurt; no price-based immunity.
	var amount: float = clampf((3.0+relative_speed*relative_speed*.008)*lerpf(.35,1.0,frontal)*(1.12 if object_type=="barrier" else 1.0),.5,45.0)/resistance
	# Short controller backstop; existing vehicle contact debouncing remains.
	grace_left = .22
	if shield_ready and amount>=shield_threshold:
		shield_ready = false
		return
	health = maxf(0,health-amount)
	var fraction: float = health/maximum
	stage = 4 if health<=0 else (3 if fraction<=.25 else (2 if fraction<=.5 else (1 if fraction<=.75 else 0)))
	damaged.emit(amount,stage)
	if health<=0:
		enabled = false
		destroyed.emit()

func restore_fraction(value: float) -> void:
	health = minf(maximum,health+maximum*clampf(value,0,1))
	var fraction: float = health/maximum
	stage = 3 if fraction<=.25 else (2 if fraction<=.5 else (1 if fraction<=.75 else 0))
	restored.emit()
