class_name RushSteeringModel
extends RefCounted
## Original sculpted wheel: variable-section leather rim, shaped hub and curved spokes.
static func build(parent: Node3D, style: int, leather: Material, carbon: Material, metal: Material, accent: Material) -> Node3D:
	var wheel := Node3D.new()
	parent.add_child(wheel)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var width: float = [.108,.101,.106,.116,.113,.115][style]
	var height: float = [.108,.097,.092,.101,.089,.111][style]
	for i: int in 80:
		var angle := TAU*float(i)/80.0
		var x := cos(angle)*width
		var y := maxf(sin(angle)*height,-height*[.79,.72,.77,.69,.78,.89][style])
		# Thumb pockets and thicker palm zones at nine and three o'clock.
		var grip := pow(absf(cos(angle)),10)
		path.append(Vector3(x-grip*signf(x)*.003,y,.006*grip))
		radii.append((.012 if style==5 else .0105)+grip*(.005 if style in [2,3] else .003))
	RushInteriorGeometry.sweep(wheel,path,radii,leather,true)
	var hub_width: float = [.048,.040,.042,.050,.054,.052][style]
	var hub := PackedVector2Array([Vector2(-hub_width,.019),Vector2(-hub_width*.80,.031),Vector2(hub_width*.80,.031),Vector2(hub_width,.019),Vector2(hub_width*.82,-.025),Vector2(0,-.039),Vector2(-hub_width*.82,-.025)])
	# panel expects counter-clockwise outline; authored outline is reversed below.
	hub.reverse()
	RushInteriorGeometry.panel(wheel,Vector3(0,-.007,.009),hub,.035,leather)
	for side: float in [-1.0,1.0]:
		var spine := PackedVector3Array([Vector3(side*.03,-.018,-.004),Vector3(side*.063,-.012,-.007),Vector3(side*.091,.006,-.003)])
		if style in [3,4]:
			spine[1] = Vector3(side*.063,-.029,-.007)
		RushInteriorGeometry.sweep(wheel,spine,PackedFloat32Array([.014,.012,.010]),carbon)
		var controls := RushInteriorGeometry.shell(wheel,Vector3(side*.063,-.005,.014),Vector3(.034,.028,.014),carbon)
		controls.rotation.z = side*(.12 if style!=3 else .35)
		for row: int in 2:
			for col: int in (3 if style==5 else 2):
				RushInteriorGeometry.shell(wheel,Vector3(side*.063+(col-1)*.009,.001-row*.010,.024),Vector3(.006,.005,.003),metal if style!=4 else accent)
		if style in [2,3,5]:
			# Fixed column paddles sit behind the rotating rim.
			var paddle := RushInteriorGeometry.shell(parent,Vector3(side*.077,.028,-.029),Vector3(.016,.070,.009),metal)
			paddle.rotation.z = -side*.12
	var lower := PackedVector3Array([Vector3(0,-.025,-.007),Vector3(.008 if style==3 else 0,-.053,-.012),Vector3(0,-height*.77,-.005)])
	RushInteriorGeometry.sweep(wheel,lower,PackedFloat32Array([.018,.010,.008]),metal if style in [0,5] else carbon)
	if style in [2,3,4]:
		for side: float in [-1.0,1.0]:
			RushInteriorGeometry.shell(wheel,Vector3(side*.036,-.036,.023),Vector3(.013,.013,.009),accent)
	RushInteriorGeometry.shell(wheel,Vector3(0,height+.001,.002),Vector3(.008,.012,.004),accent)
	return wheel
