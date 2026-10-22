class_name RushHudCustomizeOverlay
extends Control

## Interactive HUD Customizer: Drag reposition, corner resize, two-finger pinch, and opacity control.
## Exactly follows game aesthetics with neon cyan accents, glass badges, and responsive controls.

signal closed

var ui: AutomotiveUI
var items: Dictionary = {} # id -> {"control": Control, "name": String, "min": Vector2, "max": Vector2}

var selected_id: String = ""
var active_drag_id: String = ""
var active_corner: int = -1 # 0: TL, 1: TR, 2: BL, 3: BR, -1: body drag
var drag_start_pointer: Vector2 = Vector2.ZERO
var drag_start_rect: Rect2 = Rect2()

# Multitouch tracking
var touch_points: Dictionary = {} # pointer_index -> Vector2
var pinch_active: bool = false
var pinch_id: String = ""
var pinch_initial_dist: float = 0.0
var pinch_initial_rect: Rect2 = Rect2()

var opacity_slider: HSlider
var opacity_label: Label

const CORNER_SIZE: float = 28.0

func setup(owner_ui: AutomotiveUI) -> void:
	ui = owner_ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 300
	_build_elements()
	_build_ui()
	if not items.is_empty():
		_select_item(items.keys()[0])

func _build_elements() -> void:
	items.clear()
	var mode := DriveInput.effective_mode()
	if mode == 0 and ui.hud_elements.has("wheel"):
		items["wheel"] = {
			"control": ui.hud_elements["wheel"],
			"name": "STEERING WHEEL",
			"min": Vector2(180, 180),
			"max": Vector2(560, 560)
		}
	elif mode == 1 and ui.hud_elements.has("steer_buttons"):
		items["steer_buttons"] = {
			"control": ui.hud_elements["steer_buttons"],
			"name": "STEER BUTTONS",
			"min": Vector2(160, 80),
			"max": Vector2(460, 200)
		}
	if ui.hud_elements.has("pedals"):
		items["pedals"] = {
			"control": ui.hud_elements["pedals"],
			"name": "PEDALS",
			"min": Vector2(200, 90),
			"max": Vector2(520, 240)
		}
	if ui.hud_elements.has("horn"):
		items["horn"] = {
			"control": ui.hud_elements["horn"],
			"name": "HORN",
			"min": Vector2(60, 60),
			"max": Vector2(180, 180)
		}
	if ui.hud_elements.has("turbo"):
		items["turbo"] = {
			"control": ui.hud_elements["turbo"],
			"name": "TURBO / BOOST",
			"min": Vector2(64, 64),
			"max": Vector2(220, 220)
		}
	if ui.hud_elements.has("pause"):
		items["pause"] = {
			"control": ui.hud_elements["pause"],
			"name": "PAUSE",
			"min": Vector2(40, 40),
			"max": Vector2(130, 130)
		}
	if ui.hud_elements.has("powerup_dock"):
		items["powerup_dock"] = {
			"control": ui.hud_elements["powerup_dock"],
			"name": "POWER-UPS",
			"min": Vector2(60, 150),
			"max": Vector2(140, 480)
		}
	# Ensure controls are visible for editing
	for id: String in items:
		var c: Control = items[id].control
		if is_instance_valid(c):
			c.visible = true

func _build_ui() -> void:
	# Top bar banner
	var top_bar := PanelContainer.new()
	add_child(top_bar)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 16
	top_bar.offset_right = -16
	top_bar.offset_top = 12
	top_bar.offset_bottom = 80
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color("071422ee")
	bar_style.border_color = Color("00e5ffaa")
	bar_style.set_border_width_all(1)
	bar_style.set_corner_radius_all(14)
	bar_style.shadow_color = Color("00e5ff33")
	bar_style.shadow_size = 12
	bar_style.content_margin_left = 16
	bar_style.content_margin_right = 16
	bar_style.content_margin_top = 8
	bar_style.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", bar_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	top_bar.add_child(hbox)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title_box)

	var title := Label.new()
	title.text = "CUSTOMIZE HUD"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("00e5ff"))
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Drag reposition • Corner/pinch resize • Tap element to adjust opacity"
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color("a8c7d8"))
	title_box.add_child(subtitle)

	# Opacity controller
	var opacity_box := HBoxContainer.new()
	opacity_box.add_theme_constant_override("separation", 8)
	hbox.add_child(opacity_box)

	opacity_label = Label.new()
	opacity_label.text = "OPACITY: 100%"
	opacity_label.add_theme_font_size_override("font_size", 12)
	opacity_label.add_theme_color_override("font_color", Color("00e5ff"))
	opacity_box.add_child(opacity_label)

	opacity_slider = HSlider.new()
	opacity_slider.min_value = 20
	opacity_slider.max_value = 100
	opacity_slider.step = 5
	opacity_slider.value = 100
	opacity_slider.custom_minimum_size = Vector2(100, 24)
	opacity_slider.value_changed.connect(_on_opacity_changed)
	opacity_box.add_child(opacity_slider)

	var reset_btn := Button.new()
	reset_btn.text = "RESET DEFAULTS"
	reset_btn.custom_minimum_size = Vector2(140, 40)
	_style_button(reset_btn, false)
	reset_btn.pressed.connect(_on_reset_pressed)
	hbox.add_child(reset_btn)

	var save_btn := Button.new()
	save_btn.text = "SAVE & EXIT"
	save_btn.custom_minimum_size = Vector2(130, 40)
	_style_button(save_btn, true)
	save_btn.pressed.connect(_on_save_pressed)
	hbox.add_child(save_btn)

