extends Node
## Run through the isolated engine runner. Not executed in the authoring environment.
var failures: int = 0
var checks: int = 0
func _ready() -> void:
	var game: Node = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for _frame: int in 10000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame
	_check(game.ready_for_drive,"Premium resources boot")
	if not game.ready_for_drive:
		_finish()
		return
	_check(game.showroom.active and game.showroom.camera.current,"Home has showroom centerpiece")
	var studio_sky: Sky = game.showroom.environment.sky
	SaveService.settings.quality = 2
	game.performance.apply_quality()
	_check(game.showroom.environment.sky!=game.highway.lighting.sky,"Quality changes keep studio and highway reflections separate")
	_check(studio_sky.sky_material is PanoramaSkyMaterial,"Studio HDR imported")
	_check(game.ui.controls.accelerate is RushPedalControl and game.ui.controls.brake is RushPedalControl,"Both pedals use artwork controls")
	_check(GameAudio.music_home.stream is AudioStreamOggVorbis and GameAudio.music_race.stream is AudioStreamOggVorbis,"Compressed original music imported")
	_check(GameAudio.music_home.stream.loop and GameAudio.music_race.stream.loop,"Both decks loop")
	var balance: int = SaveService.balance()
	var progression: Dictionary = SaveService.progression.duplicate(true)
	game.start_drive()
	await get_tree().process_frame
	_check(game.cameras.camera.current and not game.showroom.active,"Race restores driving camera")
	SaveService.settings.steering_mode = 1
	DriveInput.set_enabled(true)
	game.ui.steering_ui._update()
	_touch(1,"left",true)
	_touch(2,"accelerate",true)
	_touch(3,"turbo",true)
	_check(DriveInput.pointers.size()==3,"Three simultaneous touch owners")
	_check(DriveInput.sample()==Vector2(-1,1),"Steering and gas remain active with Turbo finger")
	_touch(3,"turbo",false)
	_touch(2,"accelerate",false)
	_touch(4,"brake",true)
	_check(DriveInput.sample()==Vector2(-1,-1),"Steering and brake work together")
	DriveInput.clear()
	game.go_home()
	_check(SaveService.balance()==balance,"Presentation does not spend coins")
	_check(SaveService.progression.xp==progression.xp,"Presentation does not grant XP")
	for page: String in ["missions","daily","profile"]:
		game.open_progression(page)
		_check(game.ui.screen==page,"Menu opens: "+page)
		game.go_home()
	_check(game.progression_ui.mission_rows[0].progress is ProgressBar,"Mission cards have progress meters")
	game.queue_free()
	await get_tree().process_frame
	_finish()
func _touch(index: int, action: String, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = DriveInput.regions[action].get_global_rect().get_center()
	DriveInput._input(event)
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _finish() -> void:
	print("PREMIUM_SMOKE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
