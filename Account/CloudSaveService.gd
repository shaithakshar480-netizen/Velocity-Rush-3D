extends Node
signal changed
var status: String = "NOT_CONNECTED"
var pending: bool = true
var busy: bool = false
var fetching: bool = false
var blocked: bool = false
var delay_left: float = 4.0
var backoff: float = 5.0
var epoch: int = 0
var account_uid: String = ""
var can_restore: Callable
var restoring: bool = false
var poll_left: float = 5.0
var bound_scope_generation: int = -1
var skip_reason: String = ""
var bootstrap_started_ms: int = 0
var first_upload_pending: bool = false
var confirmed_absent: Dictionary = {}
var foreground: bool = true
var retry_count: int = 0
var progress_state: String = ""
var recheck_left: float = 15.0
var force_full_read: bool = false
var bound_auth_generation: int = -1
func retry_reconciliation() -> void:
	if not AuthService.is_authenticated() or AuthService.busy or busy: return
	blocked = false
	force_full_read = true
	confirmed_absent.clear()
	pending = true
	delay_left = 0.0
	recheck_left = 15.0
	RushAuthDiagnostics.stage("CLOUD_CONFLICT_RECHECK_START")
func _progress(value: String) -> void:
	if value!=progress_state:
		progress_state = value
		RushAuthDiagnostics.stage("ACCOUNT_PROGRESS_STATE:"+value)
		RushAuthDiagnostics.stage("ACCOUNT_PROGRESS_WAIT_MS:"+str(maxi(0,Time.get_ticks_msec()-bootstrap_started_ms)))
func _fetch_remote(uid: String, callback: Callable) -> void:
	# Consume the authoritative absence once; compare_and_set still rechecks and
	# uses exists:false preconditions, so another device cannot be overwritten.
	if not confirmed_absent.is_empty() and uid==account_uid and bound_scope_generation==SaveService.scope_generation:
		var remote: Dictionary = confirmed_absent
		confirmed_absent = {}
		callback.call(true,remote)
		return
	var marker: Dictionary = SaveService.cloud_meta
	if force_full_read:
		force_full_read = false
		AuthService.provider.fetch_save(uid,callback)
		return
	if not SaveService.bootstrap_pending and not bool(marker.get("repair",false)) and String(marker.get("owner",""))==uid and String(marker.get("local_digest",""))==RushFirestoreCodec.digest(snapshot()):
		AuthService.provider.poll_save(uid,marker.get("versions",{}),callback)
	else: AuthService.provider.fetch_save(uid,callback)
func _bootstrap_stage(marker: String) -> void:
	RushAuthDiagnostics.stage(marker)
	RushAuthDiagnostics.stage(marker+"_ELAPSED_MS:"+str(maxi(0,Time.get_ticks_msec()-bootstrap_started_ms)))
func _poll_skipped(reason: String) -> void:
	if skip_reason!=reason:
		skip_reason = reason
		RushAuthDiagnostics.stage("REMOTE_POLL_SKIPPED:"+reason)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RushAuthDiagnostics.stage("REMOTE_POLL_INTERVAL_MS:5000")
	SaveService.committed.connect(schedule)
	AuthService.changed.connect(account_changed)
	account_changed.call_deferred()
