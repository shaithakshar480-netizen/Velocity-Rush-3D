class_name RushRemoteEdit
extends RefCounted
## No grants or disk writes. Resolve existing mirrors only against a clean baseline.
static func same(a: Variant, b: Variant) -> bool:
	return RushFirestoreCodec.digest({"v":a})==RushFirestoreCodec.digest({"v":b})
static func wire_fields(fields: Dictionary, depth: int = 0) -> bool:
	if depth>16: return false
	for key: String in fields:
		var value: Variant = fields[key]
		if not value is Dictionary or value.size()!=1: return false
		if depth==0 and key in ["created_at","last_login_at","updated_at"]:
			if stamp(value.get("timestampValue")).is_empty(): return false
		elif not wire_value(value,depth): return false
	return true
static func wire_value(value: Dictionary, depth: int) -> bool:
	if depth>16 or value.size()!=1: return false
	if value.has("stringValue"): return value.stringValue is String
	if value.has("integerValue"): return value.integerValue is String and value.integerValue.is_valid_int()
	if value.has("doubleValue"): return (value.doubleValue is int or value.doubleValue is float) and is_finite(float(value.doubleValue))
	if value.has("booleanValue"): return value.booleanValue is bool
	if value.has("nullValue"): return value.nullValue==null or value.nullValue=="NULL_VALUE"
	if value.has("mapValue"):
		return value.mapValue is Dictionary and value.mapValue.get("fields",{}) is Dictionary and wire_fields(value.mapValue.get("fields",{}),depth+1)
	if value.has("arrayValue"):
		if not value.arrayValue is Dictionary or not value.arrayValue.get("values",[]) is Array: return false
		for item: Variant in value.arrayValue.get("values",[]):
			if not item is Dictionary or not wire_value(item,depth+1): return false
		return true
	return false
static func mirror(a: Variant, b: Variant, baseline: Variant) -> Dictionary:
	if same(a,b): return {"value":a}
	if same(a,baseline): return {"value":b}
	if same(b,baseline): return {"value":a}
	return {}
static func stamp(value: Variant) -> String:
	if not value is String: return ""
	var pattern: RegEx = RegEx.new()
	pattern.compile("^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(?:\\.([0-9]{1,9}))?Z$")
	var found: RegExMatch = pattern.search(value)
	if found==null: return ""
	return found.get_string(1)+"."+found.get_string(2).rpad(9,"0")+"Z"
static func newer(remote: Dictionary, marker: Dictionary) -> bool:
	var revision: int = int(remote.get("revision",0))
	if revision<int(marker.get("revision",0)): return false
	var versions: Dictionary = remote.get("versions",{})
	var baseline: Dictionary = marker.get("versions",{})
	var advanced: bool = revision>int(marker.get("revision",0))
	for path: String in versions:
		var current: String = stamp(versions[path])
		if current.is_empty(): return false
		if baseline.has(path):
			var previous: String = stamp(baseline[path])
			if previous.is_empty() or current<previous: return false
			if current>previous: advanced = true
		else:
			advanced = true
	for path: String in baseline:
		if not versions.has(path): return false # deletion has no usable updateTime
	if baseline.is_empty():
		# Upgrade bridge: unchanged stored digest identifies the last acknowledged
		# canonical revision; changed actual content is its out-of-band successor.
		return revision==int(marker.get("revision",0)) and not String(marker.get("digest","")).is_empty() and String(remote.get("stored_digest",""))==String(marker.digest)
	return advanced
