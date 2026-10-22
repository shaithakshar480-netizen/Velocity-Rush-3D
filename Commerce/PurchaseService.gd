class_name RushPurchaseService
extends RefCounted
signal status_changed(message: String)
var provider: RushPurchaseProvider
var pending: String = ""
var epoch: int = 0
var purchase_scope: int = -1
var purchase_provider: RushPurchaseProvider
var retry_scope: int = -1
var retry_product: String = ""
var retry_provider: RushPurchaseProvider
var settling: bool = false
var retry_receipt: String = ""
func available() -> bool:
	return provider!=null and provider.available()
func price(product_id: String) -> String:
	if not available():
		return ""
	var product: Dictionary = provider.localized_product(product_id)
	return String(product.get("formatted_price","")) if bool(product.get("available",false)) else ""
func purchase(product_id: String) -> bool:
	if purchase_scope!=SaveService.scope_generation:
		pending = ""
	if retry_scope!=SaveService.scope_generation:
		retry_receipt = ""
	if not pending.is_empty() or not retry_receipt.is_empty() or not available() or price(product_id).is_empty():
		status_changed.emit("Purchases are currently unavailable.")
		return false
	if RushStoreCatalog.find_offer("coin_packs",product_id).is_empty():
		return false
	purchase_scope = SaveService.scope_generation
	purchase_provider = provider
	epoch += 1
	pending = product_id
	var request_epoch: int = epoch
	status_changed.emit("Waiting for purchase confirmation…")
	var accepted: bool = provider.purchase(product_id,_completed.bind(request_epoch))
	if not accepted and epoch==request_epoch and pending==product_id:
		pending = ""
		status_changed.emit("Purchase could not be started.")
	return accepted
func _completed(receipt: String, request_epoch: int) -> void:
	if purchase_scope!=SaveService.scope_generation or purchase_provider!=provider:
		pending = ""
		return
	if request_epoch!=epoch or pending.is_empty():
		return
	if receipt.is_empty():
		pending = ""
		status_changed.emit("Purchase cancelled or unavailable.")
		return
	_settle(receipt,pending)
func _settle(receipt: String, expected: String = "") -> void:
	if settling or not available():
		return
	settling = true
	var verification_scope: int = SaveService.scope_generation
	var verification_provider: RushPurchaseProvider = provider
	var verified: Dictionary = provider.verify_receipt(receipt)
	if verification_scope!=SaveService.scope_generation or verification_provider!=provider:
		settling = false
		pending = ""
		return
	if not verified.get("product_id") is String or not verified.get("purchase_token") is String:
		settling = false
		pending = ""
		status_changed.emit("Purchase verification is pending or unavailable.")
		return
	var product: String = String(verified.get("product_id",""))
	var token: String = String(verified.get("purchase_token",""))
	var valid: bool = verified.get("verified") is bool and verified.get("verified")==true and verified.get("paid") is bool and verified.get("paid")==true and not RushStoreCatalog.find_offer("coin_packs",product).is_empty() and not token.strip_edges().is_empty() and (expected.is_empty() or expected==product)
	if not valid:
		settling = false
		pending = ""
		status_changed.emit("Purchase verification is pending or unavailable.")
		return
	var saved: bool = SaveService.grant_store_coins(product,token)
	settling = false
	pending = ""
	if not saved:
		retry_product = product
		retry_provider = verification_provider
		retry_scope = SaveService.scope_generation
		retry_receipt = receipt
		status_changed.emit("Could not save your purchase. Please retry delivery.")
		return
	retry_receipt = ""
	provider.acknowledge_consumed(receipt)
	status_changed.emit("Purchase delivered.")
func retry_delivery() -> void:
	if retry_scope!=SaveService.scope_generation or retry_provider!=provider:
		retry_receipt = ""
		return
	if not retry_receipt.is_empty():
		_settle(retry_receipt,retry_product)
func restore_purchases() -> void:
	if available() and pending.is_empty() and not settling:
		var scope_ticket: int = SaveService.scope_generation
		var provider_ticket: RushPurchaseProvider = provider
		var epoch_ticket: int = epoch
		provider.restore_unconsumed(func(receipt: String) -> void:
			if scope_ticket==SaveService.scope_generation and provider_ticket==provider and epoch_ticket==epoch: _restore_receipt(receipt))
func _restore_receipt(receipt: String) -> void:
	if pending.is_empty() and not receipt.is_empty():
		_settle(receipt)
