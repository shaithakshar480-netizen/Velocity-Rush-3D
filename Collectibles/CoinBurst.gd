class_name RushCoinBurst
extends MeshInstance3D
var remaining: float = 0.0
var material: StandardMaterial3D
const DURATION: float = 0.26

func build(shared_mesh: Mesh) -> void:
	mesh = shared_mesh
	material = RoadGeometry.material(Color("ffe39c"),0.25,0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rotation.x = PI/2.0
	visible = false

func activate(at: Vector3) -> void:
	position = at
	remaining = DURATION
	visible = true
	scale = Vector3.ONE*0.6

func tick(delta: float) -> void:
	if remaining <= 0.0:
		return
	remaining = maxf(0.0,remaining-delta)
	var fraction := remaining/DURATION
	scale = Vector3.ONE*lerpf(1.7,0.6,fraction)
	var color := material.albedo_color
	color.a = fraction
	material.albedo_color = color
	visible = remaining>0.0
