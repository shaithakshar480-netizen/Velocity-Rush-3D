"""Offline config arithmetic, packaging and source contracts. NOT GDScript execution.
Actual engine assertions live in Tests/Phase5Smoke.gd and remain a separate gate.
"""
from pathlib import Path
import datetime as dt
import json, re, struct, wave, zipfile, hashlib
R=Path(__file__).resolve().parents[1]; checks=[]
def check(name,passed):checks.append({'check':name,'passed':bool(passed)})
def read(path):return (R/path).read_text()
def body(source,fn):
    m=re.search(r'^(?:static )?func '+fn+r'\([^\n]*\).*?:\n(.*?)(?=^(?:static )?func |\Z)',source,re.M|re.S)
    return m.group(1) if m else ''
spec=json.loads(read('Data/ProgressionSpec.json'))
missions=json.loads(read('Data/MissionCatalog.json')); achievements=json.loads(read('Data/AchievementCatalog.json'))
model=read('Progression/ProgressionData.gd'); service=read('Progression/RewardService.gd'); save=read('Save/SaveService.gd');run=read('Gameplay/RunManager.gd');game=read('Core/Game.gd');ui=read('UI/ProgressionUI.gd')
def required(level):n=level-1;return spec['xp_base']+spec['xp_linear']*n+spec['xp_quadratic']*n*n
def threshold(level):return sum(required(n) for n in range(1,level))
def level_for(xp):return max(l for l in range(1,51) if xp>=threshold(l))
def level_coins(level):return next(b['coins'] for b in spec['level_rewards'] if level<=b['through'])
check('Configured cap 50',spec['max_level']==50)
for l in range(1,50):
    check(f'Positive increasing XP {l}',required(l)>0 and required(l+1)>required(l))
    check(f'Boundary {l}',level_for(threshold(l+1)-1)==l and level_for(threshold(l+1))==l+1)
    check(f'Level reward band {l+1}',250<=level_coins(l+1)<=4000)
check('Early onboarding L5 within six 404-XP runs',threshold(5)<=6*404)
check('Long-term L50',threshold(50)>400000)
check('Level ID implicit in earned-level boundary','range(old+1,int(p.level)+1)' in body(model,'award_xp'))
check('XP capped persistently','threshold(int(spec.max_level))' in body(model,'award_xp'))
check('Level derived from XP on migration','p.level = level_for(p.xp)' in body(model,'normalize'))
check('Race XP supports completion, score, near miss, high speed and Turbo',all(k in body(model,'race_xp') for k in ['completion','score','near_misses','high_speed_seconds','turbo_activations']))
for catalog,label in [(missions,'Daily'),(achievements,'Career')]:
    check(label+' unique stable IDs',len(catalog)==len({x['id'] for x in catalog}))
    for m in catalog:
        check(label+' positive target/reward '+m['id'],m['target']>0 and 0<m['coins']<=1500 and 0<m['xp']<=500)
        check(label+' known event '+m['id'],m['event'] in ['completed','pickups','near_misses','highest_speed','best_combo','turbo_activations','distance','best_score','clean_finish','cars_owned','upgrades_purchased','cumulative_score'])
check('At least 15 achievements',len(achievements)>=15)
for tier in ['easy','medium','hard']:
    pool=[m for m in missions if m['tier']==tier]
    check(tier+' has four choices',len(pool)==4)
    low,high={'easy':(150,300),'medium':(300,500),'hard':(500,800)}[tier]
    check(tier+' reward budget',all(low<=m['coins']<=high for m in pool))
check('No unowned-car prerequisite',all(m.get('car') is None and (m['event']!='highest_speed' or m['target']<=270) for m in missions))
for d in [dt.date(2026,9,6)+dt.timedelta(days=i) for i in range(35)]:
    seed=int(d.isoformat().replace('-',''))
    chosen=[([m for m in missions if m['tier']==tier])[(seed+slot*7)%4] for slot,tier in enumerate(['easy','medium','hard'])]
    check('Fair deterministic set '+d.isoformat(),len({m['id'] for m in chosen})==3 and sum(m['coins'] for m in chosen)<=1050)
for a,b in [('2026-09-06','2026-09-07'),('2026-09-30','2026-10-01'),('2026-12-31','2027-01-01'),('2028-02-28','2028-02-29'),('2028-02-29','2028-03-01')]:
    check('Full-date ordering '+a+' -> '+b,dt.date.fromisoformat(a)+dt.timedelta(days=1)==dt.date.fromisoformat(b) and a<b)
