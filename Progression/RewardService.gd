extends Node
## Sole award coordinator. SaveService owns atomic storage, this service owns eligibility.
signal progression_changed
signal reward_claimed(kind: String)
var date_clock: float = 0.0
var active_run: int = 0
var best_before_run: float = 0.0
var run_scope: int = -1
var staged_snapshot: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh_date()
	SaveService.collection_changed.connect(func() -> void: progression_changed.emit())

func _process(delta: float) -> void:
	# Calendar only, once a second. No JSON, mission scans, menu rebuilding or save writes.
	date_clock += delta
	if date_clock>=1.0:
		date_clock = 0.0
		refresh_date()

func refresh_date(date: String = "") -> void:
	if date.is_empty():
		date = RushProgressionData.local_date()
	if RushProgressionData.ensure_date(SaveService.progression,date):
		progression_changed.emit()

func bind_run(run: RushRunManager) -> void:
	run.started.connect(func() -> void: begin_run(run.run_id))
	run.telemetry.connect(record_snapshot)
	run.abandoned.connect(abandon_run)

func begin_run(id: int) -> void:
	var p: Dictionary = SaveService.progression
	if id<=int(p.last_started) or id!=int(SaveService.wallet.issued_run): return
	active_run = id
	run_scope = SaveService.scope_generation
	best_before_run = float(p.stats.best_score)
	staged_snapshot.clear()

func record_snapshot(snapshot: Dictionary) -> void:
	if run_scope!=SaveService.scope_generation or active_run<=0 or int(snapshot.get("run_id",0))!=active_run: return
	staged_snapshot = snapshot.duplicate(true)

func _apply_snapshot(p: Dictionary) -> void:
	var cp: Dictionary = p.run_checkpoint
	for key: String in RushProgressionData.SUM_FIELDS:
		var value: float = RushProgressionData.number(staged_snapshot.get(key,0))
		var delta: float = maxf(value-float(cp.get(key,0)),0.0)
		p.stats[key] += delta
		RushProgressionData.event(p,key,delta)
		cp[key] = maxf(value,float(cp.get(key,0)))
	for key: String in RushProgressionData.MAX_FIELDS:
		var value: float = RushProgressionData.number(staged_snapshot.get(key,0),450.0 if key=="highest_speed" else RushProgressionData.LIMIT)
		p.stats[key] = maxf(p.stats[key],value)
		if value>float(cp.get(key,0)): RushProgressionData.event(p,key,value)
		cp[key] = maxf(value,float(cp.get(key,0)))

func abandon_run(id: int) -> void:
	if id!=active_run: return
	active_run = 0
	run_scope = -1
	staged_snapshot.clear() # No rollback of already saved account data.

func settle_race(amount: int, id: int, summary: Dictionary) -> bool:
	# Reject before XP/bonus arithmetic or progression mutation.
	if amount<0 or amount>SaveService.MAX_COINS: return false
	if SaveService.transaction_busy or id<=0 or id!=int(SaveService.wallet.issued_run) or SaveService.is_settled(id):
		return false
	refresh_date()
	var p: Dictionary = SaveService.progression.duplicate(true)
	# Synthetic older test/API callers can settle coins, but cannot invent career runs.
	var tracked: bool = id==active_run and run_scope==SaveService.scope_generation and id>int(p.last_finalized)
	var details := {"xp_earned":0,"level_coins":0,"level":p.level,"xp":p.xp,"new_best":false}
	if tracked:
		p.last_started = id
		p.stats.started += 1
		p.run_checkpoint = {"run_id":id}
		_apply_snapshot(p)
		p.last_finalized = id
		if bool(summary.get("completed",true)):
			p.stats.completed += 1
			RushProgressionData.event(p,"completed",1)
			if float(p.run_checkpoint.get("collisions",0))<=2: RushProgressionData.event(p,"clean_finish",1)
			var earned_xp: int = RushProgressionData.race_xp(summary)
			if summary.get("race_mode","")=="five_racer":
				var rank: int = clampi(int(summary.get("finish_place",5)),1,5)
				earned_xp = int(RushDrivingData.get_data().five_racer_rewards[rank-1].xp)
			details = RushProgressionData.award_xp(p,earned_xp)
			details.new_best = float(summary.get("score",0))>best_before_run
	var total := amount+int(details.level_coins)
	if amount<0 or total<0 or total>SaveService.MAX_COINS-SaveService.balance():
		return SaveService._fail("Reward cannot be saved: wallet limit.")
	p.stats.lifetime_coins += total
	var saved_summary := summary.duplicate(true)
	saved_summary.merge(details,true)
	var receipt := {"run_id":id,"reward_id":"race_%d"%id,"amount":total,"summary":saved_summary}
	if not SaveService.commit_reward(p,total,receipt):
		return false
	active_run = 0
	staged_snapshot.clear()
	run_scope = -1
	progression_changed.emit()
	return true

