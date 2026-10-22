class_name RushGarageUI
extends Node

signal closed
signal play_requested
signal vehicle_previewed(id: String, paint: int)

var ui: AutomotiveUI
var ads: RushRewardedAdService
var index: int = 0
var first_launch: bool = false

# Contract UI Node references
var title: Label
var wallet: Label
var message: Label
var action: Button
var play: Button
var back: Button
var name_edit: LineEdit
var interaction: Control
var pages: Array[Control] = []
var browse_buttons: Array[Button] = []
var swatches: Array[Button] = []
var stats: Dictionary = {}
var upgrade_buttons: Dictionary = {}
var upgrade_levels: Dictionary = {}
var last_purchase_ms: int = -1000

# Redesign UI Elements & Animation Containers
var page_root: Control
var top_bar: HBoxContainer
var identity_panel: PanelContainer
var car_class_label: Label
var car_status_badge: Label
var car_counter_label: Label
var bottom_deck: Control
var deck_panel: PanelContainer
var tab_buttons: Array[Button] = []
var active_tab_index: int = 0
var stat_bars: Dictionary = {}
var stat_values: Dictionary = {}
var stat_anim_tweens: Dictionary = {}
var browse_tween: Tween
var entrance_tween: Tween

# Color Palette Constants
const COLOR_BG_GLASS := Color("07101ae8")
const COLOR_DECK_GLASS := Color("07121ce6")
const COLOR_PANEL_BORDER := Color("173042")
const COLOR_ACCENT_CYAN := Color("00e5ff")
const COLOR_ACCENT_SOFT := Color("83cede")
const COLOR_GOLD := Color("ffd360")
const COLOR_EMERALD := Color("5aff9f")
const COLOR_AMBER := Color("ffaa33")
const COLOR_MUTED := Color("6c8294")
const COLOR_TEXT_WHITE := Color("f0f6fa")

func id() -> String:
	return RushVehicleCatalog.garage_slot(RushVehicleCatalog.PLAYABLE_IDS[index], SaveService.collection)

func build(owner_ui: AutomotiveUI) -> void:
	ui = owner_ui
	page_root = ui._page("garage")
	page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Top Vignette Scrim for cinematic depth
	var top_scrim := TextureRect.new()
	top_scrim.texture = preload("res://Assets/UI/menu_scrim.svg")
	top_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_scrim.modulate = Color(1, 1, 1, 0.4)
	page_root.add_child(top_scrim)
	
	_build_top_bar()
	_build_car_identity_card()
	_build_interaction_and_chevrons()
	_build_bottom_studio_deck()
	
	SaveService.collection_changed.connect(refresh)
	SaveService.wallet_changed.connect(func(_balance: int) -> void: refresh())
	
	_tab(0)
	refresh()