static func prepare(local: Dictionary, incoming: Dictionary, versions: Dictionary = {}, bootstrap: bool = false, stored_digest: String = "") -> Dictionary:
	if not RushCloudRestore.safe_tree(incoming): return reject("ROOT_INVALID:B001")
	var docs: Dictionary = incoming.duplicate(true)
	structural(docs)
	if not normalize_coin_mirror(docs,versions,stored_digest): return {}
	if not legacy_metadata(docs): return reject("LEGACY_COMPATIBILITY_FAILED")
	if not canonical_wallet(docs): return {}
	for path: String in ["profile","progression/main","inventory/main","meta/main"]:
		if not docs.get(path) is Dictionary: return reject("MISSING_REQUIRED_DOCUMENT:B002")
	for path: String in docs:
		if path not in ["profile","progression/main","inventory/main","meta/main"] and (not path.begins_with("cars/") or path.trim_prefix("cars/") not in RushVehicleCatalog.IDS): return reject("ROOT_INVALID:B003")
	var root: Dictionary = docs.profile
	var p: Dictionary = docs["progression/main"]
	var meta: Dictionary = docs["meta/main"]
	if not meta.get("wallet_ledger") is Dictionary: return reject("WALLET_INVALID:B004")
	for key: String in meta:
		if key not in ["settings","onboarding","wallet_ledger","purchase_claims","membership_cache","upgrade_ads"]: return reject("ROOT_INVALID:B005")
	for key: String in meta.wallet_ledger:
		if key not in ["coins","issued_run","settled_run","receipt"]: return reject("WALLET_INVALID:B006")
	var xp_mismatch: bool = not same(root.get("xp"),p.get("xp"))
	var level_mismatch: bool = not same(root.get("level"),p.get("level"))
	var pairs: Array = [["coins",meta.wallet_ledger,"coins",local.wallet.coins],["xp",p,"xp",local.progression.xp],["level",p,"level",local.progression.level],["display_name",p,"name",local.progression.name]]
	for pair: Array in pairs:
		if not root.has(pair[0]) or not pair[1].has(pair[2]): return reject("MIRROR_FIELD_MISSING:B007:"+String(pair[0]).to_upper())
		var resolved: Dictionary = mirror(root[pair[0]],pair[1][pair[2]],pair[3])
		if bootstrap:
			var path: String = "meta/main" if pair[0]=="coins" else "progression/main"
			resolved = remote_mirror(root[pair[0]],pair[1][pair[2]],versions.get("profile"),versions.get(path))
		if resolved.is_empty(): return reject("MIRROR_AMBIGUOUS:B008:"+String(pair[0]).to_upper())
		root[pair[0]] = resolved.value
		pair[1][pair[2]] = resolved.value
	RushProgressionData.prepare()
	if not RushCloudRestore.integer(p.xp,RushProgressionData.threshold(int(RushProgressionData.spec.max_level))): return reject("XP_LEVEL_INVALID:B009")
	if not RushCloudRestore.integer(p.level,int(RushProgressionData.spec.max_level)) or p.level<1: return reject("XP_LEVEL_INVALID:B010")
	var xp_changed: bool = not same(p.xp,local.progression.xp)
	var level_changed: bool = not same(p.level,local.progression.level)
	if bootstrap:
		if level_mismatch and not xp_mismatch: p.xp = RushProgressionData.threshold(int(p.level))
		elif level_mismatch and xp_mismatch and int(p.level)!=RushProgressionData.level_for(int(p.xp)): return reject("XP_LEVEL_INVALID:B011")
		elif not xp_mismatch and int(p.level)!=RushProgressionData.level_for(int(p.xp)): return reject("XP_LEVEL_INVALID:B012")
	elif level_changed and not xp_changed: p.xp = RushProgressionData.threshold(int(p.level))
	elif not bootstrap and xp_changed and level_changed and int(p.level)!=RushProgressionData.level_for(int(p.xp)): return reject("XP_LEVEL_INVALID:B013")
	p.level = RushProgressionData.level_for(int(p.xp))
	root.xp = p.xp
	root.level = p.level
	if not bootstrap:
		# Protected replay/entitlement metadata cannot be edited through this route.
		for key: String in ["issued_run","settled_run","receipt"]:
			if not same(meta.wallet_ledger.get(key),local.wallet.get(key)): return reject("WALLET_INVALID:B014")
		for key: String in ["purchase_claims","membership_cache","upgrade_ads"]:
			var baseline: Variant = local.store_claims if key=="purchase_claims" else (local.membership if key=="membership_cache" else local.collection.get("upgrade_ads",{}))
			if not same(meta.get(key),baseline): return reject("PROTECTED_FIELD_INVALID:B015")
		for key: String in docs["inventory/main"]:
			if key not in ["turbo_inventory","repair_kits","coin_magnets","shields"] and not local.consumables.has(key): return reject("PROTECTED_FIELD_INVALID:B016")
			if key not in ["turbo_inventory","repair_kits","coin_magnets","shields"] and not same(docs["inventory/main"][key],local.consumables.get(key)): return reject("PROTECTED_FIELD_INVALID:B017")
		# Auth fields are descriptive mirrors, never an editable Firebase identity.
		if root.get("provider")!=AuthService.user.get("provider","anonymous") or root.get("email")!=AuthService.current_user_email() or root.get("is_guest")!=AuthService.is_guest(): return reject("PROTECTED_FIELD_INVALID:B018")
		for key: String in ["last_started","last_finalized","last_reward_id","run_checkpoint","pending_level"]:
			if not same(p.get(key),local.progression.get(key)): return reject("PROTECTED_FIELD_INVALID:B019")
	else:
		# Bootstrap has no prior reward ledger. Restore the validated remote ledger,
		# never synthesize grants; auth identity still comes from the provider.
		root["email"] = AuthService.current_user_email()
		root["provider"] = AuthService.user.get("provider","anonymous")
		root["is_guest"] = AuthService.is_guest()
	# Normalise remote settings for documented legacy preset compatibility.
	# Preserves strict schema validation: unknown keys are retained so valid() rejects
	# them with SETTINGS_INVALID:B058, and type-incompatible values are left untouched
	# so valid() rejects genuinely malformed data. Only known, type-compatible values
	# (such as legacy map_time sentinels -1, 3, 4, 5 written by earlier builds) are
	# normalised through SaveService._validated() to valid presets before strict validation.
	# Wallet, progression, inventory, cars, and all other documents are untouched.
	if meta.get("settings") is Dictionary:
		var normalised_settings: Dictionary = meta.settings.duplicate(true)
		for key: String in normalised_settings:
			if SaveService.DEFAULTS.has(key):
				var raw: Variant = normalised_settings[key]
				if RushCloudRestore.compatible(SaveService.DEFAULTS[key], raw):
					normalised_settings[key] = SaveService._validated(key, raw)
		meta["settings"] = normalised_settings
		RushAuthDiagnostics.stage("REMOTE_SETTINGS_COMPAT_NORMALISED")
	return docs if valid(local,docs) else {}
