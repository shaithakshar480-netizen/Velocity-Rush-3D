class_name RushDuelWebSocket
extends RushDuelProvider
var socket: WebSocketPeer
var credential: String = ""
var authenticated_request: bool = false
var deadline: int = 0
var last_received: int = 0
func open(endpoint: String, token: String) -> bool:
	close()
	if not endpoint.begins_with("wss://") or token.is_empty(): return false
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 65536
	socket.outbound_buffer_size = 65536
	credential = token
	deadline = Time.get_ticks_msec()+20000
	last_received = Time.get_ticks_msec()
	if socket.connect_to_url(endpoint)!=OK:
		close()
		return false
	return true
func send(packet: Dictionary) -> bool:
	if socket==null or socket.get_ready_state()!=WebSocketPeer.STATE_OPEN or socket.get_current_outbound_buffered_amount()>32768: return false
	return socket.send_text(JSON.stringify(packet))==OK
func close() -> void:
	if socket!=null: socket.close()
	socket = null
	credential = ""
	authenticated_request = false
func _process(_delta: float) -> void:
	if socket==null: return
	socket.poll()
	var state: int = socket.get_ready_state()
	if state==WebSocketPeer.STATE_CLOSED or Time.get_ticks_msec()-last_received>20000 or (not authenticated_request and Time.get_ticks_msec()>deadline):
		close()
		disconnected.emit()
		return
	if state!=WebSocketPeer.STATE_OPEN: return
	if not authenticated_request:
		authenticated_request = send({"v":RushDuelService.PROTOCOL_VERSION,"type":"authenticate","token":credential})
		credential = ""
	for _i: int in 32:
		if socket.get_available_packet_count()==0: break
		var bytes: PackedByteArray = socket.get_packet()
		if bytes.size()>8192:
			close()
			disconnected.emit()
			return
		var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if value is Dictionary:
			last_received = Time.get_ticks_msec()
			received.emit(value)
			if socket==null: return