# ------------------------------------------------------------------------------
# 1. TOP BAR: [ ‹ BACK ]       CAR STUDIO           [ COINS ] [ LEVEL ]
# ------------------------------------------------------------------------------
func _build_top_bar() -> void:
	top_bar = HBoxContainer.new()
	page_root.add_child(top_bar)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_top = 6
	top_bar.offset_bottom = 48
	top_bar.offset_left = 12
	top_bar.offset_right = -12
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.alignment = BoxContainer.ALIGNMENT_CENTER

	# Back Button (Sleek glass pill)
	back = Button.new()
	back.text = "‹  BACK"
	back.custom_minimum_size = Vector2(96, 36)
	back.focus_mode = Control.FOCUS_ALL
	back.add_theme_font_size_override("font_size", 13)
	back.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
	back.add_theme_color_override("font_hover_color", COLOR_ACCENT_CYAN)
	back.add_theme_stylebox_override("normal", _glass_style(Color("081420cc"), Color("1f3c50"), 8))
	back.add_theme_stylebox_override("hover", _glass_style(Color("0f2434e0"), COLOR_ACCENT_CYAN, 8))
	back.add_theme_stylebox_override("pressed", _glass_style(Color("081e2cee"), COLOR_ACCENT_SOFT, 8))
	back.pressed.connect(func() -> void:
		GameAudio.click()
		closed.emit())
	top_bar.add_child(back)

	# Center Brand / Studio Header with Clear Hierarchy
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_theme_constant_override("separation", 1)
	top_bar.add_child(title_box)

	var studio_lbl := Label.new()
	studio_lbl.text = "CAR STUDIO"
	studio_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	studio_lbl.add_theme_font_size_override("font_size", 18)
	studio_lbl.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
	studio_lbl.add_theme_color_override("font_shadow_color", Color("000000cc"))
	studio_lbl.add_theme_constant_override("shadow_offset_y", 1)
	studio_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(studio_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "CUSTOM SPECIFICATION LAB"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", COLOR_ACCENT_SOFT)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(sub_lbl)

	# Right: Currency & Level Cluster
	var wallet_panel := PanelContainer.new()
	wallet_panel.custom_minimum_size = Vector2(165, 36)
	wallet_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wallet_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet_panel.add_theme_stylebox_override("panel", _glass_style(Color("081420cc"), Color("e6b83088"), 10))
	top_bar.add_child(wallet_panel)

	var wallet_row := HBoxContainer.new()
	wallet_row.alignment = BoxContainer.ALIGNMENT_CENTER
	wallet_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet_row.add_theme_constant_override("separation", 8)
	wallet_panel.add_child(wallet_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture = preload("res://Assets/UI/icon_coin.svg")
	coin_icon.custom_minimum_size = Vector2(17, 17)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet_row.add_child(coin_icon)

	wallet = Label.new()
	wallet.add_theme_font_size_override("font_size", 13)
	wallet.add_theme_color_override("font_color", COLOR_GOLD)
	wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet_row.add_child(wallet)

# ------------------------------------------------------------------------------
# 2. CAR IDENTITY CARD (Floating Top-Left Telemetry)
# ------------------------------------------------------------------------------
func _build_car_identity_card() -> void:
	identity_panel = PanelContainer.new()
	identity_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	identity_panel.offset_left = 16
	identity_panel.offset_top = 54
	identity_panel.offset_right = 296
	identity_panel.offset_bottom = 126
	identity_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity_panel.add_theme_stylebox_override("panel", _glass_style(COLOR_BG_GLASS, COLOR_PANEL_BORDER, 8, 1))
	page_root.add_child(identity_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	identity_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	margin.add_child(box)

	var header_row := HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header_row)

	car_class_label = Label.new()
	car_class_label.text = "SPORT COUPE"
	car_class_label.add_theme_font_size_override("font_size", 10)
	car_class_label.add_theme_color_override("font_color", COLOR_ACCENT_CYAN)
	car_class_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	car_class_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(car_class_label)

	car_counter_label = Label.new()
	car_counter_label.text = "01 / 12"
	car_counter_label.add_theme_font_size_override("font_size", 10)
	car_counter_label.add_theme_color_override("font_color", COLOR_MUTED)
	car_counter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(car_counter_label)

	# Main Car Title (Contract reference `title`)
	title = Label.new()
	title.text = String(RushVehicleCatalog.definition("vortex_s").name).to_upper()
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
	title.add_theme_color_override("font_shadow_color", Color("000000cc"))
	title.add_theme_constant_override("shadow_offset_y", 1)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	car_status_badge = Label.new()
	car_status_badge.text = "● ACTIVE / SELECTED"
	car_status_badge.add_theme_font_size_override("font_size", 9)
	car_status_badge.add_theme_color_override("font_color", COLOR_ACCENT_CYAN)
	car_status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(car_status_badge)

# ------------------------------------------------------------------------------
# 3. INTERACTION VIEWPORT & CLEAN NON-CLIPPED CHEVRONS
# ------------------------------------------------------------------------------
func _build_interaction_and_chevrons() -> void:
	# Large Unobstructed 3D Viewport Touch Target (Contract reference `interaction`)
	interaction = Control.new()
	page_root.add_child(interaction)
	interaction.set_anchors_preset(Control.PRESET_FULL_RECT)
	interaction.offset_top = 54
	interaction.offset_bottom = -220
	interaction.offset_left = 64
	interaction.offset_right = -64
	interaction.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Exactly 2 Navigation Chevrons, cleanly anchored inside safe viewport
	browse_buttons.clear()
	for direction: int in [-1, 1]:
		var arrow := Button.new()
		arrow.text = "‹" if direction < 0 else "›"
		arrow.custom_minimum_size = Vector2(48, 68)
		arrow.focus_mode = Control.FOCUS_ALL
		arrow.add_theme_font_size_override("font_size", 32)
		arrow.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
		arrow.add_theme_color_override("font_hover_color", COLOR_ACCENT_CYAN)
		arrow.add_theme_stylebox_override("normal", _glass_style(Color("06121acc"), Color("1a3548"), 12))
		arrow.add_theme_stylebox_override("hover", _glass_style(Color("0e2432e6"), COLOR_ACCENT_CYAN, 12))
		arrow.add_theme_stylebox_override("pressed", _glass_style(Color("081a24f0"), COLOR_ACCENT_SOFT, 12))

		# Anchored directly to page_root with positive safe-area offsets
		if direction < 0:
			arrow.set_anchors_preset(Control.PRESET_CENTER_LEFT)
			arrow.offset_left = 16
			arrow.offset_right = 64
		else:
			arrow.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
			arrow.offset_left = -64
			arrow.offset_right = -16
		arrow.offset_top = -34
		arrow.offset_bottom = 34
		arrow.tooltip_text = "Previous vehicle" if direction < 0 else "Next vehicle"

		var dir_copy: int = direction
		arrow.pressed.connect(func() -> void:
			_browse(dir_copy))
		page_root.add_child(arrow)
		browse_buttons.append(arrow)

# ------------------------------------------------------------------------------
# 4. COMPACT BOTTOM STUDIO CONTROL DECK & UNIFIED ACTION CLUSTER
# ------------------------------------------------------------------------------
func _build_bottom_studio_deck() -> void:
	# Readable mobile workspace; the showroom interaction ends above this deck.
	bottom_deck = Control.new()
	page_root.add_child(bottom_deck)
	bottom_deck.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_deck.offset_top = -212
	bottom_deck.offset_bottom = -8
	bottom_deck.offset_left = 12
	bottom_deck.offset_right = -12
	bottom_deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var readable_font := FontVariation.new()
	readable_font.base_font = bottom_deck.get_theme_font("font")
	readable_font.variation_embolden = 0.6
	var readable_theme := Theme.new()
	readable_theme.default_font = readable_font
	bottom_deck.theme = readable_theme

	var deck_layout := VBoxContainer.new()
	deck_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	deck_layout.add_theme_constant_override("separation", 3)
	deck_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_deck.add_child(deck_layout)

	# --- ROW A: TAB RAIL + CONTEXTUAL MICROCOPY HINT ---
	var rail_row := HBoxContainer.new()
	rail_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail_row.add_theme_constant_override("separation", 8)
	deck_layout.add_child(rail_row)

	var tab_bar := HBoxContainer.new()
	tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_bar.add_theme_constant_override("separation", 6)
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail_row.add_child(tab_bar)

	var tab_names := ["OVERVIEW", "CUSTOMIZE", "UPGRADES"]
	for i: int in 3:
		var tab_btn := Button.new()
		tab_btn.text = tab_names[i]
		tab_btn.custom_minimum_size = Vector2(0, 40)
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.focus_mode = Control.FOCUS_ALL
		tab_btn.add_theme_font_size_override("font_size", 18)
		var tab_font := FontVariation.new()
		tab_font.base_font = tab_btn.get_theme_font("font")
		tab_font.variation_embolden = 1.0
		tab_btn.add_theme_font_override("font", tab_font)
		tab_btn.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
		tab_btn.add_theme_color_override("font_hover_color", COLOR_TEXT_WHITE)
		tab_btn.add_theme_stylebox_override("normal", _glass_style(Color.TRANSPARENT, Color.TRANSPARENT, 5))
		tab_btn.add_theme_stylebox_override("hover", _glass_style(Color("10223080"), Color.TRANSPARENT, 5))
		tab_btn.add_theme_stylebox_override("pressed", _glass_style(Color("142c3d90"), Color.TRANSPARENT, 5))
		var idx: int = i
		tab_btn.pressed.connect(func() -> void:
			GameAudio.click()
			_tab(idx))
		tab_bar.add_child(tab_btn)
		tab_buttons.append(tab_btn)

	# Subtle Contextual Microcopy (Integrated beneath header, never competes with CTA)
	message = Label.new()
	message.text = "◈  Drag to rotate • Paint is free"
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	message.add_theme_font_size_override("font_size", 14)
	message.add_theme_color_override("font_color", Color("a3bacb"))
	message.clip_text = true
	message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail_row.add_child(message)

	# --- ROW B: WORKSPACE DECK & UNIFIED ACTION CLUSTER ---
	var deck_body := HBoxContainer.new()
	deck_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deck_body.add_theme_constant_override("separation", 10)
	deck_layout.add_child(deck_body)

	# Compact Workspace Panel hugging content
	deck_panel = PanelContainer.new()
	deck_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_panel.add_theme_stylebox_override("panel", _glass_style(COLOR_DECK_GLASS, COLOR_PANEL_BORDER, 8))
	deck_body.add_child(deck_panel)

	# 3 Scrollable Pages for Tabs (Contract reference `pages`)
	for tab_idx: int in 3:
		var scroll := RushTouchScroll.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		deck_panel.add_child(scroll)

		var content := MarginContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("margin_left", 12)
		content.add_theme_constant_override("margin_right", 12)
		content.add_theme_constant_override("margin_top", 6)
		content.add_theme_constant_override("margin_bottom", 6)
		scroll.add_child(content)
		pages.append(content)

	_build_overview_tab(pages[0])
	_build_customize_tab(pages[1])
	_build_upgrades_tab(pages[2])

	# Unified Bottom-Right Action Cluster
	var action_box := VBoxContainer.new()
	action_box.custom_minimum_size = Vector2(160, 0)
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_box.add_theme_constant_override("separation", 5)
	deck_body.add_child(action_box)

	# Race / Play Button (Hero Gameplay CTA when available)
	play = Button.new()
	play.text = "RACE  ▶"
	play.custom_minimum_size = Vector2(160, 48)
	play.focus_mode = Control.FOCUS_ALL
	play.add_theme_font_size_override("font_size", 18)
	play.add_theme_color_override("font_color", Color("061a22"))
	play.add_theme_color_override("font_hover_color", Color("061a22"))
	play.add_theme_color_override("font_pressed_color", Color("061a22"))
	play.add_theme_color_override("font_disabled_color", Color("486070"))
	play.add_theme_stylebox_override("normal", _glass_style(COLOR_ACCENT_CYAN, Color("d0f6ff"), 6, 1))
	play.add_theme_stylebox_override("hover", _glass_style(Color("5cedff"), Color.WHITE, 6, 1))
	play.add_theme_stylebox_override("pressed", _glass_style(Color("00b4cc"), COLOR_ACCENT_SOFT, 6, 1))
	play.add_theme_stylebox_override("disabled", _glass_style(Color("0d1c26cc"), Color("162c3a"), 6, 1))
	play.pressed.connect(func() -> void:
		GameAudio.click()
		_play())
	action_box.add_child(play)

	# Primary Contextual State Button (SELECT / SELECTED / BUY)
	action = Button.new()
	action.text = "SELECT"
	action.custom_minimum_size = Vector2(160, 44)
	action.focus_mode = Control.FOCUS_ALL
	action.add_theme_font_size_override("font_size", 16)
	action.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
	action.add_theme_stylebox_override("normal", _glass_style(Color("0f293acc"), COLOR_ACCENT_CYAN, 6, 1))
	action.add_theme_stylebox_override("hover", _glass_style(Color("163c54e6"), Color.WHITE, 6, 1))
	action.add_theme_stylebox_override("pressed", _glass_style(Color("0b202eee"), COLOR_ACCENT_SOFT, 6, 1))
	action.add_theme_stylebox_override("disabled", _glass_style(Color("0a151ecc"), Color("17303f"), 6, 1))
	action.pressed.connect(func() -> void:
		GameAudio.click()
		_action())
	action_box.add_child(action)

# ------------------------------------------------------------------------------
# 5. TAB 0: OVERVIEW (Snug High-Density Telemetry Rack)
# ------------------------------------------------------------------------------
func _build_overview_tab(parent: Control) -> void:
	# 2-Column Balanced Grid that completely eliminates empty space
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)

	var stat_keys := ["SPEED", "ACCELERATION", "HANDLING", "BRAKING", "TURBO"]
	for key: String in stat_keys:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		grid.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = key
		name_lbl.custom_minimum_size.x = 126
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", Color("b3c9d8"))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_lbl)

		var value_lbl := Label.new()
		value_lbl.text = "0.0"
		value_lbl.custom_minimum_size.x = 80
		value_lbl.add_theme_font_size_override("font_size", 16)
		value_lbl.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
		value_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(value_lbl)

		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 4
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", _meter_bg_style())
		bar.add_theme_stylebox_override("fill", _meter_fill_style(COLOR_ACCENT_CYAN))
		row.add_child(bar)

		# Contract dictionary: stats[key] = [Label, ProgressBar]
		stats[key] = [value_lbl, bar]
		stat_bars[key] = bar
		stat_values[key] = value_lbl

# ------------------------------------------------------------------------------
# 6. TAB 1: CUSTOMIZE (Vehicle Callsign + 16 Circular Paint Swatches)
# ------------------------------------------------------------------------------
func _build_customize_tab(parent: Control) -> void:
	var custom_layout := GridContainer.new()
	custom_layout.columns = 2
	custom_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_layout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_layout.add_theme_constant_override("h_separation", 20)
	custom_layout.add_theme_constant_override("v_separation", 12)
	parent.add_child(custom_layout)
	custom_layout.resized.connect(func() -> void:
		custom_layout.columns = 2 if parent.size.x >= 730.0 else 1)

	# Left: Compact Car Callsign Editor
	var name_box := VBoxContainer.new()
	name_box.custom_minimum_size = Vector2(340, 0)
	name_box.add_theme_constant_override("separation", 4)
	custom_layout.add_child(name_box)

	var name_title := Label.new()
	name_title.text = "CALLSIGN"
	name_title.add_theme_font_size_override("font_size", 16)
	name_title.add_theme_color_override("font_color", COLOR_MUTED)
	name_box.add_child(name_title)

	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 6)
	name_box.add_child(edit_row)

	name_edit = LineEdit.new()
	name_edit.max_length = 18
	name_edit.placeholder_text = "Name vehicle"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size.y = 44
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.add_theme_stylebox_override("normal", _glass_style(Color("0a1724dd"), Color("22445c"), 5))
	name_edit.add_theme_stylebox_override("focus", _glass_style(Color("0f2233f0"), COLOR_ACCENT_CYAN, 5))
	edit_row.add_child(name_edit)

	var save_btn := Button.new()
	save_btn.text = "SAVE"
	save_btn.custom_minimum_size = Vector2(68, 44)
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.add_theme_stylebox_override("normal", _glass_style(Color("102a3ccc"), COLOR_ACCENT_CYAN, 5))
	save_btn.add_theme_stylebox_override("hover", _glass_style(Color("163c54e6"), Color.WHITE, 5))
	save_btn.pressed.connect(func() -> void:
		GameAudio.click()
		_name(false))
	edit_row.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = "RESET"
	reset_btn.custom_minimum_size = Vector2(68, 44)
	reset_btn.add_theme_font_size_override("font_size", 16)
	reset_btn.add_theme_color_override("font_color", COLOR_MUTED)
	reset_btn.add_theme_stylebox_override("normal", _glass_style(Color("0b151fcc"), Color("1f3342"), 5))
	reset_btn.add_theme_stylebox_override("hover", _glass_style(Color("122230e6"), Color("35556d"), 5))
	reset_btn.pressed.connect(func() -> void:
		GameAudio.click()
		_name(true))
	edit_row.add_child(reset_btn)

	# Right: 16 Circular / Rounded Swatches
	var paint_box := VBoxContainer.new()
	paint_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint_box.add_theme_constant_override("separation", 4)
	custom_layout.add_child(paint_box)

	var paint_title := Label.new()
	paint_title.text = "FINISH PALETTE  •  16 FORMULAS"
	paint_title.add_theme_font_size_override("font_size", 16)
	paint_title.add_theme_color_override("font_color", COLOR_MUTED)
	paint_box.add_child(paint_title)

	var colors_grid := GridContainer.new()
	colors_grid.columns = 8
	colors_grid.add_theme_constant_override("h_separation", 6)
	colors_grid.add_theme_constant_override("v_separation", 4)
	paint_box.add_child(colors_grid)

	swatches.clear()
	for paint_index: int in RushVehicleCatalog.paint_count():
		var button := Button.new()
		button.custom_minimum_size = Vector2(38, 38)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = RushVehicleCatalog.data.paints[paint_index].name
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", 12)

		var swatch_style := StyleBoxFlat.new()
		swatch_style.bg_color = RushVehicleCatalog.paint_color(paint_index)
		swatch_style.set_corner_radius_all(5)
		swatch_style.set_border_width_all(1)
		swatch_style.border_color = Color("ffffff25")
		button.add_theme_stylebox_override("normal", swatch_style)

		var hover_style := swatch_style.duplicate() as StyleBoxFlat
		hover_style.border_color = Color.WHITE
		hover_style.set_border_width_all(2)
		button.add_theme_stylebox_override("hover", hover_style)

		var p_idx: int = paint_index
		button.pressed.connect(func() -> void:
			GameAudio.click()
			_paint(p_idx))
		colors_grid.add_child(button)
		swatches.append(button)