static func valid(local: Dictionary, docs: Dictionary) -> bool:
	var root: Dictionary = docs.profile
	var p: Dictionary = docs["progression/main"]
	var meta: Dictionary = docs["meta/main"]
	# Imported replay metadata must keep the existing shapes and bounds too.
	for key: String in ["coins","issued_run","settled_run"]:
		if not RushCloudRestore.integer(meta.wallet_ledger.get(key),SaveService.MAX_COINS): return invalid("WALLET_INVALID:B020:"+key.to_upper())
	for key: String in ["purchase_claims","membership_cache","upgrade_ads"]:
		if not meta.get(key) is Dictionary: return invalid("WALLET_INVALID:B021")
	for token_hash: String in meta.purchase_claims:
		if token_hash.length()!=64 or not meta.purchase_claims[token_hash] is String or RushStoreCatalog.find_offer("coin_packs",meta.purchase_claims[token_hash]).is_empty(): return invalid("WALLET_INVALID:B022")
	if not meta.membership_cache.get("period_claims",{}) is Dictionary or not meta.membership_cache.get("metadata",{}) is Dictionary: return invalid("WALLET_INVALID:B023")
	for claim: String in meta.membership_cache.get("period_claims",{}):
		if not meta.membership_cache.period_claims[claim] is bool: return invalid("WALLET_INVALID:B024")
	for key: String in ["last_started","last_finalized"]:
		if not RushCloudRestore.integer(p.get(key),int(RushProgressionData.LIMIT)): return invalid("WALLET_INVALID:B025")
	if p.last_finalized>p.last_started or p.last_started>meta.wallet_ledger.get("issued_run",0): return invalid("WALLET_INVALID:B026")
	if not p.get("last_reward_id") is String or not p.get("run_checkpoint") is Dictionary or not p.get("pending_level") is Dictionary: return invalid("WALLET_INVALID:B027")
	for key: String in p.run_checkpoint:
		if key not in RushProgressionData.SUM_FIELDS+RushProgressionData.MAX_FIELDS+["run_id"]: return invalid("WALLET_INVALID:B028")
		if not (p.run_checkpoint[key] is int or p.run_checkpoint[key] is float) or float(p.run_checkpoint[key])<0 or float(p.run_checkpoint[key])>RushProgressionData.LIMIT: return invalid("WALLET_INVALID:B029")
	for key: String in p.pending_level:
		if key not in ["old","new","coins"] or not RushCloudRestore.integer(p.pending_level[key],SaveService.MAX_COINS): return invalid("WALLET_INVALID:B030")
	var inventory: Dictionary = docs["inventory/main"]
	for key: String in inventory:
		if key not in ["turbo_inventory","repair_kits","coin_magnets","shields","ad_issued","ad_settled","double_reward_run","initial_grant_claimed"]: return invalid("INVENTORY_INVALID:B031")
	if inventory.has("initial_grant_claimed") and not inventory.initial_grant_claimed is bool: return invalid("INVENTORY_INVALID:B032")
	if not RushCloudRestore.integer(root.get("schema_version"),5) or root.schema_version!=5: return invalid("SCHEMA_INVALID:B033")
	for key: String in root:
		if key not in ["schema_version","coins","xp","level","display_name","email","provider","is_guest","selected_car"]: return invalid("ROOT_INVALID:B034")
	for key: String in ["display_name","email","provider","selected_car"]:
		if not root.get(key) is String: return invalid("ROOT_INVALID:B035")
	if not root.get("is_guest") is bool: return invalid("ROOT_INVALID:B036")
	if root.display_name!=RushProgressionData.clean_name(root.display_name): return invalid("ROOT_INVALID:B037")
	if root.selected_car not in RushVehicleCatalog.IDS: return invalid("ROOT_INVALID:B038")
	for key: String in p:
		if not RushProgressionData.defaults().has(key): return invalid("PROGRESSION_INVALID:B039")
	if not p.get("stats") is Dictionary: return invalid("PROGRESSION_INVALID:B040")
	for key: String in p.stats:
		var value: Variant = p.stats[key]
		if key not in RushProgressionData.STAT_KEYS or not (value is int or value is float) or not is_finite(float(value)) or float(value)<0 or float(value)>RushProgressionData.LIMIT: return invalid("PROGRESSION_INVALID:B041")
		if key=="highest_speed" and float(value)>450: return invalid("PROGRESSION_INVALID:B042")
	for key: String in ["achievement_claims","achievement_notices"]:
		if not p.get(key) is Array: return invalid("PROGRESSION_INVALID:B043")
		var seen: Array = []
		for id: Variant in p[key]:
			var known: bool = false
			for item: Dictionary in RushProgressionData.achievements:
				if id is String and id==item.id: known = true
			if not known or id in seen: return invalid("PROGRESSION_INVALID:B044")
			seen.append(id)
	if not RushCloudRestore.integer(p.get("reward_day"),7): return invalid("PROGRESSION_INVALID:B045")
	for key: String in ["last_claim_date","date_highwater"]:
		if not p.get(key) is String or (not p[key].is_empty() and not RushProgressionData.valid_date(p[key])): return invalid("PROGRESSION_INVALID:B046")
	if not p.get("daily") is Dictionary or not p.daily.get("date") is String or not p.daily.get("tasks") is Array: return invalid("PROGRESSION_INVALID:B047")
	for key: String in p.daily:
		if key not in ["date","tasks"]: return invalid("PROGRESSION_INVALID:B048")
	if p.daily.date.is_empty():
		if not p.daily.tasks.is_empty(): return invalid("PROGRESSION_INVALID:B049")
	else:
		if not RushProgressionData.valid_date(p.daily.date): return invalid("PROGRESSION_INVALID:B050")
		var expected: Dictionary = RushProgressionData.generate_daily(p.daily.date)
		if p.daily.tasks.size()!=expected.tasks.size(): return invalid("PROGRESSION_INVALID:B051")
		for index: int in range(expected.tasks.size()):
			var task: Variant = p.daily.tasks[index]
			if not task is Dictionary: return invalid("PROGRESSION_INVALID:B052")
			for key: String in task:
				if not expected.tasks[index].has(key): return invalid("PROGRESSION_INVALID:B053")
			for key: String in expected.tasks[index]:
				if key not in ["progress","claimed"] and not same(task.get(key),expected.tasks[index][key]): return invalid("PROGRESSION_INVALID:B054")
			if not (task.get("progress") is int or task.get("progress") is float) or task.progress<0 or task.progress>expected.tasks[index].target or not task.get("claimed") is bool: return invalid("PROGRESSION_INVALID:B055")
			if task.claimed and task.progress<expected.tasks[index].target: return invalid("PROGRESSION_INVALID:B056")
	if not meta.get("settings") is Dictionary or not meta.get("onboarding") is Dictionary: return invalid("SETTINGS_INVALID:B057")
	for key: String in meta.settings:
		if not SaveService.DEFAULTS.has(key):
			RushAuthDiagnostics.stage("SETTINGS_REJECTED:" + key + ":UNKNOWN_KEY")
			return invalid("SETTINGS_INVALID:B058:" + key + ":UNKNOWN_KEY")
		if not RushCloudRestore.compatible(SaveService.DEFAULTS[key], meta.settings[key]):
			RushAuthDiagnostics.stage("SETTINGS_REJECTED:" + key + ":TYPE_MISMATCH")
			return invalid("SETTINGS_INVALID:B058:" + key + ":TYPE_MISMATCH")
		if not same(meta.settings[key], SaveService._validated(key, meta.settings[key])):
			RushAuthDiagnostics.stage("SETTINGS_REJECTED:" + key + ":NON_CANONICAL_VALUE")
			return invalid("SETTINGS_INVALID:B058:" + key + ":NON_CANONICAL_VALUE")
	for key: String in meta.onboarding:
		if key not in ["completed","starter"]: return invalid("SETTINGS_INVALID:B059")
	if not meta.onboarding.get("completed") is bool or meta.onboarding.get("starter") not in RushVehicleCatalog.IDS: return invalid("SETTINGS_INVALID:B060")
	for path: String in docs:
		if not path.begins_with("cars/"): continue
		if not docs[path] is Dictionary: return invalid("CAR_INVALID:B061")
		for key: String in docs[path]:
			if key not in ["owned","custom_name","paint_index","upgrades"]: return invalid("CAR_INVALID:B062")
		if docs[path].has("custom_name") and (not docs[path].custom_name is String or docs[path].custom_name!=SaveService.clean_car_name(docs[path].custom_name)): return invalid("CAR_INVALID:B063")
	# Existing restore validates wallet bounds, inventory, upgrades, ownership and
	# monotonic reward claims; it also preserves all local-only envelope fields.
	if RushCloudRestore.candidate(local,docs).is_empty(): return invalid("RESTORE_CANDIDATE_INVALID")
	return true
