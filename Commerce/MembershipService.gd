class_name RushMembershipService
extends RefCounted
signal status_changed(message: String)
var provider: RushPurchaseProvider
var pending: bool = false
var request_id: int = 0
var retry_receipt: String = ""
var retry_plan: String = ""
var verifier: Object
func claim_period(receipt: String, expected_plan: String = "") -> bool:
	# No local/debug entitlement override. Verifier must return a validated paid period.
	if not is_instance_valid(verifier) or not verifier.has_method("verify_paid_period"):
		return false
	var result: Variant = verifier.call("verify_paid_period",receipt)
	if not result is Dictionary or not bool(result.get("verified",false)):
		return false
	var period: String = String(result.get("period_id",""))
	var account: String = String(result.get("account_id",""))
	var plan: String = String(result.get("plan",""))
	if period.is_empty() or account.is_empty() or plan not in ["weekly","monthly"] or SaveService.transaction_busy or (not expected_plan.is_empty() and expected_plan!=plan):
		return false
	var marker: String = account+":"+plan+":"+period
	var claims: Dictionary = SaveService.membership.get("period_claims",{})
	if claims.has(marker):
		# Restore verified expiry/grace/cancellation metadata without another bundle.
		var previous_metadata: Dictionary = SaveService.membership.duplicate(true)
		SaveService.membership.metadata = result.duplicate(true)
		SaveService.transaction_busy = true
		var restored: bool = SaveService.commit()
		SaveService.transaction_busy = false
		if not restored:
			SaveService.membership = previous_metadata
		return restored
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/Memberships.json"))
	var bundle: Dictionary = config[plan]
	var coin_reward: int = int(bundle.get("initial_coins",0))
	if coin_reward<0 or SaveService.balance()>SaveService.MAX_COINS-coin_reward:
		return false
	var coins_before: int = SaveService.balance()
	var before: Dictionary = SaveService.consumables.duplicate(true)
	var old_membership: Dictionary = SaveService.membership.duplicate(true)
	for key: String in ["turbo","magnets","repairs"]:
		var storage_key: String = {"turbo":"turbo_inventory","magnets":"coin_magnets","repairs":"repair_kits"}[key]
		var limit: int = SaveService.MAX_TURBO if key=="turbo" else SaveService.MAX_COINS
		if int(SaveService.consumables.get(storage_key,0))>limit-int(bundle[key]):
			SaveService.consumables = before
			return false
		SaveService.consumables[storage_key] = int(SaveService.consumables.get(storage_key,0))+int(bundle[key])
	claims = claims.duplicate(true)
	claims[marker] = true
	SaveService.membership.period_claims = claims
	SaveService.membership.metadata = result.duplicate(true)
	SaveService.wallet.coins = coins_before+coin_reward
	SaveService.transaction_busy = true
	var saved: bool = SaveService.commit()
	SaveService.transaction_busy = false
	if not saved:
		SaveService.consumables = before
		SaveService.wallet.coins = coins_before
		SaveService.membership = old_membership
	else:
		SaveService.turbo_inventory_changed.emit()
		SaveService.wallet_changed.emit(SaveService.balance())
	return saved

func localized_price(plan: String) -> String:
	if provider==null or not provider.available():
		return ""
	var details: Dictionary = provider.localized_product(plan)
	return String(details.get("formatted_price","")) if bool(details.get("available",false)) else ""
func ready(plan: String) -> bool:
	# Never sell the advertised pass until its provider integration supports all benefits.
	return provider!=null and provider.available() and provider.has_method("acknowledge_subscription") and provider.has_method("restore_subscriptions") and is_instance_valid(verifier) and verifier.has_method("verify_paid_period") and verifier.has_method("membership_features_ready") and bool(verifier.call("membership_features_ready",plan)) and not localized_price(plan).is_empty()
func request_plan(plan: String) -> bool:
	if pending or not retry_receipt.is_empty() or not ready(plan):
		status_changed.emit("Google Play purchase setup is currently unavailable.")
		return false
	pending = true
	request_id += 1
	status_changed.emit("Waiting for purchase confirmation…")
	var accepted: bool = provider.purchase(plan,_completed.bind(plan,request_id))
	if not accepted:
		pending = false
		status_changed.emit("Purchase could not be started.")
	return accepted
func _completed(receipt: String, plan: String, expected_request: int) -> void:
	if not pending or expected_request!=request_id:
		return
	pending = false
	if receipt.is_empty():
		status_changed.emit("Purchase cancelled or unavailable.")
		return
	if not claim_period(receipt,plan):
		retry_receipt = receipt
		retry_plan = plan
		status_changed.emit("Your membership could not be delivered. Please retry.")
		return
	if provider!=null and provider.has_method("acknowledge_subscription"):
		provider.call("acknowledge_subscription",receipt)
	status_changed.emit("Verified membership rewards delivered.")
func retry_delivery() -> void:
	if retry_receipt.is_empty() or pending:
		return
	var receipt: String = retry_receipt
	var plan: String = retry_plan
	retry_receipt = ""
	retry_plan = ""
	pending = true
	request_id += 1
	_completed(receipt,plan,request_id)
func entitlement_state() -> String:
	# Display only. Gameplay benefits must use provider-authoritative entitlements.
	var metadata: Dictionary = SaveService.membership.get("metadata",{})
	var state: String = String(metadata.get("state","INACTIVE"))
	if state not in ["INACTIVE","ACTIVE","GRACE_PERIOD","EXPIRED"]:
		return "INACTIVE"
	var end: int = int(metadata.get("expires_at",0))
	if state in ["ACTIVE","GRACE_PERIOD"] and (end<=0 or end<=int(Time.get_unix_time_from_system())):
		return "EXPIRED"
	return state

func restore_purchases() -> void:
	if pending or provider==null or not provider.available() or not is_instance_valid(verifier) or not provider.has_method("restore_subscriptions"):
		return
	var scope_ticket: int = SaveService.scope_generation
	provider.call("restore_subscriptions",func(receipt: String) -> void:
		if scope_ticket==SaveService.scope_generation: _restore_receipt(receipt))
func _restore_receipt(receipt: String) -> void:
	if pending or receipt.is_empty():
		return
	if claim_period(receipt):
		if provider!=null and provider.has_method("acknowledge_subscription"):
			provider.call("acknowledge_subscription",receipt)
		status_changed.emit("Verified membership restored.")
