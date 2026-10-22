extends Node
signal changed
signal completed
var provider: RushFirebaseProvider = RushFirebaseProvider.new()
var user: Dictionary = {}
var busy: bool = false
var generation: int = 0
var chosen: bool = false
var message: String = ""
var preference: ConfigFile = ConfigFile.new()
var can_change_account: Callable
var native_bridge: RushAndroidCredentialBridge
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if preference.load("user://account.cfg")==OK:
		chosen = bool(preference.get_value("account","chosen",false))
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://Data/FirebaseConfig.json"))
	if raw is Dictionary:
		var rest: RushFirebaseRestProvider = RushFirebaseRestProvider.new()
		rest.initialize(self,raw)
		provider = rest
		native_bridge = RushAndroidCredentialBridge.new()
		add_child(native_bridge)
		var bound: bool = await native_bridge.bind(rest,raw)
		print("[VelocityRushAuth] ANDROID_BRIDGE_BOUND:"+("true" if bound else "false"))
func configure(adapter: RushFirebaseProvider) -> void:
	generation += 1
	provider.cancel_pending()
	busy = false
	user.clear()
	provider = adapter
	changed.emit()
func remember() -> void:
	chosen = true
	preference.set_value("account","chosen",true)
	if preference.save("user://account.pending.cfg")==OK:
		DirAccess.rename_absolute("user://account.pending.cfg","user://account.cfg")
func sign_in_as_guest() -> void:
	# Local choice is immediate; anonymous network failure cannot block Home.
	if not user.is_empty() and is_guest() and not SaveService.bootstrap_pending:
		completed.emit()
		return
	if busy or not _scope_change_safe(): return
	provider.cancel_pending()
	if not SaveService.bind_account(""):
		message = "Could not open Guest storage. Existing saves are safe."
		changed.emit()
		return
	generation += 1
	provider.sign_out()
	user.clear()
	preference.set_value("account","mode","guest")
	preference.set_value("account","had_cloud_identity",false)
	remember()
	message = "Playing as Guest. Local progress is safe."
	SaveService.publish_account_scope()
	changed.emit()
	completed.emit()
	request("anonymous")
func sign_out() -> void:
	RushAuthDiagnostics.stage("LOGOUT_REQUESTED")
	if busy or not _scope_change_safe(): return
	provider.cancel_pending()
	if not SaveService.bind_account(""):
		message = "Could not save this account before signing out. Please retry."
		changed.emit()
		return
	generation += 1
	busy = false
	provider.sign_out()
	user.clear()
	chosen = false
	preference.set_value("account","chosen",false)
	preference.set_value("account","mode","logged_out")
	preference.set_value("account","had_cloud_identity",false)
	if preference.save("user://account.pending.cfg")==OK:
		DirAccess.rename_absolute("user://account.pending.cfg","user://account.cfg")
	message = "Signed out. Local progress is safe."
	SaveService.publish_account_scope()
	RushAuthDiagnostics.stage("LOGOUT_AUTH_CLEARED")
	changed.emit()
func sign_in_with_google() -> void:
	print("[VelocityRushAuth] AUTH_SERVICE_GOOGLE_REQUEST")
	request("link_google" if is_authenticated() and is_guest() else "google")
func link_guest_to_google() -> void:
	print("[VelocityRushAuth] AUTH_SERVICE_GOOGLE_REQUEST")
	if not is_guest(): return
	request("link_google" if is_authenticated() else "google")
func restore_session() -> void:
	request("restore")
func request(operation: String) -> void:
	if busy:
		RushAuthDiagnostics.stage("AUTH_REQUEST_BLOCKED:BUSY")
		return
	if not _scope_change_safe(): return
	if not provider.available():
		RushAuthDiagnostics.stage("AUTH_REQUEST_BLOCKED:PROVIDER_UNAVAILABLE")
		message = "Cloud connection unavailable. Local progress is safe."
		changed.emit()
		return
	var carry_guest: bool = chosen and is_guest() and (operation in ["link_google","anonymous"] or (operation=="google" and String(preference.get_value("account","mode",""))=="guest"))
	provider.cancel_pending()
	busy = true
	changed.emit()
	generation += 1
	var ticket: int = generation
	provider.authenticate(operation,func(ok: bool, identity: Dictionary) -> void:
		if ticket!=generation or not busy:
			return
		busy = false
		var uid: String = String(identity.get("uid",""))
		if ok and not uid.is_empty() and not uid.contains("/"):
			if operation=="anonymous" and (RewardService.active_run!=0 or (can_change_account.is_valid() and not bool(can_change_account.call()))):
				# Guest play may begin before its optional network request finishes.
				# Do not switch storage underneath that run or sign the local Guest out.
				provider.sign_out()
				message = "Playing as Guest. Cloud connection can be retried after this drive."
				changed.emit()
				return
			if not SaveService.bind_account(uid,carry_guest):
				provider.sign_out()
				user.clear()
				chosen = false
				message = "Account storage could not be opened. Existing saves are safe."
				changed.emit()
				return
			user = {"uid":uid,"email":String(identity.get("email","")),"display_name":String(identity.get("display_name","")),"provider":String(identity.get("provider","google")),"is_guest":bool(identity.get("is_guest",false))}
			if operation=="anonymous" and bool(user.is_guest) and SaveService.bootstrap_pending:
				# signUp created this anonymous UID; keep its carried Guest cache playable
				# offline. Google/restored accounts still require the remote bootstrap gate.
				if not SaveService.finish_new_account():
					message = "Guest progress could not be saved. Please retry."
			preference.set_value("account","mode","guest" if bool(user.is_guest) else "google")
			preference.set_value("account","had_cloud_identity",true)
			remember()
			message = "Account connected."
			SaveService.publish_account_scope()
			RushAuthDiagnostics.stage("AUTH_STATE_UPDATED")
			# The account screen remains until a missing cache has been checked remotely.
			if not SaveService.bootstrap_pending: completed.emit()
		else:
			message = "Playing as Guest — cloud connection unavailable." if operation=="anonymous" else ("Sign-in cancelled." if provider.last_error_code=="CANCELLED" else "Could not connect your account. Local progress is safe.")
			if operation=="restore" and String(preference.get_value("account","mode","guest"))=="guest" and not bool(preference.get_value("account","had_cloud_identity",false)):
				request.call_deferred("anonymous")
		changed.emit())
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		if ticket==generation and busy:
			generation += 1
			provider.cancel_pending()
			busy = false
			message = "Connection timed out. You can play offline."
			RushAuthDiagnostics.stage("AUTH_REQUEST_FAILED:TIMEOUT")
			changed.emit())
func current_user_id() -> String:
	return String(user.get("uid",""))
func current_user_email() -> String:
	return String(user.get("email",""))
func current_display_name() -> String:
	return String(user.get("display_name",""))
func is_guest() -> bool:
	return bool(user.get("is_guest",true))
func is_authenticated() -> bool:
	return not current_user_id().is_empty()

func _scope_change_safe() -> bool:
	if SaveService.transaction_busy or RewardService.active_run!=0 or (can_change_account.is_valid() and not bool(can_change_account.call())):
		message = "Finish the current activity before switching accounts."
		changed.emit()
		return false
	return true