static func remote_mirror(a: Variant, b: Variant, a_version: Variant, b_version: Variant) -> Dictionary:
	if same(a,b): return {"value":a}
	var first: String = stamp(a_version)
	var second: String = stamp(b_version)
	if first.is_empty() or second.is_empty() or first==second: return {}
	return {"value":a if first>second else b}

static func invalid(reason: String) -> bool:
	RushAuthDiagnostics.stage("REMOTE_VALIDATION_FAILED:"+reason)
	return false
static func reject(reason: String) -> Dictionary:
	invalid(reason)
	return {}
static func structural(docs: Dictionary) -> void:
	var root: Variant = docs.get("profile")
	var meta: Variant = docs.get("meta/main")
	var flags: Dictionary = {
		"REMOTE_ROOT_PRESENT":root is Dictionary,
		"REMOTE_WALLET_PRESENT":meta is Dictionary and meta.get("wallet_ledger") is Dictionary,
		"REMOTE_PROGRESSION_PRESENT":docs.get("progression/main") is Dictionary,
		"REMOTE_INVENTORY_PRESENT":docs.get("inventory/main") is Dictionary,
		"REMOTE_SCHEMA_SUPPORTED":root is Dictionary and RushCloudRestore.integer(root.get("schema_version"),5) and root.get("schema_version")==5}
	for key: String in flags:
		RushAuthDiagnostics.stage(key+(":true" if bool(flags[key]) else ":false"))
