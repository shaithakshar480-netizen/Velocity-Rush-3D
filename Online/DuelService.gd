class_name RushDuelService
extends RushOnlineService
const PROTOCOL_VERSION: int = 2
const MIN_PLAYERS: int = 2
const MAX_PLAYERS: int = 5
signal changed
signal race_event(packet: Dictionary)
var context_valid: Callable
var phase_deadline: int = 0
var transport: RushDuelProvider
var room: Dictionary = {}
var phase: String = "OFFLINE"
var status: String = "Internet racing requires a configured race server."
var generation: int = 0
var context: int = -1
var pending: String = ""
var last_revision: int = -1
var finish_sent: bool = false
var request_deadline: int = 0
var sequences: Dictionary = {}
var results: Array = []
var disconnected_players: Dictionary = {}
# Local monotonic RTT only; never part of vehicle snapshots or persistent state.
const LATENCY_INTERVAL_MS: int = 1000
const LATENCY_TIMEOUT_MS: int = 5000
var latency_ms: int = -1
var latency_samples: Array[int] = []
var latency_nonce: int = 0
var latency_pending: int = -1
var latency_sent: int = 0
var latency_next: int = 0
var latency_received: int = 0
var latency_session: String = ""
func _reset_latency() -> void:
	latency_ms = -1
	latency_samples.clear()
	latency_pending = -1
	latency_next = 0
	latency_received = 0
	latency_session = ""
func latency_tick() -> void:
	if transport==null or phase not in ["CONNECTED","LOBBY","LOADING","COUNTDOWN","RACING"]:
		_reset_latency()
		return
	if context_valid.is_valid() and not bool(context_valid.call()):
		_reset_latency()
		return
	var session: String = String(room.get("session",""))
	if session!=latency_session:
		_reset_latency()
		latency_session = session
	var now: int = Time.get_ticks_msec()
	if latency_received>0 and now-latency_received>=LATENCY_TIMEOUT_MS:
		latency_ms = -1
		latency_samples.clear()
	if latency_pending>=0:
		if now-latency_sent<LATENCY_TIMEOUT_MS: return
		latency_pending = -1
		latency_ms = -1
		latency_samples.clear()
	if now<latency_next: return
	latency_next = now+LATENCY_INTERVAL_MS
	latency_nonce = (latency_nonce+1)%2147483647
	if transport.send({"v":PROTOCOL_VERSION,"type":"latency_ping","generation":generation,"session":session,"nonce":latency_nonce}):
		latency_pending = latency_nonce
		latency_sent = now
func latency_text() -> String:
	if latency_ms<0 or Time.get_ticks_msec()-latency_received>=LATENCY_TIMEOUT_MS: return "PING -- ms"
	var quality: String = "GOOD" if latency_ms<80 else ("OK" if latency_ms<150 else ("HIGH" if latency_ms<250 else "VERY HIGH"))
	return "PING %d ms • %s"%[latency_ms,quality]
func _latency_pong(packet: Dictionary) -> void:
	if latency_pending<0 or not integer(packet.get("nonce"),0,2147483647): return
	if int(packet.nonce)!=latency_pending or packet.get("session")!=latency_session: return
	if latency_session!=String(room.get("session","")): return
	var elapsed: int = Time.get_ticks_msec()-latency_sent
	latency_pending = -1
	if elapsed<0 or elapsed>=LATENCY_TIMEOUT_MS: return
	latency_received = Time.get_ticks_msec()
	latency_samples.append(elapsed)
	if latency_samples.size()>3: latency_samples.pop_front()
	var total: int = 0
	for sample: int in latency_samples: total += sample
	latency_ms = roundi(float(total)/float(latency_samples.size()))
func attach(value: RushDuelProvider) -> void:
	transport = value
	transport.received.connect(_receive)
	transport.disconnected.connect(_lost)
func leave() -> void:
	_reset_latency()
	generation += 1
	if transport!=null: transport.close()
	room.clear()
	sequences.clear()
	results.clear()
	disconnected_players.clear()
	last_revision = -1
	finish_sent = false
	pending = ""
	phase = "OFFLINE"
	changed.emit()
func _lost() -> void:
	leave()
	status = "Connection lost. Race cancelled; no rewards were issued."
	race_event.emit({"type":"cancelled"})
	changed.emit()
func action(kind: String, data: Dictionary = {}) -> bool:
	if transport==null or phase=="OFFLINE" or not pending.is_empty(): return false
	if kind in ["create","join","quick_join"] and phase!="CONNECTED": return false
	if kind=="ready":
		if phase!="LOBBY": return false
		for player: Dictionary in room.get("players",[]):
			if player.uid==account_id and player.ready: return false
	if kind=="start":
		if phase!="LOBBY" or String(room.get("host",""))!=account_id or room.get("players",[]).size()<MIN_PLAYERS or room.get("players",[]).size()>MAX_PLAYERS: return false
		for player: Dictionary in room.players:
			if not player.ready: return false
	if kind=="finish":
		if phase!="RACING" or finish_sent: return false
		finish_sent = true
	var packet: Dictionary = data.duplicate(true)
	packet.merge({"v":PROTOCOL_VERSION,"type":kind,"generation":generation,"session":room.get("session","")},true)
	if not transport.send(packet):
		if kind=="finish": finish_sent = false
		return false
	if kind in ["create","join","quick_join","start","ready"]:
		pending = kind
		request_deadline = Time.get_ticks_msec()+20000
	changed.emit()
	return true
static func number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high
static func integer(value: Variant, low: int, high: int) -> bool:
	return number(value,low,high) and float(value)==floor(float(value))
