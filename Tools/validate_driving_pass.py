"""Offline source, asset and numerical-reference checks. NOT Godot execution."""
from pathlib import Path
import json,re,hashlib,math,wave,struct
import numpy as np
R=Path(__file__).resolve().parents[1];checks=[]
def check(name,ok): checks.append({'check':name,'passed':bool(ok)})
def read(path):return (R/path).read_text()
def body(s,name):
 m=re.search(r'^func '+re.escape(name)+r'\([^\n]*\).*?:\n(.*?)(?=^func |\Z)',s,re.M|re.S)
 return m.group(1) if m else ''
d=json.loads(read('Data/DrivingPass.json'));catalog=json.loads(read('Data/VehicleCatalog.json'))['cars'];baseline=json.loads(read('Docs/driving-baseline.json'))
for key,digest in baseline['methods'].items():
 rel,name=key.split('::')
 if rel=='Input/DriveInput.gd' and name in ['sample','_input']:continue # Angular steering explicitly replaces these methods in the polish pass.
 check('Preserved method '+key,any(hashlib.sha256((body(read(rel),name).rstrip()+chr(10)*n).encode()).hexdigest()==digest for n in range(4)))
for rel in ['Progression/ProgressionData.gd','Progression/RewardService.gd','Data/ProgressionSpec.json','Data/MissionCatalog.json','Data/AchievementCatalog.json','Gameplay/RunManager.gd','Collectibles/CoinSystem.gd','Environment/RoadFrame.gd','project.godot','export_presets.cfg']:
 check('Untouched existing system '+rel,hashlib.sha256((R/rel).read_bytes()).hexdigest()==baseline['files'][rel])
# Reference integration of the delivered gear data using the existing acceleration taper.
acceleration=[]
for car in catalog:
 config=dict(d['transmission'],**d['vehicle_transmissions'][car['id']]);caps=config['speed_fractions'];torques=config['torque']
 check(car['id']+' six ordered gears',len(caps)==len(torques)==6 and all(a<b for a,b in zip(caps,caps[1:])))
 check(car['id']+' five finite anchors',len(car['camera_anchors'])==5 and np.isfinite(car['camera_anchors']).all())
 check(car['id']+' all attachment names',len(car['attachment_markers'])==7)
 timings=[]
 for hz in [30,60,120]:
  dt=1/hz;speed=0.;gear=1;hold=shift=0.;at100=None;changes=[]
  for frame in range(90*hz):
   hold=max(0,hold-dt);shift=max(0,shift-dt)
   if hold<=0 and shift<=0 and speed*3.6>car['top_speed_kmh']*caps[gear-1]*.94 and gear<6:
    gear+=1;hold=config['minimum_hold'];shift=config['shift_seconds'];changes.append(frame*dt)
   cap=car['top_speed_kmh']/3.6;taper=1-.82*(speed/cap)**2
   speed=min(cap,speed+car['acceleration']*(1280/car['weight_kg'])*taper*torques[gear-1]*(.15 if shift>0 else 1)*dt)
   if speed*3.6>=100 and at100 is None:at100=frame*dt
  check(car['id']+f' reference {hz}Hz reaches sixth/top',gear==6 and speed*3.6>=car['top_speed_kmh']*.98)
  check(car['id']+f' reference {hz}Hz shift hold',len(changes)==5 and all(b-a>=config['minimum_hold']-.04 for a,b in zip(changes,changes[1:])))
  timings.append(at100)
 check(car['id']+' reference launch builds progressively',all(v is not None and 2<v<15 for v in timings) and max(timings)-min(timings)<.2)
 acceleration.append({'id':car['id'],'reference_0_100_seconds_30_60_120Hz':timings})
 # Damage data / severity reference: tiny hits cannot destroy, front > scrape, finite cap.
 hp=d['durability'][car['id']]
 damage=lambda v,front: min(65,max(.5,(3+v*v*.021)*(.35+.65*front))) if v>=2 else 0
 check(car['id']+' minor impact survivable',damage(4,1)<hp*.1 and damage(1,1)==0)
 check(car['id']+' frontal severity exceeds scrape',damage(30,1)>damage(30,0)>0 and damage(100,1)<hp)
 check(car['id']+' repeated major impacts destroy',hp-2*damage(100,1)<=0)
 hashes=[]
 for i in range(4):
  path=R/'Assets/Audio'/f"engine_{car['id']}_{i}.wav"
  with wave.open(str(path)) as w:
   a=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2')/32768
   check(path.stem+' mono PCM safe',w.getnchannels()==1 and w.getframerate()==22050 and .001<float(np.sqrt(np.mean(a*a)))<.8 and np.abs(a).max()<.8)
   check(path.stem+' loop endpoints',abs(a[0]-a[-1])<.002)
  hashes.append(hashlib.sha256(path.read_bytes()).hexdigest())
 check(car['id']+' four distinct synthesized layers',len(set(hashes))==4)
