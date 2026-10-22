class_name VehicleSpec
extends Resource
## SI units internally. Economy metadata only: no future services are instantiated.
@export var vehicle_id: String = "vortex_s"
@export var display_name: String = "Vortex S"
@export var top_speed_kmh: float = 210.0
@export var acceleration: float = 11.5
@export var braking: float = 24.0
@export var reverse_speed_kmh: float = 28.0
@export var reverse_acceleration: float = 5.0
@export var steering_low_degrees: float = 31.0
@export var steering_high_degrees: float = 6.0
@export var steering_response: float = 6.5
@export var wheelbase: float = 2.65
@export var grip: float = 11.0
@export var weight_kg: float = 1280.0
@export var rolling_drag: float = 0.55
@export var air_drag: float = 0.0015
@export var gravity: float = 22.0
@export var suspension_travel: float = 0.18
@export var wheel_radius: float = 0.34
@export var turbo: RushTurboSpec = preload("res://Data/VortexTurbo.tres")
@export var camera_anchors: Array[Vector3] = [Vector3(0,3.2,7.1),Vector3(0,5.4,11.8),Vector3(0,1.04,-1.14),Vector3(0,0.54,-2.32),Vector3(-.30,1.12,-.25)]
@export var exhaust_points: Array[Vector3] = [Vector3(-0.62,0.40,2.01),Vector3(0.62,0.40,2.01)]
@export var unlock_information: Dictionary = {}
@export var upgrade_information: Dictionary = {}
