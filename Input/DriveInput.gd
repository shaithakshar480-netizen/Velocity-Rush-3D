extends Node
## Physics reads only sample(). UI registers hit regions; every touch owns its ID.
@export var wheel_max_degrees: float = 80.0
@export var wheel_return_degrees: float = 360.0
var wheel_drag_valid: bool = false
var wheel_drag_angle: float = 0.0
var last_mode: int = -1
var wheel_pointer: int = -1
var wheel_target: float = 0.0
var wheel_angle: float = 0.0
var button_steering: float = 0.0
var turbo_pending: bool = false
var enabled: bool = false
var countdown_capture: bool = false
var regions: Dictionary = {}
var pointers: Dictionary = {}
var mouse_action: String = ""
var brake_hold: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -30
	SaveService.changed.connect(_controls_changed)
	last_mode = int(SaveService.settings.steering_mode)
	_bind("accelerate", [KEY_W, KEY_UP])
	_bind("brake", [KEY_S, KEY_DOWN])
	_bind("left", [KEY_A, KEY_LEFT])
	_bind("right", [KEY_D, KEY_RIGHT])
	_bind("camera", [KEY_C])
	_bind("pause", [KEY_ESCAPE])
	_bind("restart", [KEY_R])
	_bind("turbo", [KEY_SHIFT])
	_bind("horn", [KEY_H])

func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key: int in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key as Key
		InputMap.action_add_event(action, event)

func clear() -> void:
	wheel_pointer = -1
	wheel_target = 0.0
	wheel_angle = 0.0
	button_steering = 0.0
	wheel_drag_valid = false
	turbo_pending = false
	pointers.clear()
	mouse_action = ""
	brake_hold = 0.0

func set_enabled(value: bool) -> void:
	var retain_countdown_touches := value and countdown_capture
	enabled = value
	countdown_capture = false
	if not retain_countdown_touches:
		clear()

func arm_countdown() -> void:
	enabled = false
	clear()
	countdown_capture = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		clear()

func _input(event: InputEvent) -> void:
	# Touch-to-mouse emulation enables menu widgets. Driving owns real touch IDs;
	# ignore synthetic mouse events (device -1) to avoid duplicate wheel/pedal input.
	if event.device == -1 and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if enabled and event is InputEventKey and event.is_action_pressed("turbo") and not event.echo:
		turbo_pending = true
	if not enabled and not countdown_capture:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			pointers[event.index] = _hit(event.position)
			if pointers[event.index]=="wheel" and wheel_pointer==-1:
				wheel_pointer = event.index
				_begin_wheel(event.position)
			if enabled and pointers[event.index] == "turbo":
				turbo_pending = true
		else:
			pointers.erase(event.index)
			if event.index==wheel_pointer:
				wheel_pointer = -1
	elif event is InputEventScreenDrag and pointers.has(event.index):
		if event.index==wheel_pointer:
			_wheel_position(event.position)
		elif pointers[event.index] not in ["left", "right"]:
			pointers[event.index] = _hit(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_action = _hit(event.position) if event.pressed else ""
		if mouse_action=="wheel":
			wheel_pointer = -2
			_begin_wheel(event.position)
		elif wheel_pointer==-2:
			wheel_pointer = -1
		if enabled and mouse_action == "turbo":
			turbo_pending = true
	elif event is InputEventMouseMotion and not mouse_action.is_empty():
		if wheel_pointer==-2:
			_wheel_position(event.position)
		elif mouse_action not in ["left", "right"]:
			mouse_action = _hit(event.position) if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else ""

func _hit(point: Vector2) -> String:
	for action: String in regions:
		var control: Control = regions[action]
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return action
	return ""

func held(action: String) -> bool:
	if not enabled:
		return false
	if Input.is_action_pressed(action) or mouse_action == action:
		return true
	for pointer: int in pointers:
		if pointers[pointer] == action:
			return true
	return false

func sample() -> Vector2:
	# Brake wins if both pedals are touched; opposing steering cancels.
	if not enabled:
		return Vector2.ZERO
	var steering: float = button_steering
	if held("left") and held("right"):
		steering = 0.0
	if steering==0.0 and not held("left") and not held("right"):
		match effective_mode():
			0:
				var value := clampf(wheel_angle / maxf(wheel_max_degrees, 1.0), -1.0, 1.0)
				var deadzone := clampf(float(SaveService.settings.get("wheel_deadzone", 0.04)), 0.0, 0.20)
				if absf(value) <= deadzone:
					steering = 0.0
				else:
					var norm := (absf(value) - deadzone) / maxf(1.0 - deadzone, 0.001)
					# Sensitivity is applied once by ArcadeVehicle, equally for both modes.
					steering = signf(value) * pow(clampf(norm, 0.0, 1.0), 1.1)
	return Vector2(clampf(steering,-1.0,1.0),-1.0 if held("brake") else float(held("accelerate")))

func consume_turbo_request() -> bool:
	var requested := turbo_pending and enabled
	turbo_pending = false
	return requested

func effective_mode() -> int:
	# Keep historical Schema-5 sensor settings readable without rewriting saves.
	return 0 if int(SaveService.settings["steering_mode"])==0 else 1

func _controls_changed() -> void:
	var mode := int(SaveService.settings.steering_mode)
	if mode!=last_mode:
		last_mode = mode
		clear()

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	var button_target: float = float(held("right"))-float(held("left"))
	var response: float = 10.0 if is_zero_approx(button_target) or button_target*button_steering<0.0 else 7.0
	button_steering = move_toward(button_steering,button_target,response*delta)
	if held("left") and held("right"): button_steering = 0.0
	if wheel_pointer == -1:
		wheel_target = move_toward(wheel_target, 0.0, wheel_return_degrees * delta * (1.0 if bool(SaveService.settings.steering_assist) else 0.75))
		wheel_angle = lerpf(wheel_angle, wheel_target, 1.0 - exp(-20.0 * delta))
		if is_zero_approx(wheel_target) and absf(wheel_angle) < 0.05:
			wheel_angle = 0.0
	else:
		wheel_angle = lerpf(wheel_angle, wheel_target, 1.0 - exp(-36.0 * delta))
func _wheel_drag(dx: float) -> void:
	wheel_target = clampf(wheel_target+dx*0.9,-wheel_max_degrees,wheel_max_degrees)

func _begin_wheel(point: Vector2) -> void:
	var control: Control = regions.wheel
	var offset := point - control.get_global_rect().get_center()
	wheel_drag_angle = offset.angle()
	var min_dead := minf(control.size.x, control.size.y) * 0.08
	wheel_drag_valid = offset.length() >= min_dead

func _wheel_position(point: Vector2) -> void:
	var control: Control = regions.wheel
	var offset := point - control.get_global_rect().get_center()
	var min_dead := minf(control.size.x, control.size.y) * 0.08
	if offset.length() < min_dead:
		wheel_drag_valid = false
		wheel_drag_angle = offset.angle()
		return
	var angle := offset.angle()
	if not wheel_drag_valid:
		wheel_drag_valid = true
		wheel_drag_angle = angle
		return
	var delta_rad: float = angle_difference(wheel_drag_angle, angle)
	wheel_drag_angle = angle
	if absf(delta_rad) > 2.8:
		return
	var movement := rad_to_deg(delta_rad)
	wheel_target = clampf(wheel_target + movement, -wheel_max_degrees, wheel_max_degrees)
