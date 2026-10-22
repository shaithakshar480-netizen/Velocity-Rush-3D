class_name RushTurboPresentation
extends Node

var turbo: RushTurboController
var ui: AutomotiveUI
var meter_box: VBoxContainer
var caption: Label
var button: Control
var button_label: Label
var ring_canvas: Control
var bottle_style: StyleBoxFlat
var clock: float = 0.0
var flash: float = 0.0
var boost_color := Color("58eaff")

const TURBO_SIZE := Vector2(108, 108)

func build(owner_ui: AutomotiveUI, controller: RushTurboController) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	bottle_style = StyleBoxFlat.new()
	bottle_style.set_corner_radius_all(4)
	bottle_style.border_color = Color("ddfbff")
	bottle_style.set_border_width_all(1)
	ui = owner_ui
	turbo = controller
	var page: Control = ui.screens["drive"]

	# Telemetry meter caption box in top-right hero cluster (aligned with mini segments)
	var box := VBoxContainer.new()
	meter_box = box
	page.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -228
	box.offset_right = -14
	box.offset_top = 136
	box.offset_bottom = 162
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	caption = ui._label(box, "TURBO x1  |  25+ KM/H", 15, Color("00e5ff"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_shadow_color", Color("020810d0"))
	caption.add_theme_constant_override("shadow_offset_x", 0)
	caption.add_theme_constant_override("shadow_offset_y", 1)

	# Touch button slot at bottom-right, carefully placed between power-up dock and pedals
	var slot := VBoxContainer.new()
	page.add_child(slot)
	slot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	slot.offset_left = -112
	slot.offset_right = -4
	slot.offset_top = -264
	slot.offset_bottom = -156

	ui._touch_control(slot, "turbo", "", TURBO_SIZE)
	button = ui.controls["turbo"]

	var round_style := StyleBoxFlat.new()
	round_style.bg_color = Color("071422f0")
	round_style.border_color = Color("00e5ffaa")
	round_style.set_border_width_all(1)
	round_style.set_corner_radius_all(54)
	round_style.shadow_color = Color("00e5ff44")
	round_style.shadow_size = 14
	round_style.shadow_offset = Vector2(0, 2)
	round_style.content_margin_left = 0
	round_style.content_margin_right = 0
	round_style.content_margin_top = 0
	round_style.content_margin_bottom = 0
	button.add_theme_stylebox_override("panel", round_style)

	button_label = button.get_child(0) as Label

	# Overlay Control for procedural rings + nitro bottle icon + labels
	var content := Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.remove_child(button_label)
	button.add_child(content)

	# Procedural canvas for dynamic state ring & clean nitro bottle rendering
	ring_canvas = Control.new()
	ring_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(ring_canvas)
	ring_canvas.draw.connect(_draw_turbo_ring)

	# 1. Bold BOOST text directly beneath the procedural bottle icon
	var boost_tag := Label.new()
	boost_tag.text = "BOOST"
	boost_tag.add_theme_font_size_override("font_size", 16)
	boost_tag.add_theme_color_override("font_color", Color("00e5ff"))
	boost_tag.add_theme_color_override("font_shadow_color", Color("020810d0"))
	boost_tag.add_theme_constant_override("shadow_offset_y", 1)
	boost_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boost_tag.offset_left = -32
	boost_tag.offset_right = 32
	boost_tag.offset_top = 57
	boost_tag.offset_bottom = 78
	boost_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boost_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(boost_tag)

	# 2. Inventory count label below BOOST text ("x0", "x1", etc.)
	content.add_child(button_label)
	button_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	button_label.offset_left = -32
	button_label.offset_right = 32
	button_label.offset_top = 78
	button_label.offset_bottom = 101
	button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button_label.add_theme_font_size_override("font_size", 18)
	button_label.add_theme_color_override("font_color", Color("ffffff"))
	button_label.add_theme_color_override("font_shadow_color", Color("00e5ff55"))
	button_label.add_theme_constant_override("shadow_offset_y", 1)

	# Ensure DriveInput.regions contains the updated 108x108 control
	DriveInput.regions = ui.controls
	ui.hud_elements["turbo"] = slot
	HudLayoutService.apply_control("turbo", slot, page.size)
	slot.resized.connect(func() -> void:
		if is_instance_valid(button):
			round_style.set_corner_radius_all(int(minf(button.size.x, button.size.y) * 0.5))
	)
	if is_instance_valid(button):
		round_style.set_corner_radius_all(int(minf(button.size.x, button.size.y) * 0.5))

func kick() -> void:
	flash = 1.0

func reset() -> void:
	flash = 0.0
	clock = 0.0

func _draw_turbo_ring() -> void:
	if ring_canvas == null or turbo == null:
		return

	var sz := ring_canvas.size if ring_canvas.size.x > 10.0 else TURBO_SIZE
	var center := sz * 0.5
	var s: float = minf(sz.x, sz.y) / TURBO_SIZE.x
	var radius: float = (minf(sz.x, sz.y) * 0.5) - 5.0 * s

	var count := turbo.available_charges()
	var ready := turbo.state == RushTurboController.State.READY and turbo.enabled
	var active := turbo.state == RushTurboController.State.ACTIVE
	var cooling := turbo.state == RushTurboController.State.COOLDOWN

	# 1. Dark circular interior
	ring_canvas.draw_circle(center, radius - 1.0, Color("071422f4"))

	# 2. Soft outer cyan halo
	var halo_alpha: float = 0.35 if active else (0.24 if ready else (0.08 if cooling else 0.14))
	ring_canvas.draw_arc(center, radius + 2.5, 0.0, TAU, 56, Color(0.0, 0.9, 1.0, halo_alpha), 6.0, true)

	# 3. Bright 2-3 px cyan core ring
	var core_color: Color
	var core_width: float = 2.4
	if active:
		var pulse: float = 0.85 + 0.15 * sin(clock * 14.0)
		core_color = Color("ffffff").lerp(Color("00e5ff"), 0.25)
		core_width = 3.0 * pulse
	elif ready:
		var breath: float = 0.75 + 0.25 * sin(clock * 3.5)
		core_color = Color("00e5ff").lerp(Color("7bf4ff"), breath)
		core_width = 2.4
	elif cooling:
		core_color = Color("4a6e8288")
		core_width = 1.8
	else:
		# EMPTY: still clearly visible, but subdued (not disappeared)
		core_color = Color("00e5ff66")
		core_width = 1.8
	ring_canvas.draw_arc(center, radius, 0.0, TAU, 56, core_color, core_width, true)

	# 4. Subtle inner ring
	var inner_color := Color("00e5ff28") if (ready or active) else Color("00e5ff12")
	ring_canvas.draw_arc(center, radius - 5.0, 0.0, TAU, 44, inner_color, 1.0, true)

	# 5. 4 small cardinal tick marks
	var tick_color := Color("00e5ffdd") if (ready or active) else Color("00e5ff44")
	for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir := Vector2(cos(a), sin(a))
		ring_canvas.draw_line(center + dir * (radius - 3.5), center + dir * (radius + 2.5), tick_color, 1.6, true)

	# Cooldown progress indicator when cooling
	if cooling:
		var cool_angle: float = fmod(clock * 2.2, 1.0) * TAU
		ring_canvas.draw_arc(center, radius, cool_angle, cool_angle + PI * 0.5, 20, Color("00e5ff"), 2.6, true)

	# 6. Large Procedural Nitrous Bottle Icon (28px height, optically centered in upper half)
	var bottle_col := Color("ffffff") if (ready or active) else Color("d6f3fa")
	if cooling:
		bottle_col = Color("7292a2")
	elif count == 0:
		bottle_col = Color("a2dbe8")
	ring_canvas.draw_set_transform(Vector2(center.x, 16.0 * s), -0.22, Vector2(1.2 * s, 1.2 * s))
	var bx: float = 0.0
	# Valve cap & nozzle knob
	ring_canvas.draw_rect(Rect2(bx - 1.5, 9.0, 3.0, 2.5), bottle_col)
	ring_canvas.draw_line(Vector2(bx + 1.5, 10.0), Vector2(bx + 4.5, 8.5), bottle_col, 1.8)
	# Valve neck
	ring_canvas.draw_rect(Rect2(bx - 2.5, 11.5, 5.0, 3.0), bottle_col)
	# Bottle cylinder body with rounded corners
	var body_rect := Rect2(bx - 7.0, 14.5, 14.0, 22.0)
	bottle_style.bg_color = Color("16cfee").lerp(bottle_col, 0.3)
	ring_canvas.draw_style_box(bottle_style, body_rect)
	# Dark band across the bottle
	ring_canvas.draw_line(Vector2(bx - 6.0, 24.0), Vector2(bx + 6.0, 24.0), Color("071422"), 2.2)
	# Specular highlight
	ring_canvas.draw_line(Vector2(bx - 4.5, 16.5), Vector2(bx - 4.5, 33.5), Color("00e5ffaa"), 1.2)

	ring_canvas.draw_set_transform(Vector2.ZERO)

func _process(delta: float) -> void:
	if turbo == null or not is_instance_valid(caption):
		return
	clock += delta
	flash = move_toward(flash, 0.0, delta * 3.0)

	var count := turbo.available_charges()
	var ready := turbo.state == RushTurboController.State.READY and turbo.enabled
	var active := turbo.state == RushTurboController.State.ACTIVE
	var cooling := turbo.state == RushTurboController.State.COOLDOWN

	# Telemetry caption text matching "TURBO x1 | 25+ KM/H" specification
	if active:
		caption.text = "TURBO x%d  |  ACTIVE" % count
		caption.modulate = Color("58f2ff")
	elif cooling:
		caption.text = "TURBO x%d  |  COOLING" % count
		caption.modulate = Color("85a5b5")
	elif count > 0 and turbo.car != null and turbo.car.signed_speed * 3.6 < turbo.spec.activation_min_speed:
		caption.text = "TURBO x%d  |  %d+ KM/H" % [count, int(turbo.spec.activation_min_speed)]
		caption.modulate = Color("ff9f38")
	else:
		caption.text = "TURBO x%d  |  25+ KM/H" % count if count > 0 else "TURBO x0  |  25+ KM/H"
		caption.modulate = Color("00e5ff") if ready else Color("72bccc")

	# Button label (count)
	if cooling:
		button_label.text = "COOL"
		button_label.modulate = Color("85a5b5")
	else:
		button_label.text = "x%d" % count
		button_label.modulate = Color("ffffff") if count > 0 else Color("a0d8e8")

	# Smooth pressed scale & ring redraw
	button.pivot_offset = button.size * 0.5
	button.scale = button.scale.lerp(Vector2.ONE * (0.93 if DriveInput.held("turbo") else 1.0), 1.0 - exp(-18.0 * delta))

	if ring_canvas != null and is_instance_valid(ring_canvas):
		ring_canvas.queue_redraw()

	# Speed label turbo flash/modulate
	ui.speed_label.modulate = Color.WHITE.lerp(Color("00e5ff"), turbo.intensity)
