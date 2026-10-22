class_name RushFinishGate
extends Node3D
var car: ArcadeVehicle
var run: RushRunManager
var enabled: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var dark := RoadGeometry.material(Color("11212c"))
	var white := RoadGeometry.material(Color("edf5f0"))
	var accent := RoadGeometry.material(Color("39e1db"))
	for x: float in [-9.2,9.2]:
		RoadGeometry.box(self,Vector3(x,4.0,0),Vector3(0.35,8,0.35),accent)
	RoadGeometry.box(self,Vector3(0,7.8,0),Vector3(18.6,1.2,0.3),dark)
	var title := Label3D.new()
	title.text = "HIGHWAY RUSH   /   FINISH"
	title.font_size = 64
	title.pixel_size = 0.012
	add_child(title)
	title.position = Vector3(0,7.8,0.18)
	for x: int in range(-8,8):
		for z: int in 2:
			RoadGeometry.box(self,Vector3(x+0.5,0.025,z-0.5),Vector3(1,0.02,1),white if (x+z)%2==0 else dark)
	visible = false

func _process(_delta: float) -> void:
	var remaining := run.spec.distance_m-run.distance
	visible = enabled and remaining < 510.0
	if enabled:
		position.z = run.origin_offset-run.spec.distance_m