func _style_button(btn: Button, primary: bool) -> void:
	btn.add_theme_font_size_override("font_size", 13)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("00e5ff") if primary else Color("142232")
	normal.border_color = Color("ffffff") if primary else Color("00e5ff88")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_color_override("font_color", Color("071422") if primary else Color("eaf3f7"))

func _select_item(id: String) -> void:
	selected_id = id
	if id != "" and items.has(id):
		var c: Control = items[id].control
		if is_instance_valid(c) and is_instance_valid(opacity_slider) and is_instance_valid(opacity_label):
			var a_pct := int(roundf(c.modulate.a * 100.0))
			opacity_slider.set_value_no_signal(a_pct)
			opacity_label.text = "%s: %d%%" % [items[id].name, a_pct]

func _on_opacity_changed(val: float) -> void:
	if selected_id != "" and items.has(selected_id):
		var c: Control = items[selected_id].control
		if is_instance_valid(c):
			c.modulate.a = val / 100.0
			opacity_label.text = "%s: %d%%" % [items[selected_id].name, int(val)]

func _on_reset_pressed() -> void:
	GameAudio.click()
	HudLayoutService.reset_all()
	_restore_defaults()
	if selected_id != "":
		_select_item(selected_id)
	queue_redraw()

func _restore_defaults() -> void:
	if ui.hud_elements.has("wheel"):
		var w: Control = ui.hud_elements["wheel"]
		w.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		w.offset_left = 10
		w.offset_right = 350
		w.offset_top = -350
		w.offset_bottom = -10
		w.custom_minimum_size = Vector2(340, 340)
		w.modulate.a = 1.0
	if ui.hud_elements.has("steer_buttons"):
		var b: Control = ui.hud_elements["steer_buttons"]
		b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		b.offset_left = 0
		b.offset_right = 258
		b.offset_top = -124
		b.offset_bottom = -10
		b.custom_minimum_size = Vector2(258, 114)
		b.modulate.a = 1.0
	if ui.hud_elements.has("pedals"):
		var p: Control = ui.hud_elements["pedals"]
		p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		p.offset_left = -294
		p.offset_right = 0
		p.offset_top = -136
		p.offset_bottom = -10
		p.custom_minimum_size = Vector2(294, 126)
		p.modulate.a = 1.0
	if ui.hud_elements.has("horn"):
		var h: Control = ui.hud_elements["horn"]
		h.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		h.offset_left = 360
		h.offset_right = 444
		h.offset_top = -104
		h.offset_bottom = -20
		h.custom_minimum_size = Vector2(84, 84)
		h.modulate.a = 1.0
	if ui.hud_elements.has("turbo"):
		var t: Control = ui.hud_elements["turbo"]
		t.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		t.offset_left = -112
		t.offset_right = -4
		t.offset_top = -264
		t.offset_bottom = -156
		t.custom_minimum_size = Vector2(108, 108)
		t.modulate.a = 1.0
	if ui.hud_elements.has("pause"):
		var ps: Control = ui.hud_elements["pause"]
		ps.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		ps.offset_left = 16
		ps.offset_top = 16
		ps.offset_right = 68
		ps.offset_bottom = 68
		ps.custom_minimum_size = Vector2(52, 52)
		ps.modulate.a = 1.0
	if ui.hud_elements.has("powerup_dock"):
		var d: Control = ui.hud_elements["powerup_dock"]
		d.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		d.offset_left = -84
		d.offset_right = -20
		d.offset_top = 194
		d.offset_bottom = 398
		d.custom_minimum_size = Vector2(64, 204)
		d.modulate.a = 1.0

