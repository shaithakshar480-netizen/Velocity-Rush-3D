class_name RushOnlineUI
extends Node
var duel: RushDuelService = RushDuelService.new()
var transport: RushDuelWebSocket
var room_code: LineEdit
var multiplayer_page: Control
var multiplayer_panel: PanelContainer
var landing: VBoxContainer
var connection: VBoxContainer
var room_actions: VBoxContainer
var lobby: VBoxContainer
var latency_label: Label
var details: Label
var connect_button: Button
var back_button: Button
var lobby_code: Button
var player_names: Array[Label] = []
var player_states: Array[Label] = []
var player_roles: Array[Label] = []
var lobby_leave: Button
var endpoint_configured: bool = false
var connection_attempted: bool = false
var public_button: Button
var quick_join_button: Button
var result_panel: VBoxContainer
var result_rows: Array[Label] = []
var create_button: Button
var join_button: Button
var ready_button: Button
var start_button: Button
var scope: int = -1
var ui: AutomotiveUI
var online: RushOnlineService = RushOnlineService.new()
var matchmaking: RushMatchmakingService = RushMatchmakingService.new()
var tournaments: RushTournamentService = RushTournamentService.new()
var status: Label
var quick: Button
var event_list: VBoxContainer
var tab: String = "ACTIVE"
var refresh_left: float = 0.0
func build(owner_ui: AutomotiveUI) -> void:
	ui = owner_ui
	matchmaking.online = online
	tournaments.online = online
	_build_multiplayer()
	transport = RushDuelWebSocket.new()
	add_child(transport)
	duel.attach(transport)
	duel.context_valid = _duel_context_valid
	duel.changed.connect(_duel_refresh)
	_duel_refresh()
func open(mode: String) -> void:
	if mode!="multiplayer":
		ui.show_screen("race_modes")
		return
	endpoint_configured = not _configured_endpoint().is_empty()
	_duel_refresh()
	ui.show_screen("multiplayer")
func _back() -> void:
	connection_attempted = false
	duel.leave()
	matchmaking.cancel_search()
	ui.show_screen("race_modes")
func _tab(value: String) -> void:
	tab = value
	for child: Node in event_list.get_children():
		event_list.remove_child(child)
		child.queue_free()
	if not online.is_online():
		ui._label(event_list,"ONLINE UNAVAILABLE",24,ui.ACCENT)
		ui._label(event_list,"Online service not connected yet.\nYour offline races and progress are still available.",18,ui.MUTED)
		return
	var shown: int = 0
	for event: Dictionary in tournaments.server_events:
		var state: String = String(event.get("status",""))
		if state not in RushTournamentService.STATUSES:
			continue
		if (tab=="ACTIVE" and state not in ["OPEN","IN_PROGRESS"]) or (tab=="UPCOMING" and state!="UPCOMING") or (tab=="RESULTS" and state not in ["FINISHED","CLAIMED"]):
			continue
		shown += 1
		var panel: PanelContainer = PanelContainer.new()
		panel.add_theme_stylebox_override("panel",ui._style(Color("111c29")))
		event_list.add_child(panel)
		var content: VBoxContainer = ui._column(panel,620)
		ui._label(content,String(event.get("title","TOURNAMENT")),24)
		var remaining: int = maxi(0,int(event.get("end_time",0))-int(Time.get_unix_time_from_system()))
		ui._label(content,"5-Racer Competition • Ends in %dh %dm\nROUND %d • PLACE %d • %s"%[int(float(remaining)/3600.0),int(float(remaining)/60.0)%60,int(event.get("current_round",0)),int(event.get("placement",0)),"QUALIFIED" if bool(event.get("qualified",false)) else state],16,ui.MUTED)
		var rewards: Array = event.get("reward_table",[])
		if not rewards.is_empty():
			ui._label(content,"Top Reward: %d Coins"%int(rewards[0].get("coins",0)),20,ui.ACCENT)
		for row: Dictionary in event.get("leaderboard",[]):
			ui._label(content,"%d  %s"%[int(row.get("placement",0)),String(row.get("display_name",""))],16)
		var enter: Button = ui._button(content,"ENTER",tournaments.enter.bind(String(event.get("tournament_id",""))))
		enter.disabled = state!="OPEN"
	if shown==0:
		ui._label(event_list,"No tournaments available.",20,ui.MUTED)