# ------------------------------------------------------------------------------
# 7. TAB 2: UPGRADES (Compact Technical Modules)
# ------------------------------------------------------------------------------
func _build_upgrades_tab(parent: Control) -> void:
	var upgrades_row := GridContainer.new()
	upgrades_row.columns = 5
	upgrades_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	upgrades_row.add_theme_constant_override("h_separation", 8)
	upgrades_row.add_theme_constant_override("v_separation", 10)
	parent.add_child(upgrades_row)
	upgrades_row.resized.connect(func() -> void:
		upgrades_row.columns = clampi(int(parent.size.x / 220.0), 1, 5))

	for category: String in RushVehicleCatalog.CATEGORIES:
		var module := PanelContainer.new()
		module.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		module.add_theme_stylebox_override("panel", _glass_style(Color("07121bcc"), Color("1a3547"), 6, 1))
		upgrades_row.add_child(module)

		var m_margin := MarginContainer.new()
		m_margin.add_theme_constant_override("margin_left", 6)
		m_margin.add_theme_constant_override("margin_right", 6)
		m_margin.add_theme_constant_override("margin_top", 4)
		m_margin.add_theme_constant_override("margin_bottom", 4)
		module.add_child(m_margin)

		var m_box := VBoxContainer.new()
		m_box.add_theme_constant_override("separation", 2)
		m_margin.add_child(m_box)

		var cat_lbl := Label.new()
		cat_lbl.text = category.to_upper()
		cat_lbl.add_theme_font_size_override("font_size", 16)
		cat_lbl.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
		m_box.add_child(cat_lbl)

		var info_lbl := Label.new()
		info_lbl.text = "LV 0/10"
		info_lbl.custom_minimum_size.x = 180
		info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_lbl.add_theme_font_size_override("font_size", 16)
		info_lbl.add_theme_color_override("font_color", COLOR_MUTED)
		m_box.add_child(info_lbl)
		upgrade_levels[category] = info_lbl

		var up_btn := Button.new()
		up_btn.text = "UPGRADE"
		up_btn.custom_minimum_size.y = 44
		up_btn.focus_mode = Control.FOCUS_ALL
		up_btn.add_theme_font_size_override("font_size", 16)
		up_btn.add_theme_color_override("font_color", Color("061a22"))
		up_btn.add_theme_stylebox_override("normal", _glass_style(COLOR_ACCENT_CYAN, Color.WHITE, 5))
		up_btn.add_theme_stylebox_override("hover", _glass_style(Color("5cedff"), Color.WHITE, 5))
		up_btn.add_theme_stylebox_override("disabled", _glass_style(Color("0e1d28cc"), Color("183040"), 5))

		var cat_copy: String = category
		up_btn.pressed.connect(func() -> void:
			GameAudio.click()
			_upgrade(cat_copy))
		m_box.add_child(up_btn)
		upgrade_buttons[category] = up_btn

