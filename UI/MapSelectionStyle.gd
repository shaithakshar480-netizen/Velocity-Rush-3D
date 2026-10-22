class_name RushMapSelectionStyle
extends RefCounted

static func glass(fill: Color, edge: Color, margin: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(margin)
	style.shadow_color = Color(0.1,0.8,0.95,0.12)
	style.shadow_size = 5
	return style

static func panel(page: Control, column: VBoxContainer, scroll: ScrollContainer) -> void:
	var center: Node = column.get_parent()
	center.remove_child(column)
	var shell := PanelContainer.new()
	center.add_child(shell)
	shell.add_theme_stylebox_override("panel",glass(Color("273c4caa"),Color("8dbecbbb"),24))
	shell.add_child(column)
	column.add_theme_constant_override("separation",12)
	var fit: Callable = func() -> void:
		var width: float = minf(1000.0,maxf(260.0,page.size.x-112.0))
		column.custom_minimum_size.x = width
		scroll.custom_minimum_size.x = 0
		for child: Node in scroll.get_child(0).get_children():
			if child is Button: child.custom_minimum_size.x = maxf(230.0,(width-32.0)/3.0)
	page.resized.connect(fit)
	fit.call_deferred()
	for child: Node in column.get_children():
		if child is Button:
			child.custom_minimum_size.y = 54
			child.add_theme_color_override("font_color",Color("e1faff"))
			child.add_theme_stylebox_override("normal",glass(Color("27536a77"),Color("72dce7"),10))
			child.add_theme_stylebox_override("hover",glass(Color("38758f99"),Color("d0fbff"),10))
			child.add_theme_stylebox_override("pressed",glass(Color("133040bb"),Color("72dce7"),10))

static func card(button: Button, title: String) -> void:
	var preview := TextureRect.new()
	preview.name = "MapCardPreview"
	preview.texture = button.icon
	button.icon = null
	button.text = ""
	button.clip_contents = true
	button.add_child(preview)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.offset_left = 4
	preview.offset_top = 4
	preview.offset_right = -4
	preview.offset_bottom = -4
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint := ColorRect.new()
	tint.color = Color(0.02,0.06,0.10,0.36)
	button.add_child(tint)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.offset_left = 4
	tint.offset_top = 4
	tint.offset_right = -4
	tint.offset_bottom = -4
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption := Label.new()
	caption.text = title
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",23)
	caption.add_theme_color_override("font_color",Color.WHITE)
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x",1)
	caption.add_theme_constant_override("shadow_offset_y",2)
	button.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.anchor_left = 0.40
	caption.offset_left = 8
	caption.offset_right = -16
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_theme_stylebox_override("normal",glass(Color("152c3d"),Color("788f9d"),4))
	button.add_theme_stylebox_override("pressed",glass(Color("1ea7b9"),Color("9affff"),4))
	button.add_theme_stylebox_override("hover",glass(Color("297283"),Color("b3faff"),4))
	button.tooltip_text = title