check('Month lengths and Gregorian leap years in source','year%100!=0 or year%400==0' in body(model,'valid_date') and 'day<=days[month-1]' in body(model,'valid_date'))
check('Backward clock cannot recreate missions','date<p.date_highwater' in body(model,'ensure_date'))
check('Same calendar date preserves missions','p.daily.date==date' in body(model,'ensure_date'))
check('Daily rewards repeat forgiving cycle','int(p.reward_day)%7+1' in body(service,'claim_daily_reward'))
check('Full-date same day and backward claim guard','date<=p.last_claim_date' in body(service,'claim_daily_reward') and 'date<p.date_highwater' in body(service,'claim_daily_reward'))
check('Seven configured rewards',spec['daily_rewards']==[300,400,500,650,800,1000,1500])
check('Mission date/id/claim/progress gates',all(t in body(service,'claim_mission') for t in ['date!=p.daily.date','date!=RushProgressionData.local_date()','task.id==id','not task.claimed','task.progress>=task.target']))
check('Career claim gated by ID and actual stat',all(t in body(service,'claim_achievement') for t in ['id in p.achievement_claims','item.id==id','achievement_value(p,item)>=float(item.target)']))
check('Central source identifiers',all(t in service for t in ['"race_%d"','"daily_"+date','"mission_"+date+"_"+id','"achievement_"+id']))
check('Atomic schema contains wallet collection progression','"schema_version": 5' in save and all('"'+k+'": '+k in body(save,'commit') for k in ['settings','wallet','collection','progression']))
check('Reads all prior schemas','in [1, 2, 3, 4, 5]' in body(save,'_read'))
check('Atomic reward rollback restores both',all(t in body(save,'commit_reward') for t in ['wallet = before_wallet','progression = before_progression','wallet["settled_run"] = receipt.run_id','transaction_busy = true','var success := commit()']))
check('Transaction cannot overflow wallet','amount>MAX_COINS-balance()' in body(save,'commit_reward'))
check('Failed pending cannot replay later','DirAccess.remove_absolute(TEMP)' in body(save,'_failed_commit'))
check('Race API delegates rewards','RewardService.settle_race(amount,run_id,summary)' in body(save,'add_coins'))
check('Race XP and completion in same candidate',all(t in body(service,'settle_race') for t in ['p.stats.completed += 1','RushProgressionData.award_xp','commit_reward(p,total,receipt)']))
check('No wallet writes in progression UI',not re.search(r'wallet\s*\[.*?\]\s*=|wallet\.coins\s*=',ui))
check('Idempotent cumulative run snapshots',all(t in body(service,'record_snapshot') for t in ['id<=int(p.last_finalized)','value-float(cp.get(key,0))','cp[key] = maxf']))
check('Start ID is issued and strictly increasing','id<=int(p.last_started)' in body(service,'begin_run') and 'id!=int(SaveService.wallet.issued_run)' in body(service,'begin_run'))
check('Actual forward distance, not full route','actual_distance += forward_step' in run and '"distance":actual_distance' in body(run,'checkpoint'))
check('Highest speed rejects teleport and unachieved velocity',all(t in run for t in ['displacement<=ceiling/3.6*delta+0.15','absf(displacement/delta*3.6-speed)<8.0','speed<=ceiling']))
check('Pause checkpoints before pausing',body(game,'pause_drive').index('run.checkpoint()')<body(game,'pause_drive').index('get_tree().paused = true'))
check('Restart checkpoints before reset',body(game,'start_drive').index('run.cancel()')<body(game,'start_drive').index('vehicle.reset_vehicle()'))
check('Exit checkpoint and flush', 'run.checkpoint()' in body(game,'_notification'))
check('Single debounced collision subscriber',game.count('vehicle.impact.connect(run.record_collision)')==1 and 'vehicle.traffic_contact.connect(run.record_collision)' not in game)
check('Turbo event subscriber',game.count('turbo.activated.connect(run.record_turbo)')==1)
check('Purchases and stats atomic',all(t in body(save,'_commit_collection') for t in ['RushProgressionData.purchase(progression,before,next)','progression = previous_progression']))
check('No mission scanning per render frame','RushProgressionData.event' not in body(service,'_process') and 'for task' not in body(service,'_process'))
check('No disk writes in telemetry',not any(t in body(service,'record_snapshot') for t in ['.commit(', 'FileAccess']))
check('No menu construction in refresh',not any(t in body(ui,'refresh_current') for t in ['.new(','.queue_free(']))
check('One reusable level component',all('RushLevelBadge.new()' in read(p) for p in ['UI/ProgressionUI.gd','UI/RushPresentation.gd']))
check('Profile name constraints','value.strip_edges()' in model and 'result.left(20).strip_edges()' in model and 'return "Racer" if result.is_empty()' in model)
check('Safe notices, no race HUD', 'ui.screen not in ["home","results","missions","profile","daily","garage"]' in body(ui,'present_notices'))
check('Notice cleared on navigation','ui.screen_changed.connect' in ui and 'dismiss_notice()' in ui)
check('Profile selected car reused','showroom.show_vehicle(SaveService.collection.selected' in game)
check('Menus scroll inside safe area','ScrollContainer.new()' in body(ui,'_menu') and 'ui._page(' in body(ui,'_menu'))
check('Results scroll to fit short landscape','ScrollContainer.new()' in body(read('UI/RushPresentation.gd'),'_build_results'))
check('Fast menu transition','1.0,0.25' in body(read('UI/AutomotiveUI.gd'),'show_screen'))
check('No progress reset in player UI','Reset Progress' not in ui and '_fresh' not in ui)
check('Debug inspection gated','OS.is_debug_build() else {}' in body(service,'diagnostics'))
for name in ['xp_gain','level_up','mission_complete','reward_claim','achievement','daily_reward']:
    with wave.open(str(R/'Assets/Audio'/f'{name}.wav')) as w:
        values=struct.unpack('<'+'h'*w.getnframes(),w.readframes(w.getnframes()))
        check(name+' safe original PCM',w.getnchannels()==1 and w.getsampwidth()==2 and w.getframerate()==22050 and 0<max(abs(v) for v in values)<30000)
        check(name+' silent endpoints',abs(values[0])<50 and abs(values[-1])<50)
    check(name+' prewarmed',name in body(read('Audio/GameAudio.gd'),'prewarm_feedback'))
