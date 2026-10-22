extends Node
var external_brakes: bool = false
## Shared continuous main theme for menu and races; existing SFX remain independent.
var music_blend: float = 0.0
var music_target: float = 0.0
var music_home: AudioStreamPlayer
var music_race: AudioStreamPlayer
var players: Dictionary = {}
var external_engine: bool = false
var duck_left: float = 0.0
var driving: bool = false
var suspended: bool = false
var current_rpm: float = 0.0
var current_load: float = 0.0
const TURBO_EVENT_DB: Dictionary = {"turbo_ignition": -7.0, "turbo_flare": -9.0, "turbo_end": -11.0}
const CLIPS := {"engine": "engine.wav", "skid": "skid.wav", "collision": "collision.wav", "ui": "ui.wav", "music": "ambience.wav",
	"coin": "coin.wav", "near_miss": "near_miss.wav", "countdown": "countdown.wav", "go": "go.wav", "finish": "finish.wav", "wind": "wind.wav", "turbo_spool": "turbo_spool.wav",
	"turbo_ready": "turbo_ready.wav", "turbo_ignition": "turbo_ignition.wav", "turbo_flare": "turbo_flare.wav", "turbo_end": "turbo_end.wav", "garage":"garage.wav", "car_select":"car_select.wav", "purchase":"purchase.wav", "upgrade":"upgrade.wav", "xp_gain":"xp_gain.wav", "level_up":"level_up.wav", "mission_complete":"mission_complete.wav", "reward_claim":"reward_claim.wav", "achievement":"achievement.wav", "daily_reward":"daily_reward.wav"}
const BUSES := {"engine": "Engine", "skid": "SFX", "collision": "SFX", "ui": "UI", "music": "Music",
	"coin": "SFX", "near_miss": "SFX", "countdown": "UI", "go": "UI", "finish": "UI", "wind": "SFX", "turbo_spool": "Engine",
	"turbo_ready": "UI", "turbo_ignition": "SFX", "turbo_flare": "SFX", "turbo_end": "SFX", "garage":"Music", "car_select":"UI", "purchase":"UI", "upgrade":"UI", "xp_gain":"UI", "level_up":"UI", "mission_complete":"UI", "reward_claim":"UI", "achievement":"UI", "daily_reward":"UI"}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus: String in ["Music","Engine","SFX","UI"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count-1
			AudioServer.set_bus_name(index,bus)
			AudioServer.set_bus_send(index,"Master")
	for key: String in CLIPS:
		var player := AudioStreamPlayer.new()
		var clip: AudioStreamWAV = load("res://Assets/Audio/"+CLIPS[key])
		if key in ["engine","skid","music","wind","turbo_spool","garage"]:
			clip.loop_mode = AudioStreamWAV.LOOP_FORWARD
			clip.loop_begin = 0
			clip.loop_end = int(clip.get_length()*clip.mix_rate)
		player.stream = clip
		player.bus = BUSES[key]
		add_child(player)
		players[key] = player
	players["engine"].volume_db = -80.0
	players["skid"].volume_db = -80.0
	players["engine"].play()
	players["skid"].play()
	players["music"].volume_db = -80.0
	music_home = _music_deck("res://Assets/Audio/apex_ascent.mp3")
	music_race = music_home # Same deck: no duplicate playback or restart at race entry.
	for key: String in ["wind","turbo_spool"]:
		players[key].volume_db = -80.0
		players[key].play()
	SaveService.changed.connect(apply_settings)
	apply_settings()

func apply_settings() -> void:
	_volume("Master",float(SaveService.settings["master"]))
	_volume("Music",float(SaveService.settings["music"]))
	for bus: String in ["Engine","SFX","UI"]:
		_volume(bus,float(SaveService.settings["sfx"]))

func _volume(bus: String, value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus),linear_to_db(maxf(value,0.0001)))

func set_driving(value: bool) -> void:
	driving = value
	set_suspended(false)
	music_target = 1.0 if value else 0.0
	if not value:
		players["engine"].volume_db = -80.0
		players["skid"].volume_db = -80.0
		for key: String in ["wind","turbo_spool"]:
			players[key].volume_db = -80.0
		for key: String in ["turbo_ready","turbo_ignition","turbo_flare","turbo_end"]:
			players[key].stop()

func set_suspended(value: bool) -> void:
	suspended = value
	for key: String in players:
		if key not in ["music","ui"]:
			players[key].stream_paused = value

