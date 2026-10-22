extends Node
## Real engine checks; deliberately separate from offline mesh/source validation.
var checks: int = 0
var failures: int = 0
var game: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audit_scripts("res://")
	_check(RewardService.set_player_name("  Visual Tester  "),"Renamed player-name API saves")
	_check(SaveService.progression.name=="Visual Tester","Profile field changes without renaming autoload node")
	_check(RewardService.name==&"RewardService","Native Node name remains intact")
	var wallet_before := SaveService.balance()
	var xp_before := int(SaveService.progression.xp)
	game = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for _frame: int in 8000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame
	_check(game.ready_for_drive,"All detailed resources boot and prewarm")
	if not game.ready_for_drive:
		_finish()
		return
	for id: String in RushVehicleCatalog.IDS:
		var spec := RushVehicleCatalog.effective(id,{})
		game.vehicle.apply_configuration(spec,RushVehicleCatalog.paint_color(3))
		for detail: int in 3:
			game.vehicle.visual.set_quality(detail)
			game.showroom.set_quality(detail)
			game.showroom.show_vehicle(id,3)
			_check(game.vehicle.visual.quality==detail and game.vehicle.visual.wheel_pivots.size()==4,"Four animated wheels: %s tier %d"%[id,detail])
			var index: int = game.vehicle.visual.active_index
			_check(game.vehicle.visual.lod_models[index][detail].visible,"Real requested LOD is visible")
			_check(game.vehicle.visual.material_sets[index].Paint.albedo_color.is_equal_approx(RushVehicleCatalog.paint_color(3)),"Paint shared across LOD variants")
			for mode: int in 5:
				game.cameras.mode = mode
				_check(game.cameras.vehicle_offset().is_equal_approx(spec.camera_anchors[mode]),"Vehicle-specific camera anchor")
			await get_tree().process_frame
		_check(game.vehicle is CharacterBody3D and game.vehicle.collision_mask==6,"Physics root remains constrained CharacterBody")
	game.performance.driving = true
	SaveService.settings.quality = 2
	game.performance.apply_quality()
	for _tick: int in 2100:
		game.performance._process(1.0/30.0)
	_check(game.performance.degrade_stage==6 and game.performance.fallback,"Sustained slow frames reach bounded fallback")
	_check(game.performance.visual_level==0 and Engine.max_fps==30,"Fallback selects Low visual and 30 FPS cap")
	_check(SaveService.balance()==wallet_before and int(SaveService.progression.xp)==xp_before,"Visual changes cannot mutate economy")
	game.performance.driving = false
	SaveService.settings.quality = 1
	game.performance.apply_quality()
	game.go_home()
	game.open_garage()
	_check(game.showroom.camera.current and game.showroom.visual.quality==1,"Garage uses the selected visual quality")
	game.go_home()
	_check(game.showroom.active and game.showroom.camera.current,"Home uses cinematic showroom")
	game.queue_free()
	await get_tree().process_frame
	_finish()

func _audit_scripts(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir==null:
		_check(false,"Script directory can be read")
		return
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var script := load(folder.path_join(file)) as Script
		_check(script!=null and script.can_instantiate(),"Script loads: "+file)
		if script==null:
			continue
		var native: Array[Dictionary] = ClassDB.class_get_method_list(script.get_instance_base_type())
		var names: Array[String] = []
		for method: Dictionary in native:
			names.append(String(method.name))
		for method: Dictionary in script.get_script_method_list():
			var method_name := String(method.name)
			if not method_name.begins_with("_"):
				_check(method_name not in names,"No accidental native override: "+file+":"+method_name)
	for child: String in dir.get_directories():
		if not child.begins_with(".") and child!="build":
			_audit_scripts(folder.path_join(child))

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("VISUAL PASS: "+label)

func _finish() -> void:
	print("VISUAL_PASS_SMOKE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