func account_changed() -> void:
	if AuthService.busy:
		confirmed_absent.clear()
		epoch += 1
		busy = false
		fetching = false
		schedule()
		return
	var uid: String = AuthService.current_user_id()
	if uid!=SaveService.scope_uid and not uid.is_empty():
		conflict()
		return
	if uid.is_empty():
		# Signed out/local Guest is not a failed network request. Keep persisted markers.
		confirmed_absent.clear()
		account_uid = ""
		bound_scope_generation = -1
		poll_left = 5.0
		first_upload_pending = false
		skip_reason = ""
		epoch += 1
		busy = false
		fetching = false
		blocked = false
		pending = false
		backoff = 5.0
		delay_left = 3.0
		set_status("NOT_CONNECTED")
		return
	if uid==account_uid and bound_scope_generation==SaveService.scope_generation:
		if bound_auth_generation!=AuthService.generation:
			bound_auth_generation = AuthService.generation
			retry_reconciliation()
		if AuthService.provider.last_error_code=="ACCOUNT_COLLISION":
			conflict()
			return
		if not uid.is_empty(): schedule()
		return
	confirmed_absent.clear()
	account_uid = uid
	retry_count = 0
	progress_state = ""
	bound_auth_generation = AuthService.generation
	force_full_read = true
	recheck_left = 15.0
	bound_scope_generation = SaveService.scope_generation
	fetching = false
	poll_left = 5.0
	pending = true
	skip_reason = ""
	first_upload_pending = false
	RushAuthDiagnostics.stage("REMOTE_POLL_ACCOUNT_BOUND:true")
	if SaveService.bootstrap_pending:
		bootstrap_started_ms = Time.get_ticks_msec()
		_bootstrap_stage("ACCOUNT_BOOTSTRAP_START")
	# A newly connected account must not inherit the previous session's retry delay.
	delay_left = 0.0
	backoff = 5.0
	epoch += 1
	busy = false
	blocked = false
	var owner: String = String(SaveService.cloud_meta.get("owner",""))
	if SaveService.guest_import_pending and not SaveService.bootstrap_pending:
		conflict()
	elif not uid.is_empty() and not owner.is_empty() and uid!=owner:
		conflict()
	else:
		delay_left = 0.0
		set_status("SYNCING")
func set_status(value: String) -> void:
	status = value
	if value in ["SYNCED","ERROR","OFFLINE","CONFLICT","NOT_CONNECTED"]:
		RushAuthDiagnostics.stage("CLOUD_RECONCILIATION_RESULT:"+value)
	changed.emit()
func schedule() -> void:
	pending = true
	delay_left = maxf(delay_left,3.0)
func _process(delta: float) -> void:
	if not foreground:
		_poll_skipped("BACKGROUND")
		return
	if not AuthService.is_authenticated():
		_poll_skipped("NOT_CONNECTED")
		return
	if blocked and not AuthService.busy and not busy:
		recheck_left -= delta
		if recheck_left<=0: retry_reconciliation()
	if busy or blocked or AuthService.busy:
		_poll_skipped(("CONFLICT" if status=="CONFLICT" else "VALIDATION_OR_PROVIDER_ERROR") if blocked else ("AUTH_BUSY" if AuthService.busy else "REQUEST_BUSY"))
		return
	if account_uid!=AuthService.current_user_id() or account_uid!=SaveService.scope_uid or bound_scope_generation!=SaveService.scope_generation:
		_poll_skipped("SCOPE_CHANGED")
		account_changed()
		return
	if bool(AuthService.provider.cloud_diagnostics(account_uid).get("request_busy",false)):
		_poll_skipped("PROVIDER_REQUEST_BUSY")
		return
	if SaveService.transaction_busy or not can_restore.is_valid() or not bool(can_restore.call()):
		_poll_skipped("UNSAFE_SCREEN_OR_TRANSACTION")
		return
	if not pending:
		poll_left -= delta
		if poll_left>0: return
		if not can_restore.is_valid() or not bool(can_restore.call()):
			_poll_skipped("UNSAFE_SCREEN")
			return
		pending = true
		delay_left = 0.0
		poll_left = 5.0
		RushAuthDiagnostics.stage("CLOUD_REMOTE_POLL")
	skip_reason = ""
	delay_left -= delta
	if delay_left<=0: sync()
