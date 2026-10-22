"""Source contracts, actual generated GLB data, and catalog-derived arithmetic.
Not a Godot interpreter: purchase/control runtime scenarios are in Phase4Smoke.
"""
from pathlib import Path
import json,re,struct,math,zipfile,wave
R=Path(__file__).resolve().parents[1];checks=[]
def check(name,ok):checks.append({'check':name,'passed':bool(ok)})
def read(p):return (R/p).read_text()
def body(s,fn):
 m=re.search(r'^(?:static )?func '+fn+r'\([^\n]*\).*?:\n(.*?)(?=^(?:static )?func |\Z)',s,re.M|re.S)
 return m.group(1) if m else ''
catalog=json.loads(read('Data/VehicleCatalog.json'));cars=catalog['cars'];costs=catalog['upgrade_costs'];m=catalog['upgrade_modifiers']
expected=[('vortex_s',0,210),('falcon_s1',15000,225),('apex_rs',40000,240),('inferno_r',90000,260),('phantom_x',180000,280),('titan_v12',350000,305)]
check('Six unique vehicle IDs',len(cars)==6 and len({c['id'] for c in cars})==6)
check('Ten configurable increasing costs',costs==[500,800,1200,1800,2600,3700,5000,6500,8000,10000])
check('Full category cost',sum(costs)==40100)
check('Six free paint choices',len(catalog['paints'])==6)
for c,(id,price,speed) in zip(cars,expected):
 check(id+' definition',c['id']==id and c['price']==price and c['top_speed_kmh']==speed)
 check(id+' physical proportions',3.8<=c['length']<=5.1 and 1.8<=c['width']<=2.1 and .3<=c['wheel_radius']<=.4)
 check(id+' exhaust behind rear',all(abs(p[2]-c['length']/2)<.15 and .25<p[1]<.55 for p in c['exhaust_points']))
 for level in range(11):
  top=c['top_speed_kmh']*(1+level*m['engine_speed']+level*m['transmission_speed'])
  accel=c['acceleration']*(1+level*m['engine_acceleration']+level*m['transmission_acceleration'])
  boost=c['turbo_speed']+top-c['top_speed_kmh']
  check(id+' level '+str(level)+' performance envelope',top>=c['top_speed_kmh'] and accel>=c['acceleration'] and top<boost<=425 and accel<28)
