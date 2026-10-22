class_name RushProgressionUI
extends Node
## Cached safe-area menus. Refresh only when opened or after a transaction.
var ui: AutomotiveUI
var account_content: VBoxContainer
var profile_interaction: Control
var profile_badge: RushLevelBadge
var mission_rows: Array = []
var achievement_rows: Array = []
var daily_cards: Array = []
var daily_claim: Button
var profile_values: Dictionary = {}
var name_edit: LineEdit
var driver_name_label: Label
var status_labels: Dictionary = {}
var notice: PanelContainer
var notice_title: Label
var notice_body: Label
var notice_tween: Tween
var presenting: bool = false

func build(owner_ui: AutomotiveUI) -> void:
	ui = owner_ui
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_missions()
	_build_daily()
	_build_profile()
	_build_notice()
	RewardService.progression_changed.connect(_changed)
	SaveService.collection_changed.connect(_changed)
	SaveService.account_scope_changed.connect(func() -> void:
		name_edit.release_focus()
		name_edit.text = String(SaveService.progression.name)
		for label: Label in profile_values.values(): label.text = ""
		profile_badge.refresh()
		dismiss_notice())
	SaveService.save_failed.connect(_save_failed)
	ui.screen_changed.connect(func(_page: String) -> void: dismiss_notice())
	refresh_home()