static func legacy_metadata(docs: Dictionary) -> bool:
	# Reconstruct absent presentation metadata only; never erase supplied values,
	# infer purchase claims, grant inventory, or discard an unfinished run ledger.
	var changed: bool = false
	var p: Variant = docs.get("progression/main")
	if p is Dictionary:
		for key: String in ["achievement_notices","pending_level"]:
			if not p.has(key):
				p[key] = [] if key=="achievement_notices" else {}
				changed = true
		if not p.has("run_checkpoint") and p.get("last_started")!=null and p.get("last_started")==p.get("last_finalized"):
			p["run_checkpoint"] = {}
			changed = true
		if not p.has("last_reward_id") and p.get("last_finalized")==0:
			p["last_reward_id"] = ""
			changed = true
	var inventory: Variant = docs.get("inventory/main")
	if inventory is Dictionary and not inventory.has("initial_grant_claimed"):
		# Old cloud accounts must not get an initial reward a second time.
		inventory["initial_grant_claimed"] = true
		changed = true
	RushAuthDiagnostics.stage("REMOTE_LEGACY_COMPAT_PATH:"+("true" if changed else "false"))
	return true

static func canonical_wallet(docs: Dictionary) -> bool:
	var meta: Variant = docs.get("meta/main")
	if not meta is Dictionary or not meta.get("wallet_ledger") is Dictionary: return true # Existing structural rejection.
	var wallet: Dictionary = meta.wallet_ledger
	var p: Variant = docs.get("progression/main")
	if not wallet.has("issued_run") or not wallet.has("settled_run"):
		# Recover only a fully settled redundant checkpoint. Do not guess unfinished
		# history or replace malformed supplied fields; receipt/claims remain intact.
		if not p is Dictionary or not RushCloudRestore.integer(p.get("last_started"),SaveService.MAX_COINS) or not RushCloudRestore.integer(p.get("last_finalized"),SaveService.MAX_COINS):
			return invalid("WALLET_INVALID:B020:MISSING_COUNTER_EVIDENCE")
		if p.last_started!=p.last_finalized or not wallet.get("receipt") is Dictionary:
			return invalid("WALLET_INVALID:B020:UNSETTLED_COUNTER_EVIDENCE")
		var checkpoint: int = int(p.last_finalized)
		var receipt: Dictionary = wallet.receipt
		if (checkpoint==0 and not receipt.is_empty()) or (checkpoint>0 and (not RushCloudRestore.integer(receipt.get("run_id"),SaveService.MAX_COINS) or int(receipt.run_id)!=checkpoint)):
			return invalid("WALLET_INVALID:B020:RECEIPT_COUNTER_MISMATCH")
		for key: String in ["issued_run","settled_run"]:
			if wallet.has(key):
				if not RushCloudRestore.integer(wallet[key],SaveService.MAX_COINS) or int(wallet[key])!=checkpoint:
					return invalid("WALLET_INVALID:B020:COUNTER_EVIDENCE_MISMATCH")
			else: wallet[key] = checkpoint
		RushAuthDiagnostics.stage("REMOTE_WALLET_LEGACY_COUNTERS_RECONSTRUCTED")
	for key: String in ["coins","issued_run","settled_run"]:
		if not RushCloudRestore.integer(wallet.get(key),SaveService.MAX_COINS):
			return invalid("WALLET_INVALID:B020:"+key.to_upper())
		wallet[key] = int(wallet[key])
	return true

