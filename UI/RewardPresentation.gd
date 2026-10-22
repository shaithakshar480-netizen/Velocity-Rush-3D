class_name RushRewardPresentation
extends CanvasLayer
## Observe only post-commit signals. Debits/consumption never celebrate.
## A single bounded batch coalesces bundle signals and rapid claims.
const KEYS: Array[String] = ["coins","turbo_inventory","coin_magnets","repair_kits","shields"]
const TITLES: Array[String] = ["COINS","TURBO BOOSTERS","COIN MAGNET","REPAIR KIT","SHIELD"]
const ART: Array[String] = ["coin_stack","turbo","magnet","repair","shield"]
const AUDIO: Array[String] = ["reward_claim","turbo_ignition","power_magnet","power_repair","power_shield"]
var baseline: Dictionary = {}
var pending: Dictionary = {}
var panel: HBoxContainer
var busy: bool = false
var sound: AudioStreamPlayer
var textures: Array[Texture2D] = []
var clips: Array[AudioStream] = []
func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in KEYS.size():
		baseline[KEYS[i]] = quantity(KEYS[i])
		textures.append(load("res://Assets/Store/"+ART[i]+".svg"))
		clips.append(load("res://Assets/Audio/"+AUDIO[i]+".wav"))
	sound = AudioStreamPlayer.new()
	sound.bus = "UI"
	add_child(sound)
	SaveService.wallet_changed.connect(func(_balance: int) -> void: observe())
	SaveService.turbo_inventory_changed.connect(observe)
	SaveService.cloud_restored.connect(func() -> void:
		for key: String in KEYS: baseline[key] = quantity(key))
func quantity(key: String) -> int:
	return SaveService.balance() if key=="coins" else int(SaveService.consumables.get(key,0))
func observe() -> void:
	for key: String in KEYS:
		var current: int = quantity(key)
		var gain: int = current-int(baseline[key])
		baseline[key] = current
		if gain>0:
			pending[key] = int(pending.get(key,0))+gain
	if not busy and not pending.is_empty():
		busy = true
		present.call_deferred()
func present() -> void:
	var rewards: Dictionary = pending.duplicate()
	pending.clear()
	var frame: Control = Control.new()
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center: CenterContainer = CenterContainer.new()
	frame.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_bottom = 220
	center.offset_top = 82
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = HBoxContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var first: int = -1
	for i: int in KEYS.size():
		if not rewards.has(KEYS[i]):
			continue
		if first<0:
			first = i
		var tile: VBoxContainer = VBoxContainer.new()
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(tile)
		var icon: TextureRect = TextureRect.new()
		icon.texture = textures[i]
		icon.custom_minimum_size = Vector2(105,70)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(icon)
		var text: Label = Label.new()
		text.text = "+%d\n%s"%[int(rewards[KEYS[i]]),TITLES[i]]
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.add_theme_font_size_override("font_size",16)
		text.add_theme_color_override("font_shadow_color",Color.BLACK)
		text.add_theme_constant_override("shadow_outline_size",4)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(text)
		if KEYS[i]=="coins":
			var wallet: Label = Label.new()
			wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			wallet.add_theme_font_size_override("font_size",14)
			wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.add_child(wallet)
			var count_up: Tween = create_tween()
			count_up.tween_method(func(value: float) -> void: wallet.text = "WALLET %d"%roundi(value),float(SaveService.balance()-int(rewards[KEYS[i]])),float(SaveService.balance()),.75)

	var quality: int = clampi(int(SaveService.settings.quality),0,2)
	for i: int in [3,6,10][quality]:
		var spark: ColorRect = ColorRect.new()
		spark.color = Color("83cede")
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spark.size = Vector2(3,3)
		frame.add_child(spark)
		spark.position = get_viewport().get_visible_rect().size*Vector2(.5,.25)
		var burst: Tween = create_tween()
		burst.tween_property(spark,"position",spark.position+Vector2(cos(i*2.4)*95,sin(i*2.4)*65),.6)
		burst.parallel().tween_property(spark,"modulate:a",0.0,.6)
	sound.stop()
	sound.stream = clips[first]
	sound.play()
	panel.modulate.a = 0
	var animation: Tween = create_tween()
	animation.tween_property(panel,"modulate:a",1.0,.15)
	animation.tween_interval(.8)
	animation.tween_property(panel,"modulate:a",0.0,.35)
	animation.parallel().tween_property(center,"position:y",42.0,.35)
	await animation.finished
	frame.queue_free()
	busy = false
	if not pending.is_empty():
		busy = true
		present.call_deferred()