func _on_save_pressed() -> void:
	GameAudio.click()
	var screen_sz := size
	for id: String in items:
		var c: Control = items[id].control
		if is_instance_valid(c):
			var r := Rect2(c.position, c.size)
			HudLayoutService.save_control_layout(id, r, screen_sz, c.modulate.a)
	closed.emit()
	queue_free()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Subtle dark overlay scrim
	draw_rect(Rect2(Vector2.ZERO, size), Color("040d1866"))

	for id: String in items:
		var item: Dictionary = items[id]
		var c: Control = item.control
		if not is_instance_valid(c):
			continue
		var rect := Rect2(c.global_position, c.size)
		var is_active := (id == active_drag_id or id == pinch_id or id == selected_id)
		var border_col := Color("00e5ff") if is_active else Color("00e5ff66")
		var bg_col := Color("00e5ff22") if is_active else Color("00e5ff0a")

		# Fill and frame
		draw_rect(rect, bg_col)
		draw_rect(rect, border_col, false, 2.0 if is_active else 1.2)

		# Label pill on top edge
		var opacity_pct := int(roundf(c.modulate.a * 100.0))
		var label_text := "%s (%d×%d) • %d%%" % [item.name, int(rect.size.x), int(rect.size.y), opacity_pct]
		var font: Font = get_theme_default_font()
		var font_sz := 12
		var text_w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
		var pill_rect := Rect2(rect.position + Vector2(6, -22), Vector2(text_w + 14, 20))
		draw_rect(pill_rect, Color("071422ee"))
		draw_rect(pill_rect, border_col, false, 1.0)
		draw_string(font, pill_rect.position + Vector2(7, 14), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, Color("ffffff") if is_active else Color("a8c7d8"))

		# 4 Corner resize handles
		var corners := _get_corners(rect)
		for ci: int in 4:
			var handle_rect := Rect2(corners[ci] - Vector2(CORNER_SIZE * 0.5, CORNER_SIZE * 0.5), Vector2(CORNER_SIZE, CORNER_SIZE))
			var handle_active := (is_active and active_corner == ci)
			draw_rect(handle_rect, Color("00e5ff") if handle_active else Color("071422f0"))
			draw_rect(handle_rect, Color("ffffff") if handle_active else Color("00e5ff"), false, 2.0)
			draw_circle(corners[ci], 3.0, Color("ffffff") if not handle_active else Color("071422"))

func _get_corners(r: Rect2) -> Array[Vector2]:
	return [
		r.position,                             # 0: TL
		Vector2(r.end.x, r.position.y),         # 1: TR
		Vector2(r.position.x, r.end.y),         # 2: BL
		r.end                                  # 3: BR
	]

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = event.position
			if touch_points.size() >= 2:
				_begin_pinch()
			else:
				_begin_pointer(event.position)
		else:
			touch_points.erase(event.index)
			if touch_points.size() < 2 and pinch_active:
				pinch_active = false
			if touch_points.is_empty():
				_end_drag()

	elif event is InputEventScreenDrag:
		touch_points[event.index] = event.position
		if pinch_active and touch_points.size() >= 2:
			_update_pinch()
		elif active_drag_id != "":
			_update_pointer(event.position)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_drag()

	elif event is InputEventMouseMotion and active_drag_id != "":
		_update_pointer(event.position)

func _begin_pointer(pos: Vector2) -> void:
	# 1. Check corner handles first (highest priority)
	for id: String in items:
		var c: Control = items[id].control
		if not is_instance_valid(c):
			continue
		var rect := Rect2(c.global_position, c.size)
		var corners := _get_corners(rect)
		for ci: int in 4:
			if pos.distance_to(corners[ci]) <= CORNER_SIZE:
				active_drag_id = id
				active_corner = ci
				drag_start_pointer = pos
				drag_start_rect = Rect2(c.position, c.size)
				_select_item(id)
				return

	# 2. Check element body (reposition)
	for id: String in items:
		var c: Control = items[id].control
		if not is_instance_valid(c):
			continue
		var rect := Rect2(c.global_position, c.size)
		if rect.has_point(pos):
			active_drag_id = id
			active_corner = -1
			drag_start_pointer = pos
			drag_start_rect = Rect2(c.position, c.size)
			_select_item(id)
			return

