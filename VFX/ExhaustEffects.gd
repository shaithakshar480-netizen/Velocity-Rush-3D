class_name RushExhaustEffects
extends Node3D
var car: ArcadeVehicle
var turbo: RushTurboController
var material: ShaderMaterial
var jets: Array[Node3D] = []
var crosses: Array[MeshInstance3D] = []
var clock: float = 0.0
var flare: float = 0.0
var warming: bool = false
var quality: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 110
	material = ShaderMaterial.new()
	material.shader = preload("res://VFX/exhaust.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25,1.0)
	for emitter_index: int in 4:
		var point := car.spec.exhaust_points[emitter_index] if emitter_index<car.spec.exhaust_points.size() else Vector3.ZERO
		var nozzle := Node3D.new()
		car.visual.body_root.add_child(nozzle)
		nozzle.position = point
		jets.append(nozzle)
		for plane: int in 2:
			var jet := MeshInstance3D.new()
			jet.mesh = quad
			jet.material_override = material
			jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			nozzle.add_child(jet)
			jet.position.z = 0.5
			# Both crossed ribbons run down +Z, away from the actual exhaust.
			jet.basis = Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN) if plane==0 else Basis(Vector3.UP,Vector3.BACK,Vector3.RIGHT)
			if plane == 1:
				crosses.append(jet)

func ignition() -> void:
	flare = 1.0

func reset() -> void:
	flare = 0.0
	clock = 0.0
	material.set_shader_parameter("power",0.0)

func _process(delta: float) -> void:
	clock += delta
	flare = move_toward(flare,0.0,delta*3.0)
	var normal := 0.025 if car.driving else 0.0
	if car.last_command.y>0.0 and car.driving:
		normal = 0.07
	var power := maxf(normal,maxf(turbo.intensity*0.8,flare))
	if warming:
		power = 1.0
	material.set_shader_parameter("power",power)
	material.set_shader_parameter("phase",clock)
	for i: int in jets.size():
		var jet: Node3D = jets[i]
		if i<car.spec.exhaust_points.size():
			jet.position = car.spec.exhaust_points[i]
		var flutter: float = 1.0+0.07*sin(clock*23.0+float(i)*1.7)+0.035*sin(clock*41.0+float(i))
		jet.scale = Vector3(0.82+power*0.28,0.82+power*0.28,(0.12+power*1.18)*flutter)
		jet.visible = power > 0.001 and i<car.spec.exhaust_points.size()
	for cross: MeshInstance3D in crosses:
		cross.visible = quality>0 or warming
