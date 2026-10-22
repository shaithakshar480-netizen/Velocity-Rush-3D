class_name RushProgressionData
extends RefCounted
## Pure data/rules. No scene, input, wallet or disk dependencies.
static var spec: Dictionary = {}
static var missions: Array = []
static var achievements: Array = []
const STAT_KEYS := ["started","completed","distance","play_time","road_coins","pickups","lifetime_coins","best_score","cumulative_score","highest_speed","near_misses","best_combo","turbo_activations","collisions","cars_purchased","upgrades_purchased","cars_owned"]
const SUM_FIELDS := ["distance","play_time","road_coins","pickups","near_misses","turbo_activations","collisions","cumulative_score"]
const MAX_FIELDS := ["best_score","highest_speed","best_combo"]
const LIMIT: float = 9000000000000.0

static func prepare() -> void:
	if not spec.is_empty():
		return
	spec = JSON.parse_string(FileAccess.get_file_as_string("res://Data/ProgressionSpec.json"))
	missions = JSON.parse_string(FileAccess.get_file_as_string("res://Data/MissionCatalog.json"))
	achievements = JSON.parse_string(FileAccess.get_file_as_string("res://Data/AchievementCatalog.json"))

static func number(value: Variant, maximum: float = LIMIT) -> float:
	return clampf(float(value),0.0,maximum) if (value is int or value is float) and is_finite(float(value)) else 0.0

static func local_date() -> String:
	var date := Time.get_date_dict_from_system(false)
	return "%04d-%02d-%02d"%[date.year,date.month,date.day]

static func valid_date(value: Variant) -> bool:
	if not value is String or value.length()!=10 or value[4]!="-" or value[7]!="-":
		return false
	var parts: PackedStringArray = value.split("-")
	if parts.size()!=3 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return false
	var year := int(parts[0])
	var month := int(parts[1])
	var day := int(parts[2])
	if year<1970 or year>9999 or month<1 or month>12:
		return false
	var days := [31,29 if year%4==0 and (year%100!=0 or year%400==0) else 28,31,30,31,30,31,31,30,31,30,31]
	return day>=1 and day<=days[month-1]

static func required(level: int) -> int:
	prepare()
	var n := maxi(level-1,0)
	return int(spec.xp_base)+int(spec.xp_linear)*n+int(spec.xp_quadratic)*n*n

static func threshold(level: int) -> int:
	var total: int = 0
	for n: int in range(1,level):
		total += required(n)
	return total

static func level_for(xp: int) -> int:
	prepare()
	var level: int = 1
	var remaining := maxi(xp,0)
	while level<int(spec.max_level) and remaining>=required(level):
		remaining -= required(level)
		level += 1
	return level

static func level_coins(level: int) -> int:
	prepare()
	for band: Dictionary in spec.level_rewards:
		if level<=int(band.through):
			return int(band.coins)
	return 0

static func defaults() -> Dictionary:
	prepare()
	var stats: Dictionary = {}
	for key: String in STAT_KEYS:
		stats[key] = 0.0
	stats.cars_owned = 1
	return {"xp":0,"level":1,"name":"Racer","stats":stats,"daily":{"date":"","tasks":[]},
		"achievement_claims":[],"achievement_notices":[],"reward_day":0,"last_claim_date":"",
		"last_reward_id":"","date_highwater":"","last_started":0,"last_finalized":0,"run_checkpoint":{},"pending_level":{}}

static func clean_name(value: Variant) -> String:
	if not value is String:
		return "Racer"
	var result := ""
	for character: String in value.strip_edges():
		if character.unicode_at(0)>=32 and character.unicode_at(0)!=127:
			result += character
	result = result.left(20).strip_edges()
	return "Racer" if result.is_empty() else result

