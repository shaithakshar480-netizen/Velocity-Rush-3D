class_name RushFirebaseProvider
extends RefCounted
var last_error_code: String = ""
## Native adapter boundary. No credentials enter UI or saves.
## Adapter owns Firebase/Google credential storage in Android secure storage,
## refresh, App Check, verified session identity, and Firestore transactions.
func cloud_diagnostics(_expected_uid: String) -> Dictionary:
	# Diagnostic-only contract: never return credentials or account identifiers.
	return {"supported":false,"configured":false,"token_available":false}
func available() -> bool:
	return false
func authenticate(_operation: String, callback: Callable) -> void:
	callback.call(false,{})
func cancel_pending() -> void:
	pass
func sign_out() -> void:
	pass
func fetch_save(_uid: String, callback: Callable) -> void:
	callback.call(false,{})
## Must atomically compare root save_revision to expected, write all documents,
## server timestamps and deterministic audit ID. Retry same ID is idempotent.
## Response: {revision, digest}; fetch also returns exists and documents.
func compare_and_set(_uid: String, _expected: int, _documents: Dictionary, _id: String, callback: Callable) -> void:
	callback.call(false,{})

func poll_save(uid: String, _versions: Dictionary, callback: Callable) -> void:
	fetch_save(uid,callback)
