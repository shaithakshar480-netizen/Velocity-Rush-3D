extends Node
## Executes actual GDScript and persistence; run only through the isolated test runner.
var checks: int = 0
var failures: int = 0
var game: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RushProgressionData.prepare()
	_test_rules()
	_test_migration()
	_test_rewards()
	_test_dates()
	_test_stats()
	await _test_integration()
	print("PHASE5_SMOKE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PHASE5: "+label)

func _fresh() -> void:
	SaveService._load_collection({})
	SaveService.progression = RushProgressionData.defaults()
	SaveService.wallet = SaveService.WALLET_DEFAULTS.duplicate(true)
	RewardService.active_run = 0
	RewardService.refresh_date()
	SaveService.commit()

func _test_rules() -> void:
	var last: int = 0
	for level: int in range(1,50):
		var required := RushProgressionData.required(level)
		_check(required>last,"XP curve strictly increases %d"%level)
		last = required
		_check(RushProgressionData.level_for(RushProgressionData.threshold(level+1)-1)==level,"Threshold lower boundary %d"%level)
		_check(RushProgressionData.level_for(RushProgressionData.threshold(level+1))==level+1,"Threshold exact boundary %d"%level)
	var p := RushProgressionData.defaults()
	var earned := RushProgressionData.award_xp(p,RushProgressionData.threshold(5))
	_check(p.level==5 and earned.level_coins==1000,"Multiple levels issue each configured reward once")
	_check(RushProgressionData.award_xp(p,0).level_coins==0,"Zero XP cannot duplicate level rewards")
	RushProgressionData.award_xp(p,2000000000)
	_check(p.level==50 and p.xp==RushProgressionData.threshold(50),"XP and level cap")
	_check(RushProgressionData.award_xp(p,20000).level_coins==0,"No cap reward farming")
	_check(RushProgressionData.clean_name("  \n  ")=="Racer","Empty name fallback")
	_check(RushProgressionData.clean_name("   Northline Racer   ")=="Northline Racer","Name trims whitespace")
	_check(RushProgressionData.clean_name("12345678901234567890123").length()==20,"Name length limit")
	_check(RushProgressionData.race_xp({"score":4000,"near_misses":5,"high_speed_seconds":80,"turbo_activations":2})==404,"Config-driven race XP")