# ------------------------------------------------------------------------------
# FUNCTIONAL LOGIC & REFRESH (100% Contract Preserved)
# ------------------------------------------------------------------------------
func bind_ads(service: RushRewardedAdService) -> void:
	ads = service
	ads.status_changed.connect(func(value: String) -> void:
		message.text = value
		refresh())

func open(onboarding: bool = false) -> void:
	first_launch = onboarding
	index = 0 if onboarding else maxi(RushVehicleCatalog.PLAYABLE_IDS.find(RushVehicleCatalog.canonical_id(SaveService.collection.selected)), 0)
	message.text = "◈  Make Vortex S yours, then confirm" if onboarding else "◈  Drag to rotate • Paint is free"
	_tab(1 if onboarding else 0)
	refresh()
	_animate_entrance()

func _tab(selected: int) -> void:
	active_tab_index = selected
	for i: int in pages.size():
		var scroll: Control = pages[i].get_parent() as Control
		if is_instance_valid(scroll):
			scroll.visible = (i == selected)
		if i < tab_buttons.size() and is_instance_valid(tab_buttons[i]):
			if i == selected:
				tab_buttons[i].add_theme_color_override("font_color", COLOR_ACCENT_CYAN)
				tab_buttons[i].add_theme_stylebox_override("normal", _glass_style(Color("0e273a99"), COLOR_ACCENT_CYAN, 5, 1))
			else:
				tab_buttons[i].add_theme_color_override("font_color", COLOR_TEXT_WHITE)
				tab_buttons[i].add_theme_stylebox_override("normal", _glass_style(Color.TRANSPARENT, Color.TRANSPARENT, 5))