func _process(delta: float) -> void:
	refresh_left -= delta
	if refresh_left>0:
		return
	refresh_left = 0.25
	duel.latency_tick()
	latency_label.visible = duel.phase in ["CONNECTED","LOBBY"]
	latency_label.text = duel.latency_text()
	latency_label.add_theme_color_override("font_color",Color("efc878") if "HIGH" in latency_label.text else Color("a8dce7"))
	if duel.phase in ["LOADING","COUNTDOWN","RACING"] and Time.get_ticks_msec()>duel.phase_deadline:
		duel._lost()
	if not duel.pending.is_empty() and Time.get_ticks_msec()>duel.request_deadline:
		duel._lost()
	if scope>=0 and (scope!=SaveService.scope_generation or AuthService.busy):
		scope = -1
		duel._lost()
 
func _duel_connect() -> void:
	if duel.phase!="OFFLINE": return
	var endpoint: String = _configured_endpoint()
	endpoint_configured = not endpoint.is_empty()
	if not endpoint_configured:
		_duel_refresh()
		return
	connection_attempted = true
	if not AuthService.is_authenticated() or AuthService.busy or not AuthService.provider is RushFirebaseRestProvider:
		duel.status = "Connect your account before online racing."
		_duel_refresh()
		return
	scope = SaveService.scope_generation
	duel.context = scope
	duel.phase = "CONNECTING"
	duel.status = "Connecting…"
	_duel_refresh()
	var adapter: RushFirebaseRestProvider = AuthService.provider as RushFirebaseRestProvider
	var ticket: int = duel.generation
	var scope_ticket: int = scope
	var reference: WeakRef = weakref(self)
	adapter._authorized(func(ok: bool) -> void:
		var owner_ui: RushOnlineUI = reference.get_ref() as RushOnlineUI
		if owner_ui==null or scope_ticket!=SaveService.scope_generation or ticket!=owner_ui.duel.generation or adapter!=AuthService.provider: return
		if not ok:
			owner_ui.duel._lost()
			return
		owner_ui.duel.account_id = AuthService.current_user_id()
		if not owner_ui.transport.open(endpoint,adapter.id_token): owner_ui.duel._lost())
func _room_request(kind: String, visibility: String = "PRIVATE") -> void:
	var code: String = room_code.text.strip_edges().to_upper()
	if kind=="join":
		if code.length()!=6: return
		for character: String in code:
			if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789": return
	var id: String = RushVehicleCatalog.canonical_id(String(SaveService.collection.selected))
	duel.action(kind,{"visibility":visibility,"code":code,"map":"highway","car":id,"paint":int(SaveService.collection.paints.get(String(SaveService.collection.selected),0)),"name":duel.display_name().left(24)})
