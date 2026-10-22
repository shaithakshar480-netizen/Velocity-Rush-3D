extends Node
signal cloud_restored
signal account_scope_changed
var cloud_meta: Dictionary = {}
signal committed
signal collection_changed
var collection: Dictionary = {}
var progression: Dictionary = {}
var onboarding: Dictionary = {"completed":false,"starter":"vortex_s"}
var store_claims: Dictionary = {}
var membership: Dictionary = {"period_claims":{},"metadata":{}}
var transaction_busy: bool = false
signal turbo_inventory_changed
var consumables: Dictionary = {"turbo_inventory":0,"ad_issued":0,"ad_settled":0,"coin_magnets":0,"repair_kits":0,"shields":0}
const MAX_TURBO: int = 99999
signal changed
signal save_failed(message: String)
signal wallet_changed(balance: int)
const LEGACY_PATH: String = "user://settings.json"
var PATH: String = "user://accounts/guest/settings.json"
var BACKUP: String = "user://accounts/guest/settings.backup.json"
var TEMP: String = "user://accounts/guest/settings.pending.json"
var scope_uid: String = ""
var scope_generation: int = 0
var bootstrap_pending: bool = false
var guest_import_pending: bool = false
var scope_local_available: bool = false
var scope_write_allowed: bool = false
const DEFAULTS := {"master": 0.8, "music": 0.4, "sfx": 0.8,
 "map": 0, "map_time": 0, "wheel_deadzone": 0.06, "steering": 1.0, "steering_mode": 1, "steering_assist": true, "tilt_invert": false, "tilt_center": 0.0, "tilt_center_saved": false, "vibration": true, "quality": 1, "camera": 0}
