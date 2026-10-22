class_name RushMapPreview
extends Node
## Captures the real shared 3D world once at results; never captures HUD or during racing.
var game: Node
var buttons: Dictionary = {}
var busy: bool = false
func build(owner_game: Node) -> void:
	game = owner_game
	game.run.results_ready.connect(_results)
func bind_button(id: String, button: Button) -> void:
	buttons[id] = weakref(button)
	_refresh(id)
func _path(id: String) -> String:
	return "user://map_preview_visual_v2_"+id+".png"
func _refresh(id: String) -> void:
	if not buttons.has(id) or not FileAccess.file_exists(_path(id)): return
	var button: Button = (buttons[id] as WeakRef).get_ref() as Button
	if button==null: return
	var image: Image = Image.load_from_file(_path(id))
	if image==null or image.is_empty(): return
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	var card: TextureRect = button.get_node_or_null("MapCardPreview") as TextureRect
	if card!=null: card.texture = texture
	else: button.icon = texture
	button.add_theme_constant_override("icon_max_width",150)
	button.tooltip_text = "Actual map view from your last race"
func _results(_summary: Dictionary, _saved: bool) -> void:
	_capture.call_deferred()
func _capture() -> void:
	if busy or game.state!=game.State.RESULTS: return
	busy = true
	var id: String = String(game.map_dressing.maps[game.map_dressing.selected].id)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(384,216)
	viewport.world_3d = game.world.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.fov = 68.0
	camera.far = 650.0
	camera.position = game.vehicle.global_position+Vector3(3.0,3.2,7.0)
	camera.look_at(game.vehicle.global_position+Vector3(0,1.0,-28.0))
	camera.current = true
	await RenderingServer.frame_post_draw
	if is_instance_valid(game) and game.state==game.State.RESULTS:
		var image: Image = viewport.get_texture().get_image()
		if image!=null and not image.is_empty():
			if image.save_png(_path(id))==OK: _refresh(id)
	viewport.queue_free()
	busy = false
