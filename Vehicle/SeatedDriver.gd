class_name RushSeatedDriver
extends Node3D
## Original lightweight suited driver; all geometry is local to the vehicle body.
var helmet: Node3D
var arms: Node3D
func _ready() -> void:
	var suit: StandardMaterial3D = RoadGeometry.material(Color("162333"),.12,.72)
	var trim: StandardMaterial3D = RoadGeometry.material(Color("31b8d3"),.35,.35)
	var shell: StandardMaterial3D = RoadGeometry.material(Color("d9e1e8"),.5,.24)
	var visor: StandardMaterial3D = RoadGeometry.material(Color("102336"),.75,.15)
	_part(self,Vector3(0,-.37,.10),Vector3(.34,.48,.22),suit)
	_part(self,Vector3(0,-.37,-.014),Vector3(.27,.035,.022),trim)
	for x: float in [-.105,.105]:
		_part(self,Vector3(x,-.36,-.018),Vector3(.038,.39,.025),trim)
	helmet = Node3D.new()
	add_child(helmet)
	_part(helmet,Vector3(0,.015,.035),Vector3(.255,.30,.265),shell)
	_part(helmet,Vector3(0,.035,-.093),Vector3(.23,.105,.032),visor)
	_part(helmet,Vector3(0,-.095,-.073),Vector3(.21,.05,.11),shell)
	arms = Node3D.new()
	add_child(arms)
	for side: float in [-1.0,1.0]:
		_limb(arms,Vector3(side*.16,-.20,.07),Vector3(side*.23,-.37,-.11),.055,suit)
		_limb(arms,Vector3(side*.23,-.37,-.11),Vector3(side*.14,-.28,-.36),.05,suit)
		_part(arms,Vector3(side*.14,-.28,-.36),Vector3(.075,.09,.08),shell)
		_limb(self,Vector3(side*.10,-.58,.10),Vector3(side*.13,-.65,-.30),.075,suit)
		_limb(self,Vector3(side*.13,-.65,-.30),Vector3(side*.13,-.94,-.49),.06,suit)
		_part(self,Vector3(side*.13,-.96,-.55),Vector3(.11,.09,.23),suit)
func _part(parent: Node3D, at: Vector3, dimensions: Vector3, material: Material) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.radius = .5
	mesh.height = 1.0
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.scale = dimensions
	parent.add_child(node)
func _limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(a.distance_to(b),radius*2)
	mesh.radial_segments = 10
	mesh.rings = 3
	node.mesh = mesh
	node.material_override = material
	node.position = (a+b)*.5
	var direction: Vector3 = (b-a).normalized()
	var side: Vector3 = direction.cross(Vector3.FORWARD).normalized()
	node.basis = Basis(side,direction,side.cross(direction))
	parent.add_child(node)
func steer(value: float) -> void:
	arms.rotation.z = -value*.12
	helmet.rotation.y = -value*.08