func snapshot(envelope: Dictionary = {}, sparse_override: int = -1, trace: bool = false, retained_cars: Array = []) -> Dictionary:
	var local: Dictionary = SaveService.cloud_envelope() if envelope.is_empty() else envelope
	if trace:
		_trace_flag("CLOUD_LOCAL_SAVE_FILE_EXISTS",FileAccess.file_exists(SaveService.PATH))
		_trace_flag("CLOUD_LOCAL_SNAPSHOT_AVAILABLE",not local.is_empty())
		_trace_flag("CLOUD_LOCAL_SNAPSHOT_VALID",not local.is_empty())
		if local.is_empty():
			RushAuthDiagnostics.stage("CLOUD_RECONCILE_PRECHECK_FAILED:"+("INVALID_LOCAL_SNAPSHOT" if FileAccess.file_exists(SaveService.PATH) else "NO_LOCAL_SNAPSHOT"))
	if local.is_empty(): return {}
	var p: Dictionary = local.progression
	var c: Dictionary = local.collection
	var docs: Dictionary = {}
	docs["profile"] = {"display_name":p.get("name","Racer"),"email":AuthService.current_user_email(),"provider":AuthService.user.get("provider","anonymous"),"is_guest":AuthService.is_guest(),"schema_version":5,"coins":local.wallet.coins,"level":p.get("level",1),"xp":p.get("xp",0),"selected_car":c.get("selected","vortex_s")}
	docs["progression/main"] = p.duplicate(true)
	docs["inventory/main"] = local.consumables.duplicate(true)
	var sparse: bool = (SaveService.cloud_meta.is_empty() or bool(SaveService.cloud_meta.get("sparse_cars",false))) if sparse_override<0 else sparse_override==1
	for id: String in RushVehicleCatalog.IDS:
		if sparse and id not in c.owned and id not in retained_cars and id not in SaveService.cloud_meta.get("car_documents",[]): continue
		docs["cars/"+id] = {"owned":id in c.owned,"custom_name":c.get("names",{}).get(id,""),"paint_index":c.get("paints",{}).get(id,0),"upgrades":c.get("upgrades",{}).get(id,{})}
	docs["meta/main"] = {"settings":local.settings,"onboarding":local.onboarding,"wallet_ledger":local.wallet,"purchase_claims":local.store_claims,"membership_cache":local.membership,"upgrade_ads":c.get("upgrade_ads",{})}
	return docs
func _trace_flag(marker: String, value: bool) -> void:
	RushAuthDiagnostics.stage(marker+(":true" if value else ":false"))