func claim_daily_reward(date: String = "") -> bool:
	refresh_date(date)
	if date.is_empty():
		date = RushProgressionData.local_date()
	var p: Dictionary = SaveService.progression.duplicate(true)
	if not RushProgressionData.valid_date(date) or date<p.date_highwater or date<=p.last_claim_date:
		return false
	p.reward_day = int(p.reward_day)%7+1
	p.last_claim_date = date
	return _claim(p,int(RushProgressionData.spec.daily_rewards[p.reward_day-1]),0,"daily_"+date,"daily_reward")

func daily_available() -> bool:
	var date := RushProgressionData.local_date()
	var p: Dictionary = SaveService.progression
	return date>=p.date_highwater and date>p.last_claim_date

func claim_mission(id: String, date: String) -> bool:
	refresh_date()
	var p: Dictionary = SaveService.progression.duplicate(true)
	if date!=p.daily.date or date!=RushProgressionData.local_date():
		return false
	for task: Dictionary in p.daily.tasks:
		if task.id==id and not task.claimed and task.progress>=task.target:
			task.claimed = true
			return _claim(p,int(task.coins),int(task.xp),"mission_"+date+"_"+id,"mission_complete")
	return false

func claim_achievement(id: String) -> bool:
	var p: Dictionary = SaveService.progression.duplicate(true)
	if id in p.achievement_claims:
		return false
	for item: Dictionary in RushProgressionData.achievements:
		if item.id==id and RushProgressionData.achievement_value(p,item)>=float(item.target):
			p.achievement_claims.append(id)
			return _claim(p,int(item.coins),int(item.xp),"achievement_"+id,"achievement")
	return false

func _claim(p: Dictionary, coins: int, xp: int, reward_id: String, kind: String) -> bool:
	if SaveService.transaction_busy:
		return false
	var details := RushProgressionData.award_xp(p,xp)
	var total := coins+int(details.level_coins)
	p.stats.lifetime_coins += total
	# Eligibility markers above are bounded ledgers (date, mission ID, achievement ID).
	p["last_reward_id"] = reward_id
	if not SaveService.commit_reward(p,total):
		return false
	progression_changed.emit()
	reward_claimed.emit(kind)
	GameAudio.event("reward_claim")
	GameAudio.event(kind)
	RushHaptics.pulse(25)
	return true

func set_player_name(value: String) -> bool:
	var p: Dictionary = SaveService.progression.duplicate(true)
	p.name = RushProgressionData.clean_name(value)
	if not SaveService.commit_reward(p,0):
		return false
	progression_changed.emit()
	return true

func claimable_count() -> int:
	var p: Dictionary = SaveService.progression
	var count: int = 0
	for task: Dictionary in p.daily.tasks:
		if not task.claimed and task.progress>=task.target:
			count += 1
	for item: Dictionary in RushProgressionData.achievements:
		if item.id not in p.achievement_claims and RushProgressionData.achievement_value(p,item)>=float(item.target):
			count += 1
	return count

func take_notices() -> Dictionary:
	# Called only at safe menus/results. Acknowledgement never issues a reward.
	var p: Dictionary = SaveService.progression.duplicate(true)
	var notices: Array = []
	for item: Dictionary in RushProgressionData.achievements:
		if item.id not in p.achievement_notices and RushProgressionData.achievement_value(p,item)>=float(item.target):
			p.achievement_notices.append(item.id)
			notices.append(item.title)
	var level: Dictionary = p.pending_level.duplicate(true)
	p.pending_level = {}
	if level.is_empty() and notices.is_empty():
		return {}
	if not SaveService.commit_reward(p,0):
		return {}
	return {"level":level,"achievements":notices}

func diagnostics() -> Dictionary:
	return SaveService.progression.duplicate(true) if OS.is_debug_build() else {}
