class_name RushRacePowerupDock
extends Node
var last_activation_ms: int = -1000
var game: Node
var config: Dictionary
var buttons: Dictionary = {}
var artwork: Dictionary = {}
var counters: Dictionary = {}
var magnet_left: float = 0.0
var shield_left: float = 0.0
var old_radius: float = 1.45
var tracked_run: int = -1
var shell: MeshInstance3D
var ring: MeshInstance3D
var shell_mat: StandardMaterial3D
var pulse_left: float = 0.0
var sound: AudioStreamPlayer
var clips: Dictionary = {}
var shield_was_ready: bool = false
func build(owner_game: Node) -> void:
	game = owner_game
	config = JSON.parse_string(FileAccess.get_file_as_string("res://Data/RacePowerups.json"))
	var dock: VBoxContainer = VBoxContainer.new()
	game.ui.screens.drive.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dock.offset_left = -84
	dock.offset_right = -20
	dock.offset_top = 194
	dock.offset_bottom = 398
	dock.custom_minimum_size = Vector2(64, 204)
	dock.add_theme_constant_override("separation", 7)
	game.ui.hud_elements["powerup_dock"] = dock
	HudLayoutService.apply_control("powerup_dock", dock, game.ui.screens.drive.size)
	for kind: String in ["magnet","repair","shield"]:
		var button: RushPowerIcon = RushPowerIcon.new()
		button.item_kind = kind
		button.custom_minimum_size = RushPowerIcon.TARGET_SIZE
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		var art: TextureRect = TextureRect.new()
		art.visible = false # Glyph is drawn by the existing RushPowerIcon.
		button.add_child(art)
		RushPowerIcon.fit_art(art)
		artwork[kind] = art
		var count: Label = Label.new()
		button.add_child(count)
		RushPowerIcon.fit_count(count)
		counters[kind] = count
		for state_name: String in ["normal","disabled","hover","pressed"]:
			var style := StyleBoxFlat.new()
			style.set_corner_radius_all(32)
			match state_name:
				"normal":
					style.bg_color = Color("071422f0")
					style.border_color = Color("00e5ffaa")
					style.set_border_width_all(1)
					style.shadow_color = Color("00e5ff33")
					style.shadow_size = 8
				"hover":
					style.bg_color = Color("0c273df4")
					style.border_color = Color("54f0ff")
					style.set_border_width_all(1)
					style.shadow_color = Color("00e5ff55")
					style.shadow_size = 10
				"pressed":
					style.bg_color = Color("102b3bee")
					style.border_color = Color("54f0ff")
					style.set_border_width_all(2)
					style.shadow_color = Color("00e5ff66")
					style.shadow_size = 12
				"disabled":
					style.bg_color = Color("071422f0")
					style.border_color = Color("00e5ff77")
					style.set_border_width_all(1)
					style.shadow_color = Color("00e5ff22")
					style.shadow_size = 6
			button.add_theme_stylebox_override(state_name, style)
		button.tooltip_text = kind.capitalize()
		button.pressed.connect(activate.bind(kind))
		dock.add_child(button)
		buttons[kind] = button
	sound = AudioStreamPlayer.new()
	sound.bus = "SFX"
	add_child(sound)
	for key: String in ["repair","magnet","shield","shield_break"]:
		clips[key] = load("res://Assets/Audio/power_"+key+".wav")
	shell_mat = RoadGeometry.material(Color(.15,.65,.9,.14),.1,.25)
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_mat.emission_enabled = true
	shell_mat.emission = Color("39a9dc")*.4
	shell = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radial_segments = 24
	mesh.rings = 12
	shell.mesh = mesh
	shell.material_override = shell_mat
	shell.scale = Vector3(2.3,1.4,5.0)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.world.add_child(shell)
	ring = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 1.7
	torus.outer_radius = 1.76
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = shell_mat
	game.world.add_child(ring)
