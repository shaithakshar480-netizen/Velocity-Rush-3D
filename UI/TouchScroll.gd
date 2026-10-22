class_name RushTouchScroll
extends ScrollContainer
## Menu-only gesture arbitration. Desktop wheel/native scrollbar behavior stays intact.
var finger: int = -1
var origin: Vector2 = Vector2.ZERO
var previous: Vector2 = Vector2.ZERO
var dragging: bool = false
var tap_cancelled: bool = false
var velocity: float = 0.0
var scroll_position: float = 0.0
var last_motion_ms: int = 0
var touched_slider: Slider
var slider_drag: bool = false
# The map picker is a horizontal card strip. Keep vertical scrolling as the
# default for all existing menus and opt into horizontal touch dragging there.
var touch_scroll_horizontal: bool = false
func _ready() -> void:
	scroll_deadzone = 12
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().node_added.connect(_node_added)
	_prepare_children(self)
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_reset()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if finger!=-1 or not get_global_rect().has_point(event.position) or _inner_scroll(self,event.position): return
			var bar: ScrollBar = get_h_scroll_bar() if touch_scroll_horizontal else get_v_scroll_bar()
			if bar.max_value<=bar.page or (bar.is_visible_in_tree() and bar.get_global_rect().has_point(event.position)): return
			if _text_at(self,event.position): return
			finger = event.index
			origin = event.position
			previous = origin
			velocity = 0.0
			tap_cancelled = false
			scroll_position = float(scroll_horizontal) if touch_scroll_horizontal else float(scroll_vertical)
			touched_slider = _slider_at(self,origin)
			get_viewport().set_input_as_handled()
		elif event.index==finger:
			get_viewport().set_input_as_handled()
			if dragging:
				propagate_notification(Control.NOTIFICATION_SCROLL_END)
				if event.canceled or Time.get_ticks_msec()-last_motion_ms>100: velocity = 0.0
			elif slider_drag:
				_mouse_button(event.position,false)
			elif not tap_cancelled and not event.canceled and get_global_rect().has_point(event.position):
				# Delay a tap until release: dragging can never purchase/toggle a child.
				_mouse_button(event.position,true)
				_mouse_button(event.position,false)
			finger = -1
			dragging = false
			slider_drag = false
			touched_slider = null
	elif event is InputEventScreenDrag and event.index==finger:
		get_viewport().set_input_as_handled()
		var movement: Vector2 = event.position-origin
		if movement.length()>float(scroll_deadzone): tap_cancelled = true
		if slider_drag:
			_mouse_motion(event.position,event.relative)
			return
		if not dragging:
			if absf(movement.x)>float(scroll_deadzone) and absf(movement.x)>absf(movement.y) and is_instance_valid(touched_slider):
				slider_drag = true
				_mouse_button(origin,true)
				_mouse_motion(event.position,event.relative)
				return
			if touch_scroll_horizontal:
				if absf(movement.x)<float(scroll_deadzone): return
			elif absf(movement.y)<float(scroll_deadzone):
				return
			dragging = true
			propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
			previous = event.position
			scroll_position = float(scroll_horizontal) if touch_scroll_horizontal else float(scroll_vertical)
			last_motion_ms = Time.get_ticks_msec()
		else:
			var now: int = Time.get_ticks_msec()
			var delta_seconds: float = maxf(float(now-last_motion_ms)/1000.0,0.001)
			var distance: float = previous.x-event.position.x if touch_scroll_horizontal else previous.y-event.position.y
			velocity = lerpf(velocity,clampf(distance/delta_seconds,-2400.0,2400.0),0.4)
			_move_scroll(distance)
			previous = event.position
			last_motion_ms = now
		get_viewport().set_input_as_handled()
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_reset()
		return
	if finger==-1 and absf(velocity)>5.0:
		_move_scroll(velocity*minf(delta,0.05))
		velocity *= exp(-9.0*delta)
func _move_scroll(distance: float) -> void:
	var bar: ScrollBar = get_h_scroll_bar() if touch_scroll_horizontal else get_v_scroll_bar()
	var maximum: float = maxf(0.0,bar.max_value-bar.page)
	scroll_position = clampf(scroll_position+distance,0.0,maximum)
	if touch_scroll_horizontal:
		scroll_horizontal = roundi(scroll_position)
	else:
		scroll_vertical = roundi(scroll_position)
	if scroll_position<=0.0 or scroll_position>=maximum: velocity = 0.0
func _mouse_button(point: Vector2, pressed: bool) -> void:
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.position = point
	mouse.global_position = point
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse.pressed = pressed
	Input.parse_input_event(mouse)
func _mouse_motion(point: Vector2, relative: Vector2) -> void:
	var mouse: InputEventMouseMotion = InputEventMouseMotion.new()
	mouse.position = point
	mouse.global_position = point
	mouse.relative = relative
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mouse)
func _reset() -> void:
	if slider_drag:
		slider_drag = false
		_mouse_button(previous,false)
	if dragging: propagate_notification(Control.NOTIFICATION_SCROLL_END)
	finger = -1
	dragging = false
	velocity = 0.0
	touched_slider = null
func _inner_scroll(parent: Node, point: Vector2) -> bool:
	for child: Node in parent.get_children():
		if child is ScrollContainer and child.is_visible_in_tree() and child.get_global_rect().has_point(point): return true
		if _inner_scroll(child,point): return true
	return false
func _text_at(parent: Node, point: Vector2) -> bool:
	for child: Node in parent.get_children():
		if (child is LineEdit or child is TextEdit) and child.is_visible_in_tree() and child.get_global_rect().has_point(point): return true
		if _text_at(child,point): return true
	return false
func _slider_at(parent: Node, point: Vector2) -> Slider:
	for child: Node in parent.get_children():
		if child is Slider and child.is_visible_in_tree() and child.get_global_rect().has_point(point): return child as Slider
		var found: Slider = _slider_at(child,point)
		if found!=null: return found
	return null
func _node_added(node: Node) -> void:
	if is_ancestor_of(node): _prepare_control.call_deferred(node)
func _prepare_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		_prepare_control(child)
		_prepare_children(child)
func _prepare_control(node: Node) -> void:
	if not is_instance_valid(node) or not is_ancestor_of(node): return
	if node is ScrollBar or node is Slider or node is LineEdit or node is TextEdit or node is ScrollContainer: return
	if node is Control:
		var control: Control = node as Control
		if control.mouse_filter==Control.MOUSE_FILTER_STOP: control.mouse_filter = Control.MOUSE_FILTER_PASS
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT or what==NOTIFICATION_APPLICATION_PAUSED: _reset()
func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_node_added): get_tree().node_added.disconnect(_node_added)