func sync() -> void:
	RushAuthDiagnostics.stage("CLOUD_SYNC_START")
	RushAuthDiagnostics.stage("CLOUD_AUTH_AVAILABLE:"+("true" if AuthService.is_authenticated() else "false"))
	RushAuthDiagnostics.stage("CLOUD_UID_AVAILABLE:"+("true" if not account_uid.is_empty() else "false"))
	var diagnostic: Dictionary = AuthService.provider.cloud_diagnostics(account_uid)
	_trace_flag("CLOUD_ID_TOKEN_AVAILABLE",bool(diagnostic.get("token_available",false)))
	var provider_available: bool = AuthService.provider.available()
	_trace_flag("CLOUD_PROVIDER_AVAILABLE",provider_available)
	_trace_flag("CLOUD_PROVIDER_CONFIGURED",bool(diagnostic.get("configured",false)))
	_trace_flag("CLOUD_PROVIDER_SUPPORTED",bool(diagnostic.get("supported",false)))
	_trace_flag("CLOUD_PROVIDER_HOST_AVAILABLE",bool(diagnostic.get("host_available",false)))
	_trace_flag("CLOUD_PROVIDER_APP_CHECK_READY",bool(diagnostic.get("app_check_ready",false)))
	_trace_flag("CLOUD_PROVIDER_IDENTITY_MATCH",bool(diagnostic.get("identity_match",false)))
	_trace_flag("CLOUD_PROVIDER_REQUEST_BUSY",bool(diagnostic.get("request_busy",false)))
	_trace_flag("CLOUD_LOCAL_REVISION_AVAILABLE",SaveService.cloud_meta.has("revision"))
	# An absent revision is valid for a first sync; diagnostics never invent one.
	if not provider_available:
		var reason: String = "UNSUPPORTED_STATE"
		if not bool(diagnostic.get("supported",false)): reason = "INVALID_PROVIDER"
		elif not bool(diagnostic.get("configured",false)): reason = "PROVIDER_NOT_CONFIGURED"
		elif not bool(diagnostic.get("host_available",false)): reason = "PROVIDER_HOST_UNAVAILABLE"
		elif not bool(diagnostic.get("app_check_ready",false)): reason = "APP_CHECK_UNAVAILABLE"
		RushAuthDiagnostics.stage("CLOUD_RECONCILE_PRECHECK_FAILED:"+reason)
		delay_left = 60.0
		set_status("ERROR")
		return
	# Missing/expired ID tokens may be refreshed by _authorized(); don't bypass it.
	var docs: Dictionary = snapshot({},-1,true)
	if docs.is_empty():
		failed()
		return
	if SaveService.bootstrap_pending: _progress("LOADING")
	busy = true
	fetching = true
	epoch += 1
	var ticket: int = epoch
	var uid: String = account_uid
	var scope_ticket: int = SaveService.scope_generation
	var digest_value: String = RushFirestoreCodec.digest(docs)
	set_status("SYNCING")
	RushAuthDiagnostics.stage("CLOUD_RECONCILIATION_START")
	if SaveService.bootstrap_pending: _bootstrap_stage("ACCOUNT_BOOTSTRAP_REMOTE_CHECK_START")
	_fetch_remote(uid,func(ok: bool, remote: Dictionary) -> void:
		if ticket!=epoch or not busy or not fetching or scope_ticket!=SaveService.scope_generation or uid!=AuthService.current_user_id() or uid!=SaveService.scope_uid:
			_poll_skipped("STALE_CALLBACK")
			return
		RushAuthDiagnostics.stage("REMOTE_POLL_GENERATION_VALID:true")
		if SaveService.bootstrap_pending: _bootstrap_stage("ACCOUNT_BOOTSTRAP_REMOTE_CHECK_DONE")
		fetching = false
		if not ok:
			failed()
			return
		if bool(remote.get("unchanged",false)):
			busy = false
			pending = RushFirestoreCodec.digest(snapshot())!=digest_value
			delay_left = 0.0
			poll_left = 5.0
			retry_count = 0
			set_status("SYNCED")
			return
		_trace_flag("ACCOUNT_REMOTE_SAVE_AVAILABLE",bool(remote.get("exists",false)))
		if SaveService.bootstrap_pending:
			if bool(remote.get("exists",false)):
				RushAuthDiagnostics.stage("CLOUD_BOOTSTRAP_MODE:REMOTE_RESTORE")
				if SaveService.guest_import_pending:
					RushAuthDiagnostics.stage("CLOUD_EXISTING_ACCOUNT_RESTORE_FAILED:GUEST_CONFLICT")
					conflict()
					return
				var restored_docs: Dictionary = RushRemoteEdit.prepare(SaveService.cloud_envelope(),remote.get("documents",{}),remote.get("versions",{}),true,String(remote.get("stored_digest","")))
				if restored_docs.is_empty():
					RushAuthDiagnostics.stage("REMOTE_EDIT_VALID:false")
					RushAuthDiagnostics.stage("CLOUD_EXISTING_ACCOUNT_RESTORE_FAILED:INVALID_REMOTE")
					failed()
					return
				remote["canonical_documents"] = restored_docs
				remote["bootstrap"] = true
				restore_remote(uid,remote,digest_value)
			else:
				RushAuthDiagnostics.stage("CLOUD_BOOTSTRAP_MODE:NEW_ACCOUNT")
				_bootstrap_stage("ACCOUNT_BOOTSTRAP_NEW_ACCOUNT_CONFIRMED")
				if not SaveService.finish_new_account():
					failed()
					return
				_bootstrap_stage("ACCOUNT_BOOTSTRAP_LOCAL_INIT_DONE")
				_progress("READY")
				busy = false
				confirmed_absent = remote.duplicate(true)
				first_upload_pending = true
				AuthService.completed.emit()
				_bootstrap_stage("ACCOUNT_BOOTSTRAP_HOME_READY")
				set_status("SYNCED")
				pending = true
				delay_left = 0.0
			return
		var revision: int = int(remote.get("revision",0))
		var marker: Dictionary = SaveService.cloud_meta
		var base: int = int(marker.get("revision",0))
		var exists: bool = bool(remote.get("exists",false))
		RushAuthDiagnostics.stage("CLOUD_LOCAL_REVISION:%d"%base)
		RushAuthDiagnostics.stage("CLOUD_REMOTE_REVISION:"+(str(revision) if exists else "missing"))
		RushAuthDiagnostics.stage("FIRESTORE_USER_DOC_EXISTS:"+("true" if exists else "false"))
		if exists and revision<base:
			# Never acknowledge an older revision, even if its content happens to match.
			conflict()
			return
		var edited: bool = bool(remote.get("edited",false))
		var repair: bool = edited and bool(marker.get("repair",false)) and String(marker.get("remote_content_digest",""))==String(remote.get("digest","")) and RushRemoteEdit.same(marker.get("versions",{}),remote.get("versions",{})) and String(marker.get("owner",""))==uid
		if edited and not repair:
			RushAuthDiagnostics.stage("REMOTE_EDIT_DETECTED")
			var local_clean: bool = String(marker.get("owner",""))==uid and String(marker.get("local_digest",""))==digest_value
			_trace_flag("REMOTE_EDIT_BASELINE_AVAILABLE",String(marker.get("owner",""))==uid and not String(marker.get("local_digest","")).is_empty())
			var remote_advanced: bool = RushRemoteEdit.newer(remote,marker)
			_trace_flag("REMOTE_EDIT_REMOTE_ADVANCED",remote_advanced)
			var remote_newer: bool = local_clean and remote_advanced
			_trace_flag("REMOTE_EDIT_NEWER",remote_newer)
			if not local_clean or not remote_newer:
				RushAuthDiagnostics.stage("REMOTE_EDIT_IMPORT_FAILED:CONFLICT")
				conflict()
				return
			var canonical: Dictionary = RushRemoteEdit.prepare(SaveService.cloud_envelope(),remote.get("documents",{}),remote.get("versions",{}),false,String(remote.get("stored_digest","")))
			_trace_flag("REMOTE_EDIT_VALID",not canonical.is_empty())
			if canonical.is_empty():
				RushAuthDiagnostics.stage("REMOTE_EDIT_IMPORT_FAILED:INVALID_REMOTE")
				failed()
				return
			remote["canonical_documents"] = canonical
			restore_remote(uid,remote,digest_value)
			return
		if exists and not edited and String(remote.get("digest",""))==digest_value:
			acknowledge(uid,revision,digest_value,remote.get("versions",{}))
			return
		if exists and (revision!=base or String(marker.get("owner",""))!=uid):
			var local_unchanged: bool = String(marker.get("local_digest",""))==digest_value and String(marker.get("owner",""))==uid
			var new_local: bool = marker.is_empty() and RushCloudRestore.is_new(SaveService.cloud_envelope())
			if new_local or (revision>base and local_unchanged):
				restore_remote(uid,remote,digest_value)
			else:
				conflict()
			return
		if not exists and base>0:
			# Remote deletion is not permission to recreate a formerly synced account.
			conflict()
			return
		RushAuthDiagnostics.stage("CLOUD_SYNC_UPLOAD_START")
		if first_upload_pending: _bootstrap_stage("ACCOUNT_BOOTSTRAP_FIRST_UPLOAD_START")
		AuthService.provider.compare_and_set(uid,revision,docs,digest_value,func(saved: bool, result: Dictionary) -> void:
			if ticket!=epoch or not busy or scope_ticket!=SaveService.scope_generation or uid!=AuthService.current_user_id() or uid!=SaveService.scope_uid: return
			if result.get("conflict",false):
				conflict()
				return
			if not saved or String(result.get("digest",""))!=digest_value or int(result.get("revision",0))<revision:
				failed()
				return
			RushAuthDiagnostics.stage("CLOUD_SYNC_UPLOAD_SUCCESS")
			if first_upload_pending:
				_bootstrap_stage("ACCOUNT_BOOTSTRAP_FIRST_UPLOAD_SUCCESS")
				first_upload_pending = false
			acknowledge(uid,int(result.revision),digest_value,result.get("versions",{}))))
	get_tree().create_timer(110.0).timeout.connect(func() -> void:
		if ticket==epoch and busy:
			epoch += 1
			AuthService.provider.cancel_pending()
			AuthService.provider.last_error_code = "TRANSPORT"
			failed())