static func coin_diagnostics(source: String, container: Dictionary) -> void:
	var value: Variant = container.get("coins")
	var numeric: bool = value is int or value is float
	var integral: bool = numeric and is_finite(float(value)) and float(value)==floor(float(value))
	if numeric and is_finite(float(value)):
		if float(value)<0: RushAuthDiagnostics.stage("WALLET_COINS_RANGE_REASON:NEGATIVE")
		elif float(value)>SaveService.MAX_COINS: RushAuthDiagnostics.stage("WALLET_COINS_RANGE_REASON:OVER_MAX")
	RushAuthDiagnostics.stage("WALLET_COINS_SOURCE:"+source)
	RushAuthDiagnostics.stage("WALLET_COINS_PRESENT:"+("true" if container.has("coins") else "false"))
	RushAuthDiagnostics.stage("WALLET_COINS_TYPE:"+type_string(typeof(value)))
	RushAuthDiagnostics.stage("WALLET_COINS_NUMERIC:"+("true" if numeric else "false"))
	RushAuthDiagnostics.stage("WALLET_COINS_INTEGRAL:"+("true" if integral else "false"))
	RushAuthDiagnostics.stage("WALLET_COINS_RANGE_VALID:"+("true" if numeric and is_finite(float(value)) and float(value)>=0 and float(value)<=SaveService.MAX_COINS else "false"))
