class_name RushFirebaseRestProvider
extends RushFirebaseProvider
## Real Firebase HTTPS transport; no third-party addon API is assumed.
## Platform hooks are our contract, supplied by a native integration:
## google_token(callback(bool, id_token)), app_check(callback(bool, token)),
## secure_load()->String, secure_save(refresh_token)->bool, secure_clear().
enum InitState { UNCONFIGURED, INITIALIZING, READY, ERROR }
var init_state: InitState = InitState.UNCONFIGURED
var host: Node
var config: Dictionary = {}
var google_token: Callable
var google_cancel: Callable
var app_check: Callable
var secure_load: Callable
var secure_save: Callable
var secure_clear: Callable
var google_sign_out: Callable
var identity: Dictionary = {}
var id_token: String = ""
var refresh_token: String = ""
var expires_ms: int = 0
var generation: int = 0
var requests: Array[HTTPRequest] = []
var firestore_busy: bool = false
var observed_versions: Dictionary = {}
var observed_uid: String = ""
var observed_digest: String = ""
var observed_stored_digest: String = ""
func initialize(owner_node: Node, values: Dictionary) -> void:
	if init_state!=InitState.UNCONFIGURED: return
	host = owner_node
	config = values.duplicate(true)
	if not bool(config.get("configured",false)): return
	init_state = InitState.INITIALIZING
	for key: String in ["firebase_project_id","firebase_app_id","firebase_api_key"]:
		if String(config.get(key,"")).is_empty():
			init_state = InitState.ERROR
			return
	if String(config.firebase_project_id).contains("/") or String(config.get("android_package_name",""))!="com.velocityrush3d.game":
		init_state = InitState.ERROR
		return
	init_state = InitState.READY
func cloud_diagnostics(expected_uid: String) -> Dictionary:
	return {"supported":true,"configured":init_state==InitState.READY,
		"token_available":not id_token.is_empty(),"host_available":is_instance_valid(host),
		"app_check_ready":not bool(config.get("require_app_check",true)) or app_check.is_valid(),
		"identity_match":not expected_uid.is_empty() and expected_uid==String(identity.get("uid","")),
		"request_busy":firestore_busy or not requests.is_empty()}
func available() -> bool:
	return init_state==InitState.READY and is_instance_valid(host) and (not bool(config.get("require_app_check",true)) or app_check.is_valid())
func cancel_pending() -> void:
	observed_versions.clear()
	observed_uid = ""
	generation += 1
	if google_cancel.is_valid(): google_cancel.call()
	for request: HTTPRequest in requests:
		request.cancel_request()
		request.queue_free()
	requests.clear()
	firestore_busy = false
func sign_out() -> void:
	cancel_pending()
	identity.clear()
	last_error_code = ""
	id_token = ""
	refresh_token = ""
	expires_ms = 0
	if secure_clear.is_valid(): secure_clear.call()
	if google_sign_out.is_valid(): google_sign_out.call()
func authenticate(operation: String, callback: Callable) -> void:
	last_error_code = ""
	if not available():
		callback.call(false,{})
		return
	var ticket: int = generation
	if operation=="restore":
		if refresh_token.is_empty() and secure_load.is_valid():
			refresh_token = String(secure_load.call())
		if refresh_token.is_empty():
			callback.call(false,{})
			return
		_refresh(func(ok: bool) -> void:
			if ticket!=generation: return
			if not ok:
				callback.call(false,{})
				return
			_lookup(callback))
	elif operation=="anonymous":
		if not identity.is_empty():
			callback.call(true,identity.duplicate())
			return
		_auth_post("signUp",{"returnSecureToken":true},func(ok: bool, data: Dictionary) -> void:
			if ticket!=generation: return
			var accepted: bool = ok and _accept(data,true)
			callback.call(accepted,identity.duplicate() if accepted else {}))
	elif operation in ["google","link_google"]:
		print("[VelocityRushAuth] GOOGLE_TOKEN_CALLBACK_CHECK:"+("true" if google_token.is_valid() else "false"))
		if not google_token.is_valid():
			print("[VelocityRushAuth] GOOGLE_REQUEST_BLOCKED:BRIDGE_NOT_BOUND")
			last_error_code = "GOOGLE_UNAVAILABLE"
			callback.call(false,{})
			return
		var once: Array[bool] = [false]
		google_token.call(func(ok: bool, token: String) -> void:
			if ticket!=generation or once[0]: return
			once[0] = true
			if not ok or token.is_empty():
				callback.call(false,{})
				return
			_google_exchange(operation,token,callback))
	else:
		callback.call(false,{})