func restore_remote(uid: String, remote: Dictionary, requested_digest: String) -> void:
	if not can_restore.is_valid() or not bool(can_restore.call()):
		busy = false
		fetching = false
		pending = false
		poll_left = 5.0
		RushAuthDiagnostics.stage("CLOUD_RECONCILIATION_RESULT:DEFERRED")
		set_status("ERROR")
		return
	# Protect local edits made during the network request.
	var uncommitted_bootstrap: bool = bool(remote.get("bootstrap",false)) and SaveService.bootstrap_pending and not SaveService.scope_local_available and not SaveService.guest_import_pending and uid==SaveService.scope_uid and uid==AuthService.current_user_id() and RewardService.active_run==0 and not FileAccess.file_exists(SaveService.PATH) and not FileAccess.file_exists(SaveService.BACKUP) and not FileAccess.file_exists(SaveService.TEMP)
	if not uncommitted_bootstrap and RushFirestoreCodec.digest(snapshot())!=requested_digest:
		if bool(remote.get("edited",false)): RushAuthDiagnostics.stage("REMOTE_EDIT_IMPORT_FAILED:LOCAL_CHANGED")
		conflict()
		return
	var edited: bool = bool(remote.get("edited",false))
	var bootstrap: bool = bool(remote.get("bootstrap",false))
	var docs: Dictionary = remote.get("canonical_documents",{}) if edited or bootstrap else remote.get("documents",{})
	var candidate: Dictionary = RushCloudRestore.candidate(SaveService.cloud_envelope(),docs)
	if candidate.is_empty():
		if edited: RushAuthDiagnostics.stage("REMOTE_EDIT_IMPORT_FAILED:INVALID_CANDIDATE")
		conflict()
		return
	var sparse: bool = false
	for car: String in RushVehicleCatalog.IDS:
		if not docs.has("cars/"+car): sparse = true
	var retained_cars: Array = []
	for path: String in docs:
		if path.begins_with("cars/"): retained_cars.append(path.trim_prefix("cars/"))
	var local_digest: String = RushFirestoreCodec.digest(snapshot(candidate,1 if sparse else 0,false,retained_cars))
	var marker: Dictionary = {"owner":uid,"revision":int(remote.revision),"digest":String(remote.digest),"local_digest":local_digest,"sparse_cars":sparse,"car_documents":retained_cars,"versions":remote.get("versions",{}),"repair":edited,"remote_content_digest":String(remote.digest)}
	if bootstrap: RushAuthDiagnostics.stage("CLOUD_EXISTING_ACCOUNT_RESTORE_START")
	if edited:
		if bootstrap:
			RushAuthDiagnostics.stage("REMOTE_EDIT_DETECTED")
			RushAuthDiagnostics.stage("REMOTE_EDIT_VALID:true")
		RushAuthDiagnostics.stage("REMOTE_EDIT_IMPORT_START")
	restoring = true
	var saved: bool = SaveService.restore_cloud(docs,marker)
	restoring = false
	if not saved:
		if bootstrap: RushAuthDiagnostics.stage("CLOUD_EXISTING_ACCOUNT_RESTORE_FAILED:LOCAL_COMMIT")
		if edited: RushAuthDiagnostics.stage("REMOTE_EDIT_IMPORT_FAILED:LOCAL_COMMIT")
		failed()
		return
	if bootstrap:
		RushAuthDiagnostics.stage("CLOUD_EXISTING_ACCOUNT_RESTORE_SUCCESS")
		_progress("READY")
		AuthService.completed.emit()
	if edited:
		RushAuthDiagnostics.stage("REMOTE_EDIT_IMPORT_SUCCESS")
		RushAuthDiagnostics.stage("REMOTE_CANONICAL_DIGEST_REGENERATED")
		RushAuthDiagnostics.stage("REMOTE_EDIT_UI_REFRESHED")
	busy = false
	RushAuthDiagnostics.stage("CLOUD_SYNC_DOWNLOAD_SUCCESS")
	pending = edited or local_digest!=String(remote.digest)
	delay_left = 3.0
	set_status("SYNCED")
