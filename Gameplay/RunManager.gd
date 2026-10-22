class_name RushRunManager
extends Node
signal telemetry(snapshot: Dictionary)
signal abandoned(run_id: int)
signal countdown_changed(text: String)
signal started
signal finished
signal results_ready(summary: Dictionary, saved: bool)
signal near_miss_awarded(combo: int)
signal coin_awarded(value: int)
enum RunState { PREPARING, COUNTDOWN, RUNNING, FINISHED }
@export var spec: RunSpec = preload("res://Data/HighwayRush.tres")
var state: RunState = RunState.PREPARING
var race_mode: String = "five_racer"
var difficulty: int = 1 # Race setup only; never changes economy or multiplayer.
var opponents: RushRaceOpponents
var car: ArcadeVehicle
var course: RushSampledCourse
var course_pickups: RushCoursePickups
var run_id: int = 0
var distance: float = 0.0
var furthest: float = 0.0
var origin_offset: float = 0.0
var elapsed: float = 0.0
var score: float = 0.0
var run_coins: int = 0
var near_misses: int = 0
var combo: int = 0
var best_combo: int = 0
var combo_left: float = 0.0
var high_speed_seconds: float = 0.0
var countdown_left: float = 0.0
var countdown_number: int = 0
var finish_left: float = 0.0
var result: Dictionary = {}
var reward_saved: bool = false
var suspended: bool = false
var previous_z: float = 0.0
var previous_x: float = 0.0
var telemetry_clock: float = 0.0
var actual_distance: float = 0.0
var highest_speed: float = 0.0
var turbo_activations: int = 0
var collision_count: int = 0
var pickup_count: int = 0
var traffic: Node
var coins: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 20

func prepare() -> bool:
	suspended = false
	cancel()
	run_id = SaveService.reserve_run()
	if run_id == 0:
		return false
	state = RunState.PREPARING
	distance = 0.0
	furthest = 0.0
	origin_offset = 0.0
	elapsed = 0.0
	actual_distance = 0.0
	highest_speed = 0.0
	turbo_activations = 0
	collision_count = 0
	pickup_count = 0
	telemetry_clock = 0.0
	score = 0.0
	run_coins = 0
	near_misses = 0
	combo = 0
	best_combo = 0
	combo_left = 0.0
	high_speed_seconds = 0.0
	result.clear()
	reward_saved = false
	finish_left = 0.0
	previous_z = car.position.z
	previous_x = car.position.x
	countdown_left = spec.countdown_step*3.0
	countdown_number = 3
	return true

func cancel() -> void:
	if state == RunState.RUNNING:
		checkpoint()
		abandoned.emit(run_id)
	suspended = false
	state = RunState.PREPARING
	countdown_changed.emit("")
	combo = 0

func begin_countdown() -> void:
	if state != RunState.PREPARING or run_id<=0:
		return
	state = RunState.COUNTDOWN
	countdown_changed.emit("3")
	GameAudio.event("countdown")

func advance_countdown(delta: float) -> void:
	if state == RunState.COUNTDOWN:
		countdown_left -= delta
		var number := int(ceil(maxf(countdown_left,0.0)/spec.countdown_step))
		if number != countdown_number:
			countdown_number = number
			if number > 0:
				countdown_changed.emit(str(number))
				GameAudio.event("countdown")
			else:
				state = RunState.RUNNING
				countdown_changed.emit("GO!")
				GameAudio.event("go")
				started.emit()
		return

func _physics_process(delta: float) -> void:
	if suspended:
		return
	if state == RunState.FINISHED:
		finish_left -= delta
		if finish_left <= 0.0 and finish_left+delta > 0.0:
			results_ready.emit(result,reward_saved)
		return
	if state != RunState.RUNNING:
		return
	if traffic != null:
		traffic.evaluate_passes()
	if coins != null:
		if course_pickups!=null: course_pickups.refresh_queries()
		coins.evaluate_pickups()
	elapsed += delta
	if elapsed > 0.8 and countdown_number == 0:
		countdown_number = -1
		countdown_changed.emit("")
	# Net route coordinate + high-water mark: reversing cannot farm distance score.
	var forward_step: float = maxf(course.distance_at_z(car.position.z)-course.distance_at_z(previous_z),0.0) if course!=null else maxf(previous_z-car.position.z,0.0)
	# Reject position jumps and implausible vehicle speed from career telemetry.
	var speed := car.speed_kmh()
	var ceiling := car.spec.turbo.top_speed_kmh+5.0
	var displacement := Vector2(previous_x-car.position.x,previous_z-car.position.z).length()
	if is_finite(speed) and speed<=ceiling and displacement<=ceiling/3.6*delta+0.15:
		actual_distance += forward_step
		if forward_step>0.001 and absf(displacement/delta*3.6-speed)<8.0:
			highest_speed = maxf(highest_speed,minf(speed,ceiling))
	previous_z = car.position.z
	previous_x = car.position.x
	distance = clampf(course.distance_at_z(car.position.z) if course!=null else origin_offset-car.position.z,0.0,spec.distance_m)
	var new_distance := maxf(distance-furthest,0.0)
	furthest = maxf(furthest,distance)
	score += new_distance*spec.score_per_meter
	if car.speed_kmh() >= spec.high_speed_kmh and car.velocity.z < -1.0 and new_distance > 0.001:
		var moving_time := minf(delta,new_distance/maxf(forward_step,0.001)*delta)
		high_speed_seconds += moving_time
		score += moving_time*spec.high_speed_score_per_second
	combo_left = maxf(combo_left-delta,0.0)
	if combo_left <= 0.0:
		combo = 0
	telemetry_clock += delta
	if telemetry_clock>=1.0:
		telemetry_clock = 0.0
		checkpoint()
	if distance >= spec.distance_m:
		_finish()

func progress() -> float:
	return clampf(distance/spec.distance_m,0.0,1.0)

func collect_coin() -> void:
	if state != RunState.RUNNING:
		return
	pickup_count += 1
	run_coins += spec.coin_value
	coin_awarded.emit(spec.coin_value)
	checkpoint()
	GameAudio.event("coin")

func award_near_miss() -> void:
	if state != RunState.RUNNING:
		return
	combo = mini(combo+1,spec.combo_cap)
	best_combo = maxi(best_combo,combo)
	combo_left = spec.combo_seconds
	near_misses += 1
	score += spec.near_miss_score*combo
	near_miss_awarded.emit(combo)
	checkpoint()
	GameAudio.event("near_miss")

func on_impact(_strength: float) -> void:
	combo = 0
	combo_left = 0.0

func calculate_rewards() -> Dictionary:
	var performance_bonus := mini(spec.performance_cap,int(score/30.0)+near_misses*8+int(high_speed_seconds/3.0))
	var finish_place := opponents.place() if race_mode=="five_racer" and opponents!=null else 0
	var completion := spec.completion_reward
	if finish_place>0:
		completion = int(RushDrivingData.get_data().five_racer_rewards[finish_place-1].coins)
		performance_bonus = 0
	return {"racers":opponents.results_rows() if finish_place>0 else [],"race_mode":race_mode,"finish_place":finish_place,"highest_speed":highest_speed,"run_id": run_id, "distance": distance, "score": int(score), "road_coins": run_coins,
		"near_misses": near_misses, "best_combo": best_combo, "high_speed_seconds": high_speed_seconds,
		"elapsed": elapsed, "turbo_activations": turbo_activations, "performance_bonus": performance_bonus, "completion_bonus": completion,
		"total": run_coins+performance_bonus+completion}

func _finish() -> void:
	if state != RunState.RUNNING:
		return
	checkpoint()
	state = RunState.FINISHED
	finish_left = spec.finish_seconds
	result = calculate_rewards()
	retry_reward(false)
	countdown_changed.emit("FINISH!")
	GameAudio.event("finish")
	finished.emit()

func give_up() -> void:
	if state!=RunState.RUNNING or not suspended or race_mode not in ["highway_rush","five_racer"]: return
	checkpoint()
	state = RunState.FINISHED
	suspended = false
	finish_left = 0.0
	result = calculate_rewards()
	result["completed"] = false
	result["racers"] = []
	result["finish_place"] = 0
	result["completion_bonus"] = 0
	result["performance_bonus"] = 0
	result["total"] = run_coins
	retry_reward(false)
	results_ready.emit(result,reward_saved)

func retry_reward(notify: bool = true) -> void:
	if state != RunState.FINISHED or result.is_empty():
		return
	if not reward_saved:
		reward_saved = SaveService.is_settled(run_id) or SaveService.add_coins(int(result["total"]),run_id,result)
	if reward_saved and int(SaveService.wallet.receipt.get("run_id",0))==run_id:
		result = SaveService.wallet.receipt.summary.duplicate(true)
	if notify:
		results_ready.emit(result,reward_saved)

func rebase(shift: Vector3) -> void:
	origin_offset -= shift.z
	previous_z -= shift.z
	previous_x -= shift.x

func diagnostics() -> Dictionary:
	return {"state": state, "run_id": run_id, "progress": progress(), "score": int(score),
		"run_coins": run_coins, "combo": combo, "reward_saved": reward_saved}

func checkpoint() -> void:
	if state!=RunState.RUNNING:
		return
	telemetry.emit({"run_id":run_id,"distance":actual_distance,"play_time":elapsed,
		"road_coins":run_coins,"pickups":pickup_count,"near_misses":near_misses,
		"turbo_activations":turbo_activations,"collisions":collision_count,
		"cumulative_score":int(score),"best_score":int(score),"best_combo":best_combo,"highest_speed":highest_speed})

func record_turbo() -> void:
	if state==RunState.RUNNING:
		turbo_activations += 1
		checkpoint()

func record_collision(_strength: float) -> void:
	if state==RunState.RUNNING:
		collision_count += 1
		checkpoint()
