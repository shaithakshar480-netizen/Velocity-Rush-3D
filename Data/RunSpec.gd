class_name RunSpec
extends Resource
## Highway Rush balance. Distances are meters and speeds are meters/second.
@export var distance_m: float = 8000.0
@export var countdown_step: float = 0.8
@export var finish_seconds: float = 2.8
@export var coin_value: int = 1
@export var completion_reward: int = 300
@export var performance_cap: int = 300
@export var score_per_meter: float = 0.15
@export var high_speed_kmh: float = 150.0
@export var high_speed_score_per_second: float = 12.0
@export var near_miss_score: int = 150
@export var near_miss_min_kmh: float = 85.0
@export var near_miss_min_gap: float = 0.12
@export var near_miss_max_gap: float = 1.25
@export var combo_seconds: float = 7.0
@export var combo_cap: int = 5
@export var traffic_pool_size: int = 24
@export var early_traffic_count: int = 7
@export var late_traffic_count: int = 18
@export var traffic_min_speed: float = 17.0
@export var traffic_max_speed: float = 32.0
@export var spawn_min_ahead: float = 260.0
@export var reaction_seconds: float = 5.0
@export var lane_headway: float = 2.4
@export var coin_pool_size: int = 40
@export var coin_budget: int = 360
@export var pattern_interval: float = 190.0
@export var coin_spacing: float = 12.0
