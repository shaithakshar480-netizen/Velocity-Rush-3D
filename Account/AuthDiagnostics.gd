class_name RushAuthDiagnostics
extends RefCounted
## TEMPORARY. Disable together with AUTH_DIAGNOSTICS in RushFirebaseBridge.kt.
## Only static stage text, numeric HTTP status and allowlisted errors enter this sink.
const ENABLED: bool = true
const TAG: String = "VelocityRushAuth"
const FIREBASE_ERRORS: Dictionary = {
	"INVALID_IDP_RESPONSE":"Google credential rejected",
	"INVALID_CREDENTIAL":"Credential rejected",
	"INVALID_LOGIN_CREDENTIALS":"Credential rejected",
	"OPERATION_NOT_ALLOWED":"Provider disabled",
	"USER_DISABLED":"Account disabled",
	"EMAIL_EXISTS":"Account collision",
	"FEDERATED_USER_ID_ALREADY_LINKED":"Account collision",
	"CREDENTIAL_ALREADY_IN_USE":"Account collision",
	"INVALID_ID_TOKEN":"Firebase session token rejected",
	"TOKEN_EXPIRED":"Firebase session expired",
	"CONFIGURATION_NOT_FOUND":"Firebase auth configuration missing",
	"PROJECT_NOT_FOUND":"Firebase project unavailable",
	"API_KEY_INVALID":"Client configuration rejected",
	"INVALID_API_KEY":"Client configuration rejected",
	"INVALID_OAUTH_CLIENT_ID":"OAuth client rejected",
	"INVALID_CLIENT_ID":"OAuth client rejected",
	"INVALID_PROVIDER_ID":"Identity provider rejected",
	"TOO_MANY_ATTEMPTS_TRY_LATER":"Request throttled",
	"UNAUTHORIZED_DOMAIN":"Request domain rejected",
	"INVALID_REQUEST_URI":"Request URI rejected",
	"MISSING_OR_INVALID_NONCE":"Nonce rejected",
	"INVALID_NONCE":"Nonce rejected",
	"INVALID_APP_CREDENTIAL":"App credential rejected",
	"INVALID_APP_CHECK_TOKEN":"App Check rejected",
	"APP_NOT_AUTHORIZED":"Android app authorization rejected",
	"PERMISSION_DENIED":"Request permission denied",
	"API_KEY_SERVICE_BLOCKED":"API key service restriction",
	"API_KEY_ANDROID_APP_BLOCKED":"API key Android restriction",
	"API_KEY_HTTP_REFERRER_BLOCKED":"API key referrer restriction",
	"SERVICE_DISABLED":"Required API disabled"
}
static func stage(value: String) -> void:
	if not ENABLED: return
	# Always use Godot stdout; native logging configuration cannot suppress this path.
	print("["+TAG+"] "+value)
static func firebase_error(payload: Variant) -> String:
	# Never stringify a response, header, URL or exception payload.
	if payload is Dictionary and payload.get("error") is Dictionary:
		var failure: Dictionary = payload.error
		var raw: String = String(failure.get("message",""))
		var code: String = raw.get_slice(":",0).strip_edges()
		if FIREBASE_ERRORS.has(code): return code+":"+String(FIREBASE_ERRORS[code])
		var status: String = String(failure.get("status",""))
		if FIREBASE_ERRORS.has(status): return status+":"+String(FIREBASE_ERRORS[status])
	return "UNKNOWN:Server error details omitted"