# Validate delivered mesh bytes rather than generator-reported geometry alone.
for p in sorted((R/'Assets').rglob('*.glb')):
 raw=p.read_bytes();magic,version,size=struct.unpack_from('<4sII',raw);n,kind=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+n]);binary=raw[28+n:]
 check(p.stem+' GLB integrity',magic==b'glTF' and version==2 and size==len(raw) and len(binary)>=doc['buffers'][0]['byteLength'])
 check(p.stem+' embedded resources',all('uri' not in b for b in doc['buffers']))
 values=[]
 for a in doc['accessors']:
  v=doc['bufferViews'][a['bufferView']];width={'VEC3':3,'VEC4':4}[a['type']];vals=struct.unpack_from('<'+'f'*(a['count']*width),binary,v.get('byteOffset',0)+a.get('byteOffset',0));values.append(vals)
 check(p.stem+' finite vertices/normals',all(math.isfinite(v) for a in values for v in a))
 if p.parent.name=='Player' or 'Traffic' in p.parts:
  roles={a['name'] for a in doc['materials']}
  expected_roles={'Paint','Glass','Trim','Rubber','Alloy','Headlight','Taillight'}
  if p.parent.name=='Player':expected_roles|={'Carbon','Housing','BrakeDisc','BrakeCaliper','Lens','LightInternals'}
  check(p.stem+' declared material roles',roles==expected_roles)
  check(p.stem+' no vertex-color dependency',all('COLOR_0' not in pr['attributes'] for mesh in doc['meshes'] for pr in mesh['primitives']))
  check(p.stem+' dark tires and glass',doc['materials'][3]['pbrMetallicRoughness']['baseColorFactor'][0]<.1 and doc['materials'][1]['pbrMetallicRoughness']['baseColorFactor'][0]<.15)
  wheels=[n for n in doc['nodes'] if n.get('name','').startswith('Wheel_')]
  check(p.stem+' four shared wheels',len(wheels)==4 and len({w['mesh'] for w in wheels})==1)
  for w in wheels:
   ys=[v for pr in doc['meshes'][w['mesh']]['primitives'] for v in values[pr['attributes']['POSITION']][1::3]]
   check(p.stem+' wheel contact',abs(min(ys)+w['translation'][1])<1e-5)
  tris=sum(doc['accessors'][pr['attributes']['POSITION']]['count']//3 for n in doc['nodes'] if 'mesh' in n for pr in doc['meshes'][n['mesh']]['primitives'])
  budget=(2000 if p.parent.name=='Low' else 3300) if 'Traffic' in p.parts else (10000 if p.stem.endswith('_low') else 22000 if p.stem.endswith('_medium') else 45000)
  check(p.stem+' tier-specific triangle budget',tris<=budget)
 else:
  check(p.stem+' depth layers',{'Terrain','RidgeNear','RidgeFar'}.issubset({n['name'] for n in doc['nodes']}))
save=read('Save/SaveService.gd');game=read('Core/Game.gd');input_code=read('Input/DriveInput.gd');road=read('Environment/Highway.gd')
for token in ['"schema_version": 5','in [1, 2, 3, 4, 5]','"collection": collection','_load_collection(envelope.get("collection",{}))']:
 check('Save contract: '+token,token in save)
for token in ['not owns(id)','current != expected_level','current>=10','can_afford(cost)','_commit_collection(next,cost)']:
 check('Upgrade gate: '+token,token in body(save,'buy_upgrade'))
for token in ['owns(id)','can_afford(cost)','_commit_collection(next,cost)']:
 check('Purchase gate: '+token,token in body(save,'buy_vehicle'))
for token in ['collection = before','wallet["coins"] = previous_coins','transaction_busy = true','var success := commit()']:
 check('Atomic rollback: '+token,token in body(save,'_commit_collection'))
check('Rejected pending not recoverable','remove_absolute(TEMP)' in body(save,'_failed_commit'))
check('UI debounces rapid purchases','now-last_purchase_ms<500' in read('Garage/GarageUI.gd'))
check('Base resource copied','duplicate(true) as RushTurboSpec' in read('Data/VehicleCatalog.gd'))
for key in m:check('Modifier is used '+key,key in read('Data/VehicleCatalog.gd'))
for fn in ['start_drive','go_home']:check('Selected car on '+fn,'_apply_selected()' in body(game,fn))
check('Dynamic collision extents','car.half_width()' in read('Traffic/TrafficSystem.gd') and 'car.half_length()' in read('Traffic/TrafficSystem.gd'))
for token in ['wheel_pointer','_wheel_position(event.position)','wheel_return_degrees','tilt_dead_zone','tilt_neutral','Input.get_gravity()','effective_mode()']:
 check('Control wiring '+token,token in input_code)
check('Keyboard independent', 'held("right")' in body(input_code,'sample'))
check('Android sensor flags','sensors/enable_gravity=true' in read('project.godot'))
check('Control setting validation','"steering_mode": return clampi(int(value),0,2)' in save and '"steering_assist"' in save)
check('Turbo independent touch','pointers[event.index] == "turbo"' in input_code)
check('No gravity reintroduced','MOTION_MODE_FLOATING' in read('Vehicle/ArcadeVehicle.gd') and 'velocity.y -= ' not in read('Vehicle/ArcadeVehicle.gd'))
check('No recycled colliders',all(t not in body(road,'_build_chunk') for t in ['StaticBody3D','CollisionShape3D',',true)']))
for file,fn in [('Environment/Highway.gd','update_chunks'),('Environment/SceneryTile.gd','configure'),('Environment/SceneryTile.gd','update_lod'),('Traffic/TrafficVehicle.gd','activate'),('Input/DriveInput.gd','_physics_process')]:
 code=body(read(file),fn);check('Bounded active path '+file+':'+fn,bool(code) and not any(t in code for t in ['.new(','.instantiate(','.queue_free(','load(']))
check('Four scenery variants preloaded','for scene: PackedScene in scenes:' in read('Environment/SceneryTile.gd'))
check('Building LOD retained','"StructuresFar"' in read('Environment/SceneryTile.gd'))
check('Traffic palette explicit','TRAFFIC_PAINTS[paint_index]' in read('Traffic/TrafficVehicle.gd'))
check('JSON export retained','include_filter="Data/*.json"' in read('export_presets.cfg'))
check('Contact shadows retained','RushContactShadow.create' in read('Vehicle/VortexVisual.gd') and 'RushContactShadow.create' in read('Traffic/TrafficVehicle.gd'))
base=R.parent/'VelocityRush3D-Phase3.zip'
if base.exists():
 with zipfile.ZipFile(base) as z:
  for path,funcs in [('Save/SaveService.gd',['reserve_run','is_settled']),('Gameplay/RunManager.gd',['calculate_rewards','_finish','award_near_miss','collect_coin']),('Environment/Highway.gd',['_build_continuous_collision','_static_box'])]:
   before=z.read('VelocityRush3D/'+path).decode();after=read(path)
   for fn in funcs:
    current=body(after,fn)
    # Phase 5 adds observation hooks and one informational summary field only.
    for added in ['\tcheckpoint()\n','\tpickup_count += 1\n', '"turbo_activations": turbo_activations, ']:current=current.replace(added,'')
    check('Preserved behavior source '+path+':'+fn,body(before,fn).strip()==current.strip())
for name in ['garage','car_select','purchase','upgrade']:
 with wave.open(str(R/'Assets/Audio'/f'{name}.wav')) as w:
  samples=struct.unpack('<'+'h'*w.getnframes(),w.readframes(w.getnframes()))
  check(name+' safe PCM',w.getnchannels()==1 and w.getframerate()==22050 and max(abs(v) for v in samples)<30000)
  check(name+' endpoints',abs(samples[0]-samples[-1])<500)
report={'scope':'Offline contracts, mesh bytes, PCM data and catalog arithmetic only; runtime purchase/control scenarios NOT executed','checks':len(checks),'failed':sum(not c['passed'] for c in checks),'results':checks}
(R/'Docs/phase4-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"PHASE4 OFFLINE: {report['checks']} checks, {report['failed']} failures")
for c in checks:
 if not c['passed']:print('FAIL:',c['check'])
raise SystemExit(bool(report['failed']))