func update_vehicle(delta: float, speed: float, throttle: float, skid: float, boost: float = 0.0, acceleration: float = 0.0, speed_ceiling: float = 270.0) -> void:
	if not driving or suspended:
		return
	# Simulated gear changes modulate the safe placeholder engine loop.
	var rpm := fmod(absf(speed),48.0)/48.0
	current_rpm = lerpf(current_rpm,rpm,1.0-exp(-6.0*delta))
	current_load = lerpf(current_load,maxf(throttle,boost),1.0-exp(-8.0*delta))
	players["engine"].pitch_scale = lerpf(players["engine"].pitch_scale,0.65+current_rpm*1.2+maxf(current_load,0.0)*0.18+boost*0.15+clampf(acceleration/30.0,-0.08,0.1),1.0-exp(-10.0*delta))
	players["engine"].volume_db = -80.0 if external_engine else -18.0+minf(absf(speed)/maxf(speed_ceiling,1.0),1.0)*5.0+boost*2.0
	players["skid"].volume_db = -80.0 if external_brakes else linear_to_db(maxf(skid*0.13,0.0001))

	var wind_gain := pow(clampf(speed/maxf(speed_ceiling,1.0),0.0,1.0),2.0)*(0.14+boost*0.08)
	players["wind"].volume_db = lerpf(players["wind"].volume_db,linear_to_db(maxf(wind_gain,0.0001)),1.0-exp(-5.0*delta))
	players["turbo_spool"].volume_db = linear_to_db(maxf(clampf(boost,0.0,1.0)*0.32,0.0001))
	players["turbo_spool"].pitch_scale = 0.8+boost*0.65+clampf(speed/maxf(speed_ceiling,1.0),0.0,1.0)*0.2

func click() -> void:
	players["ui"].volume_db = -14.0
	players["ui"].play()

func event(key: String) -> void:
	if players.has(key):
		players[key].volume_db = float(TURBO_EVENT_DB.get(key,-13.0))
		if key == "turbo_ignition":
			duck_music(0.75)
		players[key].play()

func prewarm_feedback() -> void:
	for key: String in ["coin","near_miss","countdown","go","finish","collision","ui","turbo_ready","turbo_ignition","turbo_flare","turbo_end","car_select","purchase","upgrade","xp_gain","level_up","mission_complete","reward_claim","achievement","daily_reward"]:
		players[key].volume_db = -80.0
		players[key].play()

func finish_prewarm() -> void:
	for key: String in ["coin","near_miss","countdown","go","finish","collision","ui","turbo_ready","turbo_ignition","turbo_flare","turbo_end","car_select","purchase","upgrade","xp_gain","level_up","mission_complete","reward_claim","achievement","daily_reward"]:
		players[key].stop()
		players[key].volume_db = -13.0

func collision(strength: float) -> void:
	players["collision"].volume_db = lerpf(-19.0,-5.0,strength)
	players["collision"].play()
	RushHaptics.pulse(int(30+strength*70))

func reset_turbo() -> void:
	for key: String in ["turbo_ready","turbo_ignition","turbo_flare","turbo_end"]:
		players[key].stop()
	for key: String in ["wind","turbo_spool"]:
		players[key].volume_db = -80.0
	current_rpm = 0.0
	current_load = 0.0

func set_garage(value: bool) -> void:
	if value:
		music_target = 0.0

func _music_deck(path: String) -> AudioStreamPlayer:
	var deck := AudioStreamPlayer.new()
	var stream := load(path) as AudioStream
	if stream == null:
		push_error("GameAudio: Failed to load music: "+path)
		return deck
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	deck.stream = stream
	deck.bus = "Music"
	deck.volume_db = -80.0
	add_child(deck)
	deck.play()
	return deck

func _process(delta: float) -> void:
	if music_home==null:
		return
	music_blend = move_toward(music_blend,music_target,delta/1.2)
	# Keep the theme playing continuously; ease its gain down during racing.
	duck_left = maxf(0,duck_left-delta)
	var duck := (0.65 if suspended else 1.0)*(0.5 if duck_left>0 else 1.0)
	music_home.volume_db = linear_to_db(maxf(lerpf(0.31,0.23,music_blend)*duck,0.0001))

func duck_music(seconds: float) -> void:
	duck_left = maxf(duck_left,seconds)