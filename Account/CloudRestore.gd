class_name RushCloudRestore
extends RefCounted
## Pure candidate construction. No reward grants, disk writes or runtime effects.
static func merge_missing(local: Dictionary, incoming: Dictionary) -> Dictionary:
	var result: Dictionary = local.duplicate(true)
	for key: String in incoming:
		if incoming[key] is Dictionary and result.get(key) is Dictionary:
			result[key] = merge_missing(result[key],incoming[key])
		else:
			result[key] = incoming[key]
	return result
static func safe_tree(value: Variant, depth: int = 0) -> bool:
	if depth>16: return false
	if value==null or value is bool: return true
	if value is String: return value.length()<=4096
	if value is int or value is float: return is_finite(float(value)) and absf(float(value))<=RushProgressionData.LIMIT
	if value is Array:
		if value.size()>4096: return false
		for item: Variant in value:
			if not safe_tree(item,depth+1): return false
		return true
	if value is Dictionary:
		if value.size()>20000: return false
		for key: Variant in value:
			if not key is String or key.length()>256 or not safe_tree(value[key],depth+1): return false
		return true
	return false
static func compatible(base: Variant, value: Variant) -> bool:
	if (base is int or base is float) and (value is int or value is float): return is_finite(float(value))
	if typeof(base)!=typeof(value): return false
	if base is Dictionary:
		for key: String in value:
			if base.has(key) and not compatible(base[key],value[key]): return false
	return true