var settings: Dictionary = DEFAULTS.duplicate(true)
var last_error: String = ""
var preserved_fields: Dictionary = {}
var recovery_blocked: bool = false
const WALLET_DEFAULTS := {"coins": 0, "issued_run": 0, "settled_run": 0, "receipt": {}}
const MAX_COINS: int = 2000000000
var wallet: Dictionary = WALLET_DEFAULTS.duplicate(true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _migrate_legacy_scope():
		load_settings()
		recovery_blocked = true
		return
	if not _set_scope_paths(""):
		load_settings()
		recovery_blocked = true
		return
	load_settings()
	ensure_initial_turbo_grant()

func load_settings() -> void:
	settings = DEFAULTS.duplicate(true)
	wallet = WALLET_DEFAULTS.duplicate(true)
	preserved_fields = {}
	recovery_blocked = false
	membership = {"period_claims":{},"metadata":{}}
	last_error = ""
	var source_path: String = PATH
	var envelope: Dictionary = _read(PATH)
	if envelope.is_empty():
		source_path = BACKUP
		envelope = _read(BACKUP)
	if envelope.is_empty():
		source_path = TEMP
		envelope = _read(TEMP)
	if envelope.is_empty() and (FileAccess.file_exists(PATH) or FileAccess.file_exists(BACKUP) or FileAccess.file_exists(TEMP)):
		recovery_blocked = true
		_save_rejected("NO_VALID_RECOVERY")
	cloud_meta = envelope.get("cloud_meta",{}).duplicate(true) if envelope.get("cloud_meta") is Dictionary else {}

	var source: Dictionary = envelope.get("settings", {})
	for key: String in DEFAULTS:
		if source.has(key):
			settings[key] = _validated(key, source[key])
	# Version 1 has settings only; absent wallet migrates to zero without altering them.
	var wallet_source: Dictionary = envelope.get("wallet", {})
	for key: String in ["coins", "issued_run", "settled_run"]:
		var value: Variant = wallet_source.get(key, 0)
		if (value is float or value is int) and is_finite(float(value)):
			wallet[key] = clampi(int(value), 0, MAX_COINS)
	wallet["settled_run"] = mini(int(wallet["settled_run"]), int(wallet["issued_run"]))
	if wallet_source.get("receipt") is Dictionary:
		wallet["receipt"] = wallet_source["receipt"].duplicate(true)

	consumables = {"turbo_inventory":0,"ad_issued":0,"ad_settled":0,"coin_magnets":0,"repair_kits":0,"shields":0}
	var inventory_source: Variant = envelope.get("consumables",{})
	if inventory_source is Dictionary:
		for key: String in consumables:
			var value: Variant = inventory_source.get(key,0)
			if (value is int or value is float) and is_finite(float(value)):
				consumables[key] = clampi(int(value),0,MAX_TURBO if key=="turbo_inventory" else MAX_COINS)
	var claimed: Variant = inventory_source.get("initial_grant_claimed",false) if inventory_source is Dictionary else false
	consumables["initial_grant_claimed"] = claimed is bool and claimed
	consumables.ad_settled = mini(int(consumables.ad_settled),int(consumables.ad_issued))
	_load_collection(envelope.get("collection",{}))
	progression = RushProgressionData.normalize(envelope.get("progression",{}),collection,int(wallet.issued_run))
	var claim_source: Variant = envelope.get("store_claims",{})
	store_claims = claim_source.duplicate(true) if claim_source is Dictionary else {}
	var membership_source: Variant = envelope.get("membership",{})
	if membership_source is Dictionary:
		membership = membership_source.duplicate(true)
		if not membership.get("period_claims",{}) is Dictionary:
			membership.period_claims = {}
		if not membership.get("metadata",{}) is Dictionary:
			membership.metadata = {}
	var onboarding_source: Variant = envelope.get("onboarding",{})
	var old_collection: Variant = envelope.get("collection",{})
	var established: bool = old_collection is Dictionary and old_collection.get("selected","") in collection.owned
	var completed: Variant = onboarding_source.get("completed",established) if onboarding_source is Dictionary else established
	onboarding = {"completed":completed is bool and completed,"starter":"vortex_s"}
	var doubled: Variant = inventory_source.get("double_reward_run",0) if inventory_source is Dictionary else 0
	consumables["double_reward_run"] = _safe_level(doubled,MAX_COINS)
	if not envelope.is_empty():
		# Retain fields this version does not interpret, including nested extensions.
		preserved_fields = _unknown_fields(envelope,_current_envelope())
		var canonical_required: bool = source_path!=PATH or int(envelope.schema_version)<5
		for key: String in ["wallet","collection","progression","consumables","onboarding","membership","store_claims","cloud_meta"]:
			if not envelope.has(key): canonical_required = true
		_save_flag("LOCAL_SAVE_MIGRATION_REQUIRED",canonical_required)
		if canonical_required:
			# Preserve the sole valid pending file before commit reuses TEMP.
			if source_path==TEMP and DirAccess.copy_absolute(TEMP,BACKUP)!=OK:
				recovery_blocked = true
				_save_flag("LOCAL_SAVE_MIGRATION_SUCCESS",false)
				_save_rejected("MIGRATION_FAILED")
				return
			var migrated: bool = commit()
			_save_flag("LOCAL_SAVE_MIGRATION_SUCCESS",migrated)
			if not migrated: _save_rejected("MIGRATION_FAILED")



func _save_flag(marker: String, value: bool) -> void:
	RushAuthDiagnostics.stage(marker+(":true" if value else ":false"))

func _scope_key(uid: String) -> String:
	return "guest" if uid.is_empty() else uid.sha256_text()

func _set_scope_paths(uid: String) -> bool:
	var directory: String = "user://accounts/"+_scope_key(uid)
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: return false
	scope_uid = uid
	PATH = directory+"/settings.json"
	BACKUP = directory+"/settings.backup.json"
	TEMP = directory+"/settings.pending.json"
	return true

func _migrate_legacy_scope() -> bool:
	# Never move/delete legacy files or assign an unowned registered save to a user.
	var legacy: Dictionary = {}
	for path: String in [LEGACY_PATH,"user://settings.backup.json","user://settings.pending.json"]:
		if not FileAccess.file_exists(path): continue
		legacy = _read(path)
		if not legacy.is_empty(): break
	if legacy.is_empty(): return true
	var metadata: Dictionary = legacy.get("cloud_meta",{})
	var owner: String = String(metadata.get("owner",""))
	if owner.is_empty():
		var sync: ConfigFile = ConfigFile.new()
		if sync.load("user://cloud_sync.cfg")==OK: owner = String(sync.get_value("sync","owner",""))
	if owner.is_empty():
		var auth: ConfigFile = ConfigFile.new()
		if auth.load("user://account.cfg")==OK and (String(auth.get_value("account","mode","guest"))=="google" or bool(auth.get_value("account","had_cloud_identity",false))):
			RushAuthDiagnostics.stage("ACCOUNT_LEGACY_SAVE_PRESERVED:UNASSIGNED")
			return true
	var directory: String = "user://accounts/"+_scope_key(owner)
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: return false
	# A migration sentinel prevents a later missing cache from resurrecting stale data.
	var sentinel: String = directory+"/legacy-migrated.cfg"
	if FileAccess.file_exists(sentinel): return true
	for suffix: String in ["json","backup.json","pending.json","before_cloud.json"]:
		var source: String = "user://settings."+suffix
		var destination: String = directory+"/settings."+suffix
		if FileAccess.file_exists(source) and not FileAccess.file_exists(destination):
			if DirAccess.copy_absolute(source,destination)!=OK: return false
	var marker: ConfigFile = ConfigFile.new()
	marker.set_value("migration","copied",true)
	return marker.save(sentinel)==OK

func bind_account(uid: String, carry_guest: bool = false) -> bool:
	if transaction_busy or RewardService.active_run!=0: return false
	if uid==scope_uid:
		_save_flag("ACCOUNT_LOCAL_SAVE_AVAILABLE",not bootstrap_pending and not recovery_blocked)
		return not recovery_blocked
	# Flush old runtime state only to its old path before changing any pointer.
	if not bootstrap_pending and not recovery_blocked and not commit(): return false
	var guest: Dictionary = _current_envelope().duplicate(true) if carry_guest else {}
	RushAuthDiagnostics.stage("ACCOUNT_SCOPE_SWITCH")
	if not _set_scope_paths(uid): return false
	scope_generation += 1
	bootstrap_pending = false
	guest_import_pending = false
	load_settings()
	var present: bool = FileAccess.file_exists(PATH) or FileAccess.file_exists(BACKUP) or FileAccess.file_exists(TEMP)
	scope_local_available = present and not recovery_blocked
	_save_flag("ACCOUNT_LOCAL_SAVE_AVAILABLE",scope_local_available)
	if recovery_blocked: return false
	var loaded: Dictionary = _read(PATH) if present else {}
	if present and not String(loaded.get("account_scope",_scope_key(uid))).is_empty() and String(loaded.get("account_scope",_scope_key(uid)))!=_scope_key(uid):
		recovery_blocked = true
		return false
	if present and not String(cloud_meta.get("owner",uid)).is_empty() and String(cloud_meta.get("owner",uid))!=uid:
		recovery_blocked = true
		return false
	bootstrap_pending = not uid.is_empty() and not present
	if present and not guest.is_empty() and not RushCloudRestore.is_new(guest):
		# Both caches survive; a local Guest must not silently merge into an account.
		guest_import_pending = true
	if bootstrap_pending and not guest.is_empty():
		settings = guest.settings.duplicate(true)
		wallet = guest.wallet.duplicate(true)
		collection = guest.collection.duplicate(true)
		progression = guest.progression.duplicate(true)
		consumables = guest.consumables.duplicate(true)
		onboarding = guest.onboarding.duplicate(true)
		membership = guest.membership.duplicate(true)
		store_claims = guest.store_claims.duplicate(true)
		cloud_meta = {}
		guest_import_pending = not RushCloudRestore.is_new(guest)
	if uid.is_empty(): return ensure_initial_turbo_grant()
	return true

func finish_new_account() -> bool:
	if not bootstrap_pending: return true
	scope_write_allowed = true
	var saved: bool = ensure_initial_turbo_grant() and commit()
	scope_write_allowed = false
	if saved:
		bootstrap_pending = false
		guest_import_pending = false
		scope_local_available = true
	return saved

func publish_account_scope() -> void:
	RewardService.active_run = 0
	RewardService.best_before_run = 0.0
	account_scope_changed.emit()
	cloud_restored.emit()
	changed.emit()
	collection_changed.emit()
	turbo_inventory_changed.emit()
	wallet_changed.emit(balance())
	RewardService.progression_changed.emit()

func _save_rejected(reason: String) -> Dictionary:
	RushAuthDiagnostics.stage("LOCAL_SAVE_REJECTED:"+reason)
	return {}

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _save_rejected("FILE_MISSING")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	_save_flag("LOCAL_SAVE_OPEN_SUCCESS",file!=null)
	if file==null:
		return _save_rejected("OPEN_FAILED")
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(text)
	_save_flag("LOCAL_SAVE_JSON_PARSE_SUCCESS",parse_error==OK)
	if parse_error!=OK:
		# Never print JSON text or parser error messages containing player data.
		return _save_rejected("JSON_PARSE_FAILED")
	var result: Variant = json.data
	_save_flag("LOCAL_SAVE_ROOT_IS_DICTIONARY",result is Dictionary)
	if not result is Dictionary:
		return _save_rejected("ROOT_NOT_DICTIONARY")
	_save_flag("LOCAL_SAVE_SCHEMA_PRESENT",result.has("schema_version"))
	if not result.has("schema_version"):
		return _save_rejected("SCHEMA_MISSING")
	var raw_schema: Variant = result.schema_version
	RushAuthDiagnostics.stage("LOCAL_SAVE_SCHEMA_TYPE:"+type_string(typeof(raw_schema)))
	# JSON numbers are floats. Array.has / `in` distinguishes 5.0 from int 5.
	# Validate before converting: never truncate fractions or accept strings/bools.
	var numeric: bool = raw_schema is int or raw_schema is float
	var supported: bool = false
	if numeric:
		var number: float = float(raw_schema)
		supported = is_finite(number) and number>=1.0 and number<=5.0 and number==floor(number)
	_save_flag("LOCAL_SAVE_SCHEMA_SUPPORTED",supported)
	if not supported:
		return _save_rejected("SCHEMA_UNSUPPORTED")
	var schema: int = int(raw_schema)
	RushAuthDiagnostics.stage("LOCAL_SAVE_SCHEMA_VALUE:%d"%schema)
	_save_flag("LOCAL_SAVE_MIGRATION_REQUIRED",schema<5)
	_save_flag("LOCAL_SAVE_SETTINGS_PRESENT",result.has("settings"))
	_save_flag("LOCAL_SAVE_SETTINGS_IS_DICTIONARY",result.get("settings") is Dictionary)
	if not result.has("settings"):
		return _save_rejected("SETTINGS_MISSING")
	if not result.settings is Dictionary:
		return _save_rejected("SETTINGS_WRONG_TYPE")
	_save_flag("LOCAL_SAVE_WALLET_PRESENT",result.has("wallet"))
	_save_flag("LOCAL_SAVE_WALLET_IS_DICTIONARY",result.get("wallet") is Dictionary)
	if result.has("wallet") and not result.wallet is Dictionary:
		return _save_rejected("WALLET_WRONG_TYPE")
	for key: String in ["collection","progression","consumables","onboarding","membership","store_claims","cloud_meta"]:
		if result.has(key) and not result[key] is Dictionary:
			return _save_rejected("SECTION_WRONG_TYPE")
	if not _save_progress_shape_valid(result):
		return _save_rejected("PROGRESS_WRONG_TYPE")
	# Preserve every other field; loading/migration remains owned by load_settings.
	result.schema_version = schema
	RushAuthDiagnostics.stage("LOCAL_SAVE_ACCEPTED")
	return result

func _saved_counter(value: Variant, maximum: int = MAX_COINS) -> bool:
	if not (value is int or value is float): return false
	var number: float = float(value)
	return is_finite(number) and number>=0.0 and number<=float(maximum) and number==floor(number)

func _save_progress_shape_valid(envelope: Dictionary) -> bool:
	var saved_wallet: Dictionary = envelope.get("wallet",{})
	for key: String in ["coins","issued_run","settled_run"]:
		if saved_wallet.has(key) and not _saved_counter(saved_wallet[key]): return false
	if saved_wallet.has("receipt") and not saved_wallet.receipt is Dictionary: return false
	var saved_progress: Dictionary = envelope.get("progression",{})
	if saved_progress.has("xp") and not _saved_counter(saved_progress.xp,int(RushProgressionData.LIMIT)): return false
	for key: String in ["stats","daily"]:
		if saved_progress.has(key) and not saved_progress[key] is Dictionary: return false
	for key: String in ["achievement_claims","achievement_notices"]:
		if saved_progress.has(key) and not saved_progress[key] is Array: return false
	var saved_collection: Dictionary = envelope.get("collection",{})
	if saved_collection.has("owned"):
		if not saved_collection.owned is Array: return false
		for car: Variant in saved_collection.owned:
			if not car is String or car not in RushVehicleCatalog.IDS: return false
	if saved_collection.has("selected") and not saved_collection.selected is String: return false
	for key: String in ["names","paints","upgrades","upgrade_ads"]:
		if saved_collection.has(key) and not saved_collection[key] is Dictionary: return false
	var saved_upgrades: Dictionary = saved_collection.get("upgrades",{})
	for car_id: Variant in saved_upgrades:
		if not car_id is String or car_id not in RushVehicleCatalog.IDS or not saved_upgrades[car_id] is Dictionary: return false
		var levels: Dictionary = saved_upgrades[car_id]
		for category: String in RushVehicleCatalog.CATEGORIES:
			if levels.has(category) and not _saved_counter(levels[category],10): return false
	var saved_inventory: Dictionary = envelope.get("consumables",{})
	for key: String in ["turbo_inventory","repair_kits","coin_magnets","shields","ad_issued","ad_settled","double_reward_run"]:
		if saved_inventory.has(key) and not _saved_counter(saved_inventory[key],MAX_TURBO if key=="turbo_inventory" else MAX_COINS): return false
	return true

func _validated(key: String, value: Variant) -> Variant:
	if key in ["vibration","steering_assist","tilt_invert","tilt_center_saved"]:
		return value if value is bool else DEFAULTS[key]
	if key == "map_time":
		return RushTimeOfDay.normalize_preset(value)
	if not (value is float or value is int) or not is_finite(float(value)):
		return DEFAULTS[key]
	match key:
		"wheel_deadzone": return clampf(float(value),0.0,0.20)
		"tilt_center": return wrapf(float(value),-PI,PI)
		"steering": return clampf(float(value), 0.5, 1.5)
		"camera": return clampi(int(value), 0, 4)
		"steering_mode": return int(value) if float(value)==floor(float(value)) and int(value) in [0,1,2] else DEFAULTS[key]
		"map": return clampi(int(value),0,7)
		"quality": return clampi(int(value), 0, 2)
		_: return clampf(float(value), 0.0, 1.0)

func set_value(key: String, value: Variant, persist: bool = true) -> void:
	if not DEFAULTS.has(key):
		return
	settings[key] = _validated(key, value)
	changed.emit()
	if persist:
		commit()

func _unknown_fields(source: Dictionary, known: Dictionary) -> Dictionary:
	var extra: Dictionary = {}
	for key: String in source:
		if not known.has(key):
			extra[key] = source[key]
		elif source[key] is Dictionary and known[key] is Dictionary:
			var nested: Dictionary = _unknown_fields(source[key],known[key])
			if not nested.is_empty(): extra[key] = nested
	return extra

func _with_preserved(extra: Dictionary, current: Dictionary) -> Dictionary:
	var value: Dictionary = extra.duplicate(true)
	for key: String in current:
		value[key] = _with_preserved(value[key],current[key]) if value.get(key) is Dictionary and current[key] is Dictionary else current[key]
	return value

func _current_envelope() -> Dictionary:
	return _with_preserved(preserved_fields,{"schema_version":5,"account_scope":_scope_key(scope_uid),"settings":settings,"wallet":wallet,"collection":collection,"progression":progression,"consumables":consumables,"onboarding":onboarding,"membership":membership,"store_claims":store_claims,"cloud_meta":cloud_meta})

func commit() -> bool:
	if bootstrap_pending and not scope_write_allowed:
		return _fail("Waiting for this account’s cloud save. Guest play remains available.")
	if recovery_blocked:
		return _fail("Existing save could not be recovered. Its files have been preserved.")
	var file := FileAccess.open(TEMP, FileAccess.WRITE)
	if file == null:
		return _fail("Could not save settings on this device.")
	file.store_string(JSON.stringify(_current_envelope()))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return _failed_commit("Settings write failed. Previous settings retained.")
	# Keep previous good primary intact until the new complete file exists.
	if not _read(PATH).is_empty():
		if DirAccess.copy_absolute(PATH, BACKUP) != OK:
			return _failed_commit("Could not back up settings. Previous settings retained.")
	if DirAccess.rename_absolute(TEMP, PATH) != OK:
		return _failed_commit("Could not replace settings. Previous settings retained.")
	last_error = ""
	committed.emit()
	return true

func balance() -> int:
	return int(wallet["coins"])

func reserve_run() -> int:
	if transaction_busy: return 0
	# Persist the run sequence before play. Abandoned runs never receive a reward.
	var previous := int(wallet["issued_run"])
	if previous >= MAX_COINS:
		_fail("Run sequence limit reached.")
		return 0
	transaction_busy = true
	wallet["issued_run"] = previous + 1
	var saved: bool = commit()
	if not saved: wallet["issued_run"] = previous
	transaction_busy = false
	return previous+1 if saved else 0

func add_coins(amount: int, run_id: int, summary: Dictionary = {}) -> bool:
	return RewardService.settle_race(amount,run_id,summary)

func is_settled(run_id: int) -> bool:
	return run_id > 0 and run_id <= int(wallet["settled_run"])

func can_afford(amount: int) -> bool:
	return amount >= 0 and balance() >= amount

func spend_coins(amount: int) -> bool:
	if transaction_busy or amount <= 0 or not can_afford(amount):
		return false
	transaction_busy = true
	var previous := balance()
	wallet["coins"] = previous-amount
	var saved: bool = commit()
	if not saved: wallet["coins"] = previous
	transaction_busy = false
	if not saved: return false
	wallet_changed.emit(balance())
	return true

func _fail(message: String) -> bool:
	last_error = message
	save_failed.emit(message)
	push_warning(message)
	return false

func _load_collection(value: Variant) -> void:
	collection = {"owned":["vortex_s"],"selected":"vortex_s","paints":{},"upgrades":{},"names":{},"upgrade_ads":{}}
	var source: Dictionary = value if value is Dictionary else {}
	if source.get("owned") is Array:
		for id: Variant in source["owned"]:
			if id is String and id in RushVehicleCatalog.IDS and id not in collection["owned"]:
				collection["owned"].append(id)
	var selected: Variant = source.get("selected","vortex_s")
	if selected is String and selected in collection["owned"]:
		collection["selected"] = selected
	var paints: Dictionary = source.get("paints",{}) if source.get("paints",{}) is Dictionary else {}
	var upgrades: Dictionary = source.get("upgrades",{}) if source.get("upgrades",{}) is Dictionary else {}
	for id: String in RushVehicleCatalog.IDS:
		var paint: Variant = paints.get(id,RushVehicleCatalog.definition(id)["default_paint"])
		collection["paints"][id] = _safe_level(paint,RushVehicleCatalog.paint_count()-1)
		var levels: Dictionary = upgrades.get(id,{}) if upgrades.get(id,{}) is Dictionary else {}
		collection["upgrades"][id] = {}
		for category: String in RushVehicleCatalog.CATEGORIES:
			collection["upgrades"][id][category] = _safe_level(levels.get(category,0),10) if owns(id) else 0

	var names: Variant = source.get("names",{})
	var ad_progress: Variant = source.get("upgrade_ads",{})
	for id: String in collection.owned:
		if names is Dictionary and names.get(id) is String:
			var cleaned := clean_car_name(String(names[id]))
			if not cleaned.is_empty():
				collection.names[id] = cleaned
		for category: String in RushVehicleCatalog.CATEGORIES:
			var target := int(collection.upgrades[id][category])+1
			if target>10:
				continue
			var key := upgrade_ad_key(id,category,target)
			if ad_progress is Dictionary:
				var count := _safe_level(ad_progress.get(key,0),RushVehicleCatalog.upgrade_ad_requirement(target)-1)
				if count>0:
					collection.upgrade_ads[key] = count

func _safe_level(value: Variant, maximum: int) -> int:
	return clampi(int(value),0,maximum) if (value is int or value is float) and is_finite(float(value)) else 0

func owns(id: String) -> bool:
	return id in collection.get("owned",[])

func buy_vehicle(id: String) -> bool:
	if transaction_busy or id not in RushVehicleCatalog.IDS or owns(id):
		return false
	var cost := RushVehicleCatalog.price(id)
	if not can_afford(cost):
		return _fail("Not enough coins for this vehicle.")
	var next := collection.duplicate(true)
	next["owned"].append(id)
	return _commit_collection(next,cost)

func select_vehicle(id: String) -> bool:
	if transaction_busy or not owns(id):
		return false
	var next := collection.duplicate(true)
	next["selected"] = id
	return _commit_collection(next,0)

func set_paint(id: String, color_index: int) -> bool:
	if transaction_busy or not owns(id) or color_index<0 or color_index>=RushVehicleCatalog.paint_count():
		return false
	var next := collection.duplicate(true)
	next["paints"][id] = color_index
	return _commit_collection(next,0)

func buy_upgrade(id: String, category: String, expected_level: int) -> bool:
	if transaction_busy or not owns(id) or category not in RushVehicleCatalog.CATEGORIES:
		return false
	var current := int(collection["upgrades"][id][category])
	# Compare-and-swap: a duplicate UI request for the same level cannot debit twice.
	if current != expected_level or current>=10:
		return false
	var cost := RushVehicleCatalog.upgrade_cost(current)
	if not can_afford(cost):
		return _fail("Not enough coins for this upgrade.")
	var next := collection.duplicate(true)
	next["upgrades"][id][category] = current+1
	next.upgrade_ads.erase(upgrade_ad_key(id,category,current+1))
	return _commit_collection(next,cost)

func _commit_collection(next: Dictionary, cost: int) -> bool:
	if transaction_busy or not can_afford(cost):
		return false
	transaction_busy = true
	var before := collection.duplicate(true)
	var previous_coins := balance()
	var previous_progression := progression.duplicate(true)
	RushProgressionData.purchase(progression,before,next)
	collection = next
	wallet["coins"] = previous_coins-cost
	var success := commit()
	if not success:
		collection = before
		progression = previous_progression
		wallet["coins"] = previous_coins
	transaction_busy = false
	if success:
		wallet_changed.emit(balance())
		collection_changed.emit()
	return success

func _failed_commit(message: String) -> bool:
	# Never recover a rejected transaction from its orphan pending file.
	if FileAccess.file_exists(TEMP):
		DirAccess.remove_absolute(TEMP)
	return _fail(message)

func commit_reward(next: Dictionary, amount: int, receipt: Dictionary = {}) -> bool:
	if not receipt.is_empty():
		var run_value: Variant = receipt.get("run_id")
		if not _saved_counter(run_value) or int(run_value)<=0 or int(run_value)!=int(wallet.issued_run) or is_settled(int(run_value)):
			return false
		if not _saved_counter(receipt.get("amount")) or int(receipt.amount)!=amount:
			return false
	if transaction_busy or amount<0 or amount>MAX_COINS-balance():
		return _fail("Reward cannot be saved: wallet limit or transaction in progress.")
	transaction_busy = true
	var before_wallet := wallet.duplicate(true)
	var before_progression := progression
	progression = next
	wallet["coins"] = balance()+amount
	if not receipt.is_empty():
		wallet["settled_run"] = receipt.run_id
		wallet["receipt"] = receipt
	var success := commit()
	if not success:
		wallet = before_wallet
		progression = before_progression
	transaction_busy = false
	if success:
		wallet_changed.emit(balance())
	return success

func _commit_consumables(next: Dictionary, cost: int = 0, credit: int = 0) -> bool:
	# Validate before assigning runtime state; retain unknown metadata unchanged.
	for key: String in ["turbo_inventory","repair_kits","coin_magnets","shields","ad_issued","ad_settled","double_reward_run"]:
		if next.has(key) and not _saved_counter(next[key],MAX_TURBO if key=="turbo_inventory" else MAX_COINS): return false
	if int(next.get("ad_settled",0))>int(next.get("ad_issued",0)): return false
	if transaction_busy or cost<0 or credit<0 or credit>MAX_COINS-balance() or not can_afford(cost):
		return false
	transaction_busy = true
	var previous := consumables
	var coins_before := balance()
	consumables = next
	wallet.coins = coins_before-cost+credit
	var ok := commit()
	if not ok:
		consumables = previous
		wallet.coins = coins_before
	transaction_busy = false
	if ok:
		turbo_inventory_changed.emit()
		wallet_changed.emit(balance())
	return ok

func buy_turbo(offer_id: String) -> bool:
	for offer: Dictionary in RushDrivingData.get_data().turbo_offers:
		if String(offer.id)==offer_id:
			if int(consumables.turbo_inventory)+int(offer.charges)>MAX_TURBO:
				return false
			var next := consumables.duplicate(true)
			next.turbo_inventory += int(offer.charges)
			return _commit_consumables(next,int(offer.coins))
	return false

func use_turbo_charge() -> bool:
	if int(consumables.turbo_inventory)<=0:
		return false
	var next := consumables.duplicate(true)
	next.turbo_inventory -= 1
	return _commit_consumables(next)

func reserve_ad_request() -> int:
	if int(consumables.ad_issued)>=MAX_COINS:
		return 0
	var next := consumables.duplicate(true)
	next.ad_issued += 1
	return int(next.ad_issued) if _commit_consumables(next) else 0

func settle_ad_request(token: int, rewarded: bool) -> bool:
	if token<=int(consumables.ad_settled) or token!=int(consumables.ad_issued):
		return false
	if rewarded and int(consumables.turbo_inventory)>MAX_TURBO-2:
		return false
	var next := consumables.duplicate(true)
	next.ad_settled = token
	if rewarded:
		next.turbo_inventory += 2
	return _commit_consumables(next)

func ensure_initial_turbo_grant() -> bool:
	if bool(consumables.get("initial_grant_claimed",false)):
		return true
	if int(consumables.turbo_inventory)>MAX_TURBO-2:
		return false
	var next := consumables.duplicate(true)
	next.turbo_inventory = int(next.turbo_inventory)+2
	next["initial_grant_claimed"] = true
	# Inventory and migration marker are committed together, with rollback on failure.
	return _commit_consumables(next)

func confirm_starter() -> bool:
	if bool(onboarding.completed):
		return true
	var before := onboarding.duplicate(true)
	onboarding = {"completed":true,"starter":"vortex_s"}
	if not commit():
		onboarding = before
		return false
	return true

func settle_powerup(token: int, kind: String, race_id: int) -> bool:
	if token<=int(consumables.ad_settled) or token!=int(consumables.ad_issued):
		return false
	var next := consumables.duplicate(true)
	var bonus := 0
	if kind=="double":
		if race_id<=int(consumables.get("double_reward_run",0)) or race_id!=int(wallet.receipt.get("run_id",0)) or not is_settled(race_id):
			return false
		var summary: Dictionary = wallet.receipt.get("summary",{})
		# Eligible base race coins only, excluding XP, level bonuses and other ad rewards.
		bonus = maxi(0,int(summary.get("road_coins",0)))
		if bonus<=0:
			return false
		next["double_reward_run"] = race_id
	next.ad_settled = token
	var previous_progression := progression
	if bonus>0:
		progression = progression.duplicate(true)
		progression.stats.lifetime_coins += bonus
	var saved := _commit_consumables(next,0,bonus)
	if not saved:
		progression = previous_progression
	return saved

func clean_car_name(value: String) -> String:
	var result := ""
	for character: String in value:
		var code := character.unicode_at(0)
		if code>=32 and not (code>=127 and code<=159) and code not in [8203,8204,8205,8232,8233,8234,8235,8236,8237,8238,8294,8295,8296,8297]:
			result += character
	return result.strip_edges().substr(0,18)

func car_name(id: String) -> String:
	return String(collection.get("names",{}).get(id,RushVehicleCatalog.definition(id).name))

func set_car_name(id: String, value: String, reset: bool = false) -> bool:
	if transaction_busy or not owns(id):
		return false
	var name_value := clean_car_name(value)
	if not reset and name_value.is_empty():
		return _fail("Please enter a car name.")
	var next := collection.duplicate(true)
	if reset:
		next.names.erase(id)
	else:
		next.names[id] = name_value
	return _commit_collection(next,0)

func upgrade_ad_key(id: String, category: String, target: int) -> String:
	return "%s:%s:%d"%[id,category,target]

func upgrade_ad_count(id: String, category: String, target: int) -> int:
	return int(collection.get("upgrade_ads",{}).get(upgrade_ad_key(id,category,target),0))

func settle_upgrade_reward(token: int, id: String, category: String, target: int) -> bool:
	if transaction_busy or token<=int(consumables.ad_settled) or token!=int(consumables.ad_issued):
		return false
	if not owns(id) or category not in RushVehicleCatalog.CATEGORIES or target<1 or target>10:
		return settle_ad_request(token,false)
	if int(collection.upgrades[id][category])+1!=target:
		return settle_ad_request(token,false)
	var next := collection.duplicate(true)
	var key := upgrade_ad_key(id,category,target)
	var count := upgrade_ad_count(id,category,target)+1
	if count>=RushVehicleCatalog.upgrade_ad_requirement(target):
		next.upgrades[id][category] = target
		next.upgrade_ads.erase(key)
	else:
		next.upgrade_ads[key] = count
	# Callback ledger, partial progress, final upgrade and career stats share one commit.
	var before := consumables.duplicate(true)
	consumables.ad_settled = token
	var saved := _commit_collection(next,0)
	if not saved:
		consumables = before
	return saved

func buy_store_boost(offer_id: String) -> bool:
	var offer: Dictionary = RushStoreCatalog.find_offer("boosts",offer_id)
	if offer.is_empty():
		return false
	var key: String = String(offer.inventory)
	var quantity: int = int(offer.quantity)
	var limit: int = MAX_TURBO if key=="turbo_inventory" else MAX_COINS
	var current: int = int(consumables.get(key,0))
	if key not in ["turbo_inventory","repair_kits","coin_magnets","shields"] or quantity<=0 or quantity>limit or current>limit-quantity:
		return false
	var next: Dictionary = consumables.duplicate(true)
	next[key] = current+quantity
	return _commit_consumables(next,int(offer.coins))

func grant_store_coins(product_id: String, verified_token: String) -> bool:
	# Internal verified-provider settlement path; never wired to a UI reward button.
	var offer: Dictionary = RushStoreCatalog.find_offer("coin_packs",product_id)
	if transaction_busy or offer.is_empty() or verified_token.is_empty():
		return false
	var marker: String = verified_token.sha256_text()
	if store_claims.has(marker):
		return String(store_claims[marker])==product_id
	var amount: int = int(offer.total)
	if amount<=0 or balance()>MAX_COINS-amount:
		return false
	var before: int = balance()
	transaction_busy = true
	store_claims[marker] = product_id
	wallet.coins = before+amount
	var saved: bool = commit()
	if not saved:
		wallet.coins = before
		store_claims.erase(marker)
	transaction_busy = false
	if saved:
		wallet_changed.emit(balance())
	return saved

func consume_boost(key: String) -> bool:
	if key not in ["repair_kits","coin_magnets","shields"] or int(consumables.get(key,0))<=0:
		return false
	var next: Dictionary = consumables.duplicate(true)
	next[key] = int(next[key])-1
	return _commit_consumables(next)

func settle_store_boost(token: int, offer_id: String) -> bool:
	if transaction_busy or token<=int(consumables.ad_settled) or token!=int(consumables.ad_issued):
		return false
	var offer: Dictionary = RushStoreCatalog.find_offer("boosts",offer_id)
	if offer.is_empty():
		return false
	var key: String = String(offer.inventory)
	var count: int = int(offer.quantity)
	var maximum: int = MAX_TURBO if key=="turbo_inventory" else MAX_COINS
	if key not in ["turbo_inventory","repair_kits","coin_magnets","shields"] or count<=0 or count>maximum:
		return false
	if int(consumables.get(key,0))>maximum-count:
		return false
	var next: Dictionary = consumables.duplicate(true)
	next[key] = int(next.get(key,0))+count
	next.ad_settled = token
	return _commit_consumables(next)

func cloud_envelope() -> Dictionary:
	# Sync committed state only. Recovery/migration belongs to load_settings/commit.
	if recovery_blocked: return _save_rejected("MIGRATION_FAILED")
	if bootstrap_pending: return _current_envelope().duplicate(true)
	var envelope: Dictionary = _read(PATH)
	if envelope.is_empty(): return {}
	if int(envelope.schema_version)!=5: return _save_rejected("MIGRATION_REQUIRED")
	for key: String in ["settings","wallet","collection","progression","consumables","onboarding","membership","store_claims","cloud_meta"]:
		if not envelope.get(key) is Dictionary: return _save_rejected("CANONICAL_SECTION_INVALID")
	return envelope

func acknowledge_cloud(marker: Dictionary) -> bool:
	if transaction_busy: return false
	var previous: Dictionary = cloud_meta
	cloud_meta = marker.duplicate(true)
	transaction_busy = true
	var saved: bool = commit()
	transaction_busy = false
	if not saved: cloud_meta = previous
	return saved

func restore_cloud(documents: Dictionary, marker: Dictionary) -> bool:
	if transaction_busy or RewardService.active_run!=0: return false
	var before: Dictionary = cloud_envelope()
	var candidate: Dictionary = RushCloudRestore.candidate(before,documents)
	if candidate.is_empty(): return false
	# Preserve an independent recovery copy before replacing the local primary.
	if FileAccess.file_exists(PATH) and DirAccess.copy_absolute(PATH,PATH.get_base_dir()+"/settings.before_cloud.json")!=OK: return false
	var was_pending: bool = bootstrap_pending
	scope_write_allowed = true
	transaction_busy = true
	settings = candidate.settings
	wallet = candidate.wallet
	collection = candidate.collection
	progression = candidate.progression
	consumables = candidate.consumables
	onboarding = candidate.onboarding
	membership = candidate.membership
	store_claims = candidate.store_claims
	cloud_meta = marker.duplicate(true)
	var saved: bool = commit()
	if not saved:
		settings = before.settings
		wallet = before.wallet
		collection = before.collection
		progression = before.progression
		consumables = before.consumables
		onboarding = before.onboarding
		membership = before.membership
		store_claims = before.store_claims
		cloud_meta = before.get("cloud_meta",{})
	transaction_busy = false
	scope_write_allowed = false
	bootstrap_pending = false if saved else was_pending
	if saved:
		guest_import_pending = false
		scope_local_available = true
		cloud_restored.emit()
		changed.emit()
		collection_changed.emit()
		turbo_inventory_changed.emit()
		wallet_changed.emit(balance())
		RewardService.progression_changed.emit()
	return saved
