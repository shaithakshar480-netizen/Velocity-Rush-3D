class_name RushTrafficSystem
extends Node3D
signal near_miss_detail(gap: float, speed: float, at: Vector3)
signal passed(at: Vector3, relative_speed: float)
var opponents: Node
const LANES: Array[float] = RushRoadFrame.LANE_CENTERS
var pool: Array[RushTrafficVehicle] = []
var car: ArcadeVehicle
var run: RushRunManager
var course: RushSampledCourse
var coins: Node
var active: bool = false
var difficulty: int = 1
var tuning: Dictionary = RushRaceDifficulty.profile(1)
var lane_plans: Dictionary = {}
var escape_lane: int = 0
var rng := RandomNumberGenerator.new()
var spawn_clock: float = 0.0
var previous_player := Vector3.ZERO
var spawn_rejections: int = 0
var ready_for_drive: bool = false
var visual_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var visual_uses: Dictionary = {}
var recent_visuals: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -10
	RushTrafficMeshLibrary.prepare()
	visual_rng.randomize()
	var fleet: Array[String] = RushProductionTrafficVisual.IDS.duplicate()
	for i: int in range(fleet.size()-1,0,-1):
		var other: int = visual_rng.randi_range(0,i)
		var id: String = fleet[i]
		fleet[i] = fleet[other]
		fleet[other] = id
	for id: String in fleet:
		var prepared: bool = await RushProductionTrafficVisual.prepare(id,get_tree())
		if not prepared:
			push_error("Production traffic resource unavailable")
			return # Never silently replace a missing production asset with dummy traffic.
		await get_tree().process_frame
	for i: int in run.spec.traffic_pool_size:
		var traffic := RushTrafficVehicle.new()
		traffic.kind = i%5
		traffic.production_id = fleet[i%fleet.size()]
		traffic.viewer = car
		add_child(traffic)
		pool.append(traffic)
		await get_tree().process_frame
	ready_for_drive = true

func reset_pool(seed_value: int) -> void:
	tuning = RushRaceDifficulty.profile(difficulty)
	lane_plans.clear()
	active = false
	for traffic: RushTrafficVehicle in pool:
		traffic.deactivate()
		traffic.course = course
	visual_uses.clear()
	recent_visuals.clear()
	rng.seed = seed_value*7919+41
	escape_lane = rng.randi_range(0,3)
	spawn_clock = 0.75 # Stagger first activation after GO rather than coinciding with it.
	spawn_rejections = 0
	previous_player = car.position

