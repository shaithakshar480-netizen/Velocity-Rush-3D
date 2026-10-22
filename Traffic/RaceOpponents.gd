class_name RushRaceOpponents
extends Node3D
## Fixed race grid, bounded acceleration, adjacent-lane changes; no teleport/rubber band.
signal passed(at: Vector3, relative_speed: float)
var car: ArcadeVehicle
var traffic: RushTrafficSystem
var course: RushSampledCourse
var active: bool = false
var difficulty: int = 1
var tuning: Dictionary = RushRaceDifficulty.profile(1)
var race_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var racers: Array[RushTrafficVehicle] = []
var plans: Array[Dictionary] = []
var previous_player := Vector3.ZERO
var profiles: Array = []
var route_offset: float = 0.0
var hud_order: Array[int] = [0,1,2,3,4]
var candidate_order: Array[int] = []
var candidate_since: float = 0.0
var name_labels: Array[Label3D] = []
var race_clock: float = 0.0
var finish_times: Array[float] = [-1.0,-1.0,-1.0,-1.0,-1.0]
func _ready() -> void:
	profiles = JSON.parse_string(FileAccess.get_file_as_string("res://Data/RacerProfiles.json"))
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -5
	# BUG-5 FIX: Ensure production visual blueprints are prepared for each opponent's preferred car
	# (REX -> falcon_s1, NOVA -> apex_rs, KAI -> inferno_r, ZANE -> phantom_x).
	for i: int in mini(4, profiles.size()):
		var car_id: String = String(profiles[i].get("preferred_car", "falcon_s1"))
		await RushProductionTrafficVisual.prepare(car_id, get_tree())

	for i: int in 4:
		var racer := RushTrafficVehicle.new()
		var profile: Dictionary = profiles[i] if i < profiles.size() else {}
		var car_id: String = String(profile.get("preferred_car", "falcon_s1"))
		racer.production_id = car_id
		racer.kind = i
		racer.viewer = car
		add_child(racer)
		racers.append(racer)
		var light := RoadGeometry.material(Color("ecbf63"),.3,.4)
		light.emission_enabled = true
		RoadGeometry.box(racer.visual_root,Vector3(0,1.36,.2),Vector3(.09,.025,1.1),light)
		var number := Label3D.new()
		number.text = String(profiles[i].display_name)
		number.font_size = 32
		number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		number.pixel_size = .007
		number.position = Vector3(0,1.65,0)
		racer.visual_root.add_child(number)
		name_labels.append(number)
		plans.append({"personality":RushDrivingData.get_data().personalities[i],"target":i,"from":i,"clock":0.0,"telegraph":0.0,"moving":false,"blend":0.0,"lamp":light})
func reset() -> void:
	tuning = RushRaceDifficulty.profile(difficulty)
	race_rng.randomize()
	race_clock = 0.0
	route_offset = 0.0
	hud_order = [4,3,2,1,0]
	candidate_order.clear()
	finish_times.fill(-1.0)
	active = false
	previous_player = car.position
	for i: int in racers.size():
		var racer := racers[i]
		var lane: int = [1,2,0,3][i]
		racer.course = course
		racer.activate(_world(RushRoadFrame.lane_point(lane,-18.0-i*34.0)),lane,0)
		racer.set_fade(1)
		var livery_color: Color = [Color("bf752f"),Color("426fac"),Color("913a49"),Color("b8c4c8")][i]
		racer.paint_material.albedo_color = livery_color
		if racer.production != null:
			racer.production.set_paint(livery_color)
		plans[i].target = lane
		plans[i].from = lane
		plans[i].clock = .4+i*.15
		plans[i].moving = false
		plans[i].telegraph = 0.0
		plans[i].blend = 0.0
		plans[i].charges = int(tuning.boosts)
		plans[i].boost_left = 0.0
		plans[i].boost_wait = float(tuning.boost_after)+i*2.0
		plans[i].recovery = 0.0
		plans[i].hit_seen = false
		plans[i].boost_visual = false
		name_labels[i].text = String(profiles[i].display_name)
		name_labels[i].modulate = Color.WHITE
func stop() -> void:
	active = false
	for racer: RushTrafficVehicle in racers:
		racer.deactivate()