func _google_exchange(operation: String, token: String, callback: Callable) -> void:
	var uri: String = String(config.get("oauth_request_uri",""))
	if uri.is_empty():
		RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:MISSING_REQUEST_URI:Exchange not started")
		callback.call(false,{})
		return
	var body: Dictionary = {"postBody":"id_token="+token.uri_encode()+"&providerId=google.com","requestUri":uri,"returnSecureToken":true}
	var previous_uid: String = String(identity.get("uid",""))
	var ticket: int = generation
	var send: Callable = func(ok: bool) -> void:
		if ticket!=generation: return
		if not ok:
			RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:SESSION_REFRESH_FAILED:Exchange not started")
			callback.call(false,{})
			return
		if operation=="link_google" and not previous_uid.is_empty(): body["idToken"] = id_token
		_auth_post("signInWithIdp",body,func(success: bool, data: Dictionary) -> void:
			if ticket!=generation: return
			# Never fall back to sign-in on EMAIL_EXISTS/credential collision.
			if operation=="link_google" and not previous_uid.is_empty() and String(data.get("localId",""))!=previous_uid:
				if success: RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:LINK_UID_MISMATCH:Existing identity preserved")
				success = false
			var accepted: bool = success and _accept(data,false)
			if accepted:
				RushAuthDiagnostics.stage("FIREBASE_IDP_SUCCESS")
			elif success:
				RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:INVALID_RESPONSE:Identity response rejected")
			callback.call(accepted,identity.duplicate() if accepted else {}))
	if operation=="link_google" and not previous_uid.is_empty(): _authorized(send)
	else: send.call(true)
func _accept(data: Dictionary, anonymous: bool) -> bool:
	var uid: String = String(data.get("localId",""))
	if uid.is_empty() or uid.contains("/") or String(data.get("idToken","")).is_empty(): return false
	id_token = String(data.idToken)
	refresh_token = String(data.get("refreshToken",""))
	expires_ms = Time.get_ticks_msec()+maxi(0,int(data.get("expiresIn",0))-60)*1000
	identity = {"uid":uid,"email":String(data.get("email","")),"display_name":String(data.get("displayName","")),"is_guest":anonymous,"provider":"anonymous" if anonymous else "google"}
	if secure_save.is_valid() and not refresh_token.is_empty(): secure_save.call(refresh_token)
	return true
func _lookup(callback: Callable) -> void:
	_auth_post("lookup",{"idToken":id_token},func(ok: bool, data: Dictionary) -> void:
		var users: Array = data.get("users",[]) if data.get("users") is Array else []
		if not ok or users.size()!=1 or not users[0] is Dictionary:
			callback.call(false,{})
			return
		var user: Dictionary = users[0]
		user["idToken"] = id_token
		user["refreshToken"] = refresh_token
		user["expiresIn"] = maxi(60,int((expires_ms-Time.get_ticks_msec())/1000)+60)
		var anonymous: bool = user.get("providerUserInfo",[]).is_empty()
		var accepted: bool = _accept(user,anonymous)
		callback.call(accepted,identity.duplicate() if accepted else {}))
func _authorized(callback: Callable) -> void:
	if not id_token.is_empty() and Time.get_ticks_msec()<expires_ms:
		callback.call(true)
	else:
		_refresh(callback)
func _refresh(callback: Callable) -> void:
	if refresh_token.is_empty():
		last_error_code = "AUTH_SESSION_MISSING"
		callback.call(false)
		return
	var body: String = "grant_type=refresh_token&refresh_token="+refresh_token.uri_encode()
	_http("https://securetoken.googleapis.com/v1/token?key="+String(config.firebase_api_key).uri_encode(),body,false,true,func(ok: bool, raw: Variant) -> void:
		var data: Dictionary = raw if raw is Dictionary else {}
		if not ok or String(data.get("id_token","")).is_empty():
			callback.call(false)
			return
		var uid: String = String(data.get("user_id",""))
		if not identity.is_empty() and uid!=String(identity.uid):
			callback.call(false)
			return
		id_token = String(data.id_token)
		refresh_token = String(data.get("refresh_token",refresh_token))
		expires_ms = Time.get_ticks_msec()+maxi(0,int(data.get("expires_in",0))-60)*1000
		if secure_save.is_valid(): secure_save.call(refresh_token)
		callback.call(true))
