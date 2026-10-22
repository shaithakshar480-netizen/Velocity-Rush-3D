class_name RushAppExitDialog
extends CanvasLayer
## Presentation-only replacement for the native exit confirmation window.
signal confirmed
var dialog_text: String = "Are you sure you want to exit?"
var canvas: Control
var message: Label
var keep_button: Button
var closed: bool = true

func _ready() -> void:
	layer = 130
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := TextureRect.new()
	backdrop.texture = preload("res://Assets/UI/exit_carbon.svg")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = Control.new()
	root.add_child(canvas)
	canvas.size = Vector2(1000,560)
	var frame := TextureRect.new()
	frame.texture = preload("res://Assets/UI/exit_frame.svg")
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(frame)
	frame.size = canvas.size
	var title := Label.new()
	title.text = "VELOCITY RUSH 3D"
	_label(title,Rect2(130,30,740,60),34)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(message,Rect2(85,180,830,140),42)
	keep_button = _button("▷  KEEP PLAYING",Rect2(60,410,425,82))
	keep_button.pressed.connect(_cancel)
	var quit := _button("EXIT GAME  ▷",Rect2(515,410,425,82))
	quit.pressed.connect(_confirm)
	var close := _button("×",Rect2(896,26,60,60))
	close.add_theme_font_size_override("font_size",50)
	close.add_theme_color_override("font_color",Color("e6edf0"))
	close.pressed.connect(_cancel)
	get_viewport().size_changed.connect(_fit)
	hide()

func _label(label: Label, rect: Rect2, font_size: int) -> void:
	canvas.add_child(label)
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("f1f5f7"))
	label.add_theme_color_override("font_shadow_color",Color("00000099"))
	label.add_theme_constant_override("shadow_offset_y",2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _button(caption: String, rect: Rect2) -> Button:
	var button := Button.new()
	canvas.add_child(button)
	button.position = rect.position
	button.size = rect.size
	button.text = caption
	button.add_theme_font_size_override("font_size",32)
	button.add_theme_color_override("font_color",Color("10212a"))
	button.add_theme_color_override("font_hover_color",Color("091820"))
	button.add_theme_color_override("font_pressed_color",Color("ffffff"))
	button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	for state: String in ["hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1,1,1,0.10) if state=="hover" else Color(0,0,0,0.10)
		style.set_corner_radius_all(40)
		style.set_border_width_all(2 if state=="focus" else 0)
		style.border_color = Color("d9faff")
		button.add_theme_stylebox_override(state,style)
	return button

func _fit() -> void:
	if canvas==null: return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var factor: float = minf(viewport_size.x*0.84/1000.0,viewport_size.y*0.86/560.0)
	canvas.scale = Vector2.ONE*factor
	canvas.position = (viewport_size-Vector2(1000,560)*factor)*0.5

func popup_centered(_requested_size: Vector2i = Vector2i.ZERO) -> void:
	closed = false
	message.text = dialog_text
	show()
	_fit()
	keep_button.grab_focus()

func _cancel() -> void:
	closed = true
	hide()

func _confirm() -> void:
	if closed: return
	closed = true
	hide()
	confirmed.emit()