func _physics_process(delta: float) -> void:
	if not active:
		return
	for i: int in racers.size():
		var racer := racers[i]
		var plan := plans[i]
		var personality: Dictionary = plan.personality
		if absf(_route(car.position).z-_route(racer.position).z)>9 or absf(_route(car.position).x-_route(racer.position).x)>4:
			racer.was_hit = false
		racer.previous_position = racer.position
		racer.previous_yaw = racer.rotation.y
		plan.clock = maxf(0,float(plan.clock)-delta)
		plan.boost_wait = maxf(0,float(plan.boost_wait)-delta)
		plan.boost_left = maxf(0,float(plan.boost_left)-delta)
		plan.recovery = maxf(0,float(plan.recovery)-delta)
		if racer.was_hit and not bool(plan.hit_seen):
			plan.recovery = float(tuning.recovery)
			plan.boost_left = 0.0
		plan.hit_seen = racer.was_hit
		var headway: float = float(personality.headway)*float(tuning.headway)
		var normal_cap: float = minf(car.spec.top_speed_kmh/3.6,car.spec.top_speed_kmh/3.6*float(profiles[i].skill)*float(tuning.pace))
		var boost_cap: float = maxf(normal_cap,minf(car.spec.turbo.top_speed_kmh,270.0)/3.6)
		var open_speed: float = _forward_speed(racer,racer.lane,headway)
		var chasing: bool = _route(car.position).z<_route(racer.position).z or (route_offset-_route(racer.position).z)>6000.0
		if int(plan.charges)>0 and float(plan.boost_wait)<=0 and float(plan.boost_left)<=0 and float(plan.recovery)<=0 and not bool(plan.moving) and float(plan.telegraph)<=0 and racer.speed>normal_cap*.8 and open_speed>=boost_cap and chasing and finish_times[i+1]<0:
			plan.charges = int(plan.charges)-1
			plan.boost_left = float(tuning.boost_duration)
			plan.boost_wait = 18.0+race_rng.randf_range(0,6)
		if open_speed<racer.speed or finish_times[i+1]>=0: plan.boost_left = 0.0
		var boosting: bool = float(plan.boost_left)>0
		var ceiling: float = boost_cap if boosting else normal_cap
		if float(plan.recovery)>0: ceiling *= .78
		if bool(plan.boost_visual)!=boosting:
			plan.boost_visual = boosting
			name_labels[i].text = String(profiles[i].display_name)+( " • BOOST" if boosting else "")
			name_labels[i].modulate = Color("5eeaff") if boosting else Color.WHITE
		var desired := minf(ceiling,_forward_speed(racer,racer.lane,headway))
		if bool(plan.moving):
			desired = minf(desired,_forward_speed(racer,int(plan.target),headway))
		elif float(plan.telegraph)>0:
			plan.telegraph = maxf(0,float(plan.telegraph)-delta)
			plan.lamp.emission = Color("f4b650")*(.7 if int(Time.get_ticks_msec()/140)%2==0 else .05)
			if float(plan.telegraph)<=0:
				if lane_safe(racer,int(plan.target),float(personality.risk_gap)*float(tuning.gap)):
					plan.moving = true
					plan.blend = 0.0
					plan.from = racer.lane
				plan.lamp.emission = Color.BLACK
		elif float(plan.clock)<=0:
			plan.clock = float(personality.decision)*float(tuning.decision)
			var best := racer.lane
			var best_speed := desired
			for direction: int in [-1,1]:
				var lane := racer.lane+direction
				if not lane_safe(racer,lane,float(personality.risk_gap)*float(tuning.gap)):
					continue
				var possible := minf(ceiling,_forward_speed(racer,lane,headway))
				# Defend only when safely well ahead; never cut directly into the player.
				var defend := difficulty>0 and i>=2 and _route(car.position).z-_route(racer.position).z>50 and _route(car.position).z-_route(racer.position).z<90 and absf(_route(car.position).x-RushRoadFrame.LANE_CENTERS[lane])<1
				if possible>best_speed+2 or (defend and possible>=desired):
					best = lane
					best_speed = possible
			# Mistakes are delayed overtakes, never deliberate unsafe swerves.
			if race_rng.randf()<float(tuning.mistake): best = racer.lane
			if best!=racer.lane:
				plan.target = best
				plan.telegraph = .65 if difficulty==0 else .5
		racer.braking = desired<racer.speed-.4
		var acceleration: float = minf(car.spec.acceleration,float(personality.acceleration)*float(tuning.acceleration))
		if boosting: acceleration *= car.spec.turbo.acceleration_multiplier
		racer.speed = move_toward(racer.speed,desired,(13.0 if racer.braking else acceleration)*delta)
		if bool(plan.moving):
			plan.blend = minf(1,float(plan.blend)+delta/float(tuning.lane_time))
			var eased := smoothstep(0,1,float(plan.blend))
			racer.lane_offset = lerpf(RushRoadFrame.LANE_CENTERS[int(plan.from)],RushRoadFrame.LANE_CENTERS[int(plan.target)],eased)
			if float(plan.blend)>=1:
				racer.lane = int(plan.target)
				plan.moving = false
		var next: Vector3 = _route(racer.position)
		next.x = racer.lane_offset
		next.z -= racer.speed*delta
		racer.position = _world(next)
		if course!=null: racer.rotation.y = course.heading_at_z(racer.position.z)
		if (Engine.get_physics_frames() + i) % 4 == 0:
			racer.update_distance_lod(car.position.distance_to(racer.position))
		var racer_dist: float = car.position.distance_to(racer.position)
		var label_alpha: float = 1.0 - smoothstep(35.0, 85.0, racer_dist)
		name_labels[i].modulate.a = label_alpha
		name_labels[i].visible = label_alpha > 0.02