func _auth_post(method: String, body: Dictionary, callback: Callable) -> void:
	if method=="signInWithIdp": RushAuthDiagnostics.stage("FIREBASE_IDP_EXCHANGE_START")
	_http("https://identitytoolkit.googleapis.com/v1/accounts:"+method+"?key="+String(config.firebase_api_key).uri_encode(),JSON.stringify(body),false,false,func(ok: bool, raw: Variant) -> void: callback.call(ok,raw if raw is Dictionary else {}),method=="signInWithIdp")
func _http(url: String, body: String, bearer: bool, form: bool, callback: Callable, trace_idp: bool = false, firestore_stage: String = "") -> void:
	if not available() or requests.size()>=3:
		last_error_code = "PROVIDER_UNAVAILABLE" if not available() else "REQUEST_BUSY"
		if trace_idp:
			RushAuthDiagnostics.stage("FIREBASE_IDP_HTTP_STATUS:0")
			RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:REQUEST_UNAVAILABLE:No HTTP request sent")
		callback.call(false,{})
		return
	var ticket: int = generation
	var send: Callable = func(check_ok: bool, check_token: String) -> void:
		if ticket!=generation: return
		if not check_ok:
			last_error_code = "APP_CHECK_UNAVAILABLE"
			if trace_idp:
				RushAuthDiagnostics.stage("FIREBASE_IDP_HTTP_STATUS:0")
				RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:APP_CHECK_UNAVAILABLE:No HTTP request sent")
			callback.call(false,{})
			return
		var request: HTTPRequest = HTTPRequest.new()
		request.timeout = 20.0
		if bearer:
			RushAuthDiagnostics.stage("FIRESTORE_REQUEST_TIMEOUT_MS:20000")
			RushAuthDiagnostics.stage("FIRESTORE_NETWORK_CLASS:IN_PROGRESS")
			var request_ref: WeakRef = weakref(request)
			host.get_tree().create_timer(8.0).timeout.connect(_slow_request.bind(ticket,request_ref))
		request.body_size_limit = 2097152
		host.add_child(request)
		requests.append(request)
		var headers: PackedStringArray = PackedStringArray(["Content-Type: application/x-www-form-urlencoded" if form else "Content-Type: application/json"])
		if bearer: headers.append("Authorization: Bearer "+id_token)
		if not check_token.is_empty(): headers.append("X-Firebase-AppCheck: "+check_token)
		request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
			requests.erase(request)
			request.queue_free()
			if ticket!=generation: return
			var ok: bool = result==HTTPRequest.RESULT_SUCCESS and code>=200 and code<300
			var decoded: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if result!=HTTPRequest.RESULT_SUCCESS:
				last_error_code = "TRANSPORT" if result in [HTTPRequest.RESULT_CANT_RESOLVE,HTTPRequest.RESULT_CANT_CONNECT,HTTPRequest.RESULT_CONNECTION_ERROR,HTTPRequest.RESULT_TIMEOUT] else "HTTP_TRANSPORT_ERROR"
			elif not ok:
				last_error_code = _http_category(code)
			elif decoded==null:
				last_error_code = "INVALID_RESPONSE"
				ok = false
			else:
				last_error_code = ""
			if bearer and url.ends_with(":commit") and not ok and decoded is Dictionary and decoded.get("error") is Dictionary:
				if String(decoded.error.get("status","")) in ["FAILED_PRECONDITION","ABORTED","ALREADY_EXISTS"]:
					last_error_code = "CONFLICT"
			if bearer:
				RushAuthDiagnostics.stage("FIRESTORE_HTTP_STATUS:%d"%code)
				if not firestore_stage.is_empty(): RushAuthDiagnostics.stage("FIRESTORE_"+firestore_stage+"_HTTP_STATUS:%d"%code)
				if not ok:
					RushAuthDiagnostics.stage("FIRESTORE_NETWORK_CLASS:FAILED")
					RushAuthDiagnostics.stage("FIRESTORE_REQUEST_FAILED:"+last_error_code)
			if trace_idp:
				RushAuthDiagnostics.stage("FIREBASE_IDP_HTTP_STATUS:%d"%code)
				if not ok:
					if result==HTTPRequest.RESULT_TIMEOUT:
						RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:TIMEOUT:HTTP request timed out")
					elif result!=HTTPRequest.RESULT_SUCCESS:
						RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:TRANSPORT_%d:Network request failed"%result)
					else:
						RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:"+RushAuthDiagnostics.firebase_error(decoded))
			if not ok and decoded is Dictionary and decoded.get("error") is Dictionary:
				var error_message: String = String(decoded.error.get("message",""))
				if error_message in ["EMAIL_EXISTS","FEDERATED_USER_ID_ALREADY_LINKED","CREDENTIAL_ALREADY_IN_USE"]:
					last_error_code = "ACCOUNT_COLLISION"
			callback.call(ok,decoded if ok else {}),CONNECT_ONE_SHOT)
		var error: Error = request.request(url,headers,HTTPClient.METHOD_POST,body)
		if error!=OK:
			last_error_code = "REQUEST_START_FAILED"
			if bearer: RushAuthDiagnostics.stage("FIRESTORE_REQUEST_FAILED:REQUEST_START_FAILED")
			if trace_idp:
				RushAuthDiagnostics.stage("FIREBASE_IDP_HTTP_STATUS:0")
				RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:REQUEST_START_%d:HTTP request not started"%int(error))
			requests.erase(request)
			request.queue_free()
			callback.call(false,{})
	if app_check.is_valid():
		var once: Array[bool] = [false]
		app_check.call(func(ok: bool, token: String) -> void:
			if once[0]: return
			once[0] = true
			send.call(ok and not token.is_empty(),token))
	elif bool(config.get("require_app_check",true)):
		if trace_idp:
			RushAuthDiagnostics.stage("FIREBASE_IDP_HTTP_STATUS:0")
			RushAuthDiagnostics.stage("FIREBASE_IDP_ERROR:APP_CHECK_UNAVAILABLE:No HTTP request sent")
		callback.call(false,{})
	else:
		send.call(true,"")
