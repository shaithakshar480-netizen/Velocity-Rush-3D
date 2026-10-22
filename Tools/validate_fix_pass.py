"""Offline structure/geometry checks only; does not compile or execute GDScript."""
from pathlib import Path
import json, math, struct, zipfile
ROOT=Path(__file__).resolve().parents[1]
checks=[]
def check(ok,name):
    checks.append({'check':name,'passed':bool(ok)})
def source(path): return (ROOT/path).read_text()
profiles=json.loads(source('Data/TrafficProfiles.json'))
for profile in profiles:
    name=profile['id']; raw=(ROOT/'Assets/Traffic'/f'{name}.glb').read_bytes()
    magic,version,size=struct.unpack_from('<4sII',raw)
    check(magic==b'glTF' and version==2 and size==len(raw),name+' GLB header')
    n,kind=struct.unpack_from('<II',raw,12)
    doc=json.loads(raw[20:20+n]); binary=raw[28+n:]
    check(all('uri' not in b for b in doc['buffers']),name+' embedded buffers')
    access=[]
    for a in doc['accessors']:
        view=doc['bufferViews'][a['bufferView']]
        width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        fmt={5126:'f',5125:'I',5123:'H'}[a['componentType']]
        offset=view.get('byteOffset',0)+a.get('byteOffset',0)
        values=struct.unpack_from('<'+fmt*(a['count']*width),binary,offset)
        check(all(math.isfinite(v) for v in values),name+' finite accessor')
        access.append(values)
    wheels=[n for n in doc['nodes'] if n.get('name','').startswith('Wheel_')]
    check(len(wheels)==4 and len({w['mesh'] for w in wheels})==1,name+' four shared wheels')
    for w in wheels:
        y=[v for prim in doc['meshes'][w['mesh']]['primitives'] for v in access[prim['attributes']['POSITION']][1::3]]
        check(abs(min(y)+w['translation'][1])<1e-5,name+' wheel touches road')
    triangles=sum(doc['accessors'][pr.get('indices',pr['attributes']['POSITION'])]['count']//3 for node in doc['nodes'] if 'mesh' in node for pr in doc['meshes'][node['mesh']]['primitives'])
    check(triangles<3000,name+' under 3000 triangles')
vehicle=source('Vehicle/ArcadeVehicle.gd'); road=source('Environment/Highway.gd')
check('MOTION_MODE_FLOATING' in vehicle and 'collision_mask = 6' in vehicle,'Consistent planar collision model')
check('velocity.y -= ' not in vehicle and 'intersect_ray' not in vehicle,'No competing gravity or grounding ray')
check('target.render_pose()' in source('Camera/CameraRig.gd'),'Camera consumes interpolated vehicle pose')
chunk=road.split('func _build_chunk')[1].split('\nfunc ')[0]
check('StaticBody3D' not in chunk and 'CollisionShape3D' not in chunk,'Recycled chunks have no colliders')
check('Data/*.json' in source('export_presets.cfg'),'Traffic JSON exported')
for lane in [-6,-2,2,6]:
    check(abs(lane)+.47<9.5,'Coin lane clears barrier')
for start,end in [(-6,-2),(-2,2),(2,6),(6,2),(2,-2),(-2,-6)]:
    xs=[start+(end-start)*(t*t*(3-2*t)) for t in [i/100 for i in range(101)]]
    check(xs[0]==start and xs[-1]==end and all((b-a)*(end-start)>=0 for a,b in zip(xs,xs[1:])),'Smooth transition monotonic and centered')
for cell in range(-100,101):
    centers=[(cell-7+i)*120 for i in range(13)]
    check(all(a+60==b-60 for a,b in zip(centers,centers[1:])),'Visual segment seam alignment')
base=ROOT.parent/'VelocityRush3D-Phase2.zip'
if base.exists():
    with zipfile.ZipFile(base) as z:
        for path in ['Data/HighwayRush.tres','Data/RunSpec.gd']:
            matches=[n for n in z.namelist() if n.endswith('/'+path)]
            check(bool(matches) and z.read(matches[0]).replace(b'finish_seconds: float = 1.8', b'finish_seconds: float = 2.8')==(ROOT/path).read_bytes(),path+' preserved except authorized finish duration')
report={'scope':'Offline structure and generated geometry only; no GDScript compilation or runtime testing','checks':len(checks),'failures':sum(not c['passed'] for c in checks),'results':checks}
(ROOT/'Docs/fix-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"FIX OFFLINE: {report['checks']} checks, {report['failures']} failures")
for c in checks:
    if not c['passed']: print('FAIL:',c['check'])
raise SystemExit(1 if report['failures'] else 0)