func _physics_process(delta: float) -> void:
	if not active:
		return
	for traffic: RushTrafficVehicle in pool:
		if not traffic.active:
			continue
		traffic.previous_position = traffic.position
		traffic.previous_yaw = traffic.rotation.y
		traffic.horn_left = maxf(0,traffic.horn_left-delta)
		var allowed := traffic.desired_speed+(1.5 if traffic.horn_left>0 else 0.0)
		# Predictable lane following; never change lanes into a player's path.
		for ahead: RushTrafficVehicle in pool:
			if not ahead.active or ahead == traffic or absf(_route(ahead.position).x-_route(traffic.position).x)>2.7:
				continue
			var gap := _route(traffic.position).z-_route(ahead.position).z-traffic.half_length-ahead.half_length
			if gap > 0.0:
				allowed = minf(allowed,maxf(0.0,(gap-12.0)/(run.spec.lane_headway*float(tuning.headway))))
		# Do not drive straight through a stopped/reversing player ahead.
		var player_gap := _route(traffic.position).z-_route(car.position).z-traffic.half_length-2.0
		if absf(_route(traffic.position).x-_route(car.position).x)<2.4 and player_gap>0.0:
			allowed = minf(allowed,maxf(0.0,(player_gap-10.0)/2.0))
		if opponents!=null:
			allowed = minf(allowed,float(opponents.traffic_limit(traffic)))
		traffic.braking = allowed<traffic.speed-.4
		if (Engine.get_physics_frames() + traffic.get_instance_id()) % 4 == 0:
			traffic.update_distance_lod(car.position.distance_to(traffic.position))
		traffic.speed = move_toward(traffic.speed,allowed,(9.0 if allowed<traffic.speed else 3.0*float(tuning.acceleration))*delta)
		_update_lane(traffic,allowed,delta)
		traffic.position.y = RushRoadFrame.SURFACE_Y
		var next: Vector3 = _route(traffic.position)
		next.x = traffic.lane_offset
		next.z -= traffic.speed*delta
		traffic.position = _world(next)
		if course!=null: traffic.rotation.y = course.heading_at_z(traffic.position.z)
		if traffic.fade < 1.0:
			traffic.set_fade(minf(traffic.fade+delta*0.8,1.0))
		var ahead_distance := _route(car.position).z-_route(traffic.position).z
		# BUG-4 FIX: Do NOT use fixed [320, 420, 560] max_ahead that is smaller than high-speed
		# lookahead spawn distance (which reaches 450-550m+ at 180-250+ km/h). Otherwise, every car
		# spawned ahead at speed gets immediately deactivated on the next physics frame.
		var lookahead := maxf(run.spec.spawn_min_ahead, car.speed_kmh()/3.6*run.spec.reaction_seconds+100.0)
		var max_ahead: float = maxf(850.0, lookahead + 150.0)
		if ahead_distance < -65.0 or ahead_distance > max_ahead:
			traffic.deactivate()
	spawn_clock -= delta
	if run.state != RushRunManager.RunState.RUNNING:
		return
	if spawn_clock <= 0.0:
		# Slightly fuller Highway Rush only; retain difficulty and mobile caps.
		var mode_density: float = 1.2 if run.race_mode=="highway_rush" else 1.0
		var spawn_density: float = float(tuning.density)*mode_density
		spawn_clock = lerpf(1.2,0.65,run.progress())/spawn_density
		var quality: int = clampi(int(SaveService.settings.get("quality", 1)), 0, 2)
		var cap: int = [11, 15, 20][quality]
		var desired_count: int = mini(mini(pool.size(), cap), int(lerpf(run.spec.early_traffic_count, run.spec.late_traffic_count, run.progress()) * spawn_density))
		if active_count() < desired_count:
			_try_spawn()

func _try_spawn() -> bool:
	var available: RushTrafficVehicle = null
	var best: float = INF
	for traffic: RushTrafficVehicle in pool:
		if traffic.active: continue
		var id: String = traffic.production_id
		var score: float = float(visual_uses.get(id,0))*4.0+visual_rng.randf()
		if id in recent_visuals: score += 12.0
		if car.spec!=null and id==RushVehicleCatalog.canonical_id(car.spec.vehicle_id): score += 2.0
		for nearby: RushTrafficVehicle in pool:
			if nearby.active and nearby.production_id==id: score += 3.0
		if score<best:
			best = score
			available = traffic
	if available == null:
		return false
	var lookahead := maxf(run.spec.spawn_min_ahead,car.speed_kmh()/3.6*run.spec.reaction_seconds+100.0)
	for attempt: int in 10:
		var lane := rng.randi_range(0,3)
		var z := _route(car.position).z-lookahead-rng.randf_range(25.0,90.0)
		var speed: float = rng.randf_range(run.spec.traffic_min_speed,run.spec.traffic_max_speed+run.progress()*3.0)*[1.04,1.0,.96][clampi(difficulty,0,2)]
		if placement_safe(lane,z,speed):
			available.activate(_world(RushRoadFrame.lane_point(lane,z)),lane,speed)
			lane_plans[available.get_instance_id()] = {"target":lane,"from":lane,"blend":1.0,"clock":rng.randf_range(2,5)*float(tuning.decision)}
			visual_uses[available.production_id] = int(visual_uses.get(available.production_id,0))+1
			recent_visuals.append(available.production_id)
			if recent_visuals.size()>2: recent_visuals.pop_front()
			escape_lane = (escape_lane + 1) % LANES.size()
			return true
		spawn_rejections += 1
	return false