func _test_migration() -> void:
	var upgrades := {"falcon_s1":{"engine":4,"handling":2}}
	var old := {"schema_version":3,"settings":{"master":0.31,"steering_mode":2,"steering_assist":false},
		"wallet":{"coins":54321,"issued_run":9,"settled_run":8},
		"collection":{"owned":["vortex_s","falcon_s1"],"selected":"falcon_s1","paints":{"falcon_s1":4},"upgrades":upgrades}}
	var file := FileAccess.open(SaveService.PATH,FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	SaveService.load_settings()
	_check(SaveService.balance()==54321 and SaveService.collection.selected=="falcon_s1","Phase 4 wallet and selected car migrate")
	_check(SaveService.collection.upgrades.falcon_s1.engine==4 and SaveService.collection.paints.falcon_s1==4,"Paint and upgrades migrate")
	_check(SaveService.settings.master==0.31 and SaveService.settings.steering_mode==2 and not SaveService.settings.steering_assist,"Controls and settings migrate")
	_check(SaveService.progression.level==1 and SaveService.progression.name=="Racer","New progression defaults")
	SaveService.commit()
	_check(SaveService._read(SaveService.PATH).schema_version==5,"Atomic envelope writes schema 5")
	var corrupt := {"xp":-10,"level":999,"name":4,"stats":{"distance":-12,"highest_speed":9999},"last_claim_date":"2026-02-31","reward_day":80,"daily":{"date":"2026-09-06","tasks":[{"id":"unknown","claimed":true}]},"achievement_claims":["fake"]}
	var p := RushProgressionData.normalize(corrupt,SaveService.collection,9)
	_check(p.xp==0 and p.level==1 and p.name=="Racer","Corrupt progression values normalize")
	_check(p.stats.distance==0 and p.stats.highest_speed==450 and p.last_claim_date=="","Corrupt stats and dates normalize")
	_check(p.daily.tasks.size()==3 and p.achievement_claims.is_empty(),"Unknown mission IDs and claims rejected")

func _test_rewards() -> void:
	_fresh()
	var id := SaveService.reserve_run()
	RewardService.begin_run(id)
	RewardService.record_snapshot({"run_id":id,"distance":8000,"best_score":3000,"cumulative_score":3000,"near_misses":5,"highest_speed":210,"play_time":180,"collisions":1})
	var summary := {"run_id":id,"score":3000,"near_misses":5,"high_speed_seconds":120,"turbo_activations":2,"total":880}
	var before := SaveService.balance()
	var xp := RushProgressionData.race_xp(summary)
	DirAccess.make_dir_absolute(SaveService.TEMP)
	_check(not SaveService.add_coins(880,id,summary),"Race failed write rejects transaction")
	_check(SaveService.balance()==before and SaveService.progression.xp==0 and SaveService.progression.stats.completed==0,"Race failure rolls back wallet, XP and completion")
	DirAccess.remove_absolute(SaveService.TEMP)
	_check(SaveService.add_coins(880,id,summary),"Race retry succeeds")
	var expected := before+880+250
	_check(SaveService.balance()==expected and SaveService.progression.xp==xp and SaveService.progression.level==2,"Race, XP and level coins commit together")
	_check(SaveService.wallet.receipt.summary.new_best and SaveService.wallet.receipt.summary.level_coins==250,"Receipt carries new best and level reward")
	_check(not SaveService.add_coins(880,id,summary) and SaveService.balance()==expected,"Race duplicate rejected")
	SaveService.load_settings()
	_check(not SaveService.add_coins(880,id,summary) and SaveService.progression.stats.completed==1,"Reload retry cannot double count race")
	RewardService.refresh_date()
	var task: Dictionary = SaveService.progression.daily.tasks[0]
	RushProgressionData.event(SaveService.progression,task.event,task.target)
	var mission_id: String = task.id
	var date: String = SaveService.progression.daily.date
	var previous_xp := int(SaveService.progression.xp)
	DirAccess.make_dir_absolute(SaveService.TEMP)
	_check(not RewardService.claim_mission(mission_id,date),"Mission write failure rejected")
	_check(not SaveService.progression.daily.tasks[0].claimed and SaveService.progression.xp==previous_xp,"Mission rollback includes claim and XP")
	DirAccess.remove_absolute(SaveService.TEMP)
	_check(RewardService.claim_mission(mission_id,date),"Completed mission claim")
	var balance := SaveService.balance()
	_check(not RewardService.claim_mission(mission_id,date) and SaveService.balance()==balance,"Double tap mission rejected")
	_check(RewardService.claim_achievement("rookie"),"Actual completed-race achievement claim")
	balance = SaveService.balance()
	_check(not RewardService.claim_achievement("rookie") and SaveService.balance()==balance,"Achievement claim once")
	SaveService.load_settings()
	_check(not RewardService.claim_achievement("rookie"),"Achievement claim survives reload")
	_check(not RewardService.claim_achievement("garage_king"),"Incomplete achievement rejected")
	_check(RewardService.set_player_name("  Lane Racer  "),"Local name transaction")
	SaveService.load_settings()
	_check(SaveService.progression.name=="Lane Racer","Name persists")
	SaveService.wallet.coins = SaveService.MAX_COINS
	balance = SaveService.balance()
	SaveService.progression.stats.near_misses = 10
	_check(not RewardService.claim_achievement("close_call") and "close_call" not in SaveService.progression.achievement_claims and SaveService.balance()==balance,"Wallet overflow rolls back claim")

func _test_dates() -> void:
	for date: String in ["2026-09-06","2026-09-07","2026-09-30","2026-10-01","2026-12-31","2027-01-01","2028-02-29"]:
		_check(RushProgressionData.valid_date(date),"Valid complete date "+date)
	for date: String in ["2026-02-29","2026-04-31","2026-13-01","2026-00-12","26-9-6","2026-09-00"]:
		_check(not RushProgressionData.valid_date(date),"Invalid complete date "+date)
	var p := RushProgressionData.defaults()
	for date: String in ["2026-09-06","2026-09-07","2026-09-30","2026-10-01","2026-12-31","2027-01-01"]:
		_check(RushProgressionData.ensure_date(p,date),"New calendar date resets "+date)
		p.daily.tasks[0].progress = 1
		_check(not RushProgressionData.ensure_date(p,date) and p.daily.tasks[0].progress==1,"Same date preserves progress "+date)
	_check(not RushProgressionData.ensure_date(p,"2026-09-06"),"Clock rollback cannot recreate older mission set")
	_fresh()
	# A dedicated date argument tests calendar behavior; no production date override UI.
	SaveService.progression = RushProgressionData.defaults()
	for i: int in range(1,8):
		var date := "2090-12-%02d"%(24+i)
		var before := SaveService.balance()
		_check(RewardService.claim_daily_reward(date),"Daily cycle claim %d"%i)
		_check(SaveService.balance()==before+int(RushProgressionData.spec.daily_rewards[i-1]),"Daily cycle value %d"%i)
		_check(not RewardService.claim_daily_reward(date),"Same-date duplicate %d"%i)
	_check(RewardService.claim_daily_reward("2091-01-05") and SaveService.progression.reward_day==1,"Year boundary and missed days continue repeating cycle")
	SaveService.load_settings()
	_check(not RewardService.claim_daily_reward("2091-01-05") and not RewardService.claim_daily_reward("2090-12-31"),"Reload and clock rollback do not duplicate daily coins")
	SaveService.progression = RushProgressionData.defaults()
	var balance := SaveService.balance()
	DirAccess.make_dir_absolute(SaveService.TEMP)
	_check(not RewardService.claim_daily_reward("2091-02-01") and SaveService.balance()==balance and SaveService.progression.last_claim_date=="","Daily failed write rolls back marker and coins")
	DirAccess.remove_absolute(SaveService.TEMP)
	_check(RewardService.claim_daily_reward("2091-02-01"),"Daily retry after failed storage")

func _test_stats() -> void:
	_fresh()
	var id := SaveService.reserve_run()
	RewardService.begin_run(id)
	RewardService.begin_run(id)
	var snapshot := {"run_id":id,"distance":750.0,"play_time":30.0,"pickups":4,"road_coins":40,"near_misses":2,"best_combo":2,"turbo_activations":1,"collisions":1,"best_score":800,"cumulative_score":800,"highest_speed":205}
	RewardService.record_snapshot(snapshot)
	RewardService.record_snapshot(snapshot)
	_check(SaveService.progression.stats.started==1 and SaveService.progression.stats.distance==750 and SaveService.progression.stats.near_misses==2,"Duplicate start and cumulative snapshot do not double count")
	SaveService.commit()
	SaveService.load_settings()
	RewardService.record_snapshot(snapshot)
	_check(SaveService.progression.stats.distance==750 and SaveService.progression.stats.play_time==30,"Checkpoint idempotency after reload")
	snapshot.distance = 900
	snapshot.play_time = 35
	RewardService.record_snapshot(snapshot)
	RewardService.abandon_run(id)
	RewardService.abandon_run(id)
	RewardService.record_snapshot(snapshot)
	_check(SaveService.progression.stats.distance==900 and SaveService.progression.stats.completed==0 and SaveService.progression.xp==0,"Partial run keeps actual distance without full-route reward")
	_check(SaveService.progression.stats.road_coins==40 and SaveService.progression.stats.lifetime_coins==0,"Unbanked road coins distinguished from wallet income")
	SaveService.wallet.coins = 1000000
	SaveService._load_collection({})
	SaveService.progression.stats.cars_owned = 1
	var purchases := int(SaveService.progression.stats.cars_purchased)
	_check(SaveService.buy_vehicle("falcon_s1"),"Purchase integrates career")
	_check(not SaveService.buy_vehicle("falcon_s1") and SaveService.progression.stats.cars_purchased==purchases+1,"Duplicate purchase cannot add stats")
	_check(SaveService.buy_upgrade("falcon_s1","engine",0),"Upgrade integrates career")
	_check(not SaveService.buy_upgrade("falcon_s1","engine",0) and SaveService.progression.stats.upgrades_purchased==1,"Duplicate upgrade cannot add stats")

func _test_integration() -> void:
	_fresh()
	SaveService._load_collection({})
	game = load("res://Core/Main.tscn").instantiate()
	add_child(game)
	for i: int in 4000:
		if game.ready_for_drive:
			break
		await get_tree().process_frame
	_check(game.ready_for_drive,"Phase 5 boot")
	if not game.ready_for_drive:
		return
	game.open_progression("daily")
	_check(game.ui.screen=="daily" and not DriveInput.enabled,"Daily menu isolates driving input")
	game.go_home()
	game.open_progression("profile")
	_check(game.showroom.active and game.showroom.camera.current and game.ui.screen=="profile","Profile uses selected car showroom")
	game.go_home()
	game.open_progression("missions")
	_check(game.progression_ui.mission_rows.size()==3 and game.progression_ui.achievement_rows.size()==15,"Cached mission rows")
	for width: int in [1280,1440,1560,1600]:
		get_window().size = Vector2i(width,720)
		await get_tree().process_frame
		_check(game.ui.screens.missions.size.x==game.ui.safe.size.x,"Safe-area menu width %d"%width)
	game.go_home()
	game.start_drive()
	await _frames(165)
	_check(game.run.state==RushRunManager.RunState.RUNNING,"Countdown still unlocks run")
	game.run.actual_distance = 500
	game.run.collect_coin()
	game.run.award_near_miss()
	game.run.record_turbo()
	game.pause_drive()
	var elapsed: float = game.run.elapsed
	await _frames(8)
	_check(game.run.elapsed==elapsed,"Pause does not count play time")
	game.resume_drive()
	game.go_home()
	_check(SaveService.progression.stats.distance>=500 and SaveService.progression.stats.distance<8000 and SaveService.progression.stats.completed==0,"Early exit records actual distance")
	_check(not game.progression_ui.notice.visible,"No unearned level notice")
	game.start_drive()
	await _frames(165)
	var high: float = game.run.highest_speed
	game.vehicle.position.z -= 1000
	game.run._physics_process(1.0/60.0)
	_check(game.run.highest_speed==high,"Teleport cannot set highest speed")
	game.run.score = 3000
	game.run._finish()
	game.run.retry_reward()
	_check(game.run.result.has("xp_earned") and game.ui.screen=="results","Results have persisted XP")
	var balance := SaveService.balance()
	var completed := int(SaveService.progression.stats.completed)
	game.run.retry_reward()
	_check(SaveService.balance()==balance and SaveService.progression.stats.completed==completed,"Results reopening is idempotent")
	game.go_home()
	game.queue_free()
	await get_tree().process_frame

func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