func _http_category(code: int) -> String:
	match code:
		401: return "UNAUTHENTICATED"
		403: return "PERMISSION_DENIED"
		404: return "NOT_FOUND"
		409: return "CONFLICT"
		429: return "RATE_LIMITED"
	return "SERVER_ERROR" if code>=500 else "HTTP_ERROR"
func _base() -> String:
	return "projects/"+String(config.firebase_project_id)+"/databases/(default)/documents"
func _endpoint(method: String) -> String:
	return "https://firestore.googleapis.com/v1/"+_base()+":"+method
func _paths() -> Array[String]:
	var paths: Array[String] = ["profile","progression/main","inventory/main","meta/main"]
	for car: String in RushVehicleCatalog.IDS: paths.append("cars/"+car)
	return paths
func _name(uid: String, path: String) -> String:
	return _base()+"/users/"+uid+("" if path=="profile" else "/"+path)
func _read(uid: String, write: bool, callback: Callable) -> void:
	var names: Array[String] = []
	for path: String in (_paths() if not write else ["profile"]): names.append(_name(uid,path))
	# Firebase Auth cannot open a REST read-write transaction. The write precheck
	# reads only the root; its server updateTime guards the entire atomic commit.
	var body: Dictionary = {"documents":names}
	if not write: body["newTransaction"] = {"readOnly":{}}
	RushAuthDiagnostics.stage("FIRESTORE_WRITE_PRECHECK_START" if write else "FIRESTORE_READ_START")
	_http(_endpoint("batchGet"),JSON.stringify(body),true,false,func(ok: bool, raw: Variant) -> void:
		if not ok or not raw is Array:
			if ok: _read_error("INVALID_BATCH_RESPONSE")
			callback.call(false,{})
			return
		var docs: Dictionary = {}
		var token: String = ""
		var revision: int = 0
		var digest_value: String = ""
		var found_root: bool = false
		var update_time: String = ""
		var seen: Dictionary = {}
		var versions: Dictionary = {}
		for row: Variant in raw:
			if not row is Dictionary:
				_read_error("INVALID_BATCH_ROW")
				callback.call(false,{})
				return
			if row.has("transaction"): token = String(row.transaction)
			var found: Dictionary = row.get("found",{}) if row.get("found") is Dictionary else {}
			var full_name: String = String(found.get("name",row.get("missing","")))
			if full_name.is_empty(): continue
			if full_name not in names or seen.has(full_name):
				_read_error("UNEXPECTED_DOCUMENT")
				callback.call(false,{})
				return
			seen[full_name] = true
			if found.is_empty(): continue
			var path: String = "profile" if full_name==_name(uid,"profile") else full_name.trim_prefix(_name(uid,"profile")+"/")
			var server_version: String = RushRemoteEdit.stamp(found.get("updateTime"))
			if server_version.is_empty() or not found.get("fields") is Dictionary:
				_read_error("INVALID_DOCUMENT_METADATA")
				callback.call(false,{})
				return
			if not RushRemoteEdit.wire_fields(found.fields):
				_read_error("INVALID_REMOTE_FIELD_TYPE")
				callback.call(false,{})
				return
			versions[path] = server_version
			var fields: Dictionary = RushFirestoreCodec.decode_fields(found.fields)
			if path=="profile":
				found_root = true
				update_time = String(found.get("updateTime",""))
				if not RushCloudRestore.integer(fields.get("schema_version"),5) or fields.schema_version!=5 or not RushCloudRestore.integer(fields.get("save_revision"),int(RushProgressionData.LIMIT)) or fields.save_revision<1 or not fields.get("digest") is String or fields.digest.length()!=64:
					_read_error("INVALID_REMOTE_SCHEMA")
					callback.call(false,{})
					return
				revision = int(fields.save_revision)
				digest_value = fields.digest
			for key: String in ["created_at","last_login_at","updated_at","save_revision","digest"]: fields.erase(key)
			docs[path] = fields
		if seen.size()!=names.size() or (not write and token.is_empty()) or (write and found_root and update_time.is_empty()):
			_read_error("INCOMPLETE_BATCH_OR_TRANSACTION")
			callback.call(false,{})
			return
		var actual_digest: String = RushFirestoreCodec.digest(docs) if not write else digest_value
		callback.call(true,{"exists":found_root,"revision":revision,"digest":actual_digest,"stored_digest":digest_value,"edited":found_root and not write and actual_digest!=digest_value,"documents":docs,"transaction":token,"update_time":update_time,"versions":versions}),false,"WRITE_PRECHECK" if write else "READ")
