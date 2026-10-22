extends SceneTree

func _init() -> void:
	var cpu := CPUParticles3D.new()
	print("has custom_aabb: ", "custom_aabb" in cpu)
	print("has visibility_aabb: ", "visibility_aabb" in cpu)
	print("has emission_shape: ", "emission_shape" in cpu)
	print("has speed_scale: ", "speed_scale" in cpu)
	var mat := StandardMaterial3D.new()
	print("mat has disable_fog: ", "disable_fog" in mat)
	quit(0)