func _duel_refresh() -> void:
	# Visibility is presentation only; all actions still pass through DuelService.action.
	var phase: String = duel.phase
	var racing: bool = phase in ["LOADING","COUNTDOWN","RACING"]
	multiplayer_page.visible = ui.screen=="multiplayer" and not racing
	var in_room: bool = phase=="LOBBY" and not duel.room.is_empty()
	var connected: bool = phase=="CONNECTED"
	var connecting: bool = phase=="CONNECTING"
	var failed: bool = phase=="CANCELLED" or (phase=="OFFLINE" and connection_attempted)
	var busy: bool = not duel.pending.is_empty()
	landing.visible = not endpoint_configured
	connection.visible = endpoint_configured and not racing and not in_room and not connected and not connecting and phase!="RESULTS"
	room_actions.visible = endpoint_configured and connected
	lobby.visible = endpoint_configured and in_room
	result_panel.visible = phase=="RESULTS"
	connect_button.text = "RETRY" if failed else "CONNECT"
	connect_button.disabled = connecting or busy
	back_button.text = "LEAVE ROOM" if in_room else "BACK"
	back_button.visible = not in_room
	if not endpoint_configured:
		status.text = "SERVER NOT CONFIGURED"
		details.text = "Online racing will be available when the race server is connected."
	elif connecting:
		status.text = "CONNECTING…"
		details.text = "Connecting to online racing. Please wait…"
	elif in_room:
		status.text = "RACE LOBBY"
		details.text = "Updating your room…" if busy else "Get ready for a 2–5 player race."
	elif connected:
		status.text = "CONNECTED"
		details.text = "Creating your room…" if duel.pending=="create" else ("Joining your room…" if duel.pending=="join" else ("Finding a public race…" if duel.pending=="quick_join" else "Create a room, join friends, or find a public race."))
		if not busy and duel.status=="Room request failed. Check the code or retry.":
			details.text = "Could not enter the room. Check the code and try again."
	elif failed:
		status.text = "CONNECTION UNAVAILABLE"
		details.text = "Sign in to your account before connecting." if not AuthService.is_authenticated() else "Could not connect. Check your connection and retry."
	elif phase=="RESULTS":
		status.text = "RACE COMPLETE"
		details.text = "UNRANKED • NO COINS OR XP AWARDED"
		for i: int in result_rows.size():
			result_rows[i].visible = i<duel.results.size()
			if i>=duel.results.size(): continue
			var row: Dictionary = duel.results[i]
			var racer_name: String = "Racer"
			for player: Dictionary in duel.room.players:
				if player.uid==row.uid: racer_name = String(player.name)
			result_rows[i].text = "%d   %s   •   %s"%[i+1,racer_name,String(row.status)]
	else:
		status.text = "NOT CONNECTED"
		details.text = "Connect to create or join a 2–5 player race."
	status.add_theme_color_override("font_color",Color("e49b8e") if phase in ["OFFLINE","CANCELLED"] else Color("8deca2") if phase in ["CONNECTED","LOBBY"] else Color("94eff3"))
	create_button.disabled = not connected or busy
	join_button.disabled = create_button.disabled
	public_button.disabled = create_button.disabled
	quick_join_button.disabled = create_button.disabled
	room_code.editable = connected and not busy
	ready_button.disabled = not in_room or busy
	start_button.visible = false
	start_button.disabled = true
	if not in_room: return
	lobby_code.text = "%s  •  %s  •  %d / 5  •  COPY"%[String(duel.room.code),String(duel.room.visibility),duel.room.players.size()]
	# Retain the existing host/ready presentation gates; service validates again on action.
	var all_ready: bool = duel.room.players.size()>=RushDuelService.MIN_PLAYERS and duel.room.players.size()<=RushDuelService.MAX_PLAYERS
	var self_ready: bool = false
	for index: int in RushDuelService.MAX_PLAYERS:
		if index>=duel.room.players.size():
			player_names[index].text = "Waiting for player…"
			player_states[index].text = "OPEN SLOT"
			player_roles[index].text = ""
			player_states[index].add_theme_color_override("font_color",Color("8b9eaa"))
			continue
		var player: Dictionary = duel.room.players[index]
		player_names[index].text = String(player.name)
		player_states[index].tooltip_text = ""
		player_roles[index].text = "HOST" if player.uid==duel.room.host else "PLAYER"
		player_states[index].text = "READY" if player.ready else "NOT READY"
		player_states[index].add_theme_color_override("font_color",Color("7deeb0") if player.ready else Color("efbd88"))
		all_ready = all_ready and bool(player.ready)
		if player.uid==duel.account_id: self_ready = bool(player.ready)
	ready_button.text = "READY ✓" if self_ready else "READY"
	ready_button.disabled = busy or self_ready
	start_button.visible = duel.room.host==duel.account_id
	start_button.disabled = busy or not all_ready

func _configured_endpoint() -> String:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://Data/DuelConfig.json"))
	if not raw is Dictionary or not raw.get("endpoint") is String or raw.get("protocol_version")!=RushDuelService.PROTOCOL_VERSION: return ""
	var endpoint: String = String(raw.endpoint).strip_edges()
	# Match the existing transport's TLS-only contract. No endpoint is supplied by UI.
	var pattern: RegEx = RegEx.new()
	pattern.compile("^wss://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[^\\s]*)?$")
	return endpoint if pattern.search(endpoint)!=null else ""