func _browse(step: int) -> void:
	if first_launch:
		return
	index = posmod(index + step, RushVehicleCatalog.PLAYABLE_IDS.size())
	GameAudio.event("car_select")
	_animate_car_browse()
	refresh()

func refresh() -> void:
	if not is_instance_valid(action):
		return
	var car_id := id()
	var d := RushVehicleCatalog.definition(car_id)
	var owned := SaveService.owns(car_id)
	var selected: bool = SaveService.collection.selected == car_id
	var levels: Dictionary = SaveService.collection.upgrades[car_id]
	var spec := RushVehicleCatalog.effective(car_id, levels)

	# 1. Car Identity Telemetry
	var custom_name: String = SaveService.car_name(car_id)
	title.text = custom_name.to_upper()
	if is_instance_valid(car_class_label):
		var class_str := String(d.get("class", "SPORT")).to_upper()
		car_class_label.text = class_str if custom_name == String(d.name) else "%s  •  %s" % [String(d.name).to_upper(), class_str]
	if is_instance_valid(car_counter_label):
		car_counter_label.text = "%02d / %02d" % [index + 1, RushVehicleCatalog.PLAYABLE_IDS.size()]
	if is_instance_valid(car_status_badge):
		if selected:
			car_status_badge.text = "● ACTIVE / SELECTED"
			car_status_badge.add_theme_color_override("font_color", COLOR_ACCENT_CYAN)
		elif owned:
			car_status_badge.text = "● OWNED"
			car_status_badge.add_theme_color_override("font_color", COLOR_EMERALD)
		else:
			car_status_badge.text = "● LOCKED"
			car_status_badge.add_theme_color_override("font_color", COLOR_AMBER)

	# 2. Currency & Level
	var player_level: int = RushProgressionData.level_for(int(SaveService.progression.get("xp", 0)))
	wallet.text = "%d COINS  •  LV. %d" % [SaveService.balance(), player_level]

	# 3. Contextual Primary State Button (Compact status pill when selected, CTA otherwise)
	if first_launch:
		action.text = "CONFIRM " + String(d.name).to_upper()
		action.disabled = false
		action.add_theme_color_override("font_color", Color("061a22"))
		action.add_theme_stylebox_override("normal", _glass_style(COLOR_ACCENT_CYAN, Color.WHITE, 6, 1))
	elif selected:
		action.text = "✓  SELECTED"
		action.disabled = true
		action.add_theme_color_override("font_disabled_color", COLOR_ACCENT_CYAN)
		action.add_theme_stylebox_override("disabled", _glass_style(Color("08202d99"), Color("00e5ff66"), 6, 1))
	elif owned:
		action.text = "SELECT VEHICLE"
		action.disabled = false
		action.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
		action.add_theme_stylebox_override("normal", _glass_style(Color("0f293acc"), COLOR_ACCENT_CYAN, 6, 1))
	else:
		action.text = "BUY — %d COINS" % int(d.price)
		action.disabled = not SaveService.can_afford(int(d.price))
		if action.disabled:
			action.add_theme_color_override("font_disabled_color", Color("708391"))
			action.add_theme_stylebox_override("disabled", _glass_style(Color("0a151ecc"), Color("17303f"), 6, 1))
		else:
			action.add_theme_color_override("font_color", Color("061a22"))
			action.add_theme_stylebox_override("normal", _glass_style(COLOR_GOLD, Color.WHITE, 6, 1))

	# 4. Hero Gameplay CTA (RACE ▶)
	play.visible = not first_launch
	play.disabled = not owned
	if not owned:
		play.add_theme_stylebox_override("disabled", _glass_style(Color("0a151ecc"), Color("142733"), 6, 1))

	back.visible = not first_launch
	for arrow: Button in browse_buttons:
		arrow.visible = not first_launch

	# 5. Customization Fields
	name_edit.editable = owned
	if not name_edit.has_focus():
		name_edit.text = custom_name
	for i: int in swatches.size():
		swatches[i].disabled = not owned
		var is_active: bool = int(SaveService.collection.paints[car_id]) == i
		swatches[i].text = "✓" if is_active else ""
		var normal_style := swatches[i].get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		if is_active:
			normal_style.border_color = COLOR_ACCENT_CYAN
			normal_style.set_border_width_all(2)
		else:
			normal_style.border_color = Color("ffffff25")
			normal_style.set_border_width_all(1)
		swatches[i].add_theme_stylebox_override("normal", normal_style)

	# 6. Performance Telemetry Stats
	var values := [spec.top_speed_kmh, spec.acceleration, spec.steering_response, spec.braking, spec.turbo.top_speed_kmh]
	var limits := [360.0, 28.0, 12.0, 50.0, 425.0]
	var names := ["SPEED", "ACCELERATION", "HANDLING", "BRAKING", "TURBO"]
	for i: int in 5:
		var stat_name: String = names[i]
		var val_text := "%.1f%s" % [values[i], " KM/H" if i in [0, 4] else ""]
		stats[stat_name][0].text = val_text
		var target_ratio: float = clampf(values[i] / limits[i] * 100.0, 0.0, 100.0)
		_animate_stat_bar(stat_name, target_ratio)

	# 7. Technical Upgrade Modules
	for category: String in RushVehicleCatalog.CATEGORIES:
		var level := int(levels[category])
		var cost := RushVehicleCatalog.upgrade_cost(level)
		var target := mini(level + 1, 10)
		var required := RushVehicleCatalog.upgrade_ad_requirement(target)
		var count := SaveService.upgrade_ad_count(car_id, category, target)
		var key: String = {"engine":"engine_acceleration","handling":"handling_response","brakes":"brakes","tires":"tires_grip","transmission":"transmission_acceleration"}[category]
		var percent := float(RushVehicleCatalog.data.upgrade_modifiers[key]) * 100.0

		upgrade_levels[category].text = "LV %d/10\n+%.0f%% → +%.0f%%\n%d COINS • ADS %d/%d" % [level, level * percent, target * percent, cost, count, required]
		var btn: Button = upgrade_buttons[category]
		btn.text = "MAX LEVEL" if level >= 10 else ("UPGRADE" if SaveService.can_afford(cost) else "WATCH AD")
		btn.disabled = not owned or level >= 10 or (ads != null and ads.pending != 0 and not ads.earned)
		if ads != null and ads.pending != 0 and ads.earned:
			btn.text = "CLAIM REWARD"

		# Button Color Coding
		if level >= 10:
			btn.add_theme_color_override("font_color", COLOR_EMERALD)
			btn.add_theme_stylebox_override("disabled", _glass_style(Color("0e241acc"), Color("1a4a30"), 5))
		elif not SaveService.can_afford(cost):
			btn.add_theme_color_override("font_color", Color("061a22"))
			btn.add_theme_stylebox_override("normal", _glass_style(COLOR_AMBER, Color.WHITE, 5))
		else:
			btn.add_theme_color_override("font_color", Color("061a22"))
			btn.add_theme_stylebox_override("normal", _glass_style(COLOR_ACCENT_CYAN, Color.WHITE, 5))

	vehicle_previewed.emit(car_id, int(SaveService.collection.paints[car_id]))

