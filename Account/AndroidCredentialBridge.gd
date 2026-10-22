class_name RushAndroidCredentialBridge
extends Node
## This project's native plugin contract, not an assumed third-party addon API.
const CAPABILITIES: String = "rushfirebase:v1:configure,requestGoogleToken,cancelPicker,secureLoad,secureSave,secureClear,clearGoogleSession,google_result"
var bound: bool = false
var native: Object
var provider: RushFirebaseRestProvider
var pending_callback: Callable
var request_id: int = 0
func bind(rest: RushFirebaseRestProvider, values: Dictionary) -> bool:
	# Rebinding cannot retain callables from a previously accepted native instance.
	cancel()
	if is_instance_valid(native) and native.is_connected("google_result",_result):
		native.disconnect("google_result",_result)
	bound = false
	provider = rest
	provider.google_token = Callable()
	provider.google_cancel = Callable()
	provider.secure_load = Callable()
	provider.secure_save = Callable()
	provider.secure_clear = Callable()
	provider.google_sign_out = Callable()
	print("[VelocityRushAuth] ANDROID_BRIDGE_BIND")
	print("[VelocityRushAuth] ANDROID_PLATFORM_CHECK:"+("true" if OS.has_feature("android") else "false"))
	print("[VelocityRushAuth] SINGLETON_CHECK:"+("true" if Engine.has_singleton("RushFirebaseBridge") else "false"))
	if not OS.has_feature("android") or not Engine.has_singleton("RushFirebaseBridge"): return false
	native = Engine.get_singleton("RushFirebaseBridge")
	if not is_instance_valid(native):
		return false
	print("[VelocityRushAuth] BRIDGE_CAPABILITY_REQUEST")
	# GDScript has no try/catch. A deferred probe isolates a stale-AAR call error;
	# if the probe aborts, this bounded await still fails closed and Guest survives.
	var probe: Dictionary = {"complete":false,"value":null}
	_probe_capabilities.call_deferred(probe)
	var deadline: int = Time.get_ticks_msec()+1000
	while not bool(probe.complete) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	var valid: bool = bool(probe.complete) and probe.value is String and probe.value==CAPABILITIES
	var status: String = "ACCEPTED" if valid else ("REJECTED" if bool(probe.complete) else "NO_RESPONSE")
	print("[VelocityRushAuth] BRIDGE_CAPABILITY_RESULT:"+status)
	print("[VelocityRushAuth] BRIDGE_CAPABILITY_VALID:"+("true" if valid else "false"))
	if not valid:
		return false
	if not native.has_signal("google_result"):
		print("[VelocityRushAuth] BRIDGE_BIND_MISSING_SIGNAL:google_result")
		return false
	var project_id: String = String(values.get("firebase_project_id",""))
	var web_client_id: String = String(values.get("web_client_id",""))
	print("[VelocityRushAuth] CONFIG_PROJECT_ID_PRESENT:"+("true" if not project_id.is_empty() else "false"))
	print("[VelocityRushAuth] CONFIG_PROJECT_ID_MATCH_EXPECTED:"+("true" if project_id=="velocity-rush-3d" else "false"))
	print("[VelocityRushAuth] CONFIG_WEB_CLIENT_ID_PRESENT:"+("true" if not web_client_id.is_empty() else "false"))
	print("[VelocityRushAuth] CONFIG_WEB_CLIENT_ID_SUFFIX_VALID:"+("true" if web_client_id.ends_with(".apps.googleusercontent.com") else "false"))
	var configured: Variant = native.call("configure",web_client_id,project_id)
	var configured_type: int = typeof(configured)
	print("[VelocityRushAuth] BRIDGE_CONFIGURE_RETURN_TYPE:"+type_string(configured_type))
	print("[VelocityRushAuth] BRIDGE_CONFIGURE_RETURN_NIL:"+("true" if configured_type==TYPE_NIL else "false"))
	var configure_accepted: bool = false
	# This engine's JNI jboolean return uses an integer Variant (0 or 1).
	# Accept only explicit success; never coerce arbitrary truthy values.
	match configured_type:
		TYPE_BOOL:
			print("[VelocityRushAuth] BRIDGE_CONFIGURE_RETURN_BOOL:"+("true" if configured==true else "false"))
			configure_accepted = configured==true
		TYPE_INT:
			print("[VelocityRushAuth] BRIDGE_CONFIGURE_RETURN_INT:"+str(configured))
			configure_accepted = configured==1
	if not configure_accepted:
		print("[VelocityRushAuth] BRIDGE_CONFIGURE_REJECTED")
		return false
	if not native.is_connected("google_result",_result):
		var connection_error: int = native.connect("google_result",_result,CONNECT_DEFERRED)
		if connection_error!=OK:
			print("[VelocityRushAuth] BRIDGE_SIGNAL_CONNECT_FAILED")
			return false
	bound = true
	provider.google_token = request_token
	provider.google_cancel = cancel
	provider.secure_load = func() -> String: return String(native.call("secureLoad"))
	provider.secure_save = func(token: String) -> bool: return bool(native.call("secureSave",token))
	provider.secure_clear = func() -> void: native.call("secureClear")
	provider.google_sign_out = func() -> void: native.call("clearGoogleSession")
	return true
func _probe_capabilities(probe: Dictionary) -> void:
	if not is_instance_valid(native):
		probe.complete = true
		return
	probe.value = native.call("getBridgeCapabilities")
	probe.complete = true

func request_token(callback: Callable) -> void:
	print("[VelocityRushAuth] ANDROID_BRIDGE_REQUEST")
	print("[VelocityRushAuth] SINGLETON_CHECK:"+("true" if Engine.has_singleton("RushFirebaseBridge") else "false"))
	if not bound or not is_instance_valid(native):
		print("[VelocityRushAuth] ANDROID_BRIDGE_BLOCKED:NOT_BOUND")
		callback.call(false,"")
		return
	if pending_callback.is_valid():
		print("[VelocityRushAuth] ANDROID_BRIDGE_BLOCKED:BUSY")
		callback.call(false,"")
		return
	request_id = request_id%2147483646+1
	pending_callback = callback
	print("[VelocityRushAuth] NATIVE_METHOD_INVOKE")
	native.call("requestGoogleToken",request_id)
func _result(ticket: int, ok: bool, token: String, code: String) -> void:
	RushAuthDiagnostics.stage("GODOT_GOOGLE_CALLBACK_RECEIVED")
	if ticket!=request_id or not pending_callback.is_valid():
		RushAuthDiagnostics.stage("GODOT_GOOGLE_CALLBACK_IGNORED:STALE")
		return
	var callback: Callable = pending_callback
	pending_callback = Callable()
	if not ok: provider.last_error_code = "CANCELLED" if code=="CANCELLED" else "GOOGLE_UNAVAILABLE"
	callback.call(ok and not token.is_empty(),token if ok else "")
func cancel() -> void:
	request_id = request_id%2147483646+1
	pending_callback = Callable()
	if bound and is_instance_valid(native): native.call("cancelPicker")
func _exit_tree() -> void:
	cancel()
	if is_instance_valid(native) and native.is_connected("google_result",_result):
		native.disconnect("google_result",_result)
