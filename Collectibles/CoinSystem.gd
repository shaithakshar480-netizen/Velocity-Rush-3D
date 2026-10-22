class_name RushCoinSystem
extends Node3D
var pickup_radius: float = 1.45
var pool: Array[RushRoadCoin] = []
var car: ArcadeVehicle
var run: RushRunManager
var traffic: RushTrafficSystem
var active: bool = false
var rng := RandomNumberGenerator.new()
var spawned: int = 0
var collected: int = 0
var pattern_index: int = 0
var next_pattern_distance: float = 0.0
var retry_clock: float = 0.0
var previous_player := Vector3.ZERO
var gold: StandardMaterial3D
var clock: float = 0.0
var ready_for_drive: bool = false
var bursts: Array[RushCoinBurst] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -5
	gold = RoadGeometry.material(Color("f6c34f"),0.8,0.24)
	gold.emission_enabled = true
	gold.emission = Color("b98724")
	gold.emission_energy_multiplier = 0.12
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.43
	mesh.bottom_radius = 0.43
	mesh.height = 0.11
	mesh.radial_segments = 24
	var rim := TorusMesh.new()
	rim.inner_radius = 0.40
	rim.outer_radius = 0.47
	rim.rings = 24
	rim.ring_segments = 8
	var badge := _badge_mesh()
	var badge_material := RoadGeometry.material(Color("79551e"),0.35,0.4)
	badge_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i: int in run.spec.coin_pool_size:
		var coin := RushRoadCoin.new()
		add_child(coin)
		coin.build(mesh,gold,rim,badge,badge_material)
		pool.append(coin)
		if i%10 == 9:
			await get_tree().process_frame
	for i: int in 8:
		var burst := RushCoinBurst.new()
		add_child(burst)
		burst.build(rim)
		bursts.append(burst)
	ready_for_drive = true

func reset_pool(seed_value: int) -> void:
	active = false
	for coin: RushRoadCoin in pool:
		coin.deactivate()
	rng.seed = seed_value*3571+23
	spawned = 0
	collected = 0
	pattern_index = 0
	next_pattern_distance = 0.0
	retry_clock = 1.15
	previous_player = car.position
	clock = 0.0
	for burst: RushCoinBurst in bursts:
		burst.remaining = 0.0
		burst.visible = false

func _process(delta: float) -> void:
	if not active:
		return
	clock += delta
	gold.emission_energy_multiplier = 0.12+sin(clock*2.5)*0.025
	for coin: RushRoadCoin in pool:
		if coin.active:
			coin.rotation.y = fmod(clock*2.2,TAU)
	for burst: RushCoinBurst in bursts:
		burst.tick(delta)

func _physics_process(delta: float) -> void:
	if not active or run.state != RushRunManager.RunState.RUNNING:
		return
	for coin: RushRoadCoin in pool:
		if coin.active:
			coin.blocked = not coin.attracting and _traffic_covers(coin.position)
			coin.visible = not coin.blocked
		if coin.active and not coin.attracting and (coin.position.z-car.position.z > 20.0 or car.position.z-coin.position.z>560.0):
			coin.deactivate()
	retry_clock -= delta
	if run.furthest >= next_pattern_distance and spawned < run.spec.coin_budget and retry_clock <= 0.0:
		retry_clock = 1.0
		if _spawn_pattern():
			next_pattern_distance = run.furthest+run.spec.pattern_interval
			pattern_index += 1

func _spawn_pattern() -> bool:
	var lengths: Array[Vector2i] = [Vector2i(5,10),Vector2i(5,8),Vector2i(3,6),Vector2i(8,15),Vector2i(5,8)]
	var limits: Vector2i = lengths[pattern_index%5]
	var count: int = mini(rng.randi_range(limits.x,limits.y),run.spec.coin_budget-spawned)
	if pool.size()-active_count() < count:
		return false
	var lookahead := maxf(230.0,car.speed_kmh()/3.6*4.0+70.0)
	if run.distance+lookahead+count*run.spec.coin_spacing > run.spec.distance_m-35.0:
		return false
	for attempt: int in 8:
		var lane := traffic.escape_lane if pattern_index == 0 else rng.randi_range(0,3)
		var target_lane := clampi(lane+(1 if lane<2 else -1),0,3)
		var pattern := pattern_index%5
		# Risk line: pick the adjacent lane to distant traffic; the predictive check still applies.
		if pattern == 3:
			for vehicle: RushTrafficVehicle in traffic.pool:
				if vehicle.active and absf((car.position.z-vehicle.position.z)-lookahead)<90.0:
					lane = clampi(vehicle.lane+(1 if vehicle.lane<2 else -1),0,3)
					break
		var points: Array[Vector3] = []
		var safe := true
		for i: int in count:
			var spacing := run.spec.coin_spacing*(0.8 if pattern==2 else 1.0)
			var z := car.position.z-lookahead-i*spacing
			var point := RushRoadFrame.lane_point(lane,z,RushRoadFrame.COIN_HEIGHT)
			if pattern == 4:
				point = RushRoadFrame.lane_point(lane if i%2==0 else target_lane,z,RushRoadFrame.COIN_HEIGHT)
			if pattern == 1:
				point = RushRoadFrame.transition_point(lane,target_lane,float(i)/maxf(count-1,1),z)
			if not point_safe(point):
				safe = false
				break
			points.append(point)
		if not safe:
			continue
		var index := 0
		for coin: RushRoadCoin in pool:
			if not coin.active:
				coin.activate(points[index],index*0.8)
				index += 1
				if index == points.size():
					break
		spawned += points.size()
		return true
	return false

