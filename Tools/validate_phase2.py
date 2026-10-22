"""Offline Phase 2 contracts and balance fixtures. Does not execute GDScript.
Uses actual source reward expression and configuration for arithmetic checks.
Also checks exact preservation of Phase 1 files when its original ZIP is present.
"""
import json
from pathlib import Path
import re
from types import SimpleNamespace
import zipfile

ROOT = Path(__file__).resolve().parents[1]
checks = []


def check(name, passed, detail=''):
    checks.append({'check': name, 'passed': bool(passed), 'detail': detail})


def function_body(source, name):
    match = re.search(r'^(?:static )?func '+re.escape(name)+r'\([^\n]*\).*?:\n(.*?)(?=^(?:static )?func |\Z)',source,re.M|re.S)
    return match.group(1) if match else ''


def main():
    spec_text = (ROOT/'Data/RunSpec.gd').read_text()
    values = {}
    for key, number in re.findall(r'@export var (\w+): (?:float|int) = ([\d.]+)',spec_text):
        values[key] = float(number) if '.' in number else int(number)
    spec = SimpleNamespace(**values)
    run = (ROOT/'Gameplay/RunManager.gd').read_text()
    wallet = (ROOT/'Save/SaveService.gd').read_text()
    traffic = (ROOT/'Traffic/TrafficSystem.gd').read_text()
    coins = (ROOT/'Collectibles/CoinSystem.gd').read_text()
    game = (ROOT/'Core/Game.gd').read_text()
    for prefix, source, functions in [
        ('Traffic',traffic,['_physics_process','_try_spawn','evaluate_passes','reset_pool']),
        ('Coins',coins,['_physics_process','_process','_spawn_pattern','evaluate_pickups','reset_pool']),
    ]:
        for fn in functions:
            body = function_body(source,fn)
            check(prefix+' no per-tick object creation/free: '+fn,bool(body) and not any(token in body for token in ['.new(','.instantiate(','.queue_free(','.free(']))
    for fragment in ['run.rebase(shift)','traffic.rebase(shift)','coins.rebase(shift)']:
        check('World rebase includes '+fragment,fragment in game)
    check('Wallet and settings share atomic schema 5 envelope','"schema_version": 5, "settings": settings, "wallet": wallet' in wallet)
    check('Schema 1 still readable','in [1, 2, 3, 4, 5]' in wallet)
    rewards = (ROOT/'Progression/RewardService.gd').read_text()
    claim = function_body(rewards,'settle_race')
    storage = function_body(wallet,'commit_reward')
    check('Claim validates issued and settled IDs',all(token in claim for token in ['id!=int(SaveService.wallet.issued_run)','SaveService.is_settled(id)']) and 'wallet["settled_run"] = receipt.run_id' in storage)
    check('Claim rollback on failed write','wallet = before_wallet' in storage and 'progression = before_progression' in storage and 'if not success:' in storage)
    check('Failed reward blocks leaving results',game.count('run.state == RushRunManager.RunState.FINISHED and not run.reward_saved')==2)
    check('Near miss requires pass completion','relative_after.z < -longitudinal-0.8' in traffic and 'traffic.pass_resolved = true' in traffic)
    check('Near miss rejects collision','not traffic.was_hit' in traffic)
    check('Escape lane excluded at spawn','lane == escape_lane' in function_body(traffic,'placement_safe'))
    check('Speed-sensitive reaction distance','car.speed_kmh()/3.6*run.spec.reaction_seconds' in traffic)
    check('Coin spawn validates traffic','point_safe(point)' in coins and 'traffic_conflicts' in traffic)
    check('Finite coin supply per run','spawned < run.spec.coin_budget' in coins)
    check('No retrace distance score','new_distance := maxf(distance-furthest,0.0)' in run)
    expression = re.search(r'var performance_bonus := (.+)',run).group(1)
    for label, road, score, near, high, expected in [
        ('modest',20,2000,3,60,430),
        ('normal',40,3000,5,120,520),
        ('skilled',60,6500,12,160,660),
    ]:
        env = {'spec':spec,'score':score,'near_misses':near,'high_speed_seconds':high,'mini':min,'int':int}
        # Expression is our checked-in arithmetic, evaluated without builtins/imports.
        bonus = eval(expression, {'__builtins__':{}}, env)
        total = road+spec.completion_reward+bonus
        check('Reward fixture '+label,total==expected, f'{road} road + {spec.completion_reward} completion + {bonus} performance = {total}')
    check('Distance supports 2–4 minutes at 120–210 KM/H', all(120 <= spec.distance_m/(speed/3.6) <= 240 for speed in [120,150,180,210]))
    check('Road coin value',spec.coin_value==1)
    original = ROOT.parent/'VelocityRush3D-Phase1.zip'
    if original.exists():
        with zipfile.ZipFile(original) as old:
            for path in ['Data/VortexS.tres','Environment/Geometry.gd']:
                check('Phase 1 unchanged: '+path, old.read('VelocityRush3D/'+path)==(ROOT/path).read_bytes())
            for name in ['engine','skid','collision','ui','ambience']:
                path = 'Assets/Audio/'+name+'.wav'
                if name=='ambience':
                    check('Unused legacy ambience retained',old.read('VelocityRush3D/'+path)==(ROOT/path).read_bytes())
                else:
                    # The premium pass explicitly replaces these clips; keep format contracts.
                    import wave
                    with wave.open(str(ROOT/path)) as sound:
                        check('Preserved audio format: '+name,sound.getnchannels()==1 and sound.getsampwidth()==2 and sound.getframerate()==22050)
    # Phase 3 intentionally extends VehicleSpec; validate the preserved driving fields separately.
    if original.exists():
        with zipfile.ZipFile(original) as old:
            before = old.read('VelocityRush3D/Data/VehicleSpec.gd').decode()
            current = (ROOT/'Data/VehicleSpec.gd').read_text()
            for line in before.splitlines():
                if line.startswith('@export') and 'turbo_capacity' not in line:
                    check('Vehicle property preserved: '+line.split(':')[0],line in current)
    report = {'scope':'Offline source contracts, arithmetic fixtures and byte comparison only; NOT GDScript/runtime tests.',
              'checks':len(checks),'failed':sum(not c['passed'] for c in checks),'results':checks}
    (ROOT/'Docs/phase2-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"Phase 2 offline checks: {report['checks']}, failures: {report['failed']}")
    for c in checks:
        if not c['passed']:
            print('FAIL:',c['check'],c['detail'])
    return 1 if report['failed'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
