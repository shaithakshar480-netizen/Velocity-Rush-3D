extends Node
## HudLayoutService: Manages custom HUD layouts for touch controls independently of SaveService schema.
## Stores positions, sizes, and opacity as JSON-safe numeric primitives (no Vector2 serialization).

const FILE_NAME: String = "hud_layout.json"
static var layouts: Dictionary = {}
static var loaded: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_loaded()

static func _get_path() -> String:
	var root: SceneTree = Engine.get_main_loop() as SceneTree
	if root != null and root.root != null:
		var save_svc = root.root.get_node_or_null("SaveService")
		if save_svc != null and not String(save_svc.PATH).is_empty():
			return String(save_svc.PATH).get_base_dir() + "/" + FILE_NAME
	return "user://" + FILE_NAME

static func ensure_loaded() -> void:
	if loaded:
		return
	load_from_disk()

static func load_from_disk() -> void:
	layouts.clear()
	loaded = true
	var file_path := _get_path()
	if not FileAccess.file_exists(file_path):
		return
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		for key: String in parsed:
			var item = parsed[key]
			if item is Dictionary:
				layouts[key] = {
					"x": float(item.get("x", 0.0)),
					"y": float(item.get("y", 0.0)),
					"w": float(item.get("w", 100.0)),
					"h": float(item.get("h", 100.0)),
					"nx": float(item.get("nx", 0.0)),
					"ny": float(item.get("ny", 0.0)),
					"opacity": float(item.get("opacity", 1.0))
				}

static func save_to_disk() -> void:
	var file_path := _get_path()
	var dir := file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return
	var sanitized: Dictionary = {}
	for key: String in layouts:
		var d: Dictionary = layouts[key]
		sanitized[key] = {
			"x": float(d.get("x", 0.0)),
			"y": float(d.get("y", 0.0)),
			"w": float(d.get("w", 100.0)),
			"h": float(d.get("h", 100.0)),
			"nx": float(d.get("nx", 0.0)),
			"ny": float(d.get("ny", 0.0)),
			"opacity": float(d.get("opacity", 1.0))
		}
	file.store_string(JSON.stringify(sanitized, "\t"))

static func save_control_layout(control_id: String, rect: Rect2, screen_size: Vector2, opacity: float = 1.0) -> void:
	ensure_loaded()
	var nx := 0.0
	var ny := 0.0
	if screen_size.x > 1.0 and screen_size.y > 1.0:
		nx = rect.position.x / screen_size.x
		ny = rect.position.y / screen_size.y
	layouts[control_id] = {
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
		"nx": nx,
		"ny": ny,
		"opacity": clampf(opacity, 0.15, 1.0)
	}
	save_to_disk()

static func get_control_layout(control_id: String) -> Dictionary:
	ensure_loaded()
	return layouts.get(control_id, {})

static func has_custom_layout(control_id: String = "") -> bool:
	ensure_loaded()
	if control_id.is_empty():
		return not layouts.is_empty()
	return layouts.has(control_id)

static func reset_all() -> void:
	layouts.clear()
	loaded = true
	var file_path := _get_path()
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)

static func apply_control(control_id: String, control: Control, screen_size: Vector2) -> bool:
	ensure_loaded()
	if not is_instance_valid(control):
		return false
	if not layouts.has(control_id):
		return false
	var data: Dictionary = layouts[control_id]
	var w: float = float(data.get("w", control.size.x))
	var h: float = float(data.get("h", control.size.y))
	var x: float = float(data.get("x", control.position.x))
	var y: float = float(data.get("y", control.position.y))
	if data.has("nx") and screen_size.x > 1.0 and screen_size.y > 1.0:
		x = float(data.nx) * screen_size.x
		y = float(data.ny) * screen_size.y
	if screen_size.x > 1.0 and screen_size.y > 1.0:
		x = clampf(x, 0.0, maxf(screen_size.x - w, 0.0))
		y = clampf(y, 0.0, maxf(screen_size.y - h, 0.0))
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = Vector2(x, y)
	control.size = Vector2(w, h)
	control.custom_minimum_size = Vector2(w, h)
	if data.has("opacity"):
		control.modulate.a = clampf(float(data.opacity), 0.15, 1.0)
	return true
