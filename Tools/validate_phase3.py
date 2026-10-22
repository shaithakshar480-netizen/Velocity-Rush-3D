"""Offline Phase 3 contracts, source-derived balance fixtures and PCM checks.
This is NOT a GDScript interpreter, compiler or gameplay test.
"""
from pathlib import Path
import json, re, math, struct, wave, zipfile
R=Path(__file__).resolve().parents[1]
checks=[]
def check(label,ok): checks.append({'check':label,'passed':bool(ok)})
def read(p): return (R/p).read_text()
def body(s,name):
    match=re.search(r'^func '+name+r'\([^\n]*\).*?:\n(.*?)(?=^func |\Z)',s,re.M|re.S)
    return match.group(1) if match else ''
values={k:float(v) for k,v in re.findall(r'^(\w+) = ([\d.]+)$',read('Data/VortexTurbo.tres'),re.M)}
turbo=read('Turbo/TurboController.gd'); game=read('Core/Game.gd'); audio=read('Audio/GameAudio.gd'); inp=read('Input/DriveInput.gd')
for name in ['EMPTY','CHARGING','READY','ACTIVE','COOLDOWN']: check('State '+name,name in turbo)
for gate in ['not enabled','get_tree().paused','RunState.RUNNING','State.READY','activation_min_speed','held("brake")']:
    check('Activation gate: '+gate,gate in body(turbo,'request_activation'))
check('Run-local meter and free uses reset; saved extras remain separate', 'starting_charge' in body(turbo,'reset') and 'free_uses = 2' in body(turbo,'reset') and 'SaveService' not in body(turbo,'reset'))
check('Charge clamps both boundaries','clampf(charge+' in turbo and 'maxf(amount,0.0)' in turbo)
check('Drain clamps zero','maxf(0.0,charge-' in turbo)
check('READY is edge-triggered', 'if state == value:' in body(turbo,'_set_state') and turbo.count('became_ready.emit()')==1)
check('Held SHIFT cannot auto-repeat','not event.echo' in inp and 'consume_turbo_request' in inp)
check('Input clear discards activation','turbo_pending = false' in body(inp,'clear'))
check('Turbo attached to pausable world','world.add_child(turbo)' in game and 'PROCESS_MODE_PAUSABLE' in turbo)
check('Finish explicitly stops boost','turbo.stop()' in body(game,'_run_finished'))
check('Restart and Home reset','_reset_turbo()' in body(game,'start_drive') and '_reset_turbo()' in body(game,'go_home'))
for signal in ['turbo.became_ready','turbo.activated.connect(_turbo_started)','turbo.ended','run.near_miss_awarded.connect(turbo.near_miss)','run.coin_awarded.connect(turbo.coin)']:
    check('Single integration connection: '+signal,game.count(signal)==1)
for action in ['cameras.turbo_kick()','exhaust.ignition()','turbo_ui.kick()','RushHaptics.pulse(45)','GameAudio.event("turbo_ignition")']:
    check('Activation integration: '+action,action in body(game,'_turbo_started'))
for file,fn in [('Turbo/TurboController.gd','_physics_process'),('Turbo/TurboController.gd','request_activation'),('VFX/ExhaustEffects.gd','_process'),('VFX/SpeedStreaks.gd','_draw'),('Audio/GameAudio.gd','update_vehicle')]:
    code=body(read(file),fn)
    check('No node/resource construction in '+file+':'+fn, bool(code) and not any(t in code for t in ['.new(','.instantiate(','.queue_free(','.load(']))
check('Audio loops are not restarted every frame','.play()' not in body(audio,'update_vehicle'))
check('Audio pauses all gameplay categories','key not in ["music","ui"]' in body(audio,'set_suspended'))
check('Exhaust model-local emitters','car.spec.exhaust_points' in read('VFX/ExhaustEffects.gd') and 'car.visual.body_root.add_child(nozzle)' in read('VFX/ExhaustEffects.gd'))
check('Finite peripheral density','else 24' in read('VFX/SpeedStreaks.gd'))
check('Effects prewarmed before ready',game.index('exhaust.warming = true')<game.index('ready_for_drive = true'))
check('No global slow motion','Engine.time_scale =' not in '\n'.join(p.read_text() for p in R.rglob('*.gd') if 'Tests' not in p.parts))
base=R.parent/'VelocityRush3D-Phase2-Fix.zip'
if base.exists():
    with zipfile.ZipFile(base) as z:
        for path in ['Data/HighwayRush.tres','Collectibles/CoinSystem.gd']:
            check('Phase 2 bytes unchanged: '+path,z.read('VelocityRush3D/'+path)==(R/path).read_bytes())
for name in ['wind','turbo_spool','turbo_ready','turbo_ignition','turbo_flare','turbo_end']:
    with wave.open(str(R/'Assets/Audio'/f'{name}.wav')) as w:
        rate=w.getframerate(); n=w.getnframes(); values_pcm=struct.unpack('<'+'h'*n,w.readframes(n))
        check(name+' PCM format',rate==22050 and w.getnchannels()==1 and w.getsampwidth()==2)
        check(name+' nonempty/unclipped',max(abs(v) for v in values_pcm)<30000 and sum(abs(v) for v in values_pcm)>0)
        check(name+' loop seam' if name in ['wind','turbo_spool'] else name+' endpoint envelope',abs(values_pcm[0]-values_pcm[-1])<500)
check('Six-second nominal duration',abs(values['capacity']/values['drain_per_second']-6)<.001)
check('Coin cannot dominate full budget',90*values['coin_charge']<values['capacity']*.35)
# Deterministic reference balance budgets, not real user telemetry or execution of GDScript.
def scenario(seconds,near_interval,combo):
    charge=0; active=0; cooldown=0; activations=0; high_time=0
    dt=1/60
    for i in range(int(seconds/dt)):
        t=i*dt
        if active>0:
            active=max(0,active-dt)
            if active==0:cooldown=values['cooldown_seconds']
        elif cooldown>0:cooldown=max(0,cooldown-dt)
        else:
            if t>10:
                charge+=values['high_speed_charge']*dt; high_time+=dt
            if i>0 and i%int(near_interval/dt)==0:
                charge+=values['near_miss_charge']*(1+(combo-1)*values['combo_step'])
            if i>0 and i%int(4/dt)==0:charge+=values['coin_charge']
            charge=min(values['capacity'],charge)
            if charge>=values['capacity']:
                charge=0;active=values['capacity']/values['drain_per_second'];activations+=1
    return activations
scenarios=[]
for label,seconds,interval,combo in [('steady',180,20,1),('skilled',180,14,2),('long skilled',240,15,2)]:
    count=scenario(seconds,interval,combo); scenarios.append({'label':label,'seconds':seconds,'near_miss_interval':interval,'combo':combo,'activations':count})
    check('Balance fixture '+label,2<=count<=4)
report={'scope':'Offline structural contracts, source-derived reference arithmetic and audio data; NOT compilation/render/runtime','checks':len(checks),'failed':sum(not c['passed'] for c in checks),'balance_fixtures':scenarios,'results':checks}
(R/'Docs/phase3-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"PHASE3 OFFLINE: {report['checks']} checks, {report['failed']} failures")
print(json.dumps(scenarios))
for c in checks:
    if not c['passed']: print('FAIL:',c['check'])
raise SystemExit(bool(report['failed']))
