extends SceneTree

func _init() -> void:
	var mat := StandardMaterial3D.new()
	print("default transparency: ", mat.transparency)
	print("default blend_mode: ", mat.blend_mode)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	print("after blend_mode=ADD, transparency: ", mat.transparency)
	print("mat.disable_fog: ", mat.disable_fog)
	mat.disable_fog = true
	print("after mat.disable_fog=true, get_flag: ", mat.get_flag(BaseMaterial3D.FLAG_DISABLE_FOG))
	mat.set_flag(BaseMaterial3D.FLAG_DISABLE_FOG, true)
	print("after set_flag, disable_fog: ", mat.disable_fog)
	quit(0)
