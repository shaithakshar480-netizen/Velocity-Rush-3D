class_name RushCrashPresentation
extends RefCounted
## Static, lightweight crash-card styling. Reward callbacks remain in PowerupService.
static func apply(page: Control, panel: PanelContainer, column: VBoxContainer, title: Label, revive: Button, give_up: Button) -> void:
	var glass := StyleBoxTexture.new()
	glass.texture = preload("res://Assets/UI/crash_glass.svg")
	glass.texture_margin_left = 28
	glass.texture_margin_right = 28
	glass.texture_margin_top = 28
	glass.texture_margin_bottom = 28
	glass.content_margin_left = 24
	glass.content_margin_right = 24
	glass.content_margin_top = 22
	glass.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel",glass)
	column.add_theme_constant_override("separation",12)
	title.add_theme_color_override("font_color",Color("e0eef4"))
	title.add_theme_color_override("font_shadow_color",Color("07131fbb"))
	title.add_theme_constant_override("shadow_offset_x",1)
	title.add_theme_constant_override("shadow_offset_y",3)
	var bold := FontVariation.new()
	bold.base_font = title.get_theme_font("font")
	bold.variation_embolden = 1.2
	title.add_theme_font_override("font",bold)
	_style_button(revive,preload("res://Assets/UI/crash_revive.svg"),Color("17353f"))
	_style_button(give_up,preload("res://Assets/UI/crash_results.svg"),Color("e2edf4"))
	var fit: Callable = func() -> void:
		var width: float = clampf(page.size.x*0.49,400.0,640.0)
		width = minf(width,maxf(240.0,page.size.x-72.0))
		column.custom_minimum_size.x = width
		title.add_theme_font_size_override("font_size",42 if width>=520.0 else 34)
	page.resized.connect(fit)
	fit.call_deferred()

static func _style_button(button: Button, texture: Texture2D, ink: Color) -> void:
	button.custom_minimum_size.y = 56
	button.add_theme_font_size_override("font_size",22)
	button.add_theme_color_override("font_color",ink)
	button.add_theme_color_override("font_hover_color",ink)
	button.add_theme_color_override("font_pressed_color",ink)
	button.add_theme_color_override("font_disabled_color",Color("82949d"))
	for state: String in ["normal","hover","pressed","disabled"]:
		var skin := StyleBoxTexture.new()
		skin.texture = texture
		skin.texture_margin_left = 20
		skin.texture_margin_right = 20
		skin.texture_margin_top = 20
		skin.texture_margin_bottom = 20
		skin.content_margin_left = 18
		skin.content_margin_right = 18
		skin.content_margin_top = 10
		skin.content_margin_bottom = 10
		if state=="hover": skin.modulate_color = Color(1.08,1.08,1.08)
		elif state=="pressed": skin.modulate_color = Color(0.8,0.86,0.9)
		elif state=="disabled": skin.modulate_color = Color(0.5,0.57,0.62,0.85)
		button.add_theme_stylebox_override(state,skin)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("c5f9ff")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(16)
	button.add_theme_stylebox_override("focus",focus)