func _allow_purchase() -> bool:
	var now := Time.get_ticks_msec()
	if now - last_purchase_ms < 500:
		return false
	last_purchase_ms = now
	return true

func _action() -> void:
	if not _allow_purchase():
		return
	if first_launch:
		if SaveService.confirm_starter():
			closed.emit()
		return
	var success := SaveService.select_vehicle(id()) if SaveService.owns(id()) else SaveService.buy_vehicle(id())
	message.text = "◈  Ready to drive" if success else ("◈  " + SaveService.last_error)
	refresh()

func _play() -> void:
	if not first_launch and SaveService.owns(id()) and SaveService.select_vehicle(id()):
		play_requested.emit()

func _upgrade(category: String) -> void:
	if not _allow_purchase():
		return
	if ads != null and ads.pending != 0:
		if ads.earned:
			ads.retry_pending_reward()
		return
	var level := int(SaveService.collection.upgrades[id()][category])
	if level >= 10 or not SaveService.owns(id()):
		return
	if SaveService.can_afford(RushVehicleCatalog.upgrade_cost(level)):
		message.text = "◈  Upgrade installed" if SaveService.buy_upgrade(id(), category, level) else ("◈  " + SaveService.last_error)
	elif ads != null:
		ads.request_upgrade_reward(id(), category, level + 1)
	refresh()