func _read_error(code: String) -> void:
	last_error_code = code
	RushAuthDiagnostics.stage("FIRESTORE_READ_FAILED:"+code)
	RushAuthDiagnostics.stage("REMOTE_VALIDATION_FAILED:"+code)
func _rollback(token: String) -> void:
	if not token.is_empty():
		_http(_endpoint("rollback"),JSON.stringify({"transaction":token}),true,false,func(_ok: bool, _data: Variant) -> void: pass)
func fetch_save(uid: String, callback: Callable) -> void:
	RushAuthDiagnostics.stage("FIRESTORE_BOOTSTRAP_START")
	RushAuthDiagnostics.stage("CLOUD_ID_TOKEN_AVAILABLE:"+("true" if not id_token.is_empty() else "false"))
	if firestore_busy or uid.is_empty() or uid!=String(identity.get("uid","")):
		RushAuthDiagnostics.stage("CLOUD_RECONCILE_PRECHECK_FAILED:"+("REQUEST_BUSY" if firestore_busy else "AUTH_CHANGED"))
		callback.call(false,{})
		return
	firestore_busy = true
	_authorized(func(ok: bool) -> void:
		if not ok:
			RushAuthDiagnostics.stage("CLOUD_RECONCILE_PRECHECK_FAILED:"+("NO_TOKEN" if id_token.is_empty() else "SESSION_AUTHORIZATION_FAILED"))
			firestore_busy = false
			callback.call(false,{})
			return
		_read(uid,false,func(success: bool, remote: Dictionary) -> void:
			_rollback(String(remote.get("transaction","")))
			remote.erase("transaction")
			if success:
				observed_uid = uid
				observed_versions = remote.get("versions",{}).duplicate(true)
				observed_digest = String(remote.get("digest",""))
				observed_stored_digest = String(remote.get("stored_digest",""))
			firestore_busy = false
			callback.call(success,remote)))
