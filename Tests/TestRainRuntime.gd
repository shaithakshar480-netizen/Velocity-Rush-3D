extends SceneTree

func _init() -> void:
	var main_scene = load("res://Core/Main.tscn")
	var game = main_scene.instantiate()
	root.add_child(game)
	for i in 200:
		if game.ready_for_drive:
			break
		await process_frame
	print("Game ready: ", game.ready_for_drive)
	var rain_map_idx = -1
	for idx in game.map_dressing.maps.size():
		if game.map_dressing.maps[idx].id == "rain":
			rain_map_idx = idx
			break
	print("Rain map idx: ", rain_map_idx)
	game.start_drive()
	for i in 100:
		if game.state == game.State.DRIVING:
			break
		await process_frame
	print("Game state: ", game.state)
	var weather = game.map_dressing.weather
	for preset in [RushTimeOfDay.Preset.MORNING, RushTimeOfDay.Preset.EVENING, RushTimeOfDay.Preset.NIGHT]:
		var pname = RushTimeOfDay.PRESET_NAMES[preset]
		game.map_dressing.apply(rain_map_idx, preset)
		for f in 20:
			await process_frame
		print("--- Preset: ", pname, " ---")
		print("weather.enabled: ", weather.enabled)
		print("weather.visible: ", weather.visible)
		print("rain.emitting: ", weather.rain.emitting)
		print("rain.visible: ", weather.rain.visible)
		print("rain.amount: ", weather.rain.amount)
		print("rain.global_position: ", weather.rain.global_position)
		print("car.global_position: ", game.vehicle.global_position)
		print("rain.visibility_aabb: ", weather.rain.visibility_aabb)
		var mat = weather.rain.material_override as StandardMaterial3D
		print("rain_mat blend_mode: ", mat.blend_mode)
		print("rain_mat transparency: ", mat.transparency)
		print("rain_mat disable_fog: ", mat.disable_fog)
		print("rain_mat albedo_color: ", mat.albedo_color)
	quit(0)