func _name(reset: bool) -> void:
	message.text = "◈  Name saved" if SaveService.set_car_name(id(), name_edit.text, reset) else "◈  Enter a name for an owned car"
	name_edit.release_focus()
	refresh()

func _paint(value: int) -> void:
	if not SaveService.set_paint(id(), value):
		message.text = "◈  " + SaveService.last_error
	refresh()

# ------------------------------------------------------------------------------
# 8. SAFE IN-BOUNDS ANIMATIONS (No Off-Screen Negative Offsets)
# ------------------------------------------------------------------------------
func _animate_entrance() -> void:
	if entrance_tween != null and entrance_tween.is_valid():
		entrance_tween.kill()
	entrance_tween = create_tween().set_parallel(true)

	if is_instance_valid(top_bar):
		top_bar.modulate.a = 0.0
		entrance_tween.tween_property(top_bar, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if is_instance_valid(identity_panel):
		identity_panel.modulate.a = 0.0
		entrance_tween.tween_property(identity_panel, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if is_instance_valid(bottom_deck):
		bottom_deck.modulate.a = 0.0
		entrance_tween.tween_property(bottom_deck, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _animate_car_browse() -> void:
	if browse_tween != null and browse_tween.is_valid():
		browse_tween.kill()
	browse_tween = create_tween().set_parallel(true)

	if is_instance_valid(title):
		title.modulate.a = 0.2
		browse_tween.tween_property(title, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _animate_stat_bar(key: String, target_value: float) -> void:
	if not stat_bars.has(key):
		return
	var bar: ProgressBar = stat_bars[key]
	if not is_instance_valid(bar):
		return
	if stat_anim_tweens.has(key) and stat_anim_tweens[key] != null and stat_anim_tweens[key].is_valid():
		stat_anim_tweens[key].kill()
	var tw := create_tween()
	tw.tween_property(bar, "value", target_value, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	stat_anim_tweens[key] = tw

# ------------------------------------------------------------------------------
# 9. STYLE HELPERS
# ------------------------------------------------------------------------------
func _glass_style(fill: Color, border: Color = Color.TRANSPARENT, radius: int = 8, border_w: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_w)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color("00000040")
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style

func _meter_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0c1722")
	style.border_color = Color("162838")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style

func _meter_fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style