func evaluate_contacts() -> void:
	# Called after player motion and before run rewards: both poses are from this tick.
	if not active:
		previous_player = car.position
		return
	for racer: RushTrafficVehicle in racers:
		if _route(previous_player).z-_route(racer.previous_position).z>=-5 and _route(car.position).z-_route(racer.position).z< -5 and absf(_route(car.position).x-_route(racer.position).x)<8:
			passed.emit(racer.position,absf(-_player_velocity().z-racer.speed))
		if _route(previous_player).z-_route(racer.previous_position).z<=5 and _route(car.position).z-_route(racer.position).z>5 and absf(_route(car.position).x-_route(racer.position).x)<8:
			passed.emit(racer.position,absf(-_player_velocity().z-racer.speed))
		if not racer.was_hit and RushTrafficSystem._swept_overlap(_route(previous_player)-_route(racer.previous_position),_route(car.position)-_route(racer.position),car.half_width()+racer.half_width,car.half_length()+racer.half_length):
			racer.mark_collision()
			var closing := absf(-_player_velocity().z-racer.speed)
			car.respond_to_traffic(clampf(closing/28,.15,1),closing,Basis(Vector3.UP,course.heading_at_z(car.position.z)).z if course!=null else Vector3.BACK)
	previous_player = car.position
func _forward_speed(racer: RushTrafficVehicle, lane: int, headway: float) -> float:
	var allowed := 150.0
	for other: RushTrafficVehicle in traffic.pool:
		if other.active:
			allowed = minf(allowed,_limit_for(racer,lane,other.position,other.speed,headway))
	for other: RushTrafficVehicle in racers:
		if other!=racer and other.active:
			allowed = minf(allowed,_limit_for(racer,lane,other.position,other.speed,headway))
	return minf(allowed,_limit_for(racer,lane,car.position,maxf(-_player_velocity().z,0),headway))
func _limit_for(racer: RushTrafficVehicle, lane: int, at: Vector3, speed: float, headway: float) -> float:
	var route_at: Vector3 = _route(at)
	var gap := _route(racer.position).z-route_at.z-5.0
	if absf(route_at.x-RushRoadFrame.LANE_CENTERS[lane])<2.6 and gap>0:
		return maxf(0,minf(speed+maxf(gap-20,0)/headway,(gap-7)/headway))
	return 150.0
func lane_safe(racer: RushTrafficVehicle, lane: int, gap: float) -> bool:
	if lane<0 or lane>3 or absi(lane-racer.lane)!=1:
		return false
	var center: float = RushRoadFrame.LANE_CENTERS[lane]
	if not _gap_safe(racer,center,car.position,-_player_velocity().z,gap+8):
		return false
	var projected_player := car.position+car.velocity*.75
	if not _gap_safe(racer,center,projected_player,-_player_velocity().z,gap+8):
		return false
	for other: RushTrafficVehicle in traffic.pool:
		if other.active and not _gap_safe(racer,center,other.position,other.speed,gap):
			return false
	for other: RushTrafficVehicle in racers:
		if other!=racer and other.active and not _gap_safe(racer,center,other.position,other.speed,gap):
			return false
	for i: int in racers.size():
		if racers[i]==racer or not racers[i].active:
			continue
		var plan := plans[i]
		if (bool(plan.moving) or float(plan.telegraph)>0) and int(plan.target)==lane and absf(_route(racers[i].position).z-_route(racer.position).z)<gap+25:
			return false
	return true
