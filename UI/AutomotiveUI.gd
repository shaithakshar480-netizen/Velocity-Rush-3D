class_name AutomotiveUI
extends CanvasLayer
signal progression_requested(page: String)
var missions_button: Button
var daily_button: Button
# Child Label refs that mirror missions_button.text / daily_button.text.
# ProgressionUI.refresh_home() sets .text on the Button directly (no signal);
# _process() below mirrors it to these Labels so the visible badge is correct
# without the Button's own .text rendering over the icon/child VBox.
var missions_nav_label: Label
var daily_nav_label: Label
var profile_button: Button
var profile_name: Label
var profile_level: Label
var profile_xp: ProgressBar
var profile_xp_text: Label
var setting_refreshers: Array[Callable] = []
var screen_fade: Tween
signal screen_changed(page: String)
signal store_requested
signal garage_requested
var car_info: Label
var home_header: Control
var home_currency: Control
var home_top_left: Control
var home_car_panel: Control
var home_race_btn: Control
var home_nav_panel: Control
signal play_requested
signal pause_requested
signal resume_requested
signal restart_requested
signal home_requested
signal camera_requested
signal settings_requested
signal settings_closed
signal retry_reward_requested
var steering_ui: RushControlPresentation
var rush: RushPresentation
var root: Control
var safe: Control
var screens: Dictionary = {}
var speed_label: Label
var gear_label: Label
var camera_label: Label
var camera_name_fade: Tween
var wrong_way_label: Label
var wrong_way_active: bool = false
var status_label: Label
var error_label: Label
var controls: Dictionary = {}
var hud_elements: Dictionary = {}
var hud_customizer: RushHudCustomizeOverlay = null
var screen: String = "splash"
var return_screen: String = "home"
var startup: RushStartupPresentation
var splash_title: Label
var boot_status: Label
const INK := Color("111720ee")
const MUTED := Color("9ba8b6")
const ACCENT := Color("83cede")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 22
	theme.set_color("font_color","Label",Color("eaf3f7"))
	theme.set_color("font_color","Button",Color("eaf3f7"))
	theme.set_color("font_hover_color","Button",Color.WHITE)
	theme.set_stylebox("normal","Button",_style(Color("10232fee"),Color("395361")))
	theme.set_stylebox("hover","Button",_style(Color("314250"),ACCENT))
	theme.set_stylebox("pressed","Button",_style(Color("174658"),ACCENT))
	theme.set_stylebox("disabled","Button",_style(Color("13202a"),Color("293a46")))
	theme.set_color("font_disabled_color","Button",MUTED)
	theme.set_stylebox("focus","Button",_style(Color.TRANSPARENT,ACCENT))
	for type_name: String in ["ProgressBar","HSlider"]:
		theme.set_stylebox("background",type_name,_meter(Color("28323e")))
		theme.set_stylebox("fill",type_name,_meter(ACCENT))
	for type_name: String in ["OptionButton","LineEdit"]:
		theme.set_stylebox("normal",type_name,_style(Color("1c2532"),Color("3b4755")))
		theme.set_stylebox("focus",type_name,_style(Color("243443"),ACCENT))
	theme.set_stylebox("slider","HSlider",_slider_track(Color("607b8d")))
	theme.set_stylebox("grabber_area","HSlider",_slider_track(Color("51bccc")))
	theme.set_stylebox("grabber_area_highlight","HSlider",_slider_track(ACCENT))
	for state: String in ["grabber","grabber_highlight"]:
		theme.set_icon(state,"HSlider",preload("res://Assets/UI/slider_thumb.svg"))
	theme.set_icon("grabber_disabled","HSlider",preload("res://Assets/UI/slider_thumb_disabled.svg"))
	theme.set_icon("checked","CheckButton",preload("res://Assets/UI/switch_on.svg"))
	theme.set_icon("unchecked","CheckButton",preload("res://Assets/UI/switch_off.svg"))
	theme.set_color("font_color","CheckButton",Color("eaf3f7"))
	root.theme = theme
	safe = Control.new()
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(safe)
	root.resized.connect(_layout_safe_area)
	_layout_safe_area()
	_build_splash()
	_build_home()
	_build_hud()
	_build_pause()
	_build_settings()
	rush = RushPresentation.new()
	add_child(rush)
	rush.build(self)
	steering_ui = RushControlPresentation.new()
	add_child(steering_ui)
	steering_ui.build(self)
	SaveService.save_failed.connect(func(message: String) -> void: error_label.text = message)
	show_screen("splash")

func _layout_safe_area() -> void:
	var rect := Rect2(Vector2.ZERO,root.size)
	if OS.has_feature("android"):
		var display := Vector2(DisplayServer.window_get_size())
		var native := DisplayServer.get_display_safe_area()
		if display.x>0.0 and display.y>0.0 and native.size.x>0:
			var scale := root.size/display
			rect = Rect2(Vector2(native.position)*scale,Vector2(native.size)*scale)
	safe.position = rect.position+Vector2(24,20)
	safe.size = rect.size-Vector2(48,40)

