class_name RushAccountUI
extends Node
var game: Node
var status_label: Label
var google_button: Button
var guest_button: Button
var account_cards: Array[Dictionary] = []
var logout_dialog: ConfirmationDialog
var was_chosen: bool = false
func build(owner_game: Node) -> void:
	game = owner_game
	was_chosen = AuthService.chosen
	var page: Control = game.ui._page("account",false)
	var shade := ColorRect.new()
	shade.color = Color(0.015,0.035,0.065,0.30)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	page.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := TextureRect.new()
	frame.texture = preload("res://Assets/UI/account_frame.svg")
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := Control.new()
	page.add_child(inset)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.offset_top = 60
	inset.offset_bottom = -60
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column: VBoxContainer = game.ui._center_column(inset,520)
	column.add_theme_constant_override("separation",12)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation",8)
	column.add_child(brand)
	var title: Label = game.ui._label(brand,"VELOCITY",34,Color("e6eff5"))
	var title_accent: Label = game.ui._label(brand,"RUSH 3D",34,Color("63bddb"))
	for label: Label in [title,title_accent]:
		label.add_theme_color_override("font_shadow_color",Color("071421"))
		label.add_theme_constant_override("shadow_offset_y",2)
	game.ui._label(column,"YOUR NEXT DRIVE STARTS HERE",15,Color("acbfcc"))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_welcome_style(Color(0.32,0.40,0.48,0.77),Color("bbccd8"),22))
	column.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",14)
	panel.add_child(body)
	game.ui._label(body,"WELCOME, RACER",25,Color("d3eaf4"))
	var intro: Label = game.ui._label(body,"Connect your account to protect your progress.\nOr start driving offline as a Guest.",18,Color("d5e0e8"))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	google_button = game.ui._button(body,"Continue with Google",_google_pressed,true,true)
	guest_button = game.ui._button(body,"CONTINUE AS GUEST",AuthService.sign_in_as_guest)
	_welcome_button(google_button,true)
	_welcome_button(guest_button,false)
	_polish(google_button)
	_polish(guest_button)
	status_label = game.ui._label(body,"",16,game.ui.ACCENT)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var privacy: Label = game.ui._label(column,"Your local progress stays on this device.\nCloud backup uses your signed-in account; credentials are never part of your game save.",15,Color("b3c4d1"))
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.resized.connect(_fit_welcome.bind(page,inset,column,title,title_accent))
	_fit_welcome.call_deferred(page,inset,column,title,title_accent)
	_build_card(game.progression_ui.account_content)
	_add_settings_card(game.ui.screens.settings)
	logout_dialog = ConfirmationDialog.new()
	logout_dialog.title = "Sign out?"
	logout_dialog.dialog_text = "Your local progress will be kept. You will return to the welcome screen."
	logout_dialog.ok_button_text = "SIGN OUT"
	logout_dialog.confirmed.connect(AuthService.sign_out)
	add_child(logout_dialog)
	AuthService.changed.connect(_auth_changed)
	CloudSaveService.changed.connect(refresh)
	AuthService.completed.connect(func() -> void:
		if AuthService.chosen and game.ui.screen=="account": game.go_home())
	AuthService.can_change_account = func() -> bool:
		return game.ready_for_drive and game.ui.screen in ["home","profile","account","settings"] and game.director.ads.pending==0 and game.shop.purchases.pending.is_empty() and not game.shop.purchases.settling and game.shop.purchases.retry_receipt.is_empty() and not game.shop.membership.pending and game.shop.membership.retry_receipt.is_empty() and (game.run.state!=RushRunManager.RunState.FINISHED or game.run.reward_saved)
	CloudSaveService.can_restore = func() -> bool:
		return game.ready_for_drive and game.ui.screen in ["home","profile","account"] and game.director.ads.pending==0 and game.shop.purchases.pending.is_empty() and not game.shop.purchases.settling and game.shop.purchases.retry_receipt.is_empty() and not game.shop.membership.pending and game.shop.membership.retry_receipt.is_empty() and (game.run.state!=RushRunManager.RunState.FINISHED or game.run.reward_saved)
	SaveService.cloud_restored.connect(func() -> void:
		game._apply_selected()
		game.progression_ui.refresh_home())
	refresh()
func _welcome_style(fill: Color, edge: Color, padding: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(padding)
	style.shadow_color = Color(0.01,0.02,0.04,0.38)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0,4)
	return style

func _welcome_button(button: Button, google: bool) -> void:
	button.custom_minimum_size.y = 58
	button.add_theme_font_size_override("font_size",22)
	var fill: Color = Color(0.055,0.11,0.17,0.85) if google else Color(0.48,0.55,0.63,0.22)
	button.add_theme_stylebox_override("normal",_welcome_style(fill,Color("b4cbd9")))
	button.add_theme_stylebox_override("hover",_welcome_style(fill.lightened(0.12),Color("d8f4ff")))
	button.add_theme_stylebox_override("pressed",_welcome_style(fill.darkened(0.18),Color("65cde9")))
	button.add_theme_stylebox_override("disabled",_welcome_style(Color(0.10,0.14,0.19,0.6),Color("657582")))
	button.add_theme_stylebox_override("focus",_welcome_style(Color(0,0,0,0),Color("81e2fa")))
	for state_name: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(state_name,Color("ecf4fa"))
	button.add_theme_color_override("font_disabled_color",Color("99a9b6"))

func _fit_welcome(page: Control, inset: Control, column: VBoxContainer, title: Label, accent: Label) -> void:
	# Safe-area parent + scroll fallback retain readable controls on short displays.
	var width: float = minf(520.0,page.size.x*0.68)
	column.custom_minimum_size.x = width
	var font_size: int = 34 if width>=480.0 else 28
	title.add_theme_font_size_override("font_size",font_size)
	accent.add_theme_font_size_override("font_size",font_size)
	inset.offset_top = page.size.y*0.10
	inset.offset_bottom = -page.size.y*0.10

func _polish(button: Button) -> void:
	button.resized.connect(func() -> void: button.pivot_offset = button.size*0.5)
	button.pressed.connect(func() -> void:
		button.scale = Vector2(0.98,0.98)
		var tween: Tween = button.create_tween()
		tween.tween_property(button,"scale",Vector2.ONE,0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
func _add_settings_card(node: Node) -> void:
	if node is VBoxContainer and node.has_meta("account_settings_host"):
		_build_card(node as VBoxContainer)
		return
	for child: Node in node.get_children(): _add_settings_card(child)
func _build_card(parent: VBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",game.ui._style(Color("101e2bed"),Color("314a5c")))
	parent.add_child(panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation",10)
	panel.add_child(body)
	var heading: Label = game.ui._label(body,"ACCOUNT",20,game.ui.ACCENT)
	var state: Label = game.ui._label(body,"",20)
	var detail: Label = game.ui._label(body,"",17,game.ui.MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cloud: Label = game.ui._label(body,"",17,game.ui.ACCENT)
	cloud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var link: Button = game.ui._button(body,"LINK TO GOOGLE",_link_google_pressed,false,true)
	var logout: Button = game.ui._button(body,"SIGN OUT",func() -> void: logout_dialog.popup_centered(Vector2i(480,180)))
	if parent.has_meta("account_settings_host"):
		heading.visible = false
		body.add_theme_constant_override("separation",7)
		var glass: StyleBoxTexture = StyleBoxTexture.new()
		glass.texture = preload("res://Assets/UI/account_circuit_glass.svg")
		glass.texture_margin_left = 18
		glass.texture_margin_right = 18
		glass.texture_margin_top = 18
		glass.texture_margin_bottom = 18
		glass.content_margin_left = 18
		glass.content_margin_right = 18
		glass.content_margin_top = 12
		glass.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel",glass)
		state.add_theme_font_size_override("font_size",21)
		state.add_theme_color_override("font_color",Color("e5f0f5"))
		detail.add_theme_color_override("font_color",Color("b6c9d4"))
		for action: Button in [link,logout]:
			action.custom_minimum_size.y = 46
			action.add_theme_font_size_override("font_size",20)
			var metal: StyleBoxTexture = StyleBoxTexture.new()
			metal.texture = preload("res://Assets/UI/account_metal_button.svg")
			metal.texture_margin_left = 30
			metal.texture_margin_right = 30
			metal.texture_margin_top = 12
			metal.texture_margin_bottom = 12
			metal.content_margin_top = 7
			metal.content_margin_bottom = 7
			action.add_theme_stylebox_override("normal",metal)
			action.add_theme_color_override("font_color",Color("e3f0f7"))
	account_cards.append({"state":state,"detail":detail,"cloud":cloud,"link":link,"logout":logout})
func _auth_changed() -> void:
	if was_chosen and not AuthService.chosen:
		RushAuthDiagnostics.stage("LOGOUT_NAVIGATE_LOGIN")
		logout_dialog.hide()
		game.go_home()
		game.ui.show_screen("account")
		game.progression_ui.dismiss_notice()
		RushAuthDiagnostics.stage("LOGOUT_COMPLETE")
	was_chosen = AuthService.chosen
	refresh()
func _google_pressed() -> void:
	print("[VelocityRushAuth] UI_GOOGLE_BUTTON_PRESSED")
	AuthService.sign_in_with_google()
	GameAudio.click()
func _link_google_pressed() -> void:
	print("[VelocityRushAuth] UI_GOOGLE_BUTTON_PRESSED")
	if not AuthService.is_guest() or AuthService.busy: return
	AuthService.link_guest_to_google()
	GameAudio.click()
func refresh() -> void:
	status_label.text = "Loading account progress…" if SaveService.bootstrap_pending and CloudSaveService.status=="SYNCING" else AuthService.message
	if SaveService.bootstrap_pending and not CloudSaveService.busy and CloudSaveService.status in ["ERROR","OFFLINE","CONFLICT"]:
		status_label.text = "Account progress is not ready. Reconnect and retry, or play separately as Guest."
	google_button.disabled = AuthService.busy
	guest_button.disabled = AuthService.busy
	var connected: bool = AuthService.is_authenticated() and not AuthService.is_guest()
	for card: Dictionary in account_cards:
		card.state.text = "Google account  •  Connected" if connected else "Playing as Guest"
		card.detail.text = AuthService.current_user_email() if connected else "Protect your progress and sync it across devices."
		var cloud_state: String = CloudSaveService.status
		if cloud_state=="SYNCING": cloud_state = "Pending / Syncing"
		if not AuthService.is_authenticated(): cloud_state = "Not connected — local save active"
		card.cloud.text = "Cloud Save  •  "+cloud_state
		card.link.visible = not connected
		card.link.disabled = AuthService.busy
		card.logout.disabled = AuthService.busy or not AuthService.chosen
func launch() -> void:
	if AuthService.chosen:
		game.ui.show_screen("account")
		AuthService.restore_session()
	else:
		game.ui.show_screen("account")