func _menu(name_value: String, title: String, profile: bool = false) -> VBoxContainer:
	var page := ui._page(name_value, not profile and name_value != "missions")
	page.visible = false
	var panel := PanelContainer.new()
	page.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if profile:
		panel.anchor_left = 0.455
		# Premium glassmorphic outer panel — deep navy/graphite, ~88% opacity,
		# thin left-edge cyan border, subtle left-side shadow for 3D depth separation.
		var glass_outer := StyleBoxFlat.new()
		glass_outer.bg_color = Color("0d1924e0")           # 88% opacity dark navy
		glass_outer.border_color = Color("1a3d5266")        # thin muted-cyan border
		glass_outer.border_width_left = 1
		glass_outer.shadow_color = Color("01050a90")
		glass_outer.shadow_size = 12
		glass_outer.shadow_offset = Vector2(-6, 0)
		glass_outer.content_margin_left = 12
		glass_outer.content_margin_right = 10
		glass_outer.content_margin_top = 8
		glass_outer.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", glass_outer)
	else:
		panel.add_theme_stylebox_override("panel", _daily_glass(Color("91b5cf"),false) if name_value == "missions" else ui._style(ui.INK))
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_theme_constant_override("separation", 12)
	if profile:
		# Thin top inner-highlight strip — glass edge impression, zero cost
		var top_line := ColorRect.new()
		top_line.custom_minimum_size = Vector2(0, 1)
		top_line.color = Color(0.165, 0.376, 0.502, 0.35)
		top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(top_line)
	var header := HBoxContainer.new()
	column.add_child(header)
	ui._label(header, tr(title), 36 if name_value == "missions" else 28, ui.ACCENT).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui._button(header, tr("HOME"), func() -> void: ui.home_requested.emit())
	var scroll := RushTouchScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	var status := ui._label(column, "", 16, Color("ffd360"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_labels[name_value] = status
	return content


func _build_missions() -> void:
	var content := _menu("missions","MISSIONS")
	ui._label(content,tr("DAILY  /  THREE CHALLENGES"),22,ui.ACCENT)
	ui._label(content,tr("New challenges each local calendar day. Claim completed rewards here."),16,ui.MUTED)
	for i: int in 3:
		var row := _task_row(content)
		row.button.pressed.connect(func() -> void: _claim_slot(i))
		mission_rows.append(row)
	ui._label(content,tr("CAREER  /  ONE-TIME ACHIEVEMENTS"),22,ui.ACCENT)
	for item: Dictionary in RushProgressionData.achievements:
		var row := _task_row(content)
		row["id"] = item.id
		row.title.add_theme_color_override("font_color",Color("dec99d"))
		row.button.pressed.connect(func() -> void:
			if RewardService.claim_achievement(item.id):
				status_labels.missions.text = tr("Reward saved.")
			present_notices())
		achievement_rows.append(row)

func _task_row(parent: Node) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_mission_surface(Color("728da5")))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = preload("res://Assets/UI/nav_garage.svg")
	icon.custom_minimum_size = Vector2(48,48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",3)
	row.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := ui._label(top,"",23)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reward := ui._label(top,"",20,Color("f3d693"))
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var detail := ui._label(column,"",17,Color("bad1df"))
	var progress := ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 8
	var track := StyleBoxFlat.new()
	track.bg_color = Color("07121f")
	track.border_color = Color("698296")
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("60dfef")
	fill.set_corner_radius_all(4)
	progress.add_theme_stylebox_override("background",track)
	progress.add_theme_stylebox_override("fill",fill)
	column.add_child(progress)
	var button := ui._button(row,"",func() -> void: pass)
	button.custom_minimum_size = Vector2(172,58)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size",19)
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,_mission_surface(Color("586575") if state == "disabled" else Color("81efff")))
	button.add_theme_color_override("font_disabled_color",Color("95a4b2"))
	return {"title":title,"detail":detail,"button":button,"progress":progress,"reward":reward,"icon":icon}

func _mission_surface(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("09192deb")
	style.border_color = border
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.shadow_color = Color(0.05,0.6,0.8,0.14)
	style.shadow_size = 3
	return style

func _build_daily() -> void:
	var page: Control = ui._page("daily")
	page.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.01,0.025,0.045,0.42)
	page.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var canvas := Control.new()
	canvas.size = Vector2(1400,620)
	page.add_child(canvas)
	var frame := Panel.new()
	canvas.add_child(frame)
	frame.size = Vector2(1400,590)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel",_daily_glass(Color("86eaff"),false))
	_daily_text(canvas,tr("DAILY REWARD"),Rect2(28,18,1140,62),48,Color("88fff4"))
	_daily_text(canvas,tr("A LITTLE FUEL FOR YOUR NEXT DRIVE"),Rect2(30,83,1190,40),28,Color("9beafa"))
	_daily_text(canvas,tr("One claim per local date. Missed days keep your place. After Day 7, the cycle repeats."),Rect2(30,124,1240,30),20,Color("a6ccdc"))
	var home: Button = ui._button(canvas,"⌂\nHOME",func() -> void: ui.home_requested.emit())
	home.position = Vector2(1242,12)
	home.size = Vector2(142,112)
	home.add_theme_font_size_override("font_size",27)
	for state: String in ["normal","hover","pressed","focus"]:
		home.add_theme_stylebox_override(state,_daily_glass(Color("8ee9fa"),state != "normal"))
	var grid := GridContainer.new()
	canvas.add_child(grid)
	grid.position = Vector2(30,169)
	grid.size = Vector2(1340,332)
	grid.columns = 4
	grid.add_theme_constant_override("h_separation",14)
	grid.add_theme_constant_override("v_separation",14)
	for i: int in 7:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(324,159)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(panel)
		var body := Control.new()
		body.custom_minimum_size = Vector2(304,139)
		panel.add_child(body)
		var gold: bool = i == 6
		var accent: Color = Color("ffdc76") if gold else Color("a6d9eb")
		_daily_text(body,tr("DAY"),Rect2(4,3,60,26),21,accent)
		_daily_text(body,str(i+1),Rect2(61,-8,65,71),57,accent)
		var art := TextureRect.new()
		art.texture = preload("res://Assets/UI/daily_coin_stack.svg")
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.position = Vector2(183,24)
		art.size = Vector2(121,108)
		art.modulate = Color("ffe093") if gold else Color.WHITE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(art)
		_daily_text(body,tr("%d COINS")%int(RushProgressionData.spec.daily_rewards[i]),Rect2(4,76,200,36),26,Color("ffe28d") if gold else Color("e4f7ff"))
		var status: Label = _daily_text(body,"",Rect2(4,111,205,29),20,accent)
		daily_cards.append({"panel":panel,"status":status})
	daily_claim = ui._button(canvas,tr("CLAIM"),func() -> void:
		if RewardService.claim_daily_reward():
			status_labels.daily.text = tr("Daily reward saved. Enjoy the drive!")
			ui.pulse_control(daily_claim,Color("efd4a0"))
		present_notices(),true)

	daily_claim.position = Vector2(30,519)
	daily_claim.size = Vector2(1340,52)
	daily_claim.add_theme_font_size_override("font_size",25)
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		daily_claim.add_theme_stylebox_override(state,_daily_glass(Color("87dfef"),state == "hover"))
	daily_claim.add_theme_color_override("font_disabled_color",Color("b0dbe6"))
	var footer: Label = _daily_text(canvas,"",Rect2(30,592,1340,28),18,Color("b4d3df"))
	status_labels["daily"] = footer
	page.resized.connect(_fit_daily.bind(page,canvas))
	_fit_daily(page,canvas)

func _fit_daily(page: Control, canvas: Control) -> void:
	var factor: float = maxf(0.1,minf((page.size.x-24.0)/1400.0,(page.size.y-16.0)/620.0))
	canvas.scale = Vector2.ONE*factor
	canvas.position = (page.size-canvas.size*factor)*0.5

func _daily_text(parent: Control, value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label: Label = ui._label(parent,value,font_size,color)
	label.position = rect.position
	label.size = rect.size
	label.add_theme_color_override("font_outline_color",Color("10232c"))
	label.add_theme_constant_override("outline_size",2)
	return label

func _daily_glass(accent: Color, active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12,0.21,0.27,0.88) if active else Color(0.08,0.15,0.20,0.83)
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(10)
	style.shadow_color = Color(accent.r,accent.g,accent.b,0.25 if active else 0.12)
	style.shadow_size = 8 if active else 4
	return style

func _build_profile() -> void:
	var page: Control = ui._page("profile",true)
	(page.get_child(0) as ColorRect).color = Color("15232eff")
	var panel: PanelContainer = PanelContainer.new()
	page.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel",_profile_glass_panel(Color("182932"),Color("96bbc5"),18,20,10,Color("60d7ef25"),5))
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation",8)
	panel.add_child(outer)
	var header: HBoxContainer = HBoxContainer.new()
	outer.add_child(header)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size.x = 120
	header.add_child(spacer)
	var title: Label = ui._label(header,"Profile",32,Color("d4e8ef"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var home: Button = ui._button(header,"HOME",func() -> void: ui.home_requested.emit())
	home.custom_minimum_size = Vector2(120,44)
	_profile_dashboard_button(home)
	var scroll: RushTouchScroll = RushTouchScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",9)
	scroll.add_child(content)
	ui._label(content,"DRIVER IDENTITY & CAREER TELEMETRY",16,Color("c6dde6"))
	var hero: PanelContainer = PanelContainer.new()
	hero.add_theme_stylebox_override("panel",_profile_glass_panel(Color("344854"),Color("93aebc"),10,12,8))
	content.add_child(hero)
	var identity: HBoxContainer = HBoxContainer.new()
	identity.add_theme_constant_override("separation",14)
	hero.add_child(identity)
	var avatar: TextureRect = TextureRect.new()
	avatar.texture = preload("res://Assets/UI/player_avatar.svg")
	avatar.custom_minimum_size = Vector2(60,66)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity.add_child(avatar)
	var identity_info: VBoxContainer = VBoxContainer.new()
	identity_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(identity_info)
	var name_row: HBoxContainer = HBoxContainer.new()
	identity_info.add_child(name_row)
	driver_name_label = ui._label(name_row,String(SaveService.progression.get("name","RACER")).to_upper(),24,Color("edf4f7"))
	driver_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	driver_name_label.clip_text = true
	name_edit = LineEdit.new()
	name_edit.max_length = 20
	name_edit.placeholder_text = tr("CALLSIGN / NAME")
	name_edit.text = String(SaveService.progression.get("name","RACER"))
	name_edit.custom_minimum_size = Vector2(230,38)
	name_edit.add_theme_font_size_override("font_size",18)
	name_row.add_child(name_edit)
	var save: Button = ui._button(name_row,"SAVE",func() -> void:
		if RewardService.set_player_name(name_edit.text):
			status_labels.profile.text = tr("Name saved.")
			driver_name_label.text = name_edit.text.to_upper())
	save.custom_minimum_size = Vector2(105,38)
	_profile_dashboard_button(save)
	profile_badge = RushLevelBadge.new()
	identity_info.add_child(profile_badge)
	profile_badge.build(ui)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation",14)
	content.add_child(columns)
	var left: VBoxContainer = VBoxContainer.new()
	var right: VBoxContainer = VBoxContainer.new()
	for col: VBoxContainer in [left,right]:
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_stretch_ratio = 1.0
		col.add_theme_constant_override("separation",8)
		columns.add_child(col)
	var highlights: GridContainer = _profile_category_card(left,"CAREER HIGHLIGHTS",preload("res://Assets/UI/nav_missions.svg"))
	_profile_telemetry_item(highlights,"Best score","best_score")
	_profile_telemetry_item(highlights,"Highest speed","highest_speed")
	_profile_telemetry_item(highlights,"Forward distance","distance")
	_profile_telemetry_item(highlights,"Driving time","play_time")
	var race: GridContainer = _profile_category_card(left,"RACE ACTIVITY",preload("res://Assets/UI/nav_missions.svg"))
	race.columns = 3
	_profile_telemetry_item(race,"Runs started","started")
	_profile_telemetry_item(race,"Runs completed","completed")
	_profile_telemetry_item(race,"Cumulative score","cumulative_score")
	var driving: GridContainer = _profile_category_card(left,"DRIVING",preload("res://Assets/UI/power_turbo.svg"))
	_profile_telemetry_item(driving,"Near misses","near_misses")
	_profile_telemetry_item(driving,"Best combo","best_combo")
	_profile_telemetry_item(driving,"Turbo activations","turbo_activations")
	_profile_telemetry_item(driving,"Traffic / barrier impacts","collisions")
	var gold: Color = Color("e1cca0")
	var economy: GridContainer = _profile_category_card(right,"ECONOMY",preload("res://Assets/UI/icon_coin.svg"),gold)
	_profile_telemetry_item(economy,"Wallet","wallet",gold)
	_profile_telemetry_item(economy,"Lifetime coins earned","lifetime_coins",gold)
	_profile_telemetry_item(economy,"Road coins picked up","pickups",gold)
	_profile_telemetry_item(economy,"Road coin value collected","road_coins",gold)
	var collection: GridContainer = _profile_category_card(right,"COLLECTION",preload("res://Assets/UI/nav_garage.svg"),gold)
	_profile_telemetry_item(collection,"Selected car","selected",gold)
	_profile_telemetry_item(collection,"Cars owned","cars_owned",gold)
	_profile_telemetry_item(collection,"Cars purchased","cars_purchased",gold)
	_profile_telemetry_item(collection,"Upgrades purchased","upgrades_purchased",gold)
	account_content = VBoxContainer.new()
	right.add_child(account_content)
	profile_interaction = Control.new()
	profile_interaction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	profile_interaction.visible = false
	page.add_child(profile_interaction)
	var status: Label = ui._label(outer,"",16,Color("ffd360"))
	status_labels.profile = status

func _profile_dashboard_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size",20)
	button.add_theme_stylebox_override("normal",_profile_glass_panel(Color("3a4e59"),Color("99bbc7"),9,12,5))
	button.add_theme_stylebox_override("hover",_profile_glass_panel(Color("476977"),Color("c2ebf5"),9,12,5))
	button.add_theme_stylebox_override("pressed",_profile_glass_panel(Color("213743"),Color("8db6c4"),9,12,5))

func _profile_glass_panel(bg: Color, border: Color, radius: int = 8, pad_h: int = 12, pad_v: int = 8, shadow_color: Color = Color("00000000"), shadow_size: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = pad_h
	style.content_margin_right = pad_h
	style.content_margin_top = pad_v
	style.content_margin_bottom = pad_v
	if shadow_size > 0:
		style.shadow_color = shadow_color
		style.shadow_size = shadow_size
	return style

func _profile_highlight_card(grid: Node, title_text: String, key: String) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Highlight cards: mid-elevation glass — slightly lighter tint, top border accent
	card.add_theme_stylebox_override("panel", _profile_glass_panel(
		Color("0e2034c8"), Color("1a4260"), 8, 12, 10, Color("0d1f30a0"), 4))
	grid.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var header_row := HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header_row)

	var title := ui._label(header_row, title_text.to_upper(), 11, Color("7e9caf"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var dot := ui._label(header_row, "◈", 10, ui.ACCENT)

	var value_label := ui._label(box, "—", 24, Color("ffffff"))
	value_label.clip_text = true
	profile_values[key] = value_label

func _profile_category_card(parent: Node, title_text: String, icon_res: Texture2D = null, accent_color: Color = Color("65ffed")) -> GridContainer:
	var section := PanelContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Category card: structural glass layer — darker, minimal border
	section.add_theme_stylebox_override("panel", _profile_glass_panel(
		Color("263741f5"), Color("75939fa0"), 8, 12, 8))
	parent.add_child(section)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	section.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(header)

	if icon_res != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_res
		icon_rect.custom_minimum_size = Vector2(16, 16)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(icon_rect)
	else:
		var pip := ui._label(header, "◈", 11, accent_color)

	var lbl := ui._label(header, title_text, 17, accent_color)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	return grid

func _profile_telemetry_item(parent: Node, title_text: String, key: String, val_color: Color = Color("eef6fa")) -> void:
	var item := PanelContainer.new()
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Telemetry items: most minimal — near-invisible technical surface
	item.add_theme_stylebox_override("panel", _profile_glass_panel(
		Color("111d25c0"), Color("69818b70"), 5, 8, 5))
	parent.add_child(item)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	item.add_child(box)

	var desc := ui._label(box, title_text.to_upper(), 13, Color("bfd0d9"))
	desc.clip_text = true

	var val := ui._label(box, "—", 20, val_color)
	val.clip_text = true
	profile_values[key] = val

func open(page: String) -> void:
	RewardService.refresh_date()
	ui.show_screen(page)
	refresh_current()
	present_notices()

func refresh_home() -> void:
	ui._refresh_profile_entry()
	var count := RewardService.claimable_count()
	ui.missions_button.text = tr("MISSIONS")+("  • %d"%count if count>0 else "")
	ui.daily_button.text = tr("DAILY REWARD")+("  •" if RewardService.daily_available() else "")

func _changed() -> void:
	if ui.screen in ["home","missions","profile","daily","results","garage"]:
		refresh_home()
		refresh_current()

func refresh_current() -> void:
	var p: Dictionary = SaveService.progression
	match ui.screen:
		"missions":
			for i: int in 3:
				var task: Dictionary = p.daily.tasks[i]
				var row: Dictionary = mission_rows[i]
				row.id = task.id
				row.date = p.daily.date
				_update_task(row,task,float(task.progress),bool(task.claimed))
			for i: int in achievement_rows.size():
				var item: Dictionary = RushProgressionData.achievements[i]
				_update_task(achievement_rows[i],item,RushProgressionData.achievement_value(p,item),item.id in p.achievement_claims)
		"daily":
			var available := RewardService.daily_available()
			var day := int(p.reward_day)
			var current := day%7+1 if available else day
			for i: int in 7:
				var card: Dictionary = daily_cards[i]
				var claimed := i+1<=day and not (available and day==7)
				card.panel.add_theme_stylebox_override("panel",_daily_glass(Color("ffda78") if i==6 else Color("82cedf"),i+1==current))
				card.status.text = "✓ " + tr("CLAIMED") if claimed else (tr("READY") if i+1==current and available else tr("UPCOMING"))
			daily_claim.disabled = not available
			daily_claim.text = tr("CLAIM DAY %d")%current if available else tr("CLAIMED  /  RETURN ON A NEW DAY")
		"profile":
			profile_badge.refresh()
			name_edit.text = p.name
			if driver_name_label != null:
				driver_name_label.text = String(p.get("name", "RACER")).to_upper()
			for key: String in profile_values:
				var value := str(int(p.stats.get(key,0)))
				match key:
					"wallet": value = tr("%d COINS")%SaveService.balance()
					"selected": value = RushVehicleCatalog.definition(SaveService.collection.selected).name
					"distance": value = "%.2f KM"%(float(p.stats.distance)/1000.0)
					"play_time": value = "%.1f MIN"%(float(p.stats.play_time)/60.0)
					"highest_speed": value = "%.0f KM/H"%float(p.stats.highest_speed)
					"cars_owned": value += " / 6"
					"best_combo": value = "x"+value
				profile_values[key].text = value

func _update_task(row: Dictionary, item: Dictionary, progress: float, claimed: bool) -> void:
	row.title.text = tr(item.title)
	row.progress.value = 100.0*clampf(progress/maxf(float(item.target),1.0),0,1)
	row.detail.text = tr("%d / %d")%[int(progress),int(item.target)]
	row.reward.text = tr("%d COINS")%int(item.coins)+"  •  "+tr("%d XP")%int(item.xp)
	var icon_path: String = "res://Assets/UI/nav_garage.svg"
	match String(item.event):
		"turbo_activations", "highest_speed", "best_combo": icon_path = "res://Assets/UI/power_turbo.svg"
		"pickups", "lifetime_coins": icon_path = "res://Assets/UI/icon_coin.svg"
	row.icon.texture = load(icon_path) as Texture2D
	row.button.disabled = claimed or progress<float(item.target)
	row.button.text = tr("CLAIMED") if claimed else (tr("CLAIM") if progress>=float(item.target) else tr("IN PROGRESS"))

func _build_notice() -> void:
	notice = PanelContainer.new()
	ui.safe.add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	notice.offset_left = -280
	notice.offset_right = 280
	notice.offset_top = -135
	notice.offset_bottom = 135
	notice.add_theme_stylebox_override("panel",ui._style(Color("103946"),ui.ACCENT))
	var box := VBoxContainer.new()
	notice.add_child(box)
	notice_title = ui._label(box,"",30,ui.ACCENT)
	notice_body = ui._label(box,"",21)
	notice_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui._button(box,tr("CONTINUE"),dismiss_notice,true)
	notice.visible = false

func present_notices() -> void:
	if presenting or ui.screen not in ["home","results","missions","profile","daily","garage"]:
		return
	var data := RewardService.take_notices()
	if data.is_empty():
		return
	presenting = true
	var level: Dictionary = data.level
	var achievements: Array = data.achievements
	notice_title.text = tr("LEVEL UP") if not level.is_empty() else tr("ACHIEVEMENT COMPLETE")
	notice_body.text = tr("LEVEL %d → %d\n+%d COINS")%[level.old,level.new,level.coins] if not level.is_empty() else ""
	if not achievements.is_empty():
		notice_body.text += "\n"+tr(achievements[0])+(tr("  + %d more")%(achievements.size()-1) if achievements.size()>1 else "")+"\n"+tr("Claim career rewards in Missions.")
	notice.visible = true
	notice.modulate.a = 0.0
	notice_tween = create_tween()
	notice_tween.tween_property(notice,"modulate:a",1.0,0.25)
	GameAudio.event("level_up" if not level.is_empty() else "achievement")
	RushHaptics.pulse(30)

func dismiss_notice() -> void:
	if notice_tween!=null and notice_tween.is_valid():
		notice_tween.kill()
	notice.visible = false
	presenting = false

func _save_failed(message: String) -> void:
	if status_labels.has(ui.screen):
		status_labels[ui.screen].text = message

func _claim_slot(slot: int) -> void:
	var row: Dictionary = mission_rows[slot]
	if RewardService.claim_mission(row.id,row.date):
		status_labels.missions.text = tr("Mission reward saved.")
	present_notices()