func usable(kind: String) -> bool:
	if game.state!=game.State.DRIVING or game.run.race_mode not in ["highway_rush","five_racer"] or game.run.state!=RushRunManager.RunState.RUNNING:
		return false
	var key: String = {"repair":"repair_kits","magnet":"coin_magnets","shield":"shields"}[kind]
	if int(SaveService.consumables.get(key,0))<=0:
		return false
	match kind:
		"repair": return game.director.damage.health<game.director.damage.maximum-.5 and game.director.damage.health>0
		"magnet": return magnet_left<=0
		"shield": return not game.director.damage.shield_ready
	return false
func activate(kind: String) -> void:
	if Time.get_ticks_msec()-last_activation_ms<500 or not usable(kind):
		return
	var key: String = {"repair":"repair_kits","magnet":"coin_magnets","shield":"shields"}[kind]
	last_activation_ms = Time.get_ticks_msec()
	if not SaveService.consume_boost(key):
		return
	match kind:
		"repair": game.director.damage.restore_fraction(float(config.repair_fraction))
		"magnet":
			old_radius = game.coins.pickup_radius
			magnet_left = float(config.magnet_seconds)
			game.coins.pickup_radius = maxf(old_radius,float(config.magnet_radius))
		"shield":
			shield_left = float(config.shield_seconds)
			game.director.damage.shield_ready = true
			shield_was_ready = true
	pulse_left = .7
	sound.stream = clips[kind]
	sound.play()
	game.director.callout.text = "REPAIRED" if kind=="repair" else kind.to_upper()+" ACTIVE"
	game.director.callout_left = 1.0
func _process(delta: float) -> void:
	if game==null:
		return
	if tracked_run!=game.run.run_id or game.state==game.State.HOME:
		magnet_left = 0
		shield_left = 0
		shield_was_ready = false
		tracked_run = game.run.run_id
	var active: bool = game.state==game.State.DRIVING
	if active:
		pulse_left = maxf(0,pulse_left-delta)
		if magnet_left>0:
			magnet_left = maxf(0,magnet_left-delta)
			if magnet_left<=0:
				game.coins.pickup_radius = old_radius
		if shield_left>0:
			shield_left = maxf(0,shield_left-delta)
			if shield_left<=0:
				game.director.damage.shield_ready = false
		if shield_was_ready and not game.director.damage.shield_ready:
			sound.stream = clips.shield_break
			sound.play()
			pulse_left = .45
		shield_was_ready = game.director.damage.shield_ready
	shell.visible = active and game.director.damage.shield_ready
	ring.visible = active and (magnet_left>0 or pulse_left>0)
	shell.global_transform = game.vehicle.render_pose()
	shell.scale = Vector3(2.3,1.4,5.0)
	shell.position.y += .7
	ring.position = game.vehicle.render_pose().origin+Vector3(0,.18,0)
	ring.scale = Vector3.ONE*(1.0+pulse_left*.6)
	shell_mat.emission_energy_multiplier = [.35,.7,1.1][int(SaveService.settings.quality)]
	for kind: String in buttons:
		var key: String = {"repair":"repair_kits","magnet":"coin_magnets","shield":"shields"}[kind]
		var count_val: int = int(SaveService.consumables.get(key, 0))
		counters[kind].text = "x%d" % count_val
		buttons[kind].modulate = Color.WHITE
		if count_val == 0:
			artwork[kind].modulate = Color("b2e4f0")
			counters[kind].modulate = Color("c0dce8")
			counters[kind].add_theme_font_size_override("font_size", 15)
		else:
			artwork[kind].modulate = Color.WHITE
			counters[kind].modulate = Color("ffffff")
			counters[kind].add_theme_font_size_override("font_size", 15)
		buttons[kind].remaining_fraction = magnet_left/float(config.magnet_seconds) if kind=="magnet" else (shield_left/float(config.shield_seconds) if kind=="shield" and game.director.damage.shield_ready else 0.0)
		buttons[kind].queue_redraw()