static func integer(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and float(value)>=0 and float(value)<=maximum
static func candidate(local: Dictionary, docs: Dictionary) -> Dictionary:
	if not safe_tree(docs) or not docs.get("profile") is Dictionary: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C001")
	var profile: Dictionary = docs.profile
	if int(profile.get("schema_version",0))!=5: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C002")
	var next: Dictionary = local.duplicate(true)
	for path: String in ["progression/main","inventory/main","meta/main"]:
		if docs.has(path) and not docs[path] is Dictionary: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C003")
	var meta: Dictionary = docs.get("meta/main",{})
	var mapping: Dictionary = {"settings":"settings","onboarding":"onboarding","wallet_ledger":"wallet","membership_cache":"membership","purchase_claims":"store_claims"}
	for source: String in mapping:
		if not meta.has(source): continue
		var dest: String = mapping[source]
		if not meta[source] is Dictionary or not compatible(next.get(dest,{}),meta[source]): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C004")
		next[dest] = merge_missing(next.get(dest,{}),meta[source])
	if docs.has("progression/main"):
		if not compatible(next.progression,docs["progression/main"]): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C005")
		next.progression = merge_missing(next.progression,docs["progression/main"])
	if docs.has("inventory/main"):
		if not compatible(next.consumables,docs["inventory/main"]): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C006")
		next.consumables = merge_missing(next.consumables,docs["inventory/main"])
	# Economy restore requires the matching replay ledgers, never amounts alone.
	if (profile.has("coins") and profile.coins!=next.wallet.coins) or docs.has("inventory/main"):
		if not meta.get("wallet_ledger") is Dictionary or not meta.get("purchase_claims") is Dictionary or not meta.get("membership_cache") is Dictionary: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C007")
		for key: String in ["issued_run","settled_run","receipt"]:
			if not meta.wallet_ledger.has(key): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C008")
		if not docs.get("inventory/main") is Dictionary: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C009")
		for key: String in ["ad_issued","ad_settled","double_reward_run","initial_grant_claimed"]:
			if not docs["inventory/main"].has(key): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C010")
	if profile.has("coins"):
		if not integer(profile.coins,SaveService.MAX_COINS): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C011")
		if meta.get("wallet_ledger",{}).has("coins") and profile.coins!=meta.wallet_ledger.coins: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C012")
		next.wallet.coins = int(profile.coins)
	if profile.has("xp") and not docs.get("progression/main",{}).has("xp"):
		next.progression.xp = profile.xp
	if profile.has("display_name") and not docs.get("progression/main",{}).has("name"):
		next.progression.name = profile.display_name
	for id: String in RushVehicleCatalog.IDS:
		var path: String = "cars/"+id
		if not docs.has(path): continue
		if not docs[path] is Dictionary: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C013")
		var car: Dictionary = docs[path]
		if car.has("owned"):
			if not car.owned is bool: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C014")
			if car.owned and id not in next.collection.owned: next.collection.owned.append(id)
			if not car.owned: next.collection.owned.erase(id)
		if car.has("custom_name"):
			if not car.custom_name is String: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C015")
			next.collection.names[id] = SaveService.clean_car_name(car.custom_name)
		if car.has("paint_index"):
			if not integer(car.paint_index,RushVehicleCatalog.paint_count()-1): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C016")
			next.collection.paints[id] = int(car.paint_index)
		if car.has("upgrades"):
			if not car.upgrades is Dictionary: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C017")
			for category: String in car.upgrades:
				if category not in RushVehicleCatalog.CATEGORIES or not integer(car.upgrades[category],10): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C018")
				next.collection.upgrades[id][category] = int(car.upgrades[category])
	if meta.has("upgrade_ads"):
		if not meta.upgrade_ads is Dictionary: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C019")
		next.collection.upgrade_ads = merge_missing(next.collection.get("upgrade_ads",{}),meta.upgrade_ads)
	if profile.has("selected_car"):
		if not profile.selected_car is String: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C020")
		next.collection.selected = profile.selected_car
	if "vortex_s" not in next.collection.owned or next.collection.selected not in next.collection.owned: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C021")
	for key: String in ["coins","issued_run","settled_run"]:
		if not integer(next.wallet.get(key),SaveService.MAX_COINS): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C022")
	if next.wallet.settled_run>next.wallet.issued_run: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C023")
	for key: String in ["issued_run","settled_run"]:
		if int(next.wallet[key])<int(local.wallet.get(key,0)): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C024")
	if not next.wallet.get("receipt",{}) is Dictionary: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C025")
	if not next.wallet.receipt.is_empty():
		if not integer(next.wallet.receipt.get("run_id",0),int(next.wallet.settled_run)): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C026")

	for key: String in ["turbo_inventory","repair_kits","coin_magnets","shields","ad_issued","ad_settled","double_reward_run"]:
		if not integer(next.consumables.get(key,0),SaveService.MAX_TURBO if key=="turbo_inventory" else SaveService.MAX_COINS): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C027")
	if next.consumables.ad_settled>next.consumables.ad_issued: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C028")
	for key: String in ["ad_issued","ad_settled","double_reward_run"]:
		if int(next.consumables.get(key,0))<int(local.consumables.get(key,0)): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C029")
	if bool(local.consumables.get("initial_grant_claimed",false)) and not bool(next.consumables.get("initial_grant_claimed",false)): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C030")
	for claim: Variant in local.progression.get("achievement_claims",[]):
		if claim not in next.progression.get("achievement_claims",[]): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C031")
	if String(next.progression.get("last_claim_date",""))<String(local.progression.get("last_claim_date","")): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C032")

	if not integer(next.progression.get("xp"),int(RushProgressionData.LIMIT)): return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C033")
	# Validate structures consumed by normalizer's typed loops; reject malformed data.
	var daily: Dictionary = next.progression.get("daily",{})
	if not daily.get("tasks",[]) is Array: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C034")
	for task: Variant in daily.get("tasks",[]):
		if not task is Dictionary or not task.get("id") is String or not (task.get("progress",0) is int or task.get("progress",0) is float) or not task.get("claimed",false) is bool: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C035")
	for key: String in ["achievement_claims","achievement_notices"]:
		for claim: Variant in next.progression.get(key,[]):
			if not claim is String: return RushRemoteEdit.reject("RESTORE_CANDIDATE_INVALID:C036")
	for key: String in next.settings:
		if SaveService.DEFAULTS.has(key): next.settings[key] = SaveService._validated(key,next.settings[key])
	# Derive level from XP, normalize supported progression without rewarding it.
	next.progression = RushProgressionData.normalize(next.progression,next.collection,int(next.wallet.issued_run))
	# A remote cache is never used to activate the membership verifier.
	return next

static func is_new(local: Dictionary) -> bool:
	var wallet: Dictionary = local.get("wallet",{})
	var progression: Dictionary = local.get("progression",{})
	var inventory: Dictionary = local.get("consumables",{})
	var collection: Dictionary = local.get("collection",{})
	if int(wallet.get("coins",0))!=0 or int(wallet.get("issued_run",0))!=0 or int(progression.get("xp",0))!=0: return false
	if String(progression.get("name","Racer"))!="Racer" or collection.get("owned",[])!=["vortex_s"]: return false
	if not local.get("store_claims",{}).is_empty() or not local.get("membership",{}).get("period_claims",{}).is_empty(): return false
	if not progression.get("achievement_claims",[]).is_empty() or not String(progression.get("last_claim_date","")).is_empty(): return false
	if int(inventory.get("ad_issued",0))!=0 or int(inventory.get("turbo_inventory",0))>2: return false
	for key: String in ["repair_kits","coin_magnets","shields"]:
		if int(inventory.get(key,0))!=0: return false
	for id: String in collection.get("names",{}):
		if not String(collection.names[id]).is_empty(): return false
	for id: String in collection.get("paints",{}):
		if int(collection.paints[id])!=int(RushVehicleCatalog.definition(id).default_paint): return false
	for id: String in collection.get("upgrades",{}):
		for category: String in collection.upgrades[id]:
			if int(collection.upgrades[id][category])!=0: return false
	return true