static func normalize(raw: Variant, collection: Dictionary, issued: int) -> Dictionary:
	var p := defaults()
	var source: Dictionary = raw if raw is Dictionary else {}
	p.xp = int(number(source.get("xp",0),threshold(int(spec.max_level))))
	p.level = level_for(p.xp)
	p.name = clean_name(source.get("name","Racer"))
	var stats: Dictionary = source.get("stats",{}) if source.get("stats") is Dictionary else {}
	for key: String in STAT_KEYS:
		p.stats[key] = number(stats.get(key,0))
	p.stats.highest_speed = minf(p.stats.highest_speed,450.0)
	p.stats.cars_owned = collection.owned.size()
	# Phase 4 ownership and installed upgrade levels are historical purchase evidence.
	p.stats.cars_purchased = maxf(p.stats.cars_purchased,collection.owned.size()-1)
	var installed: int = 0
	for id: String in collection.upgrades:
		for category: String in collection.upgrades[id]:
			installed += int(collection.upgrades[id][category])
	p.stats.upgrades_purchased = maxf(p.stats.upgrades_purchased,installed)
	if source.get("last_reward_id") is String:
		p.last_reward_id = source.last_reward_id.left(96)
	for key: String in ["date_highwater","last_claim_date"]:
		if valid_date(source.get(key)):
			p[key] = source[key]
	p.date_highwater = max_date(p.date_highwater,p.last_claim_date)
	p.reward_day = int(number(source.get("reward_day",0),7))
	for key: String in ["last_started","last_finalized"]:
		p[key] = int(number(source.get(key,0),issued))
	p.last_finalized = mini(p.last_finalized,p.last_started)
	for key: String in ["achievement_claims","achievement_notices"]:
		var values: Array = source.get(key,[]) if source.get(key) is Array else []
		for item: Dictionary in achievements:
			if item.id in values:
				p[key].append(item.id)
	var daily: Dictionary = source.get("daily",{}) if source.get("daily") is Dictionary else {}
	if valid_date(daily.get("date")):
		p.daily = generate_daily(daily.date)
		p.date_highwater = max_date(p.date_highwater,daily.date)
		var tasks: Array = daily.get("tasks",[]) if daily.get("tasks") is Array else []
		for task: Dictionary in p.daily.tasks:
			for saved: Variant in tasks:
				if saved is Dictionary and saved.get("id")==task.id:
					task.progress = number(saved.get("progress",0),task.target)
					task.claimed = saved.get("claimed") is bool and bool(saved.claimed) and task.progress>=task.target
	var cp: Dictionary = source.get("run_checkpoint",{}) if source.get("run_checkpoint") is Dictionary else {}
	if int(number(cp.get("run_id",0),issued))==p.last_started and p.last_started>p.last_finalized:
		p.run_checkpoint = {"run_id":p.last_started}
		for key: String in SUM_FIELDS+MAX_FIELDS:
			p.run_checkpoint[key] = number(cp.get(key,0))
	# Presentation only, never grants rewards. Clamp against already-earned level.
	var notice: Dictionary = source.get("pending_level",{}) if source.get("pending_level") is Dictionary else {}
	if not notice.is_empty():
		var old := clampi(int(number(notice.get("old",1),50)),1,p.level)
		var coins: int = 0
		for level: int in range(old+1,p.level+1):
			coins += level_coins(level)
		if old<p.level:
			p.pending_level = {"old":old,"new":p.level,"coins":coins}
	return p

static func max_date(a: String, b: String) -> String:
	return a if a>b else b

static func generate_daily(date: String) -> Dictionary:
	prepare()
	var tasks: Array = []
	# One easy, medium and hard task. Stable date seed, no global RNG state.
	var seed_value := int(date.replace("-",""))
	for tier: String in ["easy","medium","hard"]:
		var pool: Array = missions.filter(func(item: Dictionary) -> bool: return item.tier==tier)
		var task: Dictionary = pool[(seed_value+tasks.size()*7)%pool.size()].duplicate(true)
		task.progress = 0.0
		task.claimed = false
		tasks.append(task)
	return {"date":date,"tasks":tasks}

static func ensure_date(p: Dictionary, date: String) -> bool:
	if not valid_date(date) or date<p.date_highwater:
		return false
	p.date_highwater = date
	if p.daily.date==date:
		return false
	p.daily = generate_daily(date)
	return true

static func event(p: Dictionary, key: String, value: float) -> void:
	for task: Dictionary in p.daily.tasks:
		if task.event!=key or task.claimed:
			continue
		task.progress = minf(task.target,maxf(task.progress,value) if task.mode=="max" else task.progress+maxf(value,0.0))

static func race_xp(summary: Dictionary) -> int:
	prepare()
	var c: Dictionary = spec.race_xp
	return int(c.completion)+mini(int(c.score_cap),int(number(summary.get("score",0))/float(c.score_divisor)))+mini(int(c.near_cap),int(number(summary.get("near_misses",0)))*int(c.near_miss))+mini(int(c.high_speed_cap),int(number(summary.get("high_speed_seconds",0))/float(c.high_speed_divisor)))+mini(int(c.turbo_cap),int(number(summary.get("turbo_activations",0)))*int(c.turbo))

static func award_xp(p: Dictionary, amount: int) -> Dictionary:
	var old := int(p.level)
	var before := int(p.xp)
	p.xp = mini(threshold(int(spec.max_level)),before+maxi(amount,0))
	p.level = level_for(p.xp)
	var coins: int = 0
	for level: int in range(old+1,int(p.level)+1):
		coins += level_coins(level)
	if p.level>old:
		var previous: Dictionary = p.pending_level
		p.pending_level = {"old":previous.get("old",old),"new":p.level,"coins":int(previous.get("coins",0))+coins}
	return {"xp_earned":p.xp-before,"old_level":old,"level":p.level,"level_coins":coins,"xp":p.xp}

static func achievement_value(p: Dictionary, item: Dictionary) -> float:
	return minf(float(p.stats.get(item.event,0)),float(item.target))

static func purchase(p: Dictionary, before: Dictionary, after: Dictionary) -> void:
	var cars: int = after.owned.size()-before.owned.size()
	p.stats.cars_purchased += maxi(cars,0)
	p.stats.cars_owned = after.owned.size()
	var upgrades: int = 0
	for id: String in after.upgrades:
		for category: String in after.upgrades[id]:
			upgrades += maxi(int(after.upgrades[id][category])-int(before.upgrades.get(id,{}).get(category,0)),0)
	p.stats.upgrades_purchased += upgrades