func _gap_safe(racer: RushTrafficVehicle, center: float, at: Vector3, speed: float, gap: float) -> bool:
	if absf(_route(at).x-center)>2.65:
		return true
	var separation := _route(racer.position).z-_route(at).z
	var closing := maxf(racer.speed-speed,0) if separation>0 else maxf(speed-racer.speed,0)
	return absf(separation)>gap+closing*1.6
func spawn_clear(x: float, z: float) -> bool:
	for racer: RushTrafficVehicle in racers:
		if racer.active and absf(_route(racer.position).x-x)<3 and absf(_route(racer.position).z-z)<70:
			return false
	return true
func record_finishes(delta: float, finish_z: float) -> void:
	if not active:
		return
	_record_crossing(0,_route(previous_player).z,_route(car.position).z,finish_z,delta)
	for i: int in racers.size():
		_record_crossing(i+1,_route(racers[i].previous_position).z,_route(racers[i].position).z,finish_z,delta)
	race_clock += delta

func _record_crossing(id: int, before: float, after: float, line: float, delta: float) -> void:
	if finish_times[id]>=0.0 or after>line or after>=before:
		return
	# Fractional physics-tick crossing time; stable grid ID breaks exact ties (player=0).
	finish_times[id] = race_clock+clampf((before-line)/(before-after),0.0,1.0)*delta

func racer_name(grid_id: int) -> String:
	if grid_id>0:
		return String(profiles[grid_id-1].display_name)
	var saved: String = String(SaveService.progression.get("name","")).strip_edges()
	return "YOU" if saved.is_empty() else saved
func route_state(grid_id: int) -> Vector2:
	# Course adapter: cached arc length is shared with RunManager and finish crossing.
	var at: Vector3 = car.position if grid_id==0 else racers[grid_id-1].position
	var meters: float = maxf(0.0,route_offset-_route(at).z)
	return Vector2(floorf(meters/100.0),fmod(meters,100.0))
func _ahead(a: int, b: int) -> bool:
	var ta: float = finish_times[a]
	var tb: float = finish_times[b]
	if ta>=0.0 or tb>=0.0:
		if ta<0.0:
			return false
		if tb<0.0:
			return true
		return ta<tb if ta!=tb else a<b
	var pa: Vector2 = route_state(a)
	var pb: Vector2 = route_state(b)
	if pa.x!=pb.x:
		return pa.x>pb.x
	return pa.y>pb.y if pa.y!=pb.y else a<b
func ranking() -> Array[int]:
	var order: Array[int] = [0,1,2,3,4]
	order.sort_custom(_ahead)
	return order
func live_order() -> Array[int]:
	var next: Array[int] = ranking()
	if next!=candidate_order:
		candidate_order = next
		candidate_since = race_clock
	elif race_clock-candidate_since>=0.3:
		hud_order = next
	for i: int in racers.size():
		profiles[i].current_position = hud_order.find(i+1)+1
		profiles[i].finish_time = finish_times[i+1]
	return hud_order
func place() -> int:
	return ranking().find(0)+1
func results_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var order: Array[int] = ranking()
	for i: int in order.size():
		var grid_id: int = order[i]
		var reward: Dictionary = RushDrivingData.get_data().five_racer_rewards[i]
		rows.append({"position":i+1,"name":racer_name(grid_id),"finish_time":finish_times[grid_id],"coins":int(reward.coins) if finish_times[grid_id]>=0 else 0,"xp":int(reward.xp) if finish_times[grid_id]>=0 else 0})
	return rows
func rebase(shift: Vector3) -> void:
	route_offset -= shift.z
	previous_player -= shift
	for racer: RushTrafficVehicle in racers:
		racer.position -= shift
		racer.previous_position -= shift
		racer.visual_root.global_position -= shift

func traffic_limit(follower: RushTrafficVehicle) -> float:
	var limit := 150.0
	for racer: RushTrafficVehicle in racers:
		if racer.active:
			limit = minf(limit,_limit_for(follower,follower.lane,racer.position,racer.speed,1.8))
	return limit

func _route(at: Vector3) -> Vector3:
	return course.to_route(at) if course!=null else at
func _world(at: Vector3) -> Vector3:
	return course.to_world(at) if course!=null else at
func _player_velocity() -> Vector3:
	return course.route_velocity(car.position,car.velocity) if course!=null else car.velocity