func point_safe(point: Vector3) -> bool:
	var eta := maxf(car.position.z-point.z,0.0)/maxf(-car.velocity.z,22.0)
	for vehicle: RushTrafficVehicle in traffic.pool:
		if not vehicle.active:
			continue
		if absf(vehicle.position.x-point.x)<2.65:
			var predicted := vehicle.position.z-vehicle.speed*eta
			# Exclude both current overlap and expected arrival-time obstruction.
			if absf(vehicle.position.z-point.z)<22.0 or absf(predicted-point.z)<38.0:
				return false
	for coin: RushRoadCoin in pool:
		if coin.active and coin.position.distance_squared_to(point)<16.0:
			return false
	return true

func traffic_conflicts(x: float, z: float, speed: float) -> bool:
	for coin: RushRoadCoin in pool:
		if not coin.active or absf(coin.position.x-x)>2.65:
			continue
		var eta := maxf(car.position.z-coin.position.z,0.0)/maxf(-car.velocity.z,22.0)
		if absf(z-coin.position.z)<22.0 or absf(z-speed*eta-coin.position.z)<38.0:
			return true
	return false

func evaluate_pickups() -> void:
	if not active or run.state != RushRunManager.RunState.RUNNING:
		previous_player = car.position
		return
	var a := previous_player+Vector3(0,0.9,0)
	var b := car.position+Vector3(0,0.9,0)
	var segment := b-a
	for coin: RushRoadCoin in pool:
		if not coin.active or coin.blocked:
			continue
		var t: float = clampf((coin.position-a).dot(segment)/maxf(segment.length_squared(),0.0001),0.0,1.0)
		var distance_squared: float = coin.position.distance_squared_to(a+segment*t)
		if not coin.attracting and pickup_radius>1.5 and distance_squared<pickup_radius*pickup_radius*2.25:
			coin.begin_attraction(b)
		if coin.attracting:
			# Latched coins finish their short flight even when the magnet expires.
			# Reward only at arrival, never at attraction start.
			if coin.tick_attraction(b,get_physics_process_delta_time()):
				_collect(coin)
		elif distance_squared<pickup_radius*pickup_radius:
			_collect(coin)
	previous_player = car.position

func _collect(coin: RushRoadCoin) -> void:
	if not coin.active: return
	_emit_burst(coin.position)
	coin.deactivate()
	collected += 1
	run.collect_coin()

func active_count() -> int:
	var count := 0
	for coin: RushRoadCoin in pool:
		if coin.active:
			count += 1
	return count

func rebase(shift: Vector3) -> void:
	previous_player -= shift
	for coin: RushRoadCoin in pool:
		if coin.active:
			coin.position -= shift
			if coin.attracting: coin.attraction_origin -= shift
	for burst: RushCoinBurst in bursts:
		if burst.remaining>0.0:
			burst.position -= shift

func diagnostics() -> Dictionary:
	return {"active": active_count(), "capacity": pool.size(), "spawned": spawned,
		"collected": collected, "pattern": pattern_index%5}

func _traffic_covers(point: Vector3) -> bool:
	for vehicle: RushTrafficVehicle in traffic.pool:
		if vehicle.active and absf(vehicle.position.x-point.x)<vehicle.half_width+0.6:
			if absf(vehicle.position.z-point.z)<vehicle.half_length+3.0:
				return true
	return false

func _emit_burst(point: Vector3) -> void:
	for burst: RushCoinBurst in bursts:
		if burst.remaining<=0.0:
			burst.activate(point)
			return

func prewarm_visuals() -> void:
	for i: int in mini(4,pool.size()):
		pool[i].activate(RushRoadFrame.lane_point(i,-5.0,RushRoadFrame.COIN_HEIGHT))
	_emit_burst(Vector3(0,1.15,-4))

func _badge_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0,1.0]:
		for direction: float in [-1.0,1.0]:
			var points: Array[Vector3] = [Vector3(direction*0.2,0.15,side*0.061),Vector3(direction*0.12,0.15,side*0.061),Vector3(-direction*0.035,-0.17,side*0.061),Vector3(direction*0.045,-0.17,side*0.061)]
			for index: int in [0,1,2,0,2,3]:
				surface.set_normal(Vector3(0,0,side))
				surface.add_vertex(points[index])
	return surface.commit()