static func normalize_coin_mirror(docs: Dictionary, versions: Dictionary, stored_digest: String = "") -> bool:
	var root: Variant = docs.get("profile")
	var meta: Variant = docs.get("meta/main")
	if not root is Dictionary or not meta is Dictionary or not meta.get("wallet_ledger") is Dictionary:
		return true # Existing required-document validation handles structure.
	var wallet: Dictionary = meta.wallet_ledger
	coin_diagnostics("root",root)
	coin_diagnostics("wallet_ledger",wallet)
	var root_valid: bool = RushCloudRestore.integer(root.get("coins"),SaveService.MAX_COINS)
	var wallet_valid: bool = RushCloudRestore.integer(wallet.get("coins"),SaveService.MAX_COINS)
	if root.has("coins") and wallet.has("coins") and root_valid!=wallet_valid:
		var root_stamp: String = stamp(versions.get("profile"))
		var wallet_stamp: String = stamp(versions.get("meta/main"))
		if root_stamp.is_empty() or wallet_stamp.is_empty() or root_stamp==wallet_stamp:
			return invalid("WALLET_INVALID:B020:COINS_AUTHORITY_AMBIGUOUS")
		if root_valid and root_stamp>wallet_stamp:
			wallet["coins"] = int(root.coins)
		elif wallet_valid and wallet_stamp>root_stamp:
			root["coins"] = int(wallet.coins)
		else:
			# A later invalid mirror edit cannot authorize currency. Accept the older
			# valid mirror only if it reconstructs the ENTIRE previously stored snapshot.
			# Both usable server versions and the untouched canonical digest are required.
			var candidate: Dictionary = docs.duplicate(true)
			var value: int = int(root.coins) if root_valid else int(wallet.coins)
			candidate.profile.coins = value
			candidate["meta/main"].wallet_ledger.coins = value
			if stored_digest.length()!=64 or RushFirestoreCodec.digest(candidate)!=stored_digest:
				return invalid("WALLET_INVALID:B020:VALID_COIN_MIRROR_NOT_NEWER")
			root["coins"] = value
			wallet["coins"] = value
			RushAuthDiagnostics.stage("WALLET_COINS_AUTHORITY:STORED_CANONICAL_DIGEST")
	# Never coerce a supplied malformed value (including null/string) into currency.
	# Recover only an absent redundant key from the existing valid root mirror,
	# with server metadata proving the root is at least as recent as the wallet.
	if not wallet.has("coins"):
		var root_version: String = stamp(versions.get("profile"))
		var wallet_version: String = stamp(versions.get("meta/main"))
		if not RushCloudRestore.integer(root.get("coins"),SaveService.MAX_COINS) or root_version.is_empty() or wallet_version.is_empty() or root_version<wallet_version:
			return invalid("WALLET_INVALID:B020:COINS_MISSING_UNPROVEN_MIRROR")
		wallet["coins"] = int(root.coins)
		RushAuthDiagnostics.stage("WALLET_COINS_SOURCE:root_reconstructed_wallet_ledger")
	return true
