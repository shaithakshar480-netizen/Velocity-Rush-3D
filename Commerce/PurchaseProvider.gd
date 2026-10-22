class_name RushPurchaseProvider
extends RefCounted
## Adapter contract. Real implementation must verify receipt signature, package,
## product, paid state and stable purchase token through a trusted verifier.
## Never treat purchase-dialog completion or pending payment as verification.
func available() -> bool:
	return false
func localized_product(_product_id: String) -> Dictionary:
	# Expected keys: formatted_price, currency_code, price_micros, available.
	return {}
func purchase(_product_id: String, _callback: Callable) -> bool:
	# Callback(receipt: String). Empty receipt means cancelled/failed.
	return false
func verify_receipt(_receipt: String) -> Dictionary:
	# verified, product_id, purchase_token, paid; no caller-supplied reward amount.
	return {}
func acknowledge_consumed(_receipt: String) -> void:
	# Called only after durable grant (including duplicate-redelivery).
	pass
func restore_unconsumed(_callback: Callable) -> void:
	pass
