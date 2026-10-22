class_name RushRewardedAdService
extends Node
## A provider must call the earned callback ONLY from its verified SDK reward event.
## RushAdService supplies native SDK events; SaveService remains the reward authority.
signal status_changed(message: String)
var turbo_delegate: Callable
var grant: Callable
var settling: bool = false
var completion_message: String = "Reward saved."
var provider: Node
var pending: int = 0
var request_scope: int = -1
var request_provider: Node
var earned: bool = false
var debug_request: bool = false
func request_turbo_reward() -> bool:
	_scope_valid()
	if turbo_delegate.is_valid():
		return bool(turbo_delegate.call(false))
	if pending!=0:
		return false
	if provider==null or not provider.has_method("request_rewarded"):
		status_changed.emit("Rewarded ad unavailable right now.")
		return false
	if provider.has_method("can_request_rewarded") and not bool(provider.call("can_request_rewarded","TURBO_REFILL")):
		status_changed.emit("Rewarded ad unavailable right now. Please try again shortly.")
		return false
	request_provider = provider
	request_scope = SaveService.scope_generation
	pending = SaveService.reserve_ad_request()
	if pending==0:
		status_changed.emit("Could not save your reward. Please try again.")
		return false
	earned = false
	debug_request = false
	provider.call("request_rewarded",pending,_reward_earned,_closed_without_reward,"TURBO_REFILL")
	return true
func _reward_earned(token: int) -> void:
	if not _scope_valid(): return
	if pending==0 or token!=pending:
		return
	earned = true
	retry_pending_reward()
func retry_pending_reward() -> bool:
	if not _scope_valid(): return false
	if pending==0 or not earned or settling:
		return false
	settling = true
	var saved := bool(grant.call(pending)) if grant.is_valid() else SaveService.settle_ad_request(pending,true)
	settling = false
	if not saved:
		status_changed.emit("Could not save your reward. Please try again.")
		return false
	pending = 0
	earned = false
	grant = Callable()
	status_changed.emit(completion_message)
	return true
func _closed_without_reward(token: int) -> void:
	if not _scope_valid(): return
	if token!=pending or pending==0 or earned:
		return
	SaveService.settle_ad_request(pending,false)
	pending = 0
	grant = Callable()
	debug_request = false
	status_changed.emit("Ad incomplete or unavailable. Nothing was consumed.")
func debug_begin() -> bool:
	if turbo_delegate.is_valid():
		return bool(turbo_delegate.call(true))
	if not OS.is_debug_build() or pending!=0:
		return false
	request_provider = provider
	request_scope = SaveService.scope_generation
	pending = SaveService.reserve_ad_request()
	debug_request = pending>0
	earned = false
	status_changed.emit("Test ad ready: complete or skip.")
	return debug_request
func debug_complete(completed: bool) -> void:
	if not OS.is_debug_build() or not debug_request or pending==0:
		return
	debug_request = false
	if completed:
		_reward_earned(pending)
	else:
		_closed_without_reward(pending)

func request_offer(callback: Callable, simulate: bool = false, placement: String = "") -> bool:
	_scope_valid()
	if pending!=0 or not callback.is_valid() or (simulate and not OS.is_debug_build()):
		return false
	if not simulate and (provider==null or not provider.has_method("request_rewarded")):
		status_changed.emit("Rewarded ad unavailable right now.")
		return false
	if not simulate and provider.has_method("can_request_rewarded") and not bool(provider.call("can_request_rewarded",placement)):
		status_changed.emit("Rewarded ad unavailable right now. Please try again shortly.")
		return false
	request_provider = provider
	request_scope = SaveService.scope_generation
	pending = SaveService.reserve_ad_request()
	if pending==0:
		status_changed.emit("Could not save your reward. Please try again.")
		return false
	grant = callback
	completion_message = "Reward saved."
	earned = false
	debug_request = simulate
	if simulate:
		status_changed.emit("Test ad ready: complete or skip.")
	else:
		provider.call("request_rewarded",pending,_reward_earned,_closed_without_reward,placement)
	return true

func request_upgrade_reward(id: String, category: String, target: int, simulate: bool = false) -> bool:
	if not SaveService.owns(id) or category not in RushVehicleCatalog.CATEGORIES or target>10 or target<1:
		return false
	if int(SaveService.collection.upgrades[id][category])+1!=target:
		return false
	return request_offer(SaveService.settle_upgrade_reward.bind(id,category,target),simulate,"GARAGE_UPGRADE")

func _scope_valid() -> bool:
	if request_scope==SaveService.scope_generation and (debug_request or request_provider==provider): return true
	pending = 0
	earned = false
	grant = Callable()
	debug_request = false
	return false