# Byte comparison is evidence of untouched systems, not a runtime regression pass.
base=R.parent/'VelocityRush3D-Phase4.zip'
if base.exists():
    with zipfile.ZipFile(base) as z:
        for name in z.namelist():
            rel=name.removeprefix('VelocityRush3D/')
            if rel in ['Save/SaveService.gd', 'Vehicle/ArcadeVehicle.gd', 'Input/DriveInput.gd', 'Turbo/TurboController.gd', 'Traffic/TrafficSystem.gd', 'Environment/SceneryTile.gd']:
                continue # Driving pass extensions validated separately.
            if rel in ['Traffic/TrafficMeshLibrary.gd','Input/SteeringWheel.gd','Garage/GarageUI.gd','Environment/asphalt.gdshader','Camera/CameraRig.gd','Vehicle/AutomotiveMaterials.gd','Vehicle/VortexVisual.gd','Traffic/TrafficVehicle.gd','Data/VehicleCatalog.json','Environment/Highway.gd','Garage/Showroom.gd'] or rel.startswith(('Assets/Player/','Assets/Environment/')):
                continue # Visual-pass replacements are checked by validate_visual_pass.py; gameplay bytes below still protected.
            if rel.startswith(('Assets/Traffic/','Assets/Environment/','Vehicle/','Input/','Camera/','Traffic/','Collectibles/','Environment/','Turbo/','VFX/','Garage/')) or rel in ['Data/VehicleCatalog.json','Data/HighwayRush.tres','Data/TurboSpec.gd']:
                check('Phase 4 bytes retained '+rel,(R/rel).is_file() and z.read(name)==(R/rel).read_bytes())
# Transparent reference balance fixtures, NOT measured player behavior.
scenarios=[]
for runs_per_day in [4,6]:
    days=30; race_income=days*runs_per_day*880; xp=days*runs_per_day*404+days*310
    level=level_for(xp); levels=sum(level_coins(l) for l in range(2,level+1))
    daily=sum(spec['daily_rewards'][i%7] for i in range(days))
    mission_income=days*1000; career_income=2500
    support=daily+mission_income+levels+career_income
    share=race_income/(race_income+support)
    scenarios.append(dict(days=days,runs_per_day=runs_per_day,coins_per_run=880,race_income=race_income,daily_income=daily,mission_income=mission_income,achievement_allowance=career_income,level_rewards=levels,ending_level=level,race_income_share=round(share,4)))
    check(f'Active {runs_per_day} runs/day budget 60–75%',.60<=share<=.75)
check('Car prices unchanged',[c['price'] for c in json.loads(read('Data/VehicleCatalog.json'))['cars']]==[0,15000,40000,90000,180000,350000])
report={'scope':'Offline data arithmetic, file bytes, PCM and source contracts only; GDScript tests NOT executed','checks':len(checks),'failed':sum(not c['passed'] for c in checks),'level_50_total_xp':threshold(50),'total_level_coins':sum(level_coins(l) for l in range(2,51)),'economy_fixtures':scenarios,'results':checks}
(R/'Docs/phase5-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"PHASE5 OFFLINE: {report['checks']} checks, {report['failed']} failures")
print(json.dumps(scenarios))
for c in checks:
    if not c['passed']:print('FAIL:',c['check'])
raise SystemExit(bool(report['failed']))