static func text(value: Variant, limit: int) -> bool:
	return value is String and not value.is_empty() and value.length()<=limit
func _receive(packet: Dictionary) -> void:
	if context_valid.is_valid() and not bool(context_valid.call()):
		_lost()
		return
	if packet.get("v")!=PROTOCOL_VERSION or not packet.get("type") is String: return
	var kind: String = packet.type
	if kind=="ping":
		transport.send({"v":PROTOCOL_VERSION,"type":"pong"})
		return
	if kind=="authenticated" and phase=="CONNECTING":
		if packet.get("uid")!=account_id: _lost(); return
		phase = "CONNECTED"
		status = "Connected — create or join a room."
		changed.emit()
		return
	if not integer(packet.get("generation"),0,2147483647) or int(packet.generation)!=generation: return
	if kind=="latency_pong":
		_latency_pong(packet)
		return
	if kind=="error":
		pending = ""
		status = "Room request failed. Check the code or retry."
		changed.emit()
		return
	if kind=="room":
		if phase not in ["CONNECTED","LOBBY"] or not text(packet.get("session"),128) or not text(packet.get("code"),8) or not packet.get("players") is Array: return
		if not room.is_empty() and packet.session!=room.session: return
		if not integer(packet.get("revision"),0,2147483647) or int(packet.revision)<=last_revision: return
		var players: Array = packet.players
		if players.size()<1 or players.size()>MAX_PLAYERS or packet.get("map")!="highway": return
		if packet.get("visibility") not in ["PUBLIC","PRIVATE"]: return
		var ids: Array[String] = []
		for player: Variant in players:
			if not player is Dictionary: return
			if not text(player.get("uid"),128) or not text(player.get("name"),24) or not player.get("ready") is bool: return
			if player.get("car") not in RushVehicleCatalog.PLAYABLE_IDS or not integer(player.get("paint"),0,RushVehicleCatalog.paint_count()-1): return
			if player.uid in ids or not integer(player.get("grid"),0,MAX_PLAYERS-1) or int(player.grid)!=ids.size(): return
			ids.append(player.uid)
		if account_id not in ids or packet.get("host") not in ids: return
		room = packet.duplicate(true)
		last_revision = int(packet.revision)
		pending = ""
		phase = "LOBBY"
		status = "HIGHWAY • 2 KM • UNRANKED • NO CURRENCY REWARDS"
		changed.emit()
		return
	if room.is_empty() or packet.get("session")!=room.session: return
	if kind=="countdown":
		if phase!="LOBBY" or room.players.size()<MIN_PLAYERS or room.players.size()>MAX_PLAYERS: return
		for player: Dictionary in room.players:
			if not player.ready: return
		phase = "LOADING"
		phase_deadline = Time.get_ticks_msec()+75000
		pending = ""
	elif kind=="tick":
		if phase!="COUNTDOWN" or not integer(packet.get("count"),1,3): return
	elif kind=="go":
		if phase!="COUNTDOWN": return
		phase = "RACING"
		phase_deadline = Time.get_ticks_msec()+750000
	elif kind=="snapshot":
		if phase!="RACING" or not _snapshot_valid(packet): return
	elif kind=="player_left":
		if phase not in ["LOADING","COUNTDOWN","RACING"] or not _member(packet.get("uid")) or packet.uid==account_id: return
		disconnected_players[packet.uid] = true
	elif kind=="results":
		if phase!="RACING" or not packet.get("order") is Array or packet.order.size()!=room.players.size(): return
		if not packet.get("standings") is Array or packet.standings.size()!=packet.order.size(): return
		var seen: Array[String] = []
		for i: int in packet.order.size():
			var id: Variant = packet.order[i]
			var row: Variant = packet.standings[i]
			if not _member(id) or id in seen or not row is Dictionary: return
			if row.get("uid")!=id or row.get("status") not in ["FINISHED","DNF","DISCONNECTED"]: return
			seen.append(String(id))
		results = packet.standings.duplicate(true)
		phase = "RESULTS"
	elif kind=="cancelled":
		phase = "CANCELLED"
	else: return
	race_event.emit(packet)
	if kind!="snapshot": changed.emit()
func _snapshot_valid(p: Dictionary) -> bool:
	var other: String = String(p.get("uid",""))
	if not _member(other) or other==account_id or disconnected_players.has(other) or not integer(p.get("seq"),0,2147483647): return false
	if int(p.seq)<=int(sequences.get(other,-1)): return false
	for key: String in ["position","velocity"]:
		if not p.get(key) is Array or p[key].size()!=3: return false
		for value: Variant in p[key]:
			if not number(value,-2200,2200): return false
	if not number(p.get("yaw"),-PI,PI) or not number(p.get("steer"),-1.5,1.5) or not number(p.get("progress"),0,1) or not p.get("finished") is bool: return false
	if absf(float(p.position[0]))>15 or absf(float(p.position[1]))>3 or float(p.position[2])>20 or float(p.position[2])< -2050: return false
	var v: Vector3 = Vector3(float(p.velocity[0]),float(p.velocity[1]),float(p.velocity[2]))
	if v.length()>150: return false
	sequences[other] = int(p.seq)
	return true

func _member(id: Variant) -> bool:
	if not id is String: return false
	for player: Dictionary in room.get("players",[]):
		if player.uid==id: return true
	return false

static func grid_position(index: int, player_count: int = MAX_PLAYERS) -> Vector3:
	# Same start line, 3 m between centers; five cars fit within the road bounds.
	var count: int = clampi(player_count,MIN_PLAYERS,MAX_PLAYERS)
	return Vector3((float(index)-float(count-1)*0.5)*3.0,0.0,0.0)