func _build_multiplayer() -> void:
	endpoint_configured = not _configured_endpoint().is_empty()
	multiplayer_page = ui._page("multiplayer")
	multiplayer_page.hide()
	var shade: ColorRect = ColorRect.new()
	shade.color = Color("04101b40")
	multiplayer_page.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin: MarginContainer = MarginContainer.new()
	multiplayer_page.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,20)
	var scroll: RushTouchScroll = RushTouchScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	multiplayer_panel = PanelContainer.new()
	multiplayer_panel.add_theme_stylebox_override("panel",_online_glass())
	center.add_child(multiplayer_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	multiplayer_panel.add_child(column)
	var title: Label = ui._label(column,"MULTIPLAYER",32,Color("99f4ff"))
	title.add_theme_color_override("font_outline_color",Color("172732"))
	title.add_theme_constant_override("outline_size",3)
	ui._label(column,"2–5 PLAYER ONLINE RACING",17,Color("e3f4fa"))
	var line: ColorRect = ColorRect.new()
	line.color = Color("92d2dfb0")
	line.custom_minimum_size.y = 2
	column.add_child(line)
	status = ui._label(column,"",19,ui.ACCENT)
	latency_label = ui._label(column,"PING -- ms",17,ui.ACCENT)
	latency_label.visible = false
	details = ui._label(column,"",17,Color("c5dae5"))
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	landing = VBoxContainer.new()
	column.add_child(landing)
	for feature: String in ["2–5 Player Real-Time Race","Highway • 2 KM","Live Opponent Synchronization"]:
		var label: Label = ui._label(landing,"•  "+feature,18)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	connection = VBoxContainer.new()
	column.add_child(connection)
	connect_button = ui._button(connection,"CONNECT",_retry_connect,true)
	room_actions = VBoxContainer.new()
	room_actions.add_theme_constant_override("separation",6)
	column.add_child(room_actions)
	create_button = ui._button(room_actions,"CREATE PRIVATE ROOM",func() -> void: _room_request("create"),true)
	public_button = ui._button(room_actions,"CREATE PUBLIC ROOM",func() -> void: _room_request("create","PUBLIC"))
	quick_join_button = ui._button(room_actions,"QUICK JOIN",func() -> void: _room_request("quick_join","PUBLIC"),true)
	var separator: Label = ui._label(room_actions,"OR JOIN A FRIEND",16,ui.MUTED)
	separator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_code = LineEdit.new()
	room_code.placeholder_text = "ROOM CODE"
	room_code.max_length = 6
	room_code.custom_minimum_size.y = 44
	room_code.add_theme_font_size_override("font_size",20)
	room_code.add_theme_stylebox_override("normal",ui._style(Color("06111bcc"),Color("286477")))
	room_actions.add_child(room_code)
	join_button = ui._button(room_actions,"JOIN WITH CODE",func() -> void: _room_request("join"))
	lobby = VBoxContainer.new()
	lobby.add_theme_constant_override("separation",10)
	column.add_child(lobby)
	lobby_code = ui._button(lobby,"",_copy_room)
	var players: VBoxContainer = VBoxContainer.new()
	players.add_theme_constant_override("separation",5)
	lobby.add_child(players)
	for index: int in RushDuelService.MAX_PLAYERS:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color("10242dda")
		card_style.border_color = Color("426773")
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(8)
		card_style.content_margin_left = 8
		card_style.content_margin_right = 8
		card_style.content_margin_top = 5
		card_style.content_margin_bottom = 5
		card.add_theme_stylebox_override("panel",card_style)
		players.add_child(card)
		var content := HBoxContainer.new()
		content.add_theme_constant_override("separation",8)
		card.add_child(content)
		var avatar := TextureRect.new()
		avatar.texture = preload("res://Assets/UI/player_avatar.svg")
		avatar.custom_minimum_size = Vector2(30,30)
		avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(avatar)
		var name_label: Label = ui._label(content,"",18)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		player_names.append(name_label)
		var role: Label = ui._label(content,"",14,Color("80e4eb"))
		role.custom_minimum_size.x = 60
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		player_roles.append(role)
		var state_label: Label = ui._label(content,"",16,ui.ACCENT)
		state_label.custom_minimum_size.x = 104
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		player_states.append(state_label)
	ui._label(lobby,"COURSE   •   Highway • 2 KM",18)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation",12)
	lobby.add_child(actions)
	ready_button = ui._button(actions,"READY",func() -> void: duel.action("ready",{"ready":true}))
	start_button = ui._button(actions,"START RACE",func() -> void: duel.action("start"),true)
	ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_leave = ui._button(actions,"LEAVE ROOM",_back)
	lobby_leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_panel = VBoxContainer.new()
	column.add_child(result_panel)
	for i: int in RushDuelService.MAX_PLAYERS:
		var row: Label = ui._label(result_panel,"",20)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		result_rows.append(row)
	back_button = ui._button(column,"BACK",_back)
	for action: Button in [connect_button,create_button,public_button,quick_join_button,join_button,ready_button,start_button,back_button,lobby_code,lobby_leave]:
		_style_online_action(action,action != back_button)
	for action: Button in [ready_button,start_button,lobby_leave]:
		action.add_theme_font_size_override("font_size",17)
		for state: String in ["normal","hover","pressed","focus"]:
			var style: StyleBoxFlat = action.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			style.set_corner_radius_all(8)
			style.content_margin_left = 8
			style.content_margin_right = 8
			if action == ready_button:
				style.bg_color = Color("176647")
				style.border_color = Color("81dfae")
			action.add_theme_stylebox_override(state,style)
	_style_quick_join()
	_style_room_back()
	multiplayer_page.resized.connect(_fit_multiplayer)
	_fit_multiplayer()

func _fit_multiplayer() -> void:
	multiplayer_panel.custom_minimum_size.x = minf(560.0,maxf(0.0,multiplayer_page.size.x-40.0))

func _copy_room() -> void:
	if duel.phase=="LOBBY" and not duel.room.is_empty():
		DisplayServer.clipboard_set(String(duel.room.code))
		lobby_code.text = "ROOM  %s   •   COPIED"%String(duel.room.code)

func _retry_connect() -> void:
	if duel.phase=="CANCELLED": duel.leave()
	_duel_connect()

func _duel_context_valid() -> bool:
	return scope==SaveService.scope_generation and not AuthService.busy and AuthService.is_authenticated()

# Presentation only: cached styles, no network/state changes or per-frame effects.
func _online_glass() -> StyleBoxFlat:
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color("263e49e8")
	glass.border_color = Color("8ceaf0")
	glass.set_border_width_all(2)
	glass.set_corner_radius_all(20)
	glass.content_margin_left = 24
	glass.content_margin_right = 24
	glass.content_margin_top = 18
	glass.content_margin_bottom = 18
	glass.shadow_color = Color("51ddeb40")
	glass.shadow_size = 9
	return glass

func _style_online_action(button: Button, cyan: bool) -> void:
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size",20)
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		var style := StyleBoxFlat.new()
		var disabled: bool = state == "disabled"
		var highlighted: bool = state in ["hover","focus"]
		style.bg_color = Color("152433ef") if cyan else Color("222d35ef")
		if highlighted: style.bg_color = Color("20485beF")
		if state == "pressed": style.bg_color = Color("0b1925")
		style.border_color = Color("465866") if disabled else (Color("7addf1") if cyan else Color("899eaa"))
		style.set_border_width_all(1)
		style.border_width_top = 2
		style.set_corner_radius_all(24)
		style.content_margin_left = 18
		style.content_margin_right = 18
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		if cyan and not disabled:
			style.shadow_color = Color(0.08,0.78,1.0,0.24 if highlighted else 0.12)
			style.shadow_size = 7 if highlighted else 4
		button.add_theme_stylebox_override(state,style)
	button.add_theme_color_override("font_color",Color("8eefff") if cyan else Color("e4eff4"))
	button.add_theme_color_override("font_hover_color",Color("c5faff"))
	button.add_theme_color_override("font_pressed_color",Color.WHITE)
	button.add_theme_color_override("font_disabled_color",Color("8596a3"))

func _style_quick_join() -> void:
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("39c6d7") if state != "disabled" else Color("3d626c")
		if state == "pressed": style.bg_color = Color("2796ab")
		if state in ["hover","focus"]: style.bg_color = Color("74edf3")
		style.border_color = Color("9af7ff") if state != "disabled" else Color("617982")
		style.set_border_width_all(2)
		style.set_corner_radius_all(24)
		style.set_content_margin_all(8)
		style.shadow_color = Color(0.1,0.85,1.0,0.22)
		style.shadow_size = 5
		quick_join_button.add_theme_stylebox_override(state,style)
	for state: String in ["font_color","font_hover_color","font_pressed_color"]:
		quick_join_button.add_theme_color_override(state,Color("05212b"))

func _style_room_back() -> void:
	for state: String in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("9bb2bc") if state == "normal" else Color("c3dbe2")
		style.border_color = Color("d1e7ed")
		style.set_border_width_all(1)
		style.set_corner_radius_all(24)
		style.set_content_margin_all(8)
		back_button.add_theme_stylebox_override(state,style)
	for state: String in ["font_color","font_hover_color","font_pressed_color"]:
		back_button.add_theme_color_override(state,Color("101f29"))