func _update_pointer(pos: Vector2) -> void:
	if active_drag_id == "" or not items.has(active_drag_id):
		return
	var item: Dictionary = items[active_drag_id]
	var c: Control = item.control
	if not is_instance_valid(c):
		return

	var delta := pos - drag_start_pointer
	var min_sz: Vector2 = item.min
	var max_sz: Vector2 = item.max

	if active_corner == -1:
		# Body dragging
		var new_x := clampf(drag_start_rect.position.x + delta.x, 0.0, maxf(size.x - c.size.x, 0.0))
		var new_y := clampf(drag_start_rect.position.y + delta.y, 80.0, maxf(size.y - c.size.y, 80.0))
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.position = Vector2(new_x, new_y)
	else:
		# Corner dragging
		var r := drag_start_rect
		match active_corner:
			0: # TL
				var new_w := clampf(r.size.x - delta.x, min_sz.x, max_sz.x)
				var new_h := clampf(r.size.y - delta.y, min_sz.y, max_sz.y)
				var new_x := r.end.x - new_w
				var new_y := r.end.y - new_h
				c.set_anchors_preset(Control.PRESET_TOP_LEFT)
				c.position = Vector2(new_x, new_y)
				c.size = Vector2(new_w, new_h)
				c.custom_minimum_size = Vector2(new_w, new_h)
			1: # TR
				var new_w := clampf(r.size.x + delta.x, min_sz.x, max_sz.x)
				var new_h := clampf(r.size.y - delta.y, min_sz.y, max_sz.y)
				var new_y := r.end.y - new_h
				c.set_anchors_preset(Control.PRESET_TOP_LEFT)
				c.position = Vector2(r.position.x, new_y)
				c.size = Vector2(new_w, new_h)
				c.custom_minimum_size = Vector2(new_w, new_h)
			2: # BL
				var new_w := clampf(r.size.x - delta.x, min_sz.x, max_sz.x)
				var new_h := clampf(r.size.y + delta.y, min_sz.y, max_sz.y)
				var new_x := r.end.x - new_w
				c.set_anchors_preset(Control.PRESET_TOP_LEFT)
				c.position = Vector2(new_x, r.position.y)
				c.size = Vector2(new_w, new_h)
				c.custom_minimum_size = Vector2(new_w, new_h)
			3: # BR
				var new_w := clampf(r.size.x + delta.x, min_sz.x, max_sz.x)
				var new_h := clampf(r.size.y + delta.y, min_sz.y, max_sz.y)
				c.set_anchors_preset(Control.PRESET_TOP_LEFT)
				c.size = Vector2(new_w, new_h)
				c.custom_minimum_size = Vector2(new_w, new_h)

func _end_drag() -> void:
	active_drag_id = ""
	active_corner = -1

func _begin_pinch() -> void:
	var keys := touch_points.keys()
	if keys.size() < 2:
		return
	var p1: Vector2 = touch_points[keys[0]]
	var p2: Vector2 = touch_points[keys[1]]
	var center := (p1 + p2) * 0.5

	# Find closest control to pinch center
	var best_id := ""
	var best_dist := 999999.0
	for id: String in items:
		var c: Control = items[id].control
		if not is_instance_valid(c):
			continue
		var rect := Rect2(c.global_position, c.size)
		var d := rect.get_center().distance_to(center)
		if d < best_dist:
			best_dist = d
			best_id = id

	if best_id != "" and best_dist < 400.0:
		pinch_id = best_id
		pinch_active = true
		pinch_initial_dist = maxf(p1.distance_to(p2), 10.0)
		var c: Control = items[best_id].control
		pinch_initial_rect = Rect2(c.position, c.size)
		_select_item(best_id)

func _update_pinch() -> void:
	if not pinch_active or pinch_id == "" or not items.has(pinch_id):
		return
	var keys := touch_points.keys()
	if keys.size() < 2:
		return
	var p1: Vector2 = touch_points[keys[0]]
	var p2: Vector2 = touch_points[keys[1]]
	var current_dist := p1.distance_to(p2)
	var ratio := current_dist / pinch_initial_dist

	var item: Dictionary = items[pinch_id]
	var c: Control = item.control
	if not is_instance_valid(c):
		return

	var orig_sz := pinch_initial_rect.size
	var orig_center := pinch_initial_rect.get_center()
	var new_w := clampf(orig_sz.x * ratio, item.min.x, item.max.x)
	var new_h := clampf(orig_sz.y * ratio, item.min.y, item.max.y)
	var new_sz := Vector2(new_w, new_h)
	var new_pos := orig_center - new_sz * 0.5
	new_pos.x = clampf(new_pos.x, 0.0, maxf(size.x - new_sz.x, 0.0))
	new_pos.y = clampf(new_pos.y, 80.0, maxf(size.y - new_sz.y, 80.0))

	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = new_pos
	c.size = new_sz
	c.custom_minimum_size = new_sz
