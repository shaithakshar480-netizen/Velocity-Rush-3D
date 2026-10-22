"""Export a debug APK after Godot, matching templates, JDK and SDK are configured.
No release signing material or secrets are generated/embedded in the source.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', ''))
    args = parser.parse_args()
    executable = args.godot or shutil.which('godot') or shutil.which('godot4')
    if not executable:
        print('BLOCKED: Godot is not installed; pass --godot with its executable path.')
        return 2
    check = subprocess.run([sys.executable,str(ROOT/'Tools/run_engine_checks.py'),'--godot',executable])
    if check.returncode:
        return check.returncode
    output = ROOT/'build/VelocityRush3D.apk'
    output.parent.mkdir(exist_ok=True)
    result = subprocess.run([executable,'--headless','--path',str(ROOT),'--export-debug','Android',str(output)])
    if result.returncode or not output.is_file():
        print('Android export failed. Check Godot Android SDK/JDK paths and matching export templates.')
        return 1
    print('Created:',output)
    return 0


if __name__ == '__main__':
    sys.exit(main())