for key in ['horn','shift','blowoff','passby','scrape','heavy_impact','explosion','fire','damage_warning','road_noise']:
 with wave.open(str(R/'Assets/Audio'/f'{key}.wav')) as w:
  a=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2')
  check(key+' effect nonempty unclipped',len(a)>2000 and 0<np.abs(a.astype(int)).max()<30000)
for id in ['morning','evening','dusk','night']:
 raw=(R/'Assets/Environment'/f'{id}.hdr').read_bytes();check(id+' original HDR 1K',b'-Y 512 +X 1024' in raw[:150] and len(raw)>10000)
for path in (R/'Assets/Traffic/Medium').glob('*.glb'):
 raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);triangles=sum(doc['accessors'][v.get('indices',v['attributes']['POSITION'])]['count']//3 for m in doc['meshes'] for v in m['primitives'])
 check(path.name+' valid lightweight Medium',raw[:4]==b'glTF' and 1000<triangles<4000)
check('Angular wheel drag uses absolute finger position','_wheel_position(event.position)' in read('Input/DriveInput.gd'))
check('Tilt fallback uses buttons','return 1 if selected==2 and not tilt_supported else selected' in read('Input/DriveInput.gd'))
source='\n'.join(f.read_text() for f in R.rglob('*.gd'))
for invalid in ['Environment.REFLECTED_SOURCE_SKY','@warning_ignore','warnings/treat_warnings_as_errors=false']:
 check('No invalid/suppressed API '+invalid,invalid not in source+read('project.godot'))
save=read('Save/SaveService.gd');turbo=read('Turbo/TurboController.gd');ads=read('Commerce/RewardedAdService.gd');director=read('Cinematic/DrivingDirector.gd');game=read('Core/Game.gd');ai=read('Traffic/RaceOpponents.gd')
check('Schema 1–5 readable','in [1, 2, 3, 4, 5]' in body(save,'_read'))
check('All data in one atomic envelope',all('"'+key+'": '+key in body(save,'commit') for key in ['settings','wallet','collection','progression','consumables']))
check('Inventory rollback retains coins and inventory',all(t in body(save,'_commit_consumables') for t in ['if not ok:','consumables = previous','wallet.coins = coins_before','transaction_busy = true']))
check('Duplicate reward blocked before mutation',all(t in body(save,'settle_ad_request') for t in ['token<=int(consumables.ad_settled)','token!=int(consumables.ad_issued)','next.turbo_inventory += 2']))
check('No production fake provider', 'var provider: Node' in ads and 'provider==null' in ads and 'OS.is_debug_build()' in body(ads,'debug_begin') and 'OS.is_debug_build()' in body(ads,'debug_complete'))
check('Failed/skipped ad never grants', 'settle_ad_request(pending,false)' in body(ads,'_closed_without_reward'))
check('Free uses reset independently', 'free_uses = 2' in body(turbo,'reset') and 'SaveService' not in body(turbo,'reset'))
check('Paid charge before ACTIVE',body(turbo,'request_activation').index('SaveService.use_turbo_charge()')<body(turbo,'request_activation').index('_set_state(State.ACTIVE)'))
check('Offers configured 2/4/10', [v['charges'] for v in d['turbo_offers']]==[2,4,10] and all(v['coins']>0 for v in d['turbo_offers']))
check('Four clearances and lane reservations',all(t in body(ai,'lane_safe') for t in ['lane<0 or lane>3','projected_player','traffic.pool','racers.size()','plan.target']))
check('Lane changes telegraphed/rechecked',all(t in body(ai,'_physics_process') for t in ['plan.telegraph','lane_safe(racer,int(plan.target)','move_toward(racer.speed','smoothstep(0,1']))
check('No AI spawning or teleport in physics',not any(t in body(ai,'_physics_process') for t in ['.new(','.instantiate(','.activate(','.reset(']))
check('Rebase includes racers', 'director.opponents.rebase(shift)' in body(game,'_physics_process'))
check('Damage only during running lifecycle','damage.enabled = true' in body(director,'start_run') and 'damage.enabled = false' in body(director,'finish_run'))
check('Crash cancels run before reward completion','run.cancel()' in body(game,'vehicle_destroyed') and 'run._finish' not in body(game,'vehicle_destroyed'))
check('No pool allocation in active effects',all('.new(' not in body(read(rel),fn) for rel,fn in [('VFX/DamageEffects.gd','_process'),('VFX/DamageEffects.gd','explode'),('Audio/DrivingAudio.gd','play_effect'),('Traffic/TrafficVehicle.gd','update_distance_lod')]))
report={'scope':'Offline asset/source checks and Python numerical reference models only. Godot NOT run.','checks':len(checks),'failed':sum(not c['passed'] for c in checks),'reference_acceleration':acceleration,'results':checks}
(R/'Docs/driving-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"DRIVING OFFLINE: {len(checks)} checks, {report['failed']} failures")
for row in checks:
 if not row['passed']:print('FAIL:',row['check'])
raise SystemExit(bool(report['failed']))
