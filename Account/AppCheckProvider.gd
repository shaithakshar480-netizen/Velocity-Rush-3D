class_name RushAppCheckProvider
extends RefCounted
## Install a real native App Check implementation; never fabricate a token.
var token_source: Callable
func request_token(callback: Callable) -> void:
	if not token_source.is_valid():
		callback.call(false,"")
		return
	var once: Array[bool] = [false]
	token_source.call(func(ok: bool, token: String) -> void:
		if once[0]: return
		once[0] = true
		callback.call(ok and not token.is_empty(),token if ok else ""))
func attach(rest: RushFirebaseRestProvider) -> bool:
	if not token_source.is_valid(): return false
	rest.app_check = request_token
	return true