func compare_and_set(uid: String, expected: int, documents: Dictionary, operation_id: String, callback: Callable) -> void:
	if firestore_busy or uid.is_empty() or uid!=observed_uid or uid!=String(identity.get("uid","")) or RushFirestoreCodec.digest(documents)!=operation_id:
		callback.call(false,{})
		return
	firestore_busy = true
	_authorized(func(ok: bool) -> void:
		if not ok:
			firestore_busy = false
			callback.call(false,{})
			return
		_read(uid,true,func(success: bool, current: Dictionary) -> void:
			var revision: int = int(current.get("revision",0))
			if success and RushRemoteEdit.stamp(current.get("update_time",""))!=String(observed_versions.get("profile","")):
				firestore_busy = false
				callback.call(false,{"conflict":true})
				return
			if success and observed_digest==operation_id and observed_stored_digest==operation_id and String(current.get("digest",""))==operation_id:
				firestore_busy = false
				callback.call(true,{"revision":revision,"digest":operation_id,"versions":observed_versions.duplicate(true)})
				return
			if not success or revision!=expected:
				firestore_busy = false
				callback.call(false,{"conflict":success})
				return
			var creating: bool = not bool(current.get("exists",false))
			if creating: RushAuthDiagnostics.stage("FIRESTORE_USER_DOC_CREATE_START")
			var writes: Array = []
			# Preserve legacy documents, but new accounts only write owned cars.
			for required: String in ["profile","progression/main","inventory/main","meta/main"]:
				if not documents.get(required) is Dictionary:
					firestore_busy = false
					callback.call(false,{})
					return
			for path: String in documents:
				if path not in _paths():
					firestore_busy = false
					callback.call(false,{})
					return
				if not documents.get(path) is Dictionary:
					firestore_busy = false
					callback.call(false,{})
					return
				var fields: Dictionary = documents[path].duplicate(true)
				var transforms: Array = [{"fieldPath":"updated_at","setToServerValue":"REQUEST_TIME"}]
				if path=="profile":
					fields["save_revision"] = revision+1
					fields["digest"] = operation_id
					# Mask keeps created_at intact on updates.
					transforms.append({"fieldPath":"last_login_at","setToServerValue":"REQUEST_TIME"})
					if not bool(current.get("exists",false)): transforms.append({"fieldPath":"created_at","setToServerValue":"REQUEST_TIME"})
				var write: Dictionary = {"update":{"name":_name(uid,path),"fields":RushFirestoreCodec.fields(fields)},"updateTransforms":transforms}
				# Child Console edits may leave root updateTime unchanged. Protect every
				# observed document, not only the root, against edits during this sync.
				write["currentDocument"] = {"updateTime":observed_versions[path]} if observed_versions.has(path) else {"exists":false}
				if path=="profile":
					write["updateMask"] = {"fieldPaths":fields.keys()}
					write["currentDocument"] = {"exists":false} if creating else {"updateTime":String(current.update_time)}
				writes.append(write)
			var audit: Dictionary = {"source":"offline_snapshot","reward_id":operation_id,"run_id":documents.get("meta/main",{}).get("wallet_ledger",{}).get("settled_run",0),"save_revision":revision+1}
			writes.append({"update":{"name":_name(uid,"transactions/"+operation_id),"fields":RushFirestoreCodec.fields(audit)},"updateTransforms":[{"fieldPath":"created_at","setToServerValue":"REQUEST_TIME"}]})
			RushAuthDiagnostics.stage("FIRESTORE_WRITE_STAGE:"+("FIRST_BOOTSTRAP" if creating else "NORMAL_UPDATE"))
			RushAuthDiagnostics.stage("FIRESTORE_WRITE_OPERATION_COUNT:%d"%writes.size())
			for category: String in ["ROOT","PROGRESSION","INVENTORY","META","AUDIT"]:
				RushAuthDiagnostics.stage("FIRESTORE_WRITE_HAS_"+category+":true")
			RushAuthDiagnostics.stage("FIRESTORE_WRITE_HAS_CARS:"+("true" if documents.size()>4 else "false"))
			RushAuthDiagnostics.stage("FIRESTORE_WRITE_START")
			_http(_endpoint("commit"),JSON.stringify({"writes":writes}),true,false,func(saved: bool, response: Variant) -> void:
				firestore_busy = false
				var valid: bool = saved and response is Dictionary and response.get("writeResults") is Array and response.writeResults.size()==writes.size() and not RushRemoteEdit.stamp(response.get("commitTime")).is_empty()
				var committed_versions: Dictionary = {}
				if valid:
					var index: int = 0
					for path: String in documents:
						var result: Variant = response.writeResults[index]
						var version: String = RushRemoteEdit.stamp(result.get("updateTime")) if result is Dictionary else ""
						if version.is_empty(): valid = false
						committed_versions[path] = version
						index += 1
				RushAuthDiagnostics.stage("FIRESTORE_WRITE_RESULT:"+("SUCCESS" if valid else (last_error_code if not last_error_code.is_empty() else "MALFORMED_RESPONSE")))
				if creating: RushAuthDiagnostics.stage("FIRESTORE_USER_DOC_CREATE_SUCCESS" if valid else "FIRESTORE_USER_DOC_CREATE_FAILED:"+(last_error_code if not last_error_code.is_empty() else "INVALID_COMMIT_RESPONSE"))
				callback.call(valid,{"revision":revision+1,"digest":operation_id,"versions":committed_versions} if valid else {"conflict":last_error_code=="CONFLICT"}),false,"WRITE")))

