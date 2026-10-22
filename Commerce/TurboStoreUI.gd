class_name RushTurboStoreUI
extends Node
signal closed
var ui: AutomotiveUI
var ads: RushRewardedAdService
var inventory: Label
var status: Label
var panel: Control

func build(owner_ui: AutomotiveUI, service: RushRewardedAdService) -> void:
	ui = owner_ui
	ads = service
	var page: Control = ui._page("turbo_store")
	page.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.015,0.035,0.055,0.48)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	page.add_child(shade)
	panel = Control.new()
	panel.size = Vector2(840,570)
	page.add_child(panel)
	_art("res://Assets/UI/turbo_supply_glass.svg",Rect2(0,0,840,570))
	_text("GET TURBO BOOSTERS",Rect2(30,30,780,52),36,Color("84efff"))
	_art("res://Assets/UI/turbo_supply_emblem.svg",Rect2(285,88,270,220))
	inventory = _text("",Rect2(40,303,760,40),28,Color("79ffc1"))
	_text("Watch 1 rewarded ad\nGet 2 Turbo Boosters",Rect2(40,348,760,65),24,Color("e4f6ff"))
	var reward: Button = ui._button(panel,"WATCH AD & REWARD  (+2 Boosters)",func() -> void:
		if ads.pending!=0 and ads.earned:
			ads.retry_pending_reward()
		else:
			ads.request_turbo_reward())
	reward.position = Vector2(108,426)
	reward.size = Vector2(624,62)
	reward.add_theme_font_size_override("font_size",24)
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("073f55") if state == "normal" else Color("12667d")
		style.border_color = Color("61e8ff")
		style.set_border_width_all(2)
		style.set_corner_radius_all(12)
		style.shadow_color = Color(0.08,0.8,1.0,0.22)
		style.shadow_size = 7
		reward.add_theme_stylebox_override(state,style)
	reward.add_theme_color_override("font_color",Color("d8fcff"))
	status = _text("",Rect2(55,491,730,28),16,ui.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cancel: Button = ui._button(panel,"CANCEL",func() -> void: closed.emit())
	cancel.position = Vector2(300,518)
	cancel.custom_minimum_size = Vector2(240,42)
	cancel.size = Vector2(240,42)
	cancel.add_theme_font_size_override("font_size",21)
	cancel.add_theme_color_override("font_color",Color("a6bfcb"))
	for state: String in ["normal","hover","pressed","focus"]:
		cancel.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	page.resized.connect(_fit.bind(page))
	_fit(page)
	ads.status_changed.connect(func(text: String) -> void: status.text = text)
	SaveService.turbo_inventory_changed.connect(refresh)
	SaveService.wallet_changed.connect(func(_value: int) -> void: refresh())
	refresh()

func _fit(page: Control) -> void:
	var factor: float = minf((page.size.x-32.0)/840.0,(page.size.y-24.0)/570.0)
	factor = maxf(0.1,minf(factor,1.2))
	panel.scale = Vector2.ONE*factor
	panel.position = (page.size-panel.size*factor)*0.5

func _text(value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label: Label = ui._label(panel,value,font_size,color)
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color",Color("03121d"))
	label.add_theme_constant_override("outline_size",3)
	return label

func _art(path: String, rect: Rect2) -> void:
	var art := TextureRect.new()
	art.texture = load(path) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = rect.position
	art.size = rect.size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)

func refresh() -> void:
	inventory.text = "TURBO  x%d"%int(SaveService.consumables.turbo_inventory)
