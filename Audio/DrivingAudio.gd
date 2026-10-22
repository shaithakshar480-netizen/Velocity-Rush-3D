class_name RushDrivingAudio
extends Node3D
## Cached engine bank and a fixed pool of positional effect players.
var car: ArcadeVehicle
var banks: Dictionary = {}
var sound_profiles: Dictionary = {}
var sound_profile: Dictionary = {}
var engines: Array[AudioStreamPlayer] = []
var effects: Dictionary = {}
var positional: Array[AudioStreamPlayer3D] = []
var cursor: int = 0
var damage_stage: int = 0
var beds: Dictionary = {}
var active: bool = false
var engine_id: String = ""
var horn_cooldown: float = 0.0
var horn_profiles: Dictionary = {}
var horn_player: AudioStreamPlayer
var whoosh_cooldown: float = 0.0
var load_value: float = 0.0
var rough_clock: float = 0.0
func _ready() -> void:
	sound_profiles = JSON.parse_string(FileAccess.get_file_as_string("res://Data/VehicleAudioProfiles.json"))
	horn_player = AudioStreamPlayer.new()
	horn_player.bus = "SFX"
	horn_player.volume_db = -10
	add_child(horn_player)
	for id: String in RushVehicleCatalog.IDS:
		var clips: Array[AudioStreamWAV] = []
		for i: int in 4:
			var stream := load("res://Assets/Audio/"+"engine_"+String(sound_profiles[id].engine_id)+"_"+str(i)+".wav") as AudioStreamWAV
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = int(stream.get_length()*stream.mix_rate)
			clips.append(stream)
		banks[id] = clips
		horn_profiles[id] = load(String(RushVehicleCatalog.definition(id).interior.horn_path))
	for i: int in 4:
		var player := AudioStreamPlayer.new()
		player.bus = "Engine"
		player.volume_db = -80
		add_child(player)
		engines.append(player)
	for key: String in ["horn","shift","blowoff","passby","scrape","heavy_impact","explosion","fire","damage_warning","road_noise"]:
		effects[key] = load("res://Assets/Audio/"+key+".wav")
	for key: String in ["fire","road_noise"]:
		var bed := AudioStreamPlayer.new()
		var stream: AudioStreamWAV = effects[key]
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length()*stream.mix_rate)
		bed.stream = stream
		bed.bus = "SFX"
		bed.volume_db = -80
		add_child(bed)
		bed.play()
		beds[key] = bed
	for i: int in 6:
		var player := AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.max_distance = 100
		player.unit_size = 14
		add_child(player)
		positional.append(player)
func configure(id: String) -> void:
	engine_id = id
	sound_profile = sound_profiles[id]
	load_value = 0.0
	horn_player.stop()
	horn_player.stream = horn_profiles[id]
	horn_cooldown = 0.0
	for i: int in 4:
		engines[i].stream = banks[id][i]
		engines[i].play()
		engines[i].volume_db = -80
func play_effect(key: String, at: Vector3, gain: float = 1.0) -> void:
	var player := positional[cursor%positional.size()]
	cursor += 1
	player.global_position = at
	player.stream = effects[key]
	player.pitch_scale = [0.92,1.04,0.98,1.08,0.95,1.01][cursor%6] if key in ["passby","scrape","heavy_impact"] else 1.0
	player.volume_db = linear_to_db(maxf(gain,.0001))-7
	player.play()
func horn() -> bool:
	if not active or horn_cooldown>0 or horn_player.playing:
		return false
	horn_cooldown = .62
	horn_player.play()
	return true
func pass_by(at: Vector3, relative_speed: float) -> void:
	if not active or whoosh_cooldown>0 or relative_speed<8:
		return
	whoosh_cooldown = .22
	play_effect("passby",at,clampf(relative_speed/50,.25,1))
func _process(delta: float) -> void:
	beds.fire.volume_db = -24.0 if damage_stage>=4 else -80.0
	beds.road_noise.volume_db = linear_to_db(maxf(.075*clampf(car.speed_kmh()/250,0,1) if active else 0,.0001))
	horn_cooldown = maxf(0,horn_cooldown-delta)
	whoosh_cooldown = maxf(0,whoosh_cooldown-delta)
	load_value = lerpf(load_value,maxf(car.last_command.y,0),1-exp(-9*delta))
	rough_clock += delta
	var rpm := clampf(car.transmission.rpm/float(car.transmission.config.redline_rpm),0,1)
	var boost := car.turbo.intensity if car.turbo!=null else 0.0
	var shift_gain := .45 if car.transmission.shift_left>0 else 1.0
	for i: int in engines.size():
		var gain := .11*(1-rpm)
		match i:
			1: gain = .23*load_value*(.65+rpm*.35)*(1.0+boost*.48)*shift_gain
			2:
				gain = .14*smoothstep(.40,1,rpm)*(.55+load_value*.45)*(1.0+boost*.35)*shift_gain
				if rpm>.96:
					gain *= .84+.16*sin(rough_clock*85)
			3: gain = .08*(1-load_value)*(.25+rpm*.75)
		engines[i].volume_db = linear_to_db(maxf(gain*float(sound_profile.get("load_gain",1.0)) if active else 0,.0001))
		engines[i].pitch_scale = lerpf(engines[i].pitch_scale,(.60+rpm*1.65)*float(sound_profile.get("pitch",1.0))*(1.0+(.025*sin(rough_clock*37) if damage_stage==3 else 0)),1-exp(-14*delta))
func prewarm() -> void:
	for id: String in RushVehicleCatalog.IDS:
		configure(id)
	for key: String in effects:
		play_effect(key,Vector3(0,-1000,0),.0001)
	for player: AudioStreamPlayer3D in positional:
		player.stop()
func silence() -> void:
	horn_player.stop()
	active = false
	damage_stage = 0
	for bed: AudioStreamPlayer in beds.values():
		bed.volume_db = -80
	for player: AudioStreamPlayer in engines:
		player.volume_db = -80
	for player: AudioStreamPlayer3D in positional:
		player.stop()