func placement_safe(lane: int, z: float, speed: float) -> bool:
	if lane == escape_lane or lane < 0 or lane >= LANES.size():
		return false
	var ahead := _route(car.position).z-z
	var safe_ahead := maxf(run.spec.spawn_min_ahead,car.speed_kmh()/3.6*run.spec.reaction_seconds+100.0)
	if ahead < safe_ahead or ahead > 800.0:
		return false
	var occupied := 0
	for traffic: RushTrafficVehicle in pool:
		if not traffic.active:
			continue
		var separation := absf(_route(traffic.position).z-z)
		if traffic.lane == lane and separation < maxf(65.0,maxf(speed,traffic.speed)*run.spec.lane_headway+12.0):
			return false
		if separation < 32.0:
			occupied += 1
	if occupied >= 2:
		return false
	if opponents!=null and not opponents.spawn_clear(LANES[lane],z):
		return false
	if coins != null and coins.traffic_conflicts(LANES[lane],z,speed):
		return false
	return true

func evaluate_passes() -> void:
	if not active or run.state != RushRunManager.RunState.RUNNING:
		previous_player = car.position
		return
	var relative_basis: Basis = Basis(Vector3.UP,-course.heading_at_z(car.position.z))*car.basis if course!=null else car.basis
	var car_width := absf(relative_basis.x.x)*car.half_width()+absf(relative_basis.z.x)*car.half_length()
	var car_length := absf(relative_basis.x.z)*car.half_width()+absf(relative_basis.z.z)*car.half_length()
	for traffic: RushTrafficVehicle in pool:
		if not traffic.active:
			continue
		var relative_before := _route(previous_player)-_route(traffic.previous_position)
		var relative_after := _route(car.position)-_route(traffic.position)
		var longitudinal := car_length+traffic.half_length
		var lateral := car_width+traffic.half_width
		if car.position.y > traffic.position.y+traffic.body_height or car.position.y+0.97 < traffic.position.y:
			continue
		# Swept relative AABB catches fast crossings in addition to physical contact.
		if not traffic.was_hit and _swept_overlap(relative_before,relative_after,lateral,longitudinal):
			traffic.mark_collision()
			var closing := absf(-_player_velocity().z-traffic.speed)
			car.respond_to_traffic(clampf(closing/28,.15,1),closing,Basis(Vector3.UP,course.heading_at_z(car.position.z)).z if course!=null else Vector3.BACK)
		# Reverse-direction overtake sound is independent of near-miss reward eligibility.
		if relative_before.z<=longitudinal+.8 and relative_after.z>longitudinal+.8 and absf(relative_after.x)<8.0:
			passed.emit(traffic.position,absf(-_player_velocity().z-traffic.speed))
		if traffic.pass_resolved:
			continue
		var range_low := minf(relative_before.z,relative_after.z)
		var range_high := maxf(relative_before.z,relative_after.z)
		if range_low <= longitudinal and range_high >= -longitudinal:
			var t := clampf(relative_before.z/maxf(relative_before.z-relative_after.z,0.0001),0.0,1.0)
			var gap := absf(lerpf(relative_before.x,relative_after.x,t))-lateral
			traffic.minimum_gap = minf(traffic.minimum_gap,gap)
			traffic.eligible_pass = traffic.eligible_pass or (car.speed_kmh()>=run.spec.near_miss_min_kmh and _player_velocity().z < -traffic.speed and car.position.y<0.7)
		# Award only after clearing the whole vehicle, never from proximity alone.
		if relative_before.z >= -longitudinal-0.8 and relative_after.z < -longitudinal-0.8:
			traffic.pass_resolved = true
			if absf(relative_after.x)<8.0:
				passed.emit(traffic.position,absf(-_player_velocity().z-traffic.speed))
			if traffic.eligible_pass and not traffic.was_hit and car.speed_kmh()>=run.spec.near_miss_min_kmh:
				if traffic.minimum_gap >= run.spec.near_miss_min_gap and traffic.minimum_gap <= run.spec.near_miss_max_gap:
					run.award_near_miss()
					near_miss_detail.emit(traffic.minimum_gap,car.speed_kmh(),traffic.position)
	previous_player = car.position

static func _swept_overlap(a: Vector3, b: Vector3, width: float, length: float) -> bool:
	var low := 0.0
	var high := 1.0
	for axis: int in [0,2]:
		var extent := width if axis == 0 else length
		var change := b[axis]-a[axis]
		if absf(change) < 0.00001:
			if absf(a[axis]) > extent:
				return false
		else:
			var enter := (-extent-a[axis])/change
			var leave := (extent-a[axis])/change
			low = maxf(low,minf(enter,leave))
			high = minf(high,maxf(enter,leave))
			if low > high:
				return false
	return true

func active_count() -> int:
	var count := 0
	for traffic: RushTrafficVehicle in pool:
		if traffic.active:
			count += 1
	return count

func rebase(shift: Vector3) -> void:
	previous_player -= shift
	for traffic: RushTrafficVehicle in pool:
		if traffic.active:
			traffic.position -= shift
			traffic.previous_position -= shift
			traffic.visual_root.global_position -= shift

func prewarm_models(alpha: float) -> void:
	# Render every shared mesh/material variant while the opaque splash is displayed.
	for i: int in mini(8,pool.size()):
		pool[i].activate(Vector3((i-2)*2.7,0,-9-i*0.6),i%4,0.0)
		pool[i].collision_layer = 0
		pool[i].set_fade(alpha)

func diagnostics() -> Dictionary:
	return {"active": active_count(), "capacity": pool.size(), "escape_lane": escape_lane,
		"spawn_rejections": spawn_rejections}

func react_to_horn() -> void:
	for traffic: RushTrafficVehicle in pool:
		if traffic.active and _route(car.position).z-_route(traffic.position).z>0 and car.position.distance_to(traffic.position)<45 and rng.randf()<.25:
			traffic.horn_left = 1.0

func _update_lane(npc: RushTrafficVehicle, allowed: float, delta: float) -> void:
	var key: int = npc.get_instance_id()
	if not lane_plans.has(key): return
	var plan: Dictionary = lane_plans[key]
	if float(plan.blend)<1.0:
		# Keep the car's physical and swept-collision positions on the same interpolation.
		if not _lane_clear(npc,int(plan.target)):
			npc.speed = move_toward(npc.speed,0.0,9.0*delta)
			return
		plan.blend = minf(1.0,float(plan.blend)+delta/float(tuning.lane_time))
		npc.lane_offset = lerpf(LANES[int(plan.from)],LANES[int(plan.target)],smoothstep(0,1,float(plan.blend)))
		if float(plan.blend)>=1.0: npc.lane = int(plan.target)
		return
	plan.clock = float(plan.clock)-delta
	if float(plan.clock)>0: return
	plan.clock = rng.randf_range(2.0,3.5)*float(tuning.decision)
	if allowed>=npc.desired_speed-1.5 or rng.randf()<float(tuning.mistake): return
	for direction: int in [-1,1]:
		var lane: int = npc.lane+direction
		if lane<0 or lane>=LANES.size() or lane==escape_lane or not _lane_clear(npc,lane): continue
		plan.target = lane
		plan.from = npc.lane
		plan.blend = 0.0
		return

func _lane_clear(npc: RushTrafficVehicle, lane: int) -> bool:
	var x: float = LANES[lane]
	# Safe gaps are never reduced for Hard, and the escape lane remains open.
	var player_gap: float = 32.0+absf(npc.speed-maxf(-_player_velocity().z,0.0))*2.0
	if absf(_route(car.position).x-x)<3.0 and absf(_route(npc.position).z-_route(car.position).z)<player_gap: return false
	if absf(_route(car.position+car.velocity*.8).x-x)<3.0 and absf(_route(npc.position).z-_route(car.position).z)<player_gap: return false
	for other: RushTrafficVehicle in pool:
		if not other.active or other==npc: continue
		var other_plan: Dictionary = lane_plans.get(other.get_instance_id(),{})
		var targets_lane: bool = int(other_plan.get("target",other.lane))==lane
		if (absf(_route(other.position).x-x)<3.0 or targets_lane) and absf(_route(other.position).z-_route(npc.position).z)<38.0+absf(other.speed-npc.speed)*2.0: return false
	if opponents!=null and not opponents.spawn_clear(x,_route(npc.position).z): return false
	if coins!=null and coins.traffic_conflicts(x,_route(npc.position).z,npc.speed): return false
	return true

func _route(at: Vector3) -> Vector3:
	return course.to_route(at) if course!=null else at
func _world(at: Vector3) -> Vector3:
	return course.to_world(at) if course!=null else at
func _player_velocity() -> Vector3:
	return course.route_velocity(car.position,car.velocity) if course!=null else car.velocity
