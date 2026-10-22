class_name RushRaceExitDialog
extends CanvasLayer
## In-game modal: no native Window chrome, safe while the race is paused.
signal confirmed
signal canceled
var card: PanelContainer
var content: VBoxContainer
var continue_button: Button
var heading: Label
var message: Label
var actions: HBoxContainer
var closed: bool = true

func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015,0.025,0.045,0.25)
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card = PanelContainer.new()
	root.add_child(card)
	var glass: StyleBoxFlat = _style(Color(0.055,0.10,0.16,0.88),Color(0.52,0.72,0.83,0.8))
	glass.set_content_margin_all(26)
	glass.shadow_color = Color(0,0,0,0.42)
	glass.shadow_size = 18
	card.add_theme_stylebox_override("panel",glass)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation",22)
	card.add_child(content)
	var title_row := HBoxContainer.new()
	content.add_child(title_row)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 44
	title_row.add_child(spacer)
	heading = Label.new()
	heading.text = "LEAVE THIS RACE?"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color",Color("eff8ff"))
	title_row.add_child(heading)
	var close := _button("×",false)
	close.custom_minimum_size = Vector2(44,44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(cancel)
	title_row.add_child(close)
	message = Label.new()
	message.text = "Leaving discards this unfinished run’s coins, rewards and task progress.\nYour previously saved progress stays safe."
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_color",Color("dee8ee"))
	content.add_child(message)
	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation",18)
	content.add_child(actions)
	continue_button = _button("Continue Racing",false)
	continue_button.pressed.connect(cancel)
	actions.add_child(continue_button)
	var leave := _button("Leave Race",true)
	leave.pressed.connect(_confirm)
	actions.add_child(leave)
	var menu := LinkButton.new()
	menu.text = "Main Menu"
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu.custom_minimum_size.y = 44
	menu.add_theme_font_size_override("font_size",21)
	menu.add_theme_color_override("font_color",Color("c4d4de"))
	menu.pressed.connect(_confirm) # Same explicit discard confirmation; never bypass settlement guards.
	content.add_child(menu)
	get_viewport().size_changed.connect(_fit)
	hide()

func _style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	return style

func _button(text_value: String, danger: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 58
	button.add_theme_font_size_override("font_size",23)
	button.add_theme_color_override("font_color",Color("f3f8fc"))
	var fill: Color = Color("a51630") if danger else Color(0.43,0.51,0.60,0.23)
	var edge: Color = Color("c02742") if danger else Color("b6cbd8")
	button.add_theme_stylebox_override("normal",_style(fill,edge))
	button.add_theme_stylebox_override("hover",_style(fill.lightened(0.12),Color("def6ff")))
	button.add_theme_stylebox_override("pressed",_style(fill.darkened(0.18),edge))
	button.add_theme_stylebox_override("focus",_style(Color(0,0,0,0),Color("74e8ff")))
	return button

func _fit() -> void:
	if card==null: return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var width: float = minf(670.0,viewport_size.x*0.86)
	heading.add_theme_font_size_override("font_size",28 if width>500.0 else 23)
	message.add_theme_font_size_override("font_size",19 if width>500.0 else 17)
	card.custom_minimum_size = Vector2(width,0)
	card.size = Vector2(width,card.get_combined_minimum_size().y)
	card.position = (viewport_size-card.size)*0.5

func popup_centered(_requested_size: Vector2i = Vector2i.ZERO) -> void:
	closed = false
	show()
	_fit()
	_fit.call_deferred() # Containers settle wrapped text before final centering.
	continue_button.grab_focus()

func cancel() -> void:
	if closed: return
	closed = true
	hide()
	canceled.emit()

func _confirm() -> void:
	if closed: return
	closed = true
	hide()
	confirmed.emit()