func poll_save(uid: String, baseline: Dictionary, callback: Callable) -> void:
	if baseline.is_empty():
		fetch_save(uid,callback)
		return
	if firestore_busy or uid.is_empty() or uid!=String(identity.get("uid","")):
		last_error_code = "REQUEST_BUSY"
		callback.call(false,{})
		return
	firestore_busy = true
	_authorized(func(authorized: bool) -> void:
		if not authorized:
			firestore_busy = false
			callback.call(false,{})
			return
		var names: Array[String] = []
		for path: String in _paths(): names.append(_name(uid,path))
		# Probe all supported paths: a root-only probe misses Console subdocument edits.
		# Field mask minimizes payload, not Firestore document-read billing.
		var body: Dictionary = {"documents":names,"mask":{"fieldPaths":["schema_version"]}}
		_http(_endpoint("batchGet"),JSON.stringify(body),true,false,func(ok: bool, raw: Variant) -> void:
			firestore_busy = false
			if not ok or not raw is Array:
				if ok: last_error_code = "INVALID_PROBE"
				callback.call(false,{})
				return
			var seen: Dictionary = {}
			var versions: Dictionary = {}
			for row: Variant in raw:
				if not row is Dictionary:
					last_error_code = "INVALID_PROBE"
					callback.call(false,{})
					return
				var found: Dictionary = row.get("found",{}) if row.get("found") is Dictionary else {}
				var name_value: String = String(found.get("name",row.get("missing","")))
				if name_value not in names or seen.has(name_value):
					last_error_code = "INVALID_PROBE"
					callback.call(false,{})
					return
				seen[name_value] = true
				if not found.is_empty():
					var version: String = RushRemoteEdit.stamp(found.get("updateTime"))
					if version.is_empty():
						last_error_code = "INVALID_PROBE"
						callback.call(false,{})
						return
					var path: String = "profile" if name_value==_name(uid,"profile") else name_value.trim_prefix(_name(uid,"profile")+"/")
					versions[path] = version
			if seen.size()!=names.size():
				last_error_code = "INVALID_PROBE"
				callback.call(false,{})
			elif RushRemoteEdit.same(versions,baseline): callback.call(true,{"unchanged":true})
			else: fetch_save(uid,callback),false,"POLL"))

func _slow_request(ticket: int, request_ref: WeakRef) -> void:
	var request: HTTPRequest = request_ref.get_ref() as HTTPRequest
	if ticket!=generation or request==null or request not in requests:
		RushAuthDiagnostics.stage("ASYNC_CALLBACK_STALE_IGNORED:SLOW_REQUEST")
		return
	RushAuthDiagnostics.stage("FIRESTORE_NETWORK_CLASS:SLOW")
