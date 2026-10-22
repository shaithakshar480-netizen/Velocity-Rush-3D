class_name RushStoreUI
extends Node

signal closed

var ads: RushRewardedAdService
var ui: AutomotiveUI
var purchases: RushPurchaseService = RushPurchaseService.new()
var membership: RushMembershipService = RushMembershipService.new()
var balance: Label
var status: Label
var contents: VBoxContainer
var grid: GridContainer
var scroll: ScrollContainer
var selected_tab: String = "COINS"
var last_buy_ms: int = -1000
var last_success: String = ""
var claim: Button
var membership_claim: Button
var tabs: Dictionary = {}
var rebuilding: bool = false
var tab_tween: Tween
var art_cache: Dictionary = {}
var loading: Label
var clock: float = 0.0
var header_panel: PanelContainer
var tab_bar: HBoxContainer
var notice_label: Label

func build(owner_ui: AutomotiveUI) -> void:
	ui = owner_ui
	RushStoreCatalog.prepare()
	var page: Control = ui._page("store", false)
	page.visible = false

	# 1. Full-viewport base dark graphite scrim to guarantee zero floor light leaks
	var base_scrim: ColorRect = ColorRect.new()
	base_scrim.color = Color("050c15c8") # ~78% dark graphite/navy floor
	base_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	base_scrim.offset_left = -100.0
	base_scrim.offset_right = 100.0
	base_scrim.offset_top = -100.0
	base_scrim.offset_bottom = 100.0
	base_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(base_scrim)

	# 2. Controlled vertical vignette gradient: deep navy top -> dark glass mid -> deep dark graphite bottom
	var backdrop: TextureRect = TextureRect.new()
	var gradient: Gradient = Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color("07121df6")) # Top: 96% deep dark navy for razor-sharp header contrast
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color("040a12fa")) # Bottom: 98% deep dark graphite blocking bright floor wash
	gradient.add_point(0.48, Color("081522c0")) # Middle: 75% dark navy glass allowing subtle showroom silhouette
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 256
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	backdrop.texture = texture
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.offset_left = -100.0
	backdrop.offset_right = 100.0
	backdrop.offset_top = -100.0
	backdrop.offset_bottom = 100.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(backdrop)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(layout)

	# 1. Compact floating header
	header_panel = PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _panel_style(Color("081420b8"), Color("1a3a52"), 12, 6))
	layout.add_child(header_panel)

	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	header_panel.add_child(top)

	var back_btn: Button = _cta(top, "‹ BACK", func() -> void: closed.emit(), false)
	back_btn.custom_minimum_size = Vector2(88, 36)

	var divider: ColorRect = ColorRect.new()
	divider.color = Color("1c3e56")
	divider.custom_minimum_size = Vector2(1, 26)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(divider)

	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 1)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)

	var title: Label = ui._label(title_box, "VELOCITY MARKET", 19, Color("eef8fc"))
	title.add_theme_color_override("font_shadow_color", Color("03090e"))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)

	var subtitle: Label = ui._label(title_box, "PERFORMANCE SUPPLY & RACER SERVICES", 10, Color("6cb9d8"))
	subtitle.add_theme_color_override("font_shadow_color", Color("03090e"))

	loading = ui._label(top, "", 13, ui.ACCENT)
	loading.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Live Wallet capsule
	var wallet_pill: PanelContainer = PanelContainer.new()
	wallet_pill.add_theme_stylebox_override("panel", _panel_style(Color("091a29d8"), Color("254f6e"), 16, 4))
	wallet_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(wallet_pill)

	var wallet_row: HBoxContainer = HBoxContainer.new()
	wallet_row.add_theme_constant_override("separation", 6)
	wallet_pill.add_child(wallet_row)

	_art(wallet_row, "res://Assets/UI/icon_coin.svg", 18)
	balance = ui._label(wallet_row, "", 16, Color("ffe49a"))

	# 2. Thin premium category rail
	tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 8)
	layout.add_child(tab_bar)

	for tab: String in ["COINS", "BOOSTS", "MEMBERSHIP"]:
		var button: Button = _cta(tab_bar, tab, _tab.bind(tab), false)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(110, 36)
		tabs[tab] = button

	# 3. Touch scroll container
	scroll = RushTouchScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)

	contents = VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 10)
	scroll.add_child(contents)
	scroll.resized.connect(_columns)

	# 4. Compact contextual notification strip
	status = ui._label(layout, "", 13, ui.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Retry action buttons (compact, warning-accented, only visible when needed)
	claim = _cta(layout, "RETRY DELIVERY", purchases.retry_delivery, false)
	claim.visible = false
	membership_claim = _cta(layout, "RETRY MEMBERSHIP DELIVERY", membership.retry_delivery, false)
	membership_claim.visible = false

	purchases.status_changed.connect(_status)
	membership.status_changed.connect(_status)
	SaveService.wallet_changed.connect(func(_value: int) -> void: refresh())
	SaveService.turbo_inventory_changed.connect(refresh)

func open() -> void:
	status.text = ""
	membership.provider = purchases.provider
	refresh()
	ui.show_screen("store")
	purchases.restore_purchases()
	membership.restore_purchases()
	_animate_entrance()

func _tab(tab: String) -> void:
	selected_tab = tab
	status.text = ""
	scroll.scroll_vertical = 0
	refresh()
	if tab_tween != null and tab_tween.is_valid():
		tab_tween.kill()
	contents.modulate.a = 0.2
	contents.position.y = 8.0
	tab_tween = create_tween().set_parallel(true)
	tab_tween.tween_property(contents, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tab_tween.tween_property(contents, "position:y", 0.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _status(message: String) -> void:
	status.text = message
	refresh()

func refresh() -> void:
	if contents == null or rebuilding:
		return
	rebuilding = true
	call_deferred("_rebuild")

func _rebuild() -> void:
	rebuilding = false
	balance.text = "%s COINS" % _number(SaveService.balance())
	claim.visible = not purchases.retry_receipt.is_empty()
	membership_claim.visible = not membership.retry_receipt.is_empty()
	if claim.visible:
		claim.add_theme_stylebox_override("normal", _panel_style(Color("2d2107"), Color("d49822"), 10, 8))
	if membership_claim.visible:
		membership_claim.add_theme_stylebox_override("normal", _panel_style(Color("2d2107"), Color("d49822"), 10, 8))

	for tab: String in tabs:
		var is_sel: bool = (tab == selected_tab)
		tabs[tab].add_theme_stylebox_override("normal", _tab_style(is_sel, false))
		tabs[tab].add_theme_stylebox_override("hover", _tab_style(is_sel, true))
		tabs[tab].add_theme_stylebox_override("focus", _tab_style(is_sel, true))
		tabs[tab].add_theme_stylebox_override("pressed", _tab_style(true, false))
		tabs[tab].add_theme_color_override("font_color", Color.WHITE if is_sel else Color("8ca5b7"))

	for child: Node in contents.get_children():
		contents.remove_child(child)
		child.queue_free()

	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	contents.add_child(grid)
	_columns()

	match selected_tab:
		"COINS":
			for offer: Dictionary in RushStoreCatalog.data.coin_packs:
				_coin_card(offer)
			if not purchases.available():
				_notice("Purchases unavailable right now. ₹ prices are reference prices; final prices come from your store.")
		"BOOSTS":
			for offer: Dictionary in RushStoreCatalog.data.boosts:
				_boost_card(offer)
		"MEMBERSHIP":
			for plan: String in ["weekly", "monthly"]:
				_membership_card(plan)

	last_success = ""

func _columns() -> void:
	if grid == null or scroll == null:
		return
	var width: float = maxf(260.0, scroll.size.x - 16.0)
	if selected_tab == "COINS":
		grid.columns = clampi(int((width+14.0) / 274.0), 1, 4)
	elif selected_tab == "BOOSTS":
		grid.columns = clampi(int((width+14.0) / 294.0), 1, 4)
	else:
		grid.columns = clampi(int((width+14.0) / 374.0), 1, 2)

func _panel_style(fill: Color, border: Color, radius: int = 12, margin: int = 10) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color("00000040")
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

func _tab_style(active: bool, hovered: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	if active:
		style.bg_color = Color("11374edc")
		style.border_color = Color("4edaf0")
		style.border_width_bottom = 2
		style.border_width_top = 1
		style.border_width_left = 1
		style.border_width_right = 1
		style.shadow_color = Color("4edaf030")
		style.shadow_size = 5
	elif hovered:
		style.bg_color = Color("0d243690")
		style.border_color = Color("2e597c")
		style.set_border_width_all(1)
	else:
		style.bg_color = Color("08142070")
		style.border_color = Color("162c3d")
		style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _style(primary: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = ui._style(Color("13364c") if primary else Color("0d1e2e"), Color("53d5ea") if primary else Color("2a475f"))
	style.set_corner_radius_all(12)
	style.shadow_size = 4
	return style

func _cta(parent: Node, text: String, callback: Callable, primary: bool) -> Button:
	var button: RushStoreProductCard = RushStoreProductCard.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("e2f8ff"))
	button.add_theme_stylebox_override("normal", _style(primary))
	button.add_theme_stylebox_override("hover", _style(true))
	button.add_theme_stylebox_override("focus", _style(true))
	button.add_theme_stylebox_override("pressed", _style(true))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("0b1620"), Color("182c3b"), 12, 8))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _panel() -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = 280 if selected_tab != "MEMBERSHIP" else 350
	panel.add_theme_stylebox_override("panel", _panel_style(Color("0c1c2be8"), Color("32708b"), 18, 16))
	grid.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	return column

func _art(parent: Node, path: String, height: float) -> void:
	if not art_cache.has(path):
		art_cache[path] = load(path)
	var picture: TextureRect = TextureRect.new()
	picture.texture = art_cache[path]
	picture.custom_minimum_size.y = height
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)

func _badge(parent: Node, text: String, gold: bool = false) -> void:
	var badge_box: PanelContainer = PanelContainer.new()
	var fill: Color = Color("382c0ecc") if gold else (Color("0a3547cc") if not text.is_empty() else Color.TRANSPARENT)
	var border: Color = Color("eec044") if gold else (Color("38cbe0") if not text.is_empty() else Color.TRANSPARENT)
	badge_box.add_theme_stylebox_override("panel", _panel_style(fill, border, 8, 4))
	badge_box.custom_minimum_size.y = 22
	parent.add_child(badge_box)

	if not text.is_empty():
		var label: Label = ui._label(badge_box, text, 11, Color("ffe49a") if gold else Color("68e1f2"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if text in ["POPULAR", "BEST VALUE", "HIGH VALUE"]:
			var pulse: Tween = label.create_tween().set_loops()
			pulse.tween_property(label, "modulate", Color(0.82, 0.94, 1.0), 1.2)
			pulse.tween_property(label, "modulate", Color.WHITE, 1.2)

func _coin_card(offer: Dictionary) -> void:
	var visual: Dictionary = RushStoreCatalog.presentation.coins[String(offer.id)]
	var is_best: bool = (String(visual.badge) == "BEST VALUE")
	var is_popular: bool = (String(visual.badge) == "POPULAR")
	var is_high: bool = (String(visual.badge) == "HIGH VALUE")

	var card: RushStoreProductCard = RushStoreProductCard.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(250, 336)

	var norm_style: StyleBoxFlat = _panel_style(
		Color("141107d8") if is_best else Color("091826cf"),
		Color("614b18") if is_best else (Color("204764") if is_popular else Color("1b3d56")),
		14, 10
	)
	var hover_style: StyleBoxFlat = _panel_style(
		Color("1e180bd8") if is_best else Color("112c3fd8"),
		Color("f0c248") if is_best else Color("47d5eb"),
		14, 10
	)
	card.add_theme_stylebox_override("normal", norm_style)
	card.add_theme_stylebox_override("disabled", _panel_style(Color("081119"), Color("162633"), 14, 10))
	card.add_theme_stylebox_override("hover", hover_style)
	card.add_theme_stylebox_override("focus", hover_style)
	card.add_theme_stylebox_override("pressed", hover_style)
	card.pressed.connect(_coin.bind(String(offer.id)))
	grid.add_child(card)

	var column: VBoxContainer = VBoxContainer.new()
	card.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 12
	column.offset_right = -12
	column.offset_top = 10
	column.offset_bottom = -10
	column.add_theme_constant_override("separation", 5)

	_badge(column, String(visual.badge), is_best)
	_art(column, String(visual.art), 112)

	var amount: Label = ui._label(column, _number(int(offer.total)), 32)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var sub_label: Label = ui._label(column, "COINS", 14, ui.MUTED)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if int(offer.bonus) > 0:
		var bonus_label: Label = ui._label(column, "+%s BONUS" % _number(int(offer.bonus)), 15, Color("ffe49a"))
		bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var split: Label = ui._label(column, "(%s + %s)" % [_number(int(offer.base)), _number(int(offer.bonus))], 10, Color("7a92a3"))
		split.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		var standard: Label = ui._label(column, "STANDARD PACK", 11, Color("6b8292"))
		standard.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var spacer_sub: Control = Control.new()
		spacer_sub.custom_minimum_size.y = 12
		column.add_child(spacer_sub)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var localized: String = purchases.price(String(offer.id))
	var is_available: bool = not localized.is_empty()
	var price_panel: PanelContainer = PanelContainer.new()
	var price_fill: Color
	var price_border: Color
	var price_color: Color

	if not is_available:
		# Muted reference price styling when billing is unavailable
		price_fill = Color("091520cc")
		price_border = Color("1e384c")
		price_color = Color("8ea4b3")
	elif is_best:
		price_fill = Color("2c220c")
		price_border = Color("e2b339")
		price_color = Color("fff1c7")
	else:
		price_fill = Color("0e2d3e")
		price_border = Color("3cc2d6")
		price_color = Color("e0f9ff")

	price_panel.add_theme_stylebox_override("panel", _panel_style(price_fill, price_border, 10, 6))
	column.add_child(price_panel)

	var price_text: String = localized if is_available else ("₹%d" % int(offer.reference_price_inr))
	var price_lbl: Label = ui._label(price_panel, price_text, 22, price_color)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	card.disabled = not is_available or not purchases.pending.is_empty() or not purchases.retry_receipt.is_empty() or membership.pending
	_ignore_children(column)

func _ignore_children(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		if child is Control:
			_ignore_children(child)

func _boost_card(offer: Dictionary) -> void:
	var visual: Dictionary = RushStoreCatalog.presentation.boosts[String(offer.id)]
	var column: VBoxContainer = _panel()

	# Module Header Row: Title on Left, Inventory count on Right
	var head_row: VBoxContainer = VBoxContainer.new()
	head_row.add_theme_constant_override("separation", 6)
	column.add_child(head_row)

	var title_lbl: Label = ui._label(head_row, String(visual.title), 18)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var count: int = int(SaveService.consumables.get(String(offer.inventory), 0))
	var owned_pill: PanelContainer = PanelContainer.new()
	owned_pill.add_theme_stylebox_override("panel", _panel_style(Color("082433"), Color("246487"), 8, 4))
	head_row.add_child(owned_pill)

	var owned_lbl: Label = ui._label(owned_pill, "OWNED x%02d" % count, 14, Color("7fe9f8"))
	if last_success == String(offer.id):
		ui.pulse_control(owned_pill, ui.ACCENT)

	_art(column, String(visual.art), 106)

	var description: Label = ui._label(column, String(visual.description), 16, ui.MUTED)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	# Option A: Coin purchase
	var affordable: bool = SaveService.can_afford(int(offer.coins))
	var buy_btn: Button = _cta(column, "%s COINS  ➔  +%d" % [_number(int(offer.coins)), int(offer.quantity)], _boost.bind(String(offer.id)), affordable)
	buy_btn.custom_minimum_size.y = 48
	buy_btn.disabled = not affordable

	if not affordable:
		var note: Label = ui._label(column, "Insufficient coins", 14, Color("8094a3"))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		var pad: Control = Control.new()
		pad.custom_minimum_size.y = 12
		column.add_child(pad)

	# OR divider
	var or_row: HBoxContainer = HBoxContainer.new()
	or_row.add_theme_constant_override("separation", 6)
	column.add_child(or_row)

	var line_left: ColorRect = ColorRect.new()
	line_left.color = Color("183042")
	line_left.custom_minimum_size = Vector2(10, 1)
	line_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	or_row.add_child(line_left)

	var or_lbl: Label = ui._label(or_row, "OR", 9, Color("6b8496"))
	or_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var line_right: ColorRect = ColorRect.new()
	line_right.color = Color("183042")
	line_right.custom_minimum_size = Vector2(10, 1)
	line_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	or_row.add_child(line_right)

	# Option B: Rewarded Ad
	var reward_ready: bool = (ads != null and ads.pending != 0 and ads.earned)
	var reward_text: String = "★ CLAIM BOOST ★" if reward_ready else ("WATCH AD  ➔  +%s" % String(visual.reward_label).replace("+", ""))
	var reward_btn: Button = _cta(column, reward_text, _reward.bind(String(offer.id)), false)
	reward_btn.custom_minimum_size.y = 48
	reward_btn.disabled = (ads != null and ads.pending != 0 and not ads.earned)

	if reward_ready:
		reward_btn.add_theme_stylebox_override("normal", _panel_style(Color("19452b"), Color("40d685"), 10, 6))
		reward_btn.add_theme_color_override("font_color", Color("f0fff6"))
		ui.pulse_control(reward_btn, Color("40d685"))
	else:
		reward_btn.add_theme_stylebox_override("normal", _panel_style(Color("0c2921"), Color("229670"), 10, 6))
		reward_btn.add_theme_color_override("font_color", Color("c5fae6"))

	var ad_note: Label = ui._label(column, "Optional rewarded ad", 10, Color("6a8494"))
	ad_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _benefit(parent: Node, icon: String, text: String, preview: bool = false) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var image: TextureRect = TextureRect.new()
	image.texture = load(icon)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(24, 20)
	row.add_child(image)

	var label: Label = ui._label(row, text + (" • PREVIEW" if preview else ""), 13, Color("8ba0ad") if preview else Color("dcf4ff"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _membership_card(plan: String) -> void:
	var view: Dictionary = RushStoreCatalog.presentation.memberships[plan]
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/Memberships.json"))
	var bundle: Dictionary = config[plan]
	var is_monthly: bool = (plan == "monthly")

	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = 350
	var panel_fill: Color = Color("11171dd8") if is_monthly else Color("091826d8")
	var panel_border: Color = Color("70551c") if is_monthly else Color("1e415b")
	panel.add_theme_stylebox_override("panel", _panel_style(panel_fill, panel_border, 14, 14))
	grid.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	# Header row: Badge + Title + Duration
	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	column.add_child(top_row)

	var title_col: VBoxContainer = VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title_col)

	var head_label: Label = ui._label(title_col, String(view.title), 17, Color("ffe49a") if is_monthly else Color("ffffff"))
	var dur_label: Label = ui._label(title_col, String(view.duration), 11, ui.ACCENT)

	var badge_text: String = String(view.badge)
	if not badge_text.is_empty():
		var badge_pill: PanelContainer = PanelContainer.new()
		badge_pill.add_theme_stylebox_override("panel", _panel_style(
			Color("382c0ecc") if is_monthly else Color("0a3547cc"),
			Color("eec044") if is_monthly else Color("38cbe0"),
			8, 4
		))
		badge_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top_row.add_child(badge_pill)
		var b_lbl: Label = ui._label(badge_pill, badge_text, 10, Color("ffe49a") if is_monthly else Color("68e1f2"))

	_art(column, String(view.art), 52)

	var localized: String = membership.localized_price(String(view.provider_product_id))
	var price_str: String = localized if not localized.is_empty() else ("₹%d" % int(view.fallback_price_inr))
	var price_lbl: Label = ui._label(column, "%s / %s" % [price_str, String(view.price_period)], 20, Color("ffe49a"))
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# SECTION 1: INCLUDED NOW (Real Implemented Benefits)
	var incl_head: Label = ui._label(column, "INCLUDED NOW", 11, Color("5ce0f2"))
	incl_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var icons: Dictionary = RushStoreCatalog.presentation.benefit_icons
	_benefit(column, String(icons.coins), "%s initial coins" % _number(int(bundle.initial_coins)))
	for pair: Array in [["turbo", "Turbo Boosters"], ["magnets", "Coin Magnets"], ["repairs", "Repair Kits"]]:
		var art_id: String = {"turbo": "turbo", "magnets": "magnet", "repairs": "repair"}[String(pair[0])]
		_benefit(column, String(RushStoreCatalog.presentation.boosts[art_id].art), "%d %s" % [int(bundle[String(pair[0])]), String(pair[1])])

	# SECTION 2: COMING / PREVIEW
	var prev_divider: ColorRect = ColorRect.new()
	prev_divider.color = Color("183042")
	prev_divider.custom_minimum_size = Vector2(10, 1)
	column.add_child(prev_divider)

	var prev_head: Label = ui._label(column, "COMING / PREVIEW", 11, Color("8ca3b3"))
	prev_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var plan_ready: bool = membership.ready(String(view.provider_product_id))
	_benefit(column, String(icons.calendar), "%s daily coins" % _number(int(view.daily_coins)), true)
	_benefit(column, String(icons.bonus), "+%d%% race coins" % int(view.race_bonus_percent), true)
	_benefit(column, String(icons.car), "Rotating premium car access" if plan == "weekly" else "Premium-car collection access", true)
	_benefit(column, String(icons.paint), "Exclusive member paint", true)
	_benefit(column, String(icons.no_ads), "No forced interstitial ads", true)

	var reward_note: Label = ui._label(column, "Rewarded ads remain optional", 10, Color("6a8494"))

	var cta: Button = _cta(column, "GET " + plan.to_upper() + " PASS", _membership.bind(String(view.provider_product_id)), true)
	cta.custom_minimum_size.y = 40
	if is_monthly:
		cta.add_theme_stylebox_override("normal", _panel_style(Color("362709"), Color("e6b73b"), 10, 6))
		cta.add_theme_color_override("font_color", Color("fff2cf"))
	else:
		cta.add_theme_stylebox_override("normal", _panel_style(Color("0f3245"), Color("47d0e5"), 10, 6))
		cta.add_theme_color_override("font_color", Color("e0f9ff"))

	cta.disabled = not plan_ready or membership.pending or not membership.retry_receipt.is_empty() or not purchases.pending.is_empty()

	if not plan_ready:
		var note: Label = ui._label(column, "Google Play purchase setup is currently unavailable. Preview benefits are not active.", 10, Color("8ba0ad"))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _notice(text: String) -> void:
	var notice_box: PanelContainer = PanelContainer.new()
	notice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_box.custom_minimum_size.y = 34
	notice_box.add_theme_stylebox_override("panel", _panel_style(Color("081420d8"), Color("1b3c54"), 8, 8))
	contents.add_child(notice_box)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_box.add_child(row)

	var icon: Label = ui._label(row, "ℹ", 13, ui.ACCENT)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	notice_label = ui._label(row, text, 11, Color("b0c6d6"))
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _coin(id: String) -> void:
	if membership.pending or (ads != null and ads.pending != 0):
		return
	purchases.purchase(id)
	refresh()

func _membership(plan: String) -> void:
	if not purchases.pending.is_empty() or (ads != null and ads.pending != 0):
		return
	membership.request_plan(plan)

func _boost(id: String) -> void:
	var now: int = Time.get_ticks_msec()
	if now - last_buy_ms < 500:
		return
	last_buy_ms = now
	var success: bool = SaveService.buy_store_boost(id)
	status.text = "Added to your inventory." if success else "Purchase unavailable. Check your coins and inventory capacity."
	if success:
		last_success = id
		ui.pulse_control(status, ui.ACCENT)
	refresh()

static func _number(value: int) -> String:
	var digits: String = str(value)
	var result: String = ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return result

func bind_ads(service: RushRewardedAdService) -> void:
	ads = service
	ads.status_changed.connect(_status)

func _reward(id: String) -> void:
	if membership.pending or not purchases.pending.is_empty():
		status.text = "Finish your current purchase first."
		return
	if ads == null:
		status.text = "Rewarded ad unavailable right now."
		return
	if ads.pending != 0 and ads.earned:
		ads.retry_pending_reward()
	else:
		ads.request_offer(SaveService.settle_store_boost.bind(id),false,"STORE_"+id)
	refresh()

func _animate_entrance() -> void:
	if header_panel == null or tab_bar == null or contents == null:
		return
	header_panel.modulate.a = 0.0
	header_panel.position.y = -15.0
	tab_bar.modulate.a = 0.0
	contents.modulate.a = 0.0

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(header_panel, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(header_panel, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(tab_bar, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(contents, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if ui == null or ui.screen != "store":
		return
	clock += delta
	var pending: bool = not purchases.pending.is_empty() or membership.pending or (ads != null and ads.pending != 0 and not ads.earned)
	loading.text = ("PROCESSING" + ".".repeat(int(clock * 2.0) % 4)) if pending else ""
