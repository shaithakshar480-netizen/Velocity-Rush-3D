class_name RushRaceModeStyle
extends RefCounted
static func skin(kind: String, margin: int = 10) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://Assets/UI/race_mode_"+kind+".svg") as Texture2D
	style.texture_margin_left = 24
	style.texture_margin_right = 24
	style.texture_margin_top = 24
	style.texture_margin_bottom = 24
	style.set_content_margin_all(margin)
	return style

static func button(control: Button, selected: bool = false) -> void:
	control.custom_minimum_size.y = 54
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.add_theme_font_size_override("font_size",23)
	control.add_theme_color_override("font_color",Color("e4f5fc"))
	control.add_theme_color_override("font_pressed_color",Color.WHITE)
	control.add_theme_color_override("font_hover_color",Color.WHITE)
	control.add_theme_stylebox_override("normal",skin("silver"))
	control.add_theme_stylebox_override("hover",skin("cyan"))
	control.add_theme_stylebox_override("pressed",skin("cyan"))
	if selected: control.add_theme_stylebox_override("normal",skin("cyan"))

static func frame(page: Control, column: VBoxContainer) -> void:
	var parent: Node = column.get_parent()
	parent.remove_child(column)
	var panel := PanelContainer.new()
	parent.add_child(panel)
	panel.add_theme_stylebox_override("panel",skin("frame",32))
	panel.add_child(column)
	column.add_theme_constant_override("separation",12)
	var fit: Callable = func() -> void:
		column.custom_minimum_size.x = minf(660.0,maxf(280.0,page.size.x-128.0))
	page.resized.connect(fit)
	fit.call_deferred()

static func hero(control: Button) -> void:
	button(control,true)
	control.text = ""
	control.custom_minimum_size.y = 170
	var content := VBoxContainer.new()
	control.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 18
	content.offset_right = -18
	content.offset_top = 18
	content.offset_bottom = -18
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = "5-RACER HIGHWAY RACE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",26)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)
	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)
	var tiles := HBoxContainer.new()
	tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(tiles)
	for caption: String in ["♟ ♟ ♟ ♟ ♟\nYOU + 4 RIVALS","≋\n8 KM","★\nPOSITION REWARDS"]:
		var label := Label.new()
		label.text = caption
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",18)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tiles.add_child(label)
