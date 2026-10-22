"""Import, run integration checks, and smoke-launch with a locally installed Godot.
Usage: python Tools/run_engine_checks.py --godot /path/to/godot
Uses isolated user data so corruption-recovery tests cannot touch a player save.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', ''))
    args = parser.parse_args()
    executable = args.godot or shutil.which('godot') or shutil.which('godot4')
    if not executable:
        print('BLOCKED: Godot is not installed. Pass --godot with the Godot 4 executable.')
        return 2
    logs = []
    with tempfile.TemporaryDirectory(prefix='velocity-rush-tests-') as profile:
        env = os.environ.copy()
        env['XDG_DATA_HOME'] = profile
        env['APPDATA'] = profile
        # Godot's macOS data path is under HOME/Library/Application Support.
        # Use project override instead of repurposing HOME for isolation.
        override = ROOT/'override.cfg'
        if override.exists():
            print('BLOCKED: override.cfg already exists; preserve your override and test in a fresh project copy.')
            return 2
        user_name = 'VelocityRush3D-Tests-' + Path(profile).name
        override.write_text('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir="'+user_name+'"\n')
        try:
            commands = [
                [executable,'--headless','--path',str(ROOT),'--editor','--import'],
                [executable,'--headless','--path',str(ROOT),'res://Tests/Smoke.tscn'],
                [executable,'--headless','--path',str(ROOT),'res://Tests/Phase2Smoke.tscn'],
                [executable,'--headless','--path',str(ROOT),'res://Tests/Phase2FixSmoke.tscn'],
                [executable,'--headless','--path',str(ROOT),'res://Tests/Phase3Smoke.tscn'],
                [executable,'--headless','--path',str(ROOT),'res://Tests/Phase4Smoke.tscn'],
                [executable,'--headless','--path',str(ROOT),'res://Tests/Phase5Smoke.tscn'],
                [executable,'--headless','--path',str(ROOT),'res://Tests/VisualPassSmoke.tscn'],
                [executable,'--headless','--path',str(ROOT),'res://Tests/PremiumSmoke.tscn'],
                [executable,'--headless','--path',str(ROOT),'res://Tests/DrivingPassSmoke.tscn'],
                [executable,'--headless','--path',str(ROOT),'--quit-after','240'],
            ]
            for command in commands:
                result = subprocess.run(command,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
                logs.append(result.stdout)
                print(result.stdout)
                if result.returncode or 'SCRIPT ERROR:' in result.stdout or '\nERROR:' in result.stdout:
                    return 1
            if not all(any(marker in log and '0 failures' in log for log in logs) for marker in ('PHASE1_SMOKE:', 'PHASE2_SMOKE:', 'PHASE2_FIX_SMOKE:', 'PHASE3_SMOKE:', 'PHASE4_SMOKE:', 'PHASE5_SMOKE:', 'VISUAL_PASS_SMOKE:', 'PREMIUM_SMOKE:', 'DRIVING_PASS_SMOKE:')):
                print('FAIL: Integration runner did not reach its completion marker.')
                return 1
            return 0
        finally:
            override.unlink(missing_ok=True)
            (ROOT/'Docs/engine-checks.log').write_text('\n'.join(logs))


if __name__ == '__main__':
    sys.exit(main())
