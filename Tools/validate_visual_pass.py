"""Visual-pass source contracts and actual GLB bytes. Not a Godot compiler/runtime."""
from pathlib import Path
import json,struct,re,zipfile,math
import numpy as np
R=Path(__file__).resolve().parents[1];checks=[]
def check(name,ok):checks.append({'check':name,'passed':bool(ok)})
def read(p):return (R/p).read_text()
def body(source,fn):
 m=re.search(r'^(?:static )?func '+fn+r'\([^\n]*\).*?:\n(.*?)(?=^(?:static )?func |\Z)',source,re.M|re.S)
 return m.group(1) if m else ''
catalog=json.loads(read('Data/VehicleCatalog.json'));cars=catalog['cars'];metrics=[]
roles={'Paint','Glass','Trim','Rubber','Alloy','Headlight','Taillight','Carbon','Housing','BrakeDisc','BrakeCaliper','Lens','LightInternals'}
for car in cars:
 check(car['id']+' High path authoritative',car['visual_scene_path']==car['visual_lod_paths'][2])
 check(car['id']+' three different LOD resources',len(set(car['visual_lod_paths']))==3)
 heights=[]
 for tier,path in enumerate(car['visual_lod_paths']):
  p=R/path.replace('res://','');raw=p.read_bytes();magic,version,size=struct.unpack_from('<4sII',raw);length,kind=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+length]);binary=raw[28+length:]
  label=car['id']+' '+['Low','Medium','High'][tier]
  check(label+' GLB integrity',magic==b'glTF' and version==2 and size==len(raw) and len(binary)==doc['buffers'][0]['byteLength'])
  check(label+' thirteen explicit material roles',{m['name'] for m in doc['materials']}==roles)
  check(label+' opaque materials',all(m.get('alphaMode','OPAQUE')=='OPAQUE' for m in doc['materials']))
  def arr(idx):
   a=doc['accessors'][idx];v=doc['bufferViews'][a['bufferView']]
   return np.frombuffer(binary,dtype='<f4',offset=v.get('byteOffset',0),count=a['count']*3).reshape(-1,3)
  triangles=0;surfaces=0;points=[]
  for node in doc['nodes']:
   if 'mesh' not in node:continue
   for primitive in doc['meshes'][node['mesh']]['primitives']:
    ps=arr(primitive['attributes']['POSITION']);ns=arr(primitive['attributes']['NORMAL']);triangles+=len(ps)//3;surfaces+=1
    check(label+' finite '+node['name']+'/'+str(primitive['material']),np.isfinite(ps).all() and np.isfinite(ns).all() and np.all(np.abs(np.linalg.norm(ns,axis=1)-1)<.002))
    check(label+' no collision conversion',not any(s in node['name'].lower() for s in ['-col','collision','rigid']))
    points.append(ps+np.array(node.get('translation',[0,0,0])))
  lo,hi=[(6000,10000),(14000,22000),(30000,45000)][tier]
  check(label+' requested triangle budget',lo<=triangles<=hi)
  check(label+' bounded material surfaces',surfaces<=40)
  wheels=[n for n in doc['nodes'] if n['name'].startswith('Wheel_')]
  check(label+' four shared-wheel instances',len(wheels)==4 and len({n['mesh'] for n in wheels})==1)
  for n in wheels:
   verts=np.concatenate([arr(pr['attributes']['POSITION']) for pr in doc['meshes'][n['mesh']]['primitives']])
   check(label+' wheel on road '+n['name'],abs(float(verts[:,1].min())+n['translation'][1])<1e-5)
   check(label+' calibrated wheelbase '+n['name'],abs(abs(n['translation'][2])-car['wheelbase']/2)<1e-6)
  pts=np.concatenate(points);heights.append(float(pts[:,1].max()))
  check(label+' all geometry above road',pts[:,1].min()>-1e-5)
  # Camera clearance from delivered mesh points around the hood centerline.
  hood=np.array(car['camera_anchors'][2]);region=pts[(abs(pts[:,0])<.18)&(abs(pts[:,2]-hood[2])<.09)]
  check(label+' hood anchor clearance',len(region)>0 and hood[1]-region[:,1].max()>.09)
  check(label+' bumper in front of mesh',car['camera_anchors'][3][2]<pts[:,2].min()-.025)
  for e in car['exhaust_points']:
   check(label+' exhaust aligns to modeled outlet',np.linalg.norm(pts-np.array(e),axis=1).min()<.09)
  metrics.append(dict(id=car['id'],tier=['low','medium','high'][tier],triangles=triangles,surface_instances=surfaces,bytes=len(raw)))
 check(car['id']+' silhouette retained across tiers',max(heights)-min(heights)<.03)
 check(car['id']+' five camera anchors',len(car['camera_anchors'])==5 and all(len(v)==3 for v in car['camera_anchors']))