func acknowledge(uid: String, revision: int, digest_value: String, versions: Dictionary = {}) -> void:
	var retained_cars: Array = []
	for path: String in versions:
		if path.begins_with("cars/"): retained_cars.append(path.trim_prefix("cars/"))
	var marker: Dictionary = {"owner":uid,"revision":revision,"digest":digest_value,"local_digest":digest_value,"versions":versions,"car_documents":retained_cars,"sparse_cars":SaveService.cloud_meta.is_empty() or bool(SaveService.cloud_meta.get("sparse_cars",false))}
	if not RushRemoteEdit.same(SaveService.cloud_meta,marker) and not SaveService.acknowledge_cloud(marker):
		failed()
		return
	busy = false
	pending = RushFirestoreCodec.digest(snapshot())!=digest_value
	backoff = 5.0
	retry_count = 0
	poll_left = 5.0
	delay_left = 3.0
	set_status("SYNCING" if pending else "SYNCED")
func conflict() -> void:
	busy = false
	fetching = false
	pending = false
	blocked = true
	recheck_left = 15.0
	set_status("CONFLICT")
func failed() -> void:
	busy = false
	fetching = false
	var transient: bool = AuthService.provider.last_error_code in ["TRANSPORT","HTTP_TRANSPORT_ERROR","SERVER_ERROR","RATE_LIMITED","REQUEST_BUSY"]
	if transient and retry_count<2:
		retry_count += 1
		pending = true
		delay_left = 2.0*retry_count
		if SaveService.bootstrap_pending:
			RushAuthDiagnostics.stage("CLOUD_BOOTSTRAP_RETRY:"+str(retry_count))
			_progress("LOADING")
		set_status("SYNCING")
		return
	if SaveService.bootstrap_pending: _progress("FAILED")
	# No blind retries for authorization, permissions or malformed data.
	pending = false
	blocked = not transient
	recheck_left = 15.0
	poll_left = 20.0
	retry_count = 0
	set_status("OFFLINE" if AuthService.provider.last_error_code=="TRANSPORT" else "ERROR")
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_PAUSED:
		foreground = false
		if busy and fetching:
			epoch += 1
			AuthService.provider.cancel_pending()
			busy = false
			fetching = false
			confirmed_absent.clear()
		pending = true
	elif what==NOTIFICATION_APPLICATION_RESUMED:
		foreground = true
		if blocked: retry_reconciliation()
		pending = true
		delay_left = 0.0
		poll_left = 0.0