func _style(fill: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.shadow_color = Color("02060b50")
	style.shadow_size = 5
	style.shadow_offset = Vector2(0,3)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _page(name_value: String, dark: bool = false) -> Control:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(page)
	screens[name_value] = page
	page.visible = name_value == screen
	if dark:
		var background := ColorRect.new()
		background.color = Color("06101be8")
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.mouse_filter = Control.MOUSE_FILTER_STOP
		page.add_child(background)
	return page

func _label(parent: Node, value: String, size_value: int = 22, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",size_value)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, callback: Callable, primary: bool = false, direct_handler: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(0,54)
	button.focus_mode = Control.FOCUS_ALL
	button.button_down.connect(func() -> void: button.modulate = Color("a7becb"))
	button.button_up.connect(func() -> void: button.modulate = Color.WHITE)
	if primary:
		button.add_theme_stylebox_override("normal",_style(Color("c6e2e7"),Color("e1f6f7")))
		button.add_theme_color_override("font_color",Color("06252d"))
		button.add_theme_color_override("font_hover_color",Color("06252d"))
		button.add_theme_color_override("font_pressed_color",Color("06252d"))
		button.add_theme_stylebox_override("hover",_style(Color("e1f8fa"),Color("efffff")))
		button.add_theme_stylebox_override("pressed",_style(Color("83bdc7"),ACCENT))
	if direct_handler:
		button.pressed.connect(callback)
	else:
		button.pressed.connect(func() -> void:
			GameAudio.click()
			callback.call())
	parent.add_child(button)
	return button

func _column(parent: Control, width: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = width
	box.add_theme_constant_override("separation",12)
	parent.add_child(box)
	return box

func _center_column(page: Control, width: float) -> VBoxContainer:
	var scroll: RushTouchScroll = RushTouchScroll.new()
	page.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	return _column(center,width)

func _build_splash() -> void:
	var page: Control = _page("splash")
	boot_status = _label(page,"",16,MUTED)
	boot_status.hide()
	startup = RushStartupPresentation.new()
	root.add_child(startup)
	startup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	startup.z_index = 100

func _build_home() -> void:
	var page := _page("home")
	var shade := TextureRect.new()
	shade.texture = preload("res://Assets/UI/menu_scrim.svg")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(shade)

	# 1. TOP BAR CONTAINER (Responsive HBox across entire width)
	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 12
	top_bar.offset_top = 8
	top_bar.offset_right = -12
	top_bar.offset_bottom = 80
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(top_bar)

	# TOP-LEFT: RACER IDENTITY (Floating HUD Card)
	_build_player_card(top_bar)

	# Spacer pushing Brand & Currency to top-right
	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(top_spacer)

	# TOP-RIGHT: BRAND + CURRENCY PILL CLUSTER
	var top_right := VBoxContainer.new()
	top_right.add_theme_constant_override("separation", 6)
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.custom_minimum_size.x = 370
	top_bar.add_child(top_right)

	# Elegant brand title & studio badge
	var brand_box := VBoxContainer.new()
	brand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	brand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_box.add_theme_constant_override("separation", 0)
	# Explicit minimum width prevents zero-allocation in HBoxContainer before first layout
	brand_box.custom_minimum_size = Vector2(0, 76)
	brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var brand_glass := PanelContainer.new()
	brand_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_glass.add_theme_stylebox_override("panel", _home_glass())
	top_right.add_child(brand_glass)
	brand_glass.add_child(brand_box)
	home_header = brand_glass

	var title_lbl := _label(brand_box, "VELOCITY RUSH 3D", 30, Color("eef6fa"))
	var title_font := FontVariation.new()
	title_font.base_font = title_lbl.get_theme_font("font")
	title_font.variation_embolden = 1.1
	title_font.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.18, 1), Vector2.ZERO)
	title_lbl.add_theme_font_override("font", title_font)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_lbl.clip_text = true
	var fit_home_title: Callable = func() -> void:
		var width: float = clampf(page.size.x*0.34,250.0,440.0)
		top_right.custom_minimum_size.x = width
		var measured: float = title_font.get_string_size(title_lbl.text,HORIZONTAL_ALIGNMENT_LEFT,-1,30).x
		title_lbl.add_theme_font_size_override("font_size",clampi(int(30.0*(width-28.0)/maxf(measured,1.0)),18,30))
	page.resized.connect(fit_home_title)
	fit_home_title.call_deferred()
	title_lbl.add_theme_color_override("font_shadow_color", Color("000000aa"))
	title_lbl.add_theme_constant_override("shadow_offset_y", 1)

	var sub_lbl := _label(brand_box, "GEN-Z SOFTWARES", 13, ACCENT)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Compact Currency Pill Card with luminous gold border
	var currency_card := PanelContainer.new()
	currency_card.custom_minimum_size = Vector2(184, 48)
	currency_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	currency_card.size_flags_horizontal = Control.SIZE_SHRINK_END
	currency_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	currency_card.add_theme_stylebox_override("panel", _home_glass())
	top_right.add_child(currency_card)
	home_currency = currency_card

	var currency_row := HBoxContainer.new()
	currency_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	currency_row.add_theme_constant_override("separation", 8)
	currency_row.alignment = BoxContainer.ALIGNMENT_CENTER
	currency_card.add_child(currency_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture = preload("res://Assets/UI/icon_coin.svg")
	coin_icon.custom_minimum_size = Vector2(22, 22)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	currency_row.add_child(coin_icon)

	# 2. BOTTOM-LEFT: LIGHTWEIGHT FLOATING AUTOMOTIVE TELEMETRY
	var car_panel := PanelContainer.new()
	car_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	car_panel.offset_left = 12
	car_panel.offset_right = 310
	car_panel.offset_top = -176
	car_panel.offset_bottom = -92
	car_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car_panel.add_theme_stylebox_override("panel", _home_glass())
	page.add_child(car_panel)
	home_car_panel = car_panel

	var car_margin := MarginContainer.new()
	car_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car_margin.add_theme_constant_override("margin_left", 12)
	car_margin.add_theme_constant_override("margin_right", 12)
	car_margin.add_theme_constant_override("margin_top", 8)
	car_margin.add_theme_constant_override("margin_bottom", 8)
	car_panel.add_child(car_margin)

	var car_box := VBoxContainer.new()
	car_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car_box.add_theme_constant_override("separation", 2)
	car_margin.add_child(car_box)

	var telemetry_header := HBoxContainer.new()
	telemetry_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car_box.add_child(telemetry_header)

	var category_lbl := _label(telemetry_header, "TELEMETRY  /  SELECTED", 12, ACCENT)
	category_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var live_pip := _label(telemetry_header, "● READY", 12, Color("5aff9f"))
	live_pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Thin luminous accent divider line
	var div_line := ColorRect.new()
	div_line.custom_minimum_size = Vector2(0, 1)
	div_line.color = Color("83cede55")
	div_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car_box.add_child(div_line)

	car_info = _label(car_box, "VORTEX S\n210 KM/H   /   SELECTED", 16, Color("f0f7fb"))
	car_info.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 3. BOTTOM-RIGHT: ANGULAR HIGH-VOLTAGE RACE CTA
	var race_btn := _button(page, "", func() -> void: play_requested.emit(), true)
	race_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	race_btn.offset_left = -265
	race_btn.offset_right = -12
	race_btn.offset_top = -178
	race_btn.offset_bottom = -92
	race_btn.custom_minimum_size = Vector2(253, 86)
	race_btn.pivot_offset = Vector2(126, 43)
	home_race_btn = race_btn

	# Angular style: sharp left edge, rounded right edge — gives a speed-bar / HUD feel.
	# StyleBoxFlat corners: TL=0, TR=14, BR=14, BL=0 (left side razor-sharp).
	var race_normal_style := StyleBoxFlat.new()
	race_normal_style.bg_color = Color("081a29f2")
	race_normal_style.border_color = Color("83cedeee")
	race_normal_style.set_border_width_all(2)
	race_normal_style.corner_radius_top_left = 22
	race_normal_style.corner_radius_top_right = 14
	race_normal_style.corner_radius_bottom_right = 14
	race_normal_style.corner_radius_bottom_left = 22
	race_normal_style.shadow_color = Color("00000090")
	race_normal_style.shadow_size = 12
	race_normal_style.shadow_offset = Vector2(0, 4)

	var race_hover_style := StyleBoxFlat.new()
	race_hover_style.bg_color = Color("102e48fa")
	race_hover_style.border_color = Color("d2f7ff")
	race_hover_style.set_border_width_all(2)
	race_hover_style.corner_radius_top_left = 22
	race_hover_style.corner_radius_top_right = 14
	race_hover_style.corner_radius_bottom_right = 14
	race_hover_style.corner_radius_bottom_left = 22
	race_hover_style.shadow_color = Color("3ab8cc60")
	race_hover_style.shadow_size = 16
	race_hover_style.shadow_offset = Vector2(0, 4)

	var race_pressed_style := StyleBoxFlat.new()
	race_pressed_style.bg_color = Color("05101a")
	race_pressed_style.border_color = Color("5bb9cc")
	race_pressed_style.set_border_width_all(2)
	race_pressed_style.corner_radius_top_left = 22
	race_pressed_style.corner_radius_top_right = 14
	race_pressed_style.corner_radius_bottom_right = 14
	race_pressed_style.corner_radius_bottom_left = 22
	race_pressed_style.shadow_size = 4

	race_btn.add_theme_stylebox_override("normal", _home_glass())
	race_btn.add_theme_stylebox_override("hover", race_hover_style)
	race_btn.add_theme_stylebox_override("pressed", race_pressed_style)
	race_btn.add_theme_stylebox_override("focus", race_hover_style)

	# Angular left-edge accent stripe (thin cyan bar on the sliced left side)
	var left_stripe := ColorRect.new()
	left_stripe.color = Color("55e7ffcc")
	left_stripe.hide()
	left_stripe.custom_minimum_size = Vector2(3, 0)
	left_stripe.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left_stripe.offset_top = 10
	left_stripe.offset_bottom = -10
	left_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	race_btn.add_child(left_stripe)

	var race_margin := MarginContainer.new()
	race_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	race_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	race_margin.add_theme_constant_override("margin_left", 18)
	race_margin.add_theme_constant_override("margin_right", 14)
	race_margin.add_theme_constant_override("margin_top", 0)
	race_margin.add_theme_constant_override("margin_bottom", 0)
	race_btn.add_child(race_margin)

	var race_row := HBoxContainer.new()
	race_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	race_row.alignment = BoxContainer.ALIGNMENT_CENTER
	race_row.add_theme_constant_override("separation", 10)
	race_margin.add_child(race_row)

	var race_labels := VBoxContainer.new()
	race_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	race_labels.alignment = BoxContainer.ALIGNMENT_CENTER
	race_labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_labels.add_theme_constant_override("separation", 0)
	race_row.add_child(race_labels)

	var race_text := _label(race_labels, "RACE", 26, Color("ffffff"))
	race_text.add_theme_color_override("font_shadow_color", Color("83cede88"))
	race_text.add_theme_constant_override("shadow_offset_y", 1)

	_label(race_labels, "START ENGINE", 13, ACCENT)

	# Arrow: pulse modulate only — do NOT tween position:x inside HBoxContainer
	# (the layout engine overrides position every frame, causing permanent drift).
	var play_ring := PanelContainer.new()
	play_ring.custom_minimum_size = Vector2(54, 54)
	play_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_ring.add_theme_stylebox_override("panel", _glass_style(Color("314758bd"), Color("bce8f2"), 27, 1, 3))
	race_row.add_child(play_ring)
	var arrow_lbl := _label(play_ring, "▶", 24, Color("e7f7ff"))
	arrow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var arrow_motion := arrow_lbl.create_tween()
	arrow_motion.set_loops()
	arrow_motion.tween_property(arrow_lbl, "modulate:a", 0.4, 0.55).set_trans(Tween.TRANS_SINE)
	arrow_motion.tween_property(arrow_lbl, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)

	race_btn.mouse_entered.connect(func() -> void:
		var t := race_btn.create_tween()
		t.tween_property(race_btn, "scale", Vector2(1.025, 1.025), 0.12)
		race_text.modulate = Color("a6edff")
		left_stripe.color = Color("55e7ff"))
	race_btn.mouse_exited.connect(func() -> void:
		var t := race_btn.create_tween()
		t.tween_property(race_btn, "scale", Vector2.ONE, 0.12)
		race_text.modulate = Color.WHITE
		left_stripe.color = Color("55e7ffcc"))
	race_btn.button_down.connect(func() -> void:
		var t := race_btn.create_tween()
		t.tween_property(race_btn, "scale", Vector2(0.97, 0.97), 0.08))
	race_btn.button_up.connect(func() -> void:
		var t := race_btn.create_tween()
		t.tween_property(race_btn, "scale", Vector2.ONE, 0.12))

	# 4. BOTTOM NAVIGATION DOCK (Thin Floating Glass Rail)
	var navigation_panel := PanelContainer.new()
	page.add_child(navigation_panel)
	navigation_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	navigation_panel.offset_left = 12
	navigation_panel.offset_right = -12
	navigation_panel.offset_top = -82
	navigation_panel.offset_bottom = -8
	navigation_panel.add_theme_stylebox_override("panel", _home_glass())
	home_nav_panel = navigation_panel

	var nav_margin := MarginContainer.new()
	nav_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_margin.add_theme_constant_override("margin_left", 6)
	nav_margin.add_theme_constant_override("margin_right", 6)
	nav_margin.add_theme_constant_override("margin_top", 3)
	nav_margin.add_theme_constant_override("margin_bottom", 3)
	navigation_panel.add_child(nav_margin)

	var navigation_row := HBoxContainer.new()
	navigation_row.add_theme_constant_override("separation", 6)
	navigation_row.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_margin.add_child(navigation_row)

	var store_button := _dock_item(navigation_row, "STORE", preload("res://Assets/UI/nav_store.svg"), func() -> void: store_requested.emit())
	var garage := _dock_item(navigation_row, "GARAGE", preload("res://Assets/UI/nav_garage.svg"), func() -> void: garage_requested.emit())
	missions_button = _dock_item(navigation_row, "MISSIONS", preload("res://Assets/UI/nav_missions.svg"), func() -> void: progression_requested.emit("missions"))
	daily_button = _dock_item(navigation_row, "DAILY REWARD", preload("res://Assets/UI/nav_daily.svg"), func() -> void: progression_requested.emit("daily"))
	var settings := _dock_item(navigation_row, "SETTINGS", preload("res://Assets/UI/nav_settings.svg"), func() -> void: settings_requested.emit())
	# Capture the inner Label refs (child index 1 of VBoxContainer, which is child 0 of Button).
	# _process() mirrors missions_button.text / daily_button.text into these Labels,
	# since ProgressionUI.refresh_home() sets button.text directly (no change signal available).
	var _mc: VBoxContainer = missions_button.get_child(0) as VBoxContainer
	if _mc != null and _mc.get_child_count() > 1:
		missions_nav_label = _mc.get_child(1) as Label
	var _dc: VBoxContainer = daily_button.get_child(0) as VBoxContainer
	if _dc != null and _dc.get_child_count() > 1:
		daily_nav_label = _dc.get_child(1) as Label

	# Bind progression events
	RewardService.progression_changed.connect(_refresh_profile_entry)
	SaveService.account_scope_changed.connect(_refresh_profile_entry)
	_refresh_profile_entry()

func _build_player_card(parent: Control) -> void:
	profile_button = _button(parent, "", func() -> void: progression_requested.emit("profile"))
	profile_button.tooltip_text = "Profile"
	profile_button.custom_minimum_size = Vector2(250, 56)
	profile_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	profile_button.pivot_offset = Vector2(125, 28)
	home_top_left = profile_button

	# Compact floating HUD glass style with cyan luminous edge
	profile_button.add_theme_stylebox_override("normal", _home_glass())
	profile_button.add_theme_stylebox_override("hover", _glass_style(Color("0f2233e6"), ACCENT, 12, 1, 8))
	profile_button.add_theme_stylebox_override("pressed", _glass_style(Color("050c14"), Color("203848"), 12, 1, 2))
	profile_button.add_theme_stylebox_override("focus", _glass_style(Color("0f2233e6"), ACCENT, 12, 1, 8))

	var margin := MarginContainer.new()
	profile_button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(row)

	var avatar := TextureRect.new()
	avatar.texture = preload("res://Assets/UI/player_avatar.svg")
	avatar.custom_minimum_size = Vector2(40, 40)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(avatar)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.add_theme_constant_override("separation", 2)
	row.add_child(identity)

	var header_row := HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(header_row)

	profile_name = _label(header_row, "RACER", 18, Color("eef5f8"))
	profile_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_name.clip_text = true

	profile_level = _label(header_row, "LV. 1", 14, ACCENT)
	profile_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	profile_xp = ProgressBar.new()
	profile_xp.custom_minimum_size = Vector2(0, 4)
	profile_xp.show_percentage = false
	profile_xp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	profile_xp.add_theme_stylebox_override("fill", _meter(ACCENT))
	identity.add_child(profile_xp)

	profile_xp_text = _label(identity, "0 / 100 XP", 12, MUTED)
	profile_xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Micro-interaction for profile button
	profile_button.mouse_entered.connect(func() -> void:
		var t := profile_button.create_tween()
		t.tween_property(profile_button, "scale", Vector2(1.02, 1.02), 0.12))
	profile_button.mouse_exited.connect(func() -> void:
		var t := profile_button.create_tween()
		t.tween_property(profile_button, "scale", Vector2.ONE, 0.12))
	profile_button.button_down.connect(func() -> void:
		var t := profile_button.create_tween()
		t.tween_property(profile_button, "scale", Vector2(0.97, 0.97), 0.08))
	profile_button.button_up.connect(func() -> void:
		var t := profile_button.create_tween()
		t.tween_property(profile_button, "scale", Vector2.ONE, 0.12))

func _refresh_profile_entry() -> void:
	if profile_name==null: return
	var p: Dictionary = SaveService.progression
	var level: int = int(p.get("level",1))
	var xp: int = int(p.get("xp",0))-RushProgressionData.threshold(level)
	var maximum: bool = level>=int(RushProgressionData.spec.max_level)
	profile_name.text = String(p.get("name","Racer"))
	profile_level.text = "Lv. %d"%level
	profile_xp.value = 100.0 if maximum else clampf(100.0*xp/RushProgressionData.required(level),0.0,100.0)
	profile_xp_text.text = "MAX LEVEL" if maximum else "%d / %d XP"%[xp,RushProgressionData.required(level)]

var _last_speed_kmh: int = -1
var _last_gear_str: String = ""
var _last_rpm_val: int = -1

func _build_hud() -> void:
	var page := _page("drive")
	wrong_way_label = Label.new()
	wrong_way_label.text = "WRONG WAY  •  TURN AROUND"
	wrong_way_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrong_way_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrong_way_label.add_theme_font_size_override("font_size",24)
	wrong_way_label.add_theme_color_override("font_color",Color("ffce77"))
	wrong_way_label.add_theme_color_override("font_outline_color",Color("071422"))
	wrong_way_label.add_theme_constant_override("outline_size",6)
	page.add_child(wrong_way_label)
	wrong_way_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	wrong_way_label.offset_left = -220
	wrong_way_label.offset_right = 220
	wrong_way_label.offset_top = 112
	wrong_way_label.offset_bottom = 148
	wrong_way_label.visible = false
	var util_normal := StyleBoxFlat.new()
	util_normal.bg_color = Color("071422d9")
	util_normal.border_color = Color("00e5ffaa")
	util_normal.set_border_width_all(1)
	util_normal.set_corner_radius_all(10)
	util_normal.shadow_color = Color("00e5ff38")
	util_normal.shadow_size = 8
	util_normal.shadow_offset = Vector2(0, 2)

	var util_hover := StyleBoxFlat.new()
	util_hover.bg_color = Color("0c273df4")
	util_hover.border_color = Color("54f0ff")
	util_hover.set_border_width_all(1)
	util_hover.set_corner_radius_all(10)
	util_hover.shadow_color = Color("00e5ff66")
	util_hover.shadow_size = 10

	var util_pressed := StyleBoxFlat.new()
	util_pressed.bg_color = Color("05101a")
	util_pressed.border_color = Color("00c2db")
	util_pressed.set_border_width_all(1)
	util_pressed.set_corner_radius_all(10)
	util_pressed.shadow_color = Color("00e5ff40")
	util_pressed.shadow_size = 4

	var pause_button := Button.new()
	pause_button.text = "Ⅱ"
	pause_button.custom_minimum_size = Vector2(52, 52)
	pause_button.add_theme_font_size_override("font_size", 24)
	pause_button.add_theme_color_override("font_color", Color("ffffff"))
	pause_button.add_theme_color_override("font_shadow_color", Color("00e5ff55"))
	pause_button.add_theme_constant_override("shadow_offset_y", 1)
	pause_button.add_theme_stylebox_override("normal", util_normal)
	pause_button.add_theme_stylebox_override("hover", util_hover)
	pause_button.add_theme_stylebox_override("pressed", util_pressed)
	pause_button.pressed.connect(func() -> void: pause_requested.emit())
	page.add_child(pause_button)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pause_button.offset_left = 16
	pause_button.offset_top = 16
	pause_button.offset_right = 68
	pause_button.offset_bottom = 68
	hud_elements["pause"] = pause_button
	HudLayoutService.apply_control("pause", pause_button, page.size)

	# Utility top container for camera view switch
	var top := HBoxContainer.new()
	page.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	top.offset_left = 76
	top.offset_top = 16
	top.offset_right = 136
	top.offset_bottom = 68
	top.add_theme_constant_override("separation", 8)

	var camera_button := Button.new()
	camera_button.icon = preload("res://Assets/UI/camera.svg")
	camera_button.custom_minimum_size = Vector2(52, 52)
	camera_button.tooltip_text = "Change view"
	camera_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	camera_button.add_theme_stylebox_override("normal", util_normal)
	camera_button.add_theme_stylebox_override("hover", util_hover)
	camera_button.add_theme_stylebox_override("pressed", util_pressed)
	camera_button.pressed.connect(func() -> void: camera_requested.emit())
	top.add_child(camera_button)

	camera_label = _label(page, "VIEW  /  CHASE", 12, Color("76bbce"))
	camera_label.position = Vector2(0, 48)
	camera_label.modulate.a = 0.0
	camera_label.add_theme_color_override("font_shadow_color", Color("03090e"))
	camera_label.add_theme_constant_override("shadow_offset_y", 1)

	# 2. Top-Right: Hero Speed Telemetry Cluster
	# SpeedGlass backing panel (looked up by DrivingDirector)
	_hud_glass(page, Control.PRESET_TOP_RIGHT, Vector4(-304, 0, 0, 172)).name = "SpeedGlass"

	# Vector tachometer arc & RPM meter (looked up by DrivingDirector)
	var dial := RushSpeedDial.new()
	dial.name = "SpeedDial"
	page.add_child(dial)
	dial.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dial.offset_left = -304
	dial.offset_right = 0
	dial.offset_top = 0
	dial.offset_bottom = 172

	# Digital speed & gear readout (looked up by DrivingDirector)
	var speed_box := VBoxContainer.new()
	speed_box.name = "SpeedReadout"
	page.add_child(speed_box)
	speed_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	speed_box.offset_left = -256
	speed_box.offset_right = -24
	speed_box.offset_top = 20
	speed_box.offset_bottom = 118
	speed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_box.add_theme_constant_override("separation", 0)

	var speed_row := HBoxContainer.new()
	speed_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_row.add_theme_constant_override("separation", 4)
	speed_box.add_child(speed_row)

	speed_label = Label.new()
	speed_label.text = "000"
	speed_label.add_theme_font_size_override("font_size", 64)
	speed_label.add_theme_color_override("font_color", Color("f0fbff"))
	speed_label.add_theme_color_override("font_shadow_color", Color("00e5ff44"))
	speed_label.add_theme_constant_override("shadow_offset_y", 1)
	speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_row.add_child(speed_label)

	var kmh_box := VBoxContainer.new()
	kmh_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kmh_box.alignment = BoxContainer.ALIGNMENT_END
	speed_row.add_child(kmh_box)

	var kmh_label := Label.new()
	kmh_label.text = "KM/H"
	kmh_label.add_theme_font_size_override("font_size", 12)
	kmh_label.add_theme_color_override("font_color", Color("7ed4ec"))
	kmh_label.add_theme_color_override("font_shadow_color", Color("020810c0"))
	kmh_label.add_theme_constant_override("shadow_offset_y", 1)
	kmh_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kmh_box.add_child(kmh_label)

	var kmh_spacer := Control.new()
	kmh_spacer.custom_minimum_size.y = 4
	kmh_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kmh_box.add_child(kmh_spacer)

	gear_label = Label.new()
	gear_label.text = "GEAR N  |  0000 RPM"
	gear_label.add_theme_font_size_override("font_size", 16)
	gear_label.add_theme_color_override("font_color", Color("b0e8f6"))
	gear_label.add_theme_color_override("font_shadow_color", Color("020810d0"))
	gear_label.add_theme_constant_override("shadow_offset_x", 0)
	gear_label.add_theme_constant_override("shadow_offset_y", 1)
	gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_box.add_child(gear_label)

	# 3. Driving Touch Controls (Wheel / Buttons / Pedals)
	var left := HBoxContainer.new()
	page.add_child(left)
	left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	left.offset_left = 0
	left.offset_right = 258
	left.offset_top = -124
	left.offset_bottom = -10
	left.custom_minimum_size = Vector2(258, 114)
	left.add_theme_constant_override("separation", 16)
	hud_elements["steer_buttons"] = left
	HudLayoutService.apply_control("steer_buttons", left, page.size)
	_touch_control(left, "left", "«", Vector2(120, 114))
	_touch_control(left, "right", "»", Vector2(120, 114))
	var right := HBoxContainer.new()
	page.add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	right.offset_left = -294
	right.offset_right = 0
	right.offset_top = -136
	right.offset_bottom = -10
	right.custom_minimum_size = Vector2(294, 126)
	right.add_theme_constant_override("separation", 18)
	hud_elements["pedals"] = right
	HudLayoutService.apply_control("pedals", right, page.size)
	_touch_control(right, "brake", "", Vector2(128, 126))
	_touch_control(right, "accelerate", "", Vector2(148, 126))
	DriveInput.regions = controls

func _touch_control(parent: Node, action: String, caption: String, minimum: Vector2) -> void:
	if action in ["accelerate","brake"]:
		var pedal := RushPedalControl.new()
		pedal.action = action
		pedal.custom_minimum_size = minimum
		pedal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pedal.size_flags_vertical = Control.SIZE_EXPAND_FILL
		parent.add_child(pedal)
		controls[action] = pedal
		return
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Translucent deep navy glass with strong cyan neon border and soft glow
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color("071422d9")
	btn_style.border_color = Color("00e5ffaa")
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(14)
	btn_style.shadow_color = Color("00e5ff38")
	btn_style.shadow_size = 10
	btn_style.shadow_offset = Vector2(0, 2)
	btn_style.content_margin_left = 8
	btn_style.content_margin_right = 8
	btn_style.content_margin_top = 8
	btn_style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", btn_style)
	parent.add_child(panel)

	# Bold directional chevron — slightly larger for visual weight
	var label := _label(panel, caption, 72, Color("d8f6ff"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_color_override("font_shadow_color", Color("00e5ff55"))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)
	controls[action] = panel

func _build_pause() -> void:
	var page: Control = _page("pause",true)
	(page.get_child(0) as ColorRect).color = Color("02091338")
	var canvas: Control = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(canvas)
	canvas.size = Vector2(500,370)
	var fit: Callable = func() -> void:
		var factor: float = minf(1.0,minf(maxf(1.0,page.size.x-24.0)/500.0,maxf(1.0,page.size.y-24.0)/370.0))
		canvas.scale = Vector2.ONE*factor
		canvas.position = (page.size-canvas.size*factor)*0.5
	page.resized.connect(fit)
	fit.call_deferred()
	var glass: TextureRect = TextureRect.new()
	glass.texture = preload("res://Assets/UI/pause_glass.svg")
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(glass)
	var column: VBoxContainer = VBoxContainer.new()
	column.position = Vector2(100,30)
	column.size = Vector2(300,310)
	column.add_theme_constant_override("separation",10)
	canvas.add_child(column)
	var heading: Label = _label(column,"DRIVE PAUSED",27,Color("d3edf3"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.custom_minimum_size.y = 42
	heading.add_theme_color_override("font_shadow_color",Color("04141fe0"))
	heading.add_theme_constant_override("shadow_offset_y",2)
	var callbacks: Array[Callable] = [func() -> void: resume_requested.emit(),func() -> void: restart_requested.emit(),func() -> void: settings_requested.emit(),func() -> void: home_requested.emit()]
	var titles: Array[String] = ["RESUME","Restart","Settings","Main Menu"]
	var icons: Array[Texture2D] = [preload("res://Assets/UI/pause_resume.svg"),preload("res://Assets/UI/pause_restart.svg"),preload("res://Assets/UI/pause_settings.svg"),preload("res://Assets/UI/pause_home.svg")]
	for i: int in titles.size():
		var button: Button = _button(column,titles[i],callbacks[i])
		button.custom_minimum_size = Vector2(300,51)
		button.add_theme_font_size_override("font_size",22)
		button.icon = icons[i]
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",25)
		button.add_theme_constant_override("h_separation",12)
		var normal: StyleBoxFlat = _style(Color("15586cce") if i==0 else Color("1d303eaa"),Color("96d4ded0") if i==0 else Color("8aaab780"))
		normal.set_corner_radius_all(9)
		normal.content_margin_left = 16
		normal.content_margin_right = 16
		normal.content_margin_top = 8
		normal.content_margin_bottom = 8
		normal.shadow_color = Color("50d7ef25") if i==0 else Color("00000040")
		normal.shadow_size = 6
		button.add_theme_stylebox_override("normal",normal)
		var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color("27798ad9")
		hover.border_color = Color("b7f0f9")
		button.add_theme_stylebox_override("hover",hover)
		button.add_theme_stylebox_override("focus",hover)
		var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		pressed.bg_color = Color("113544e8")
		button.add_theme_stylebox_override("pressed",pressed)
		for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			button.add_theme_color_override(state,Color("e0f5fa"))

func _build_settings() -> void:
	var page := _page("settings",true)
	(page.get_child(0) as ColorRect).color = Color("05101c38")
	var frame: TextureRect = TextureRect.new()
	frame.texture = preload("res://Assets/UI/settings_metal_frame.svg")
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(frame)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",30)
	margin.add_theme_constant_override("margin_right",30)
	margin.add_theme_constant_override("margin_top",20)
	margin.add_theme_constant_override("margin_bottom",20)
	page.add_child(margin)
	var column := _column(margin,0)
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel",_settings_glass())
	column.add_child(header_panel)
	var header := HBoxContainer.new()
	header_panel.add_child(header)
	var title := _label(header,"SETTINGS",30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var done: Button = _button(header,"DONE",func() -> void:
		SaveService.commit()
		settings_closed.emit(),true)
	done.add_theme_stylebox_override("normal",_settings_glass(true))
	done.add_theme_color_override("font_color",Color("e7faff"))
	done.custom_minimum_size = Vector2(116,54)
	var tabs: HBoxContainer = HBoxContainer.new()
	column.add_child(tabs)
	tabs.add_theme_constant_override("separation",6)
	var scroll := RushTouchScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",16)
	scroll.add_child(content)
	var audio_card: VBoxContainer = _settings_card(content,"SOUND STUDIO","Balance the engine, road and soundtrack.")
	var controls_card: VBoxContainer = _settings_card(content,"YOUR DRIVING STYLE","Choose the controls that feel right for you.")
	var display_card: VBoxContainer = _settings_card(content,"VISUAL QUALITY","Choose the balance of detail and performance.")
	controls_card.add_theme_constant_override("separation",7)
	var account_card: VBoxContainer = _settings_card(content,"DRIVER ACCOUNT","Manage your connected account and cloud save.")
	account_card.set_meta("account_settings_host",true)
	account_card.add_theme_constant_override("separation",7)
	(account_card.get_child(0) as Label).add_theme_font_size_override("font_size",29)
	(account_card.get_child(0) as Label).add_theme_color_override("font_color",Color("dae7ef"))
	var account_frame: StyleBoxFlat = _style(Color("192b3690"),Color("aac4d0a0"))
	account_frame.set_corner_radius_all(12)
	(account_card.get_parent() as PanelContainer).add_theme_stylebox_override("panel",account_frame)

	var cards: Array[VBoxContainer] = [audio_card,controls_card,display_card,account_card]
	var group: ButtonGroup = ButtonGroup.new()
	for index: int in 4:
		var tab: Button = _button(tabs,["AUDIO","CONTROLS","DISPLAY","ACCOUNT"][index],func() -> void:
			for i: int in cards.size(): cards[i].get_parent().visible = i==index
			scroll.scroll_vertical = 0)
		tab.add_theme_stylebox_override("normal",_settings_glass())
		tab.add_theme_stylebox_override("hover",_settings_glass(true))
		tab.add_theme_stylebox_override("pressed",_settings_glass(true))
		tab.add_theme_stylebox_override("focus",_settings_glass(true))
		tab.add_theme_font_size_override("font_size",23)
		tab.custom_minimum_size.y = 54
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = index==0
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards[index].get_parent().visible = index==0
	_slider(audio_card,"Master Volume","master",0.0,1.0)
	_slider(audio_card,"Music Volume","music",0.0,1.0)
	_slider(audio_card,"Engine & Effects","sfx",0.0,1.0)
	_label(controls_card,"STEERING METHOD",16,ACCENT)
	var mode_choice := OptionButton.new()
	mode_choice.add_item("BUTTONS",1)
	mode_choice.add_item("STEERING WHEEL",0)
	mode_choice.select(mode_choice.get_item_index(DriveInput.effective_mode()))
	mode_choice.custom_minimum_size.y = 44
	mode_choice.add_theme_font_size_override("font_size",20)
	mode_choice.add_theme_stylebox_override("normal",_style(Color("154456b0"),Color("97b9c5")))
	controls_card.add_child(mode_choice)
	setting_refreshers.append(func() -> void: mode_choice.select(mode_choice.get_item_index(DriveInput.effective_mode())))
	mode_choice.item_selected.connect(func(value: int) -> void: SaveService.set_value("steering_mode",mode_choice.get_item_id(value)))
	_slider(controls_card,"Steering Sensitivity","steering",0.5,1.5,true)
	_slider(controls_card,"Wheel Deadzone","wheel_deadzone",0.0,0.20,true)
	var assist := CheckButton.new()
	assist.text = "Steering assist"
	assist.custom_minimum_size.y = 40
	assist.add_theme_font_size_override("font_size",20)
	for state: String in ["normal","hover","pressed","hover_pressed"]:
		var clear: StyleBoxFlat = StyleBoxFlat.new()
		clear.bg_color = Color.TRANSPARENT
		clear.content_margin_left = 0
		clear.content_margin_right = 0
		assist.add_theme_stylebox_override(state,clear)
	assist.button_pressed = bool(SaveService.settings["steering_assist"])
	setting_refreshers.append(func() -> void: assist.set_pressed_no_signal(bool(SaveService.settings["steering_assist"])) )
	assist.toggled.connect(func(value: bool) -> void: SaveService.set_value("steering_assist",value))
	controls_card.add_child(assist)
	var vibration := CheckButton.new()
	vibration.text = "Driving vibration"
	vibration.custom_minimum_size.y = 40
	vibration.add_theme_font_size_override("font_size",20)
	for state: String in ["normal","hover","pressed","hover_pressed"]:
		var clear: StyleBoxFlat = StyleBoxFlat.new()
		clear.bg_color = Color.TRANSPARENT
		clear.content_margin_left = 0
		clear.content_margin_right = 0
		vibration.add_theme_stylebox_override(state,clear)
	vibration.button_pressed = bool(SaveService.settings["vibration"])
	setting_refreshers.append(func() -> void: vibration.set_pressed_no_signal(bool(SaveService.settings["vibration"])) )
	vibration.toggled.connect(func(value: bool) -> void: SaveService.set_value("vibration",value))
	controls_card.add_child(vibration)
	var customize: Button = _button(controls_card, "CUSTOMIZE HUD", open_hud_customizer)
	customize.custom_minimum_size.y = 46
	customize.add_theme_font_size_override("font_size",20)
	customize.add_theme_stylebox_override("normal",_settings_glass())
	# Radio cards use the existing quality setter; no graphics policy changes.
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	display_card.add_child(row)
	var description: VBoxContainer = VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.size_flags_stretch_ratio = 1.5
	row.add_child(description)
	_label(description,"Graphics Quality",23,Color("e9f5fa"))
	var note: Label = _label(description,"Quality changes resolution, shadows and anti-aliasing.\n\nSustained low performance enables the 30 FPS fallback.",16,MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var choices: HBoxContainer = HBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.size_flags_stretch_ratio = 2.6
	choices.add_theme_constant_override("separation",12)
	row.add_child(choices)
	var quality_group: ButtonGroup = ButtonGroup.new()
	var names: Array[String] = ["LOW","MEDIUM","HIGH"]
	var captions: Array[String] = ["30 FPS","RECOMMENDED","60 FPS TARGET"]
	var descriptions: Array[String] = ["Lighter rendering\nReduced effects","Balanced rendering\nBalanced details","Highest quality tier\nEnhanced effects"]
	for tier: int in 3:
		var choice: Button = Button.new()
		choice.custom_minimum_size = Vector2(160,205)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.toggle_mode = true
		choice.button_group = quality_group
		choice.add_theme_stylebox_override("normal",_quality_card_style(false))
		choice.add_theme_stylebox_override("hover",_quality_card_style(true))
		choice.add_theme_stylebox_override("pressed",_quality_card_style(true))
		choice.add_theme_stylebox_override("focus",_quality_card_style(true))
		choice.set_pressed_no_signal(int(SaveService.settings.quality)==tier)
		choice.pressed.connect(func() -> void:
			GameAudio.click()
			SaveService.set_value("quality",tier))
		setting_refreshers.append(func() -> void: choice.set_pressed_no_signal(int(SaveService.settings.quality)==tier))
		choices.add_child(choice)
		var stack: VBoxContainer = VBoxContainer.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.offset_left = 10
		stack.offset_right = -10
		stack.offset_top = 14
		stack.offset_bottom = -10
		stack.add_theme_constant_override("separation",7)
		choice.add_child(stack)
		var icon: TextureRect = TextureRect.new()
		icon.texture = preload("res://Assets/UI/quality_chip.svg")
		icon.custom_minimum_size = Vector2(0,54)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(icon)
		var name_label: Label = _label(stack,names[tier],25,Color("daf3fa"))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var caption: Label = _label(stack,captions[tier],14,Color("99ccd9"))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var detail: Label = _label(stack,descriptions[tier],14,Color("c5d5dc"))
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label = _label(column,SaveService.last_error,16,Color("ffb091"))

func _settings_card(parent: Control, title: String, subtitle: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	parent.add_child(panel)
	panel.add_theme_stylebox_override("panel",_settings_glass())
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation",18)
	panel.add_child(column)
	_label(column,title,23,ACCENT)
	var hint: Label = _label(column,subtitle,16,MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return column

func _slider(parent: Node, caption: String, key: String, minimum: float, maximum: float, compact: bool = false) -> void:
	var section: VBoxContainer = VBoxContainer.new()
	parent.add_child(section)
	var row := HBoxContainer.new()
	section.add_child(row)
	var label := _label(row,caption,22)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if compact:
		label.size_flags_horizontal = Control.SIZE_FILL
		label.custom_minimum_size.x = 230
		label.add_theme_font_size_override("font_size",20)
	var slider := HSlider.new()
	var rail: StyleBoxFlat = _meter(Color("08131fe6"))
	rail.border_color = Color("91a8b5")
	rail.set_border_width_all(1)
	rail.set_corner_radius_all(7)
	rail.content_margin_top = 7
	rail.content_margin_bottom = 7
	var fill: StyleBoxFlat = _meter(Color("49dbe9"))
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider",rail)
	slider.add_theme_stylebox_override("grabber_area",fill)
	slider.add_theme_stylebox_override("grabber_area_highlight",fill)
	slider.add_theme_icon_override("grabber",preload("res://Assets/UI/settings_dial.svg"))
	slider.add_theme_icon_override("grabber_highlight",preload("res://Assets/UI/settings_dial.svg"))
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = float(SaveService.settings[key])
	slider.custom_minimum_size = Vector2(0,48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if compact:
		row.add_child(slider)
		slider.custom_minimum_size.y = 40
		var gradient_fill: StyleBoxTexture = StyleBoxTexture.new()
		gradient_fill.texture = preload("res://Assets/UI/controls_slider_fill.svg")
		gradient_fill.texture_margin_left = 7
		gradient_fill.texture_margin_right = 7
		gradient_fill.content_margin_top = 7
		gradient_fill.content_margin_bottom = 7
		slider.add_theme_stylebox_override("grabber_area",gradient_fill)
		slider.add_theme_stylebox_override("grabber_area_highlight",gradient_fill)
	else:
		section.add_child(slider)
	var readout := _label(row,"%d%%"%int(slider.value*100),18,ACCENT)
	readout.custom_minimum_size.x = 70
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(value: float) -> void:
		SaveService.set_value(key,value,false)
		readout.text = "%d%%"%int(value*100))
	setting_refreshers.append(func() -> void:
		slider.set_value_no_signal(float(SaveService.settings[key]))
		readout.text = "%d%%"%int(slider.value*100))
	slider.drag_ended.connect(func(_changed: bool) -> void: SaveService.commit())

func open_hud_customizer() -> void:
	if is_instance_valid(hud_customizer):
		return
	show_screen("drive")
	if is_instance_valid(steering_ui):
		steering_ui._update()
	hud_customizer = RushHudCustomizeOverlay.new()
	screens.drive.add_child(hud_customizer)
	hud_customizer.setup(self)
	hud_customizer.closed.connect(func() -> void:
		hud_customizer = null
		show_screen("settings")
	)

func show_screen(value: String) -> void:
	wrong_way_active = false
	if is_instance_valid(wrong_way_label): wrong_way_label.visible = false
	# One navigation gate: a signed-out player cannot reopen a stale menu.
	if (not AuthService.chosen or SaveService.bootstrap_pending) and screens.has("account") and value!="splash":
		value = "account"
	if value=="settings":
		for refresh: Callable in setting_refreshers: refresh.call()
	screen = value
	if screen_fade!=null and screen_fade.is_valid():
		screen_fade.kill()
	for key: String in screens:
		screens[key].visible = key == value
		screens[key].modulate.a = 1.0
	if value in ["home","garage","missions","daily","profile","settings","account"]:
		screens[value].modulate.a = 0.0
		screen_fade = create_tween()
		screen_fade.tween_property(screens[value],"modulate:a",1.0,0.25)
	if value == "home":
		_play_home_entrance()
	screen_changed.emit(value)

func _play_home_entrance() -> void:
	# Staggered cinematic entrance animation for floating HUD components.
	# ROOT-CAUSE NOTE: home_top_left (profile_button) and home_currency (currency_card)
	# are INSIDE HBoxContainers. Tweening position:x on layout-managed nodes fights the
	# Godot layout engine (which resets position every frame via NOTIFICATION_SORT_CHILDREN),
	# causing permanent drift and overlap on every home navigation.
	# Fix: modulate:a fade-in ONLY for layout-managed children.
	if home_top_left != null and is_instance_valid(home_top_left):
		home_top_left.modulate.a = 0.0
		var t1 := home_top_left.create_tween()
		t1.tween_property(home_top_left, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if home_currency != null and is_instance_valid(home_currency):
		home_currency.modulate.a = 0.0
		var t2 := home_currency.create_tween()
		t2.tween_property(home_currency, "modulate:a", 1.0, 0.35).set_delay(0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# home_car_panel, home_race_btn, home_nav_panel are direct page children (plain Control),
	# NOT in a layout container — position tweens are safe on them.
	if home_car_panel != null and is_instance_valid(home_car_panel):
		home_car_panel.modulate.a = 0.0
		home_car_panel.position.y += 18.0
		var t3 := home_car_panel.create_tween().set_parallel(true)
		t3.tween_property(home_car_panel, "modulate:a", 1.0, 0.38).set_delay(0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t3.tween_property(home_car_panel, "position:y", home_car_panel.position.y - 18.0, 0.42).set_delay(0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if home_race_btn != null and is_instance_valid(home_race_btn):
		home_race_btn.modulate.a = 0.0
		home_race_btn.position.x += 25.0
		var t4 := home_race_btn.create_tween().set_parallel(true)
		t4.tween_property(home_race_btn, "modulate:a", 1.0, 0.4).set_delay(0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t4.tween_property(home_race_btn, "position:x", home_race_btn.position.x - 25.0, 0.45).set_delay(0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if home_nav_panel != null and is_instance_valid(home_nav_panel):
		home_nav_panel.modulate.a = 0.0
		home_nav_panel.position.y += 20.0
		var t5 := home_nav_panel.create_tween().set_parallel(true)
		t5.tween_property(home_nav_panel, "modulate:a", 1.0, 0.4).set_delay(0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t5.tween_property(home_nav_panel, "position:y", home_nav_panel.position.y - 20.0, 0.45).set_delay(0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Restyle the Turbo Supply button injected by DrivingDirector (out-of-scope file).
	_restyle_turbo_supply()


func _update_wrong_way(car: ArcadeVehicle) -> void:
	if not DriveInput.enabled or get_tree().paused:
		wrong_way_active = false
	else:
		var road_forward: Vector3 = Vector3.FORWARD
		if car.course!=null:
			road_forward = Vector3.FORWARD.rotated(Vector3.UP,car.course.heading_at_z(car.position.z))
		elif car.road_center.is_valid():
			# Same centerline as the multiplayer road; no protocol/progress changes.
			var ahead: float = float(car.road_center.call(car.position.z-1.0))
			var behind: float = float(car.road_center.call(car.position.z+1.0))
			road_forward = Vector3(ahead-behind,0.0,-2.0).normalized()
		var car_forward: Vector3 = -car.transform.basis.z
		car_forward.y = 0.0
		var alignment: float = car_forward.normalized().dot(road_forward)
		# Hysteresis avoids flashing while the car is side-on during a U-turn.
		if alignment< -0.3: wrong_way_active = true
		elif alignment>0.15: wrong_way_active = false
	wrong_way_label.visible = wrong_way_active

func update_hud(car: ArcadeVehicle, camera_mode: int) -> void:
	_update_wrong_way(car)
	var cur_spd: int = int(round(car.speed_kmh()))
	if cur_spd != _last_speed_kmh:
		_last_speed_kmh = cur_spd
		speed_label.text = "%03d" % cur_spd

	var cur_gear: String = "R" if car.signed_speed < -0.2 else (str(car.transmission.gear) if car.signed_speed > 0.2 else "N")
	var cur_rpm: int = roundi(car.transmission.rpm)
	if cur_gear != _last_gear_str or cur_rpm != _last_rpm_val:
		_last_gear_str = cur_gear
		_last_rpm_val = cur_rpm
		gear_label.text = "GEAR %s  |  %04d RPM" % [cur_gear, cur_rpm]

	camera_label.text = "VIEW  /  " + DriveCameraRig.NAMES[clampi(camera_mode, 0, DriveCameraRig.NAMES.size()-1)]

	# 1. Vehicle speed fraction (for speed arc)
	RushSpeedDial.fraction = clampf(car.speed_kmh() / maxf(car.spec.top_speed_kmh, 1.0), 0.0, 1.25)
	RushSpeedDial.speed_value = cur_spd

	# 2. Transmission RPM telemetry (strictly distinct from vehicle speed)
	# HUD-only RPM normalization reference. VehicleSpec has no `engine` property.
	var redline: float = 7500.0
	RushSpeedDial.rpm_fraction = clampf(car.transmission.rpm / maxf(redline, 1000.0), 0.0, 1.0)
	RushSpeedDial.rpm_value = cur_rpm
	RushSpeedDial.gear_text = cur_gear

	# 3. Dedicated Turbo intensity
	RushSpeedDial.turbo_intensity = car.turbo.intensity if car.turbo != null else 0.0

	for action: String in controls:
		if action in ["turbo", "accelerate", "brake"]:
			continue
		var is_held: bool = DriveInput.held(action)
		controls[action].modulate = Color.WHITE
		if controls[action] is PanelContainer:
			var p_style: StyleBoxFlat = controls[action].get_theme_stylebox("panel") as StyleBoxFlat
			if p_style != null:
				p_style.bg_color = Color("0d2c42f0") if is_held else Color("071422ea")
				p_style.border_color = Color("00e5ff") if is_held else Color("00e5ff77")
				p_style.shadow_color = Color("00e5ff66") if is_held else Color("00e5ff2a")
				p_style.shadow_size = 14 if is_held else 8

func show_countdown(text: String) -> void:
	rush.show_countdown(text)

func update_run_hud(run: RushRunManager) -> void:
	rush.update_hud(run)

func show_results(summary: Dictionary, saved: bool) -> void:
	rush.show_results(summary,saved)

func coin_feedback(value: int) -> void:
	rush.coin_feedback(value)

func near_miss_feedback(combo: int) -> void:
	rush.near_miss_feedback(combo)

func show_home_error(message: String) -> void:
	rush.home_error.text = message

func set_boot_status(message: String) -> void:
	boot_status.text = message

func pulse_control(control: Control, tint: Color = Color("83cede")) -> void:
	control.modulate = tint
	var tween := create_tween()
	tween.tween_property(control,"modulate",Color.WHITE,.28)

func _slider_track(fill: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = _meter(fill)
	# Slider uses StyleBox minimum height; zero margins previously collapsed it.
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.set_corner_radius_all(4)
	return style

func _meter(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(3)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style

func _hud_glass(page: Control, preset: int, edges: Vector4) -> Panel:
	var panel := Panel.new()
	page.add_child(panel)
	panel.set_anchors_and_offsets_preset(preset)
	panel.offset_left = edges.x
	panel.offset_top = edges.y
	panel.offset_right = edges.z
	panel.offset_bottom = edges.w
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("06121fe6")
	style.border_color = Color("00e5ff88")
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.shadow_color = Color("00e5ff26")
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func show_camera_name(mode: int) -> void:
	if camera_name_fade!=null and camera_name_fade.is_valid():
		camera_name_fade.kill()
	camera_label.text = "VIEW  /  " + DriveCameraRig.NAMES[clampi(mode, 0, DriveCameraRig.NAMES.size()-1)]
	camera_label.modulate.a = 1.0
	camera_name_fade = create_tween()
	camera_name_fade.tween_interval(.75)
	camera_name_fade.tween_property(camera_label,"modulate:a",0.0,.4)

func _glass_style(fill: Color, border: Color = Color.TRANSPARENT, radius: int = 14, border_width: int = 1, shadow: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color("00000075")
	style.shadow_size = shadow
	style.shadow_offset = Vector2(0, 3)
	return style

func _dock_item(parent: Node, label_text: String, icon_res: Texture2D, callback: Callable) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 66)
	btn.clip_text = true
	btn.pivot_offset = Vector2(75, 33)

	# NORMAL: fully transparent — the single glass rail panel provides the unified
	# background. Individual button backgrounds make the nav look like five separate boxes.
	var normal_box := _glass_style(Color.TRANSPARENT, Color.TRANSPARENT, 10, 0, 0)
	var hover_box := _glass_style(Color("0d2030b0"), ACCENT, 10, 1, 5)
	var pressed_box := _glass_style(Color("050c14b0"), Color("3b7f8f"), 10, 1, 2)

	btn.add_theme_stylebox_override("normal", normal_box)
	btn.add_theme_stylebox_override("hover", hover_box)
	btn.add_theme_stylebox_override("pressed", pressed_box)
	btn.add_theme_stylebox_override("focus", hover_box)
	# Button.text is used by ProgressionUI.refresh_home() to store badge text (e.g. "MISSIONS • 3").
	# Make the button's own text rendering invisible — the child Label (col.get_child(1))
	# mirrors it via _process(). Without this, Godot renders button.text centered over the
	# entire button rect, overlapping the VBoxContainer icon+label children.
	btn.add_theme_color_override("font_color", Color.TRANSPARENT)
	btn.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	btn.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	btn.add_theme_color_override("font_focus_color", Color.TRANSPARENT)
	btn.add_theme_color_override("font_disabled_color", Color.TRANSPARENT)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	btn.add_child(col)

	var icon_rect := TextureRect.new()
	icon_rect.texture = icon_res
	icon_rect.custom_minimum_size = Vector2(22, 22)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon_rect)

	# col.get_child(1) == this label. Captured as missions_nav_label / daily_nav_label
	# in _build_home() after dock item creation.
	var lbl := _label(col, label_text, 22, Color("f1f8fc"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	var nav_font := FontVariation.new()
	nav_font.base_font = lbl.get_theme_font("font")
	nav_font.variation_embolden = 1.0
	lbl.add_theme_font_override("font", nav_font)
	# Fit to each equal-width slot, including live mission/reward badges.
	var fit_label: Callable = func() -> void:
		var available: float = maxf(1.0, btn.size.x - 12.0)
		var measured: float = nav_font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var fitted: int = mini(22, int(floor(22.0 * available / maxf(1.0, measured))))
		lbl.add_theme_font_size_override("font_size", maxi(1, fitted))
	lbl.resized.connect(fit_label)
	lbl.item_rect_changed.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
	lbl.set_meta("fit_navigation_label", fit_label)
	fit_label.call_deferred()

	btn.mouse_entered.connect(func() -> void:
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(1.03, 1.03), 0.12)
		icon_rect.modulate = Color("a6edff"))
	btn.mouse_exited.connect(func() -> void:
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2.ONE, 0.12)
		icon_rect.modulate = Color.WHITE)
	btn.button_down.connect(func() -> void:
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(0.97, 0.97), 0.08))
	btn.button_up.connect(func() -> void:
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2.ONE, 0.12))

	btn.pressed.connect(func() -> void:
		GameAudio.click()
		callback.call())

	parent.add_child(btn)
	return btn

## Mirror ProgressionUI badge text (set via Button.text) to the child Label each frame.
## Button has no text_changed signal; polling in _process is the only reliable hook
## that keeps badge info visible without the Button's own text overlapping the icon.
func _process(_delta: float) -> void:
	if missions_nav_label != null and missions_button != null:
		if missions_nav_label.text != missions_button.text:
			missions_nav_label.text = missions_button.text
			var fit_missions: Callable = missions_nav_label.get_meta("fit_navigation_label")
			fit_missions.call_deferred()
	if daily_nav_label != null and daily_button != null:
		var daily_text: String = daily_button.text.replace("DAILY REWARD", "DAILY").replace("DAILY", "DAILY REWARD")
		if daily_nav_label.text != daily_text:
			daily_nav_label.text = daily_text
			var fit_daily: Callable = daily_nav_label.get_meta("fit_navigation_label")
			fit_daily.call_deferred()

## Restyle the Turbo Supply button added by DrivingDirector.gd (out-of-allowed-scope).
## Called on every home entrance. Transforms the default full-height opaque button
## into a compact, transparent HUD pill that sits unobtrusively below the player card.
## Does NOT modify DrivingDirector logic or the button's pressed callback.
func _restyle_turbo_supply() -> void:
	if not screens.has("home"):
		return
	var home_page: Control = screens["home"]
	for child: Node in home_page.get_children():
		if child is Button and (child as Button).text.contains("TURBO"):
			var supply := child as Button
			# Compact secondary HUD pill: cyan-bordered glass, small font, non-competing size
			supply.add_theme_stylebox_override("normal", _home_glass())
			supply.add_theme_stylebox_override("hover", _glass_style(Color("0d2030e6"), ACCENT, 8, 1, 5))
			supply.add_theme_stylebox_override("pressed", _glass_style(Color("050c14"), Color("3b7f8f"), 8, 1, 2))
			supply.add_theme_stylebox_override("focus", _glass_style(Color("0d2030e6"), ACCENT, 8, 1, 5))
			supply.add_theme_font_size_override("font_size", 14)
			supply.add_theme_color_override("font_color", ACCENT)
			supply.add_theme_color_override("font_hover_color", Color.WHITE)
			supply.add_theme_color_override("font_pressed_color", ACCENT)
			# Follow the container's actual profile bounds, not a fixed Y offset.
			supply.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			var place_supply: Callable = _position_home_supply.bind(supply)
			if not profile_button.item_rect_changed.is_connected(place_supply):
				profile_button.item_rect_changed.connect(place_supply)
			if not home_page.resized.is_connected(place_supply):
				home_page.resized.connect(place_supply)
			place_supply.call_deferred()
			break

func _position_home_supply(supply: Button) -> void:
	if not is_instance_valid(supply) or not is_instance_valid(profile_button):
		return
	var home_page: Control = screens["home"]
	var profile_rect: Rect2 = profile_button.get_global_rect()
	var to_page: Transform2D = home_page.get_global_transform().affine_inverse()
	var bottom_left: Vector2 = to_page * Vector2(profile_rect.position.x,profile_rect.end.y)
	var bottom_right: Vector2 = to_page * profile_rect.end
	supply.position = bottom_left + Vector2(0.0,12.0)
	supply.size = Vector2(maxf(bottom_right.x-bottom_left.x,supply.get_combined_minimum_size().x),maxf(46.0,supply.get_combined_minimum_size().y))

## Home-only nine-slice glass: no shader/blur or per-frame work.
func _home_glass() -> StyleBoxTexture:
	var glass := StyleBoxTexture.new()
	glass.texture = preload("res://Assets/UI/home_silver_glass.svg")
	glass.texture_margin_left = 22.0
	glass.texture_margin_right = 22.0
	glass.texture_margin_top = 22.0
	glass.texture_margin_bottom = 22.0
	glass.content_margin_left = 12.0
	glass.content_margin_right = 12.0
	glass.content_margin_top = 6.0
	glass.content_margin_bottom = 6.0
	return glass

func _settings_glass(selected: bool = false) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = preload("res://Assets/UI/settings_glass_active.svg") if selected else preload("res://Assets/UI/settings_glass.svg")
	box.texture_margin_left = 20
	box.texture_margin_right = 20
	box.texture_margin_top = 20
	box.texture_margin_bottom = 20
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func _quality_card_style(selected: bool) -> StyleBoxFlat:
	var box: StyleBoxFlat = _style(Color("164657ef") if selected else Color("26343ed9"),Color("69e8ff") if selected else Color("a6b7bf"))
	box.set_corner_radius_all(12)
	box.set_border_width_all(2)
	box.shadow_color = Color("22d7ff66") if selected else Color("02080c90")
	box.shadow_size = 12 if selected else 4
	return box