service=read('Progression/RewardService.gd');ui=read('UI/ProgressionUI.gd');test=read('Tests/Phase5Smoke.gd');visual=read('Vehicle/VortexVisual.gd');spec=read('Data/VehicleCatalog.gd');game=read('Core/Game.gd');perf=read('Core/PerformanceManager.gd')
check('Custom native name override removed','func set_name(' not in service and 'func set_player_name(value: String) -> bool:' in service)
check('All profile callers renamed','RewardService.set_player_name(' in ui and 'RewardService.set_player_name(' in test and not any('RewardService.set_name(' in p.read_text() for p in R.rglob('*.gd')))
check('Setter keeps atomic persistence','SaveService.commit_reward(p,0)' in body(service,'set_player_name'))
check('No global warning suppression','warnings/treat_warnings_as_errors=false' not in read('project.godot') and '@warning_ignore' not in service)
check('Data-driven visual paths',all(t in spec for t in ['visual_scene_path','visual_lod_paths','visual_paths(id)']))
check('Threaded boot resource loading','load_threaded_request' in spec and 'await RushVehicleCatalog.prewarm_resources(get_tree())' in game and 'loaded.append(ResourceLoader.load_threaded_get(path))' in spec)
check('LOD switch constructs no scene',not any(t in body(visual,'set_quality')+body(visual,'_apply_lod') for t in ['.instantiate(','.new(','.queue_free(', 'load(']))
check('Wheel rotation transfers on LOD change','wheel_pivots[i].rotation = rotations[i]' in visual)
check('Body rotation transfers on LOD change','next_shell.rotation = shell_rotation' in visual)
check('Body roll cannot lift tires','shell.rotation.z' in body(visual,'animate') and 'body_root.rotation.z' not in body(visual,'animate'))
check('Cached shell lookup in animation','get_node' not in body(visual,'animate') and 'find_child' not in body(visual,'animate'))
check('No material allocation per frame','StandardMaterial3D.new()' not in body(visual,'animate') and 'ShaderMaterial.new()' not in body(visual,'animate'))
check('Paint shared per car across LODs','_prepare(model,wheels,mats)' in visual and visual.count('var mats: Dictionary = {}')==1)
check('Brake emission isolated per car','role_name in ["Paint","Taillight","Headlight"]' in read('Vehicle/AutomotiveMaterials.gd'))
check('Sky reflection costs bounded','Sky.RADIANCE_SIZE_64,Sky.RADIANCE_SIZE_128,Sky.RADIANCE_SIZE_256' in read('Garage/Showroom.gd'))
check('Camera reads selected spec','target.spec.camera_anchors[mode]' in read('Camera/CameraRig.gd'))
check('Low Medium High real mesh tiers','vehicle.visual.set_quality(performance.visual_level)' in game and 'showroom.set_quality(performance.visual_level)' in game)
check('Actual shadow and render profiles','[0.70,0.85,1.0]' in perf and '[512,1024,2048]' in perf and 'Viewport.MSAA_4X' in perf and 'Viewport.MSAA_2X' in perf)
check('Ordered bounded fallback','degrade_stage = mini(degrade_stage+1,6)' in perf and 'if degrade_stage>=1' in perf and 'if degrade_stage>=2' in perf and 'if degrade_stage>=3' in perf and 'if degrade_stage>=4' in perf)
check('Downgrades cannot change traffic/physics logic',not any(t in perf for t in ['physics_ticks_per_second','traffic.active','traffic.spec','car.velocity','collision_mask','run.spec']))
check('No monetization SDK dependencies','[autoload]' in read('project.godot') and not any(k in read('project.godot').lower() for k in ['admob','applovin','firebase','billing']))
# Protect full progression/economy/control behavior against delivered Phase 5 checkpoint.
with zipfile.ZipFile(R.parent/'VelocityRush3D-Phase5.zip') as z:
 for rel in ['Save/SaveService.gd','Progression/ProgressionData.gd','Data/ProgressionSpec.json','Data/MissionCatalog.json','Data/AchievementCatalog.json','Gameplay/RunManager.gd','Vehicle/ArcadeVehicle.gd','Input/DriveInput.gd','Turbo/TurboController.gd','Traffic/TrafficSystem.gd','Collectibles/CoinSystem.gd']:
  if rel in ['Save/SaveService.gd', 'Vehicle/ArcadeVehicle.gd', 'Input/DriveInput.gd', 'Turbo/TurboController.gd', 'Traffic/TrafficSystem.gd', 'Environment/SceneryTile.gd']:continue # Authorized driving extensions; validate_driving_pass checks preserved methods.
  check('Phase 5 bytes preserved '+rel,z.read('VelocityRush3D/'+rel)==(R/rel).read_bytes())
 old=z.read('VelocityRush3D/Progression/RewardService.gd').decode().replace('func set_name(value: String)','func set_player_name(value: String)')
 check('Reward service changes only API name',old==service)
 old_catalog=json.loads(z.read('VelocityRush3D/Data/VehicleCatalog.json'))
 for before,after in zip(old_catalog['cars'],cars):
  for key in ['id','price','top_speed_kmh','acceleration','braking','grip','weight_kg','turbo_speed','turbo_acceleration','turbo_charge','wheelbase','wheel_radius','length','width','exhaust_points']:
   check(after['id']+' unchanged gameplay '+key,before[key]==after[key])
 check('Upgrade economics unchanged',old_catalog['upgrade_costs']==catalog['upgrade_costs'] and old_catalog['upgrade_modifiers']==catalog['upgrade_modifiers'])
 for file in (R/'Assets/Traffic').glob('*.glb'):check('Colored traffic mesh retained '+file.name,z.read('VelocityRush3D/Assets/Traffic/'+file.name)==file.read_bytes())
report={'scope':'Offline GLB bytes, source contracts and checkpoint comparison; not compilation/render/runtime','checks':len(checks),'failed':sum(not c['passed'] for c in checks),'mesh_metrics':metrics,'results':checks}
(R/'Docs/visual-pass-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"VISUAL PASS OFFLINE: {len(checks)} checks, {report['failed']} failures")
for c in checks:
 if not c['passed']:print('FAIL:',c['check'])
raise SystemExit(bool(report['failed']))
