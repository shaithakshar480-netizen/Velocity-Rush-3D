class_name RushSampledCourse
extends RefCounted
## Cached, flat, monotonic-Z course. Route Z is negative arc length; X is lane offset.
## Physics, rendering, AI and progress share this reversible coordinate adapter.
const SPACING: float = 4.0
const FRACTIONS: Array[float] = [0.0,.04,.15,.23,.38,.46,.60,.68,.81,.90,1.0]
const OFFSETS: Array[float] = [0.0,0.0,-55.0,-55.0,65.0,65.0,-65.0,-65.0,35.0,0.0,0.0]
var length: float
var origin_z: float = 0.0
var points: PackedVector3Array = PackedVector3Array()
var distances: PackedFloat32Array = PackedFloat32Array()
var headings: PackedFloat32Array = PackedFloat32Array()
var z_step: float

func build(meters: float) -> void:
	length = meters
	origin_z = 0.0
	points.clear()
	distances.clear()
	headings.clear()
	var count: int = int(ceil(meters/SPACING))
	var total: float = 0.0
	var section: int = 0
	for i: int in count+1:
		var fraction: float = float(i)/float(count)
		while section<FRACTIONS.size()-2 and fraction>FRACTIONS[section+1]: section += 1
		var t: float = (fraction-FRACTIONS[section])/(FRACTIONS[section+1]-FRACTIONS[section])
		var eased: float = t*t*t*(t*(t*6.0-15.0)+10.0)
		# Smaller future courses keep the same curvature/comfort envelope.
		var x: float = lerpf(OFFSETS[section],OFFSETS[section+1],eased)*minf(1.0,meters*meters/64000000.0)
		var point: Vector3 = Vector3(x,0.0,-meters*fraction)
		if i>0: total += point.distance_to(points[i-1])
		points.append(point)
		distances.append(total)
	var scale_value: float = meters/total
	for i: int in points.size():
		points[i] *= scale_value
		distances[i] *= scale_value
		# Headings calculated in a second pass after all points have been scaled.
		headings.append(0.0)
	z_step = meters/float(count)*scale_value
	for i: int in points.size():
		var direction: Vector3 = points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]
		headings[i] = atan2(-direction.x,-direction.z)
	distances[distances.size()-1] = meters

func _index(distance: float) -> int:
	var low: int = 0
	var high: int = distances.size()-1
	while high-low>1:
		var middle: int = low+((high-low)>>1)
		if distances[middle]<=distance: low = middle
		else: high = middle
	return low

func point(distance: float) -> Vector3:
	if distance<=0.0: return Vector3(0,0,origin_z-distance)
	if distance>=length: return points[points.size()-1]+Vector3(0,0,origin_z-(distance-length))
	var i: int = _index(distance)
	var t: float = (distance-distances[i])/(distances[i+1]-distances[i])
	return points[i].lerp(points[i+1],t)+Vector3(0,0,origin_z)

func distance_at_z(z: float) -> float:
	var forward: float = origin_z-z
	if forward<=0.0: return forward
	var last_z: float = -points[points.size()-1].z
	if forward>=last_z: return length+forward-last_z
	var sample: float = forward/z_step
	var i: int = mini(int(sample),points.size()-2)
	return lerpf(distances[i],distances[i+1],sample-float(i))

func heading_at_z(z: float) -> float:
	var sample: float = clampf((origin_z-z)/z_step,0.0,float(points.size()-1))
	var i: int = mini(int(sample),points.size()-2)
	return lerp_angle(headings[i],headings[i+1],sample-float(i))

func center_x(z: float) -> float:
	var sample: float = clampf((origin_z-z)/z_step,0.0,float(points.size()-1))
	var i: int = mini(int(sample),points.size()-2)
	return lerpf(points[i].x,points[i+1].x,sample-float(i))

func to_route(world: Vector3) -> Vector3:
	return Vector3(world.x-center_x(world.z),world.y,origin_z-distance_at_z(world.z))

func to_world(route: Vector3) -> Vector3:
	return point(origin_z-route.z)+Vector3(route.x,route.y,0)

func pose(route_pose: Transform3D) -> Transform3D:
	var at: Vector3 = to_world(route_pose.origin)
	return Transform3D(Basis(Vector3.UP,heading_at_z(at.z))*route_pose.basis,at)

func route_velocity(at: Vector3, velocity: Vector3) -> Vector3:
	var yaw: float = heading_at_z(at.z)
	var slope: float = tan(yaw)
	return Vector3(velocity.x-slope*velocity.z,velocity.y,velocity.z/maxf(cos(yaw),.8))
