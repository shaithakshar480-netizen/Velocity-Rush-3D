"""Offline package validation. This is NOT a GDScript compiler/runtime test.
Checks local references, structural delimiters, configured scope and PCM assets.
"""
import json
import math
import re
import struct
import sys
import wave
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = []


def check(label, condition, detail=''):
    checks.append({'check': label, 'passed': bool(condition), 'detail': detail})


def structure(source):
    """Conservative delimiter and string check, not a syntax grammar."""
    stack = []
    quote = None
    escaped = False
    comment = False
    for ch in source:
        if comment:
            if ch == '\n':
                comment = False
            continue
        if quote:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == quote:
                quote = None
            continue
        if ch == '#':
            comment = True
        elif ch in ('"', "'"):
            quote = ch
        elif ch in '([{':
            stack.append(ch)
        elif ch in ')]}':
            if not stack or stack.pop() != dict(zip(')]}', '([{'))[ch]:
                return False
    return not quote and not stack


def main():
    files = list(ROOT.rglob('*'))
    scripts = sorted(ROOT.rglob('*.gd'))
    classes = {}
    for path in scripts:
        source = path.read_text()
        rel = str(path.relative_to(ROOT))
        check('Balanced delimiters: '+rel, structure(source))
        check('No conflict markers: '+rel, not re.search(r'^(<<<<<<<|=======|>>>>>>>)', source, re.M))
        definitions = re.findall(r'^func\s+(\w+)\(', source, re.M)
        check('No duplicate functions: '+rel, len(definitions) == len(set(definitions)))
        for name in re.findall(r'^class_name\s+(\w+)', source, re.M):
            check('Unique class '+name, name not in classes)
            classes[name] = rel
    for path in files:
        if path.is_file() and path.suffix in ('.gd', '.tscn', '.tres', '.godot'):
            for ref in re.findall(r'res://([^"\n]+)', path.read_text()):
                # The audio directory is dynamically combined with the CLIPS catalog.
                check('Resource exists: '+ref, (ROOT / ref).exists())
    project = (ROOT/'project.godot').read_text()
    check('Landscape enforced', 'window/handheld/orientation=0' in project)
    check('Compatibility renderer', 'renderer/rendering_method="gl_compatibility"' in project)
    check('60 Hz fixed physics', 'common/physics_ticks_per_second=60' in project)
    for category in ['Core','Vehicle','Input','Camera','UI','Audio','Save','Environment','Data']:
        check('Architecture folder '+category, (ROOT/category).is_dir())
    for action in ['KEY_W','KEY_UP','KEY_S','KEY_DOWN','KEY_A','KEY_LEFT','KEY_D','KEY_RIGHT','KEY_C','KEY_ESCAPE','KEY_R']:
        check('Keyboard binding '+action, action in (ROOT/'Input/DriveInput.gd').read_text())
    camera = (ROOT/'Camera/CameraRig.gd').read_text()
    check('Four named cameras', all(name in camera for name in ['"CHASE"','"FAR CHASE"','"HOOD"','"BUMPER"']))
    for name in ['engine','skid','collision','ui','ambience','coin','near_miss','countdown','go','finish']:
        path = ROOT/'Assets/Audio'/f'{name}.wav'
        with wave.open(str(path),'rb') as audio:
            samples = struct.unpack('<'+'h'*audio.getnframes(),audio.readframes(audio.getnframes()))
            check('PCM format '+name, audio.getnchannels()==1 and audio.getsampwidth()==2 and audio.getframerate()==22050)
            peak = max(abs(value) for value in samples)/32768
            rms = math.sqrt(sum((value/32768)**2 for value in samples)/len(samples))
            check('Nonempty, unclipped '+name, 0.005<rms<0.8 and peak<0.96, f'peak={peak:.4f}, RMS={rms:.4f}')
            if name in ['engine','ambience']:
                check('Loop seam '+name, abs(samples[0]-samples[-1])<3000)
    ET.parse(ROOT/'Assets/icon.svg')
    check('SVG XML parses', True)
    source = '\n'.join(p.read_text() for p in scripts if 'Tests' not in p.parts)
    check('No network, ads or billing implementation', not any(token in source for token in ['HTTPRequest.new','Firebase','AdMob','BillingClient','MobileAds']))
    check('Original traffic asset generator included', (ROOT/'Tools/generate_traffic_models.py').is_file())
    report = {
        'scope':'Offline structural/resource checks only; not compilation, rendering, physics or device testing.',
        'checks':len(checks), 'failed':sum(not row['passed'] for row in checks), 'results':checks,
    }
    (ROOT/'Docs/offline-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"Offline validation: {report['checks']} checks, {report['failed']} failures")
    for row in checks:
        if not row['passed']:
            print('FAIL:', row['check'], row['detail'])
    return 1 if report['failed'] else 0


if __name__ == '__main__':
    sys.exit(main())
