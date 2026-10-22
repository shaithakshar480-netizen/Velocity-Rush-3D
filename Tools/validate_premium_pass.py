"""Offline evidence for presentation pass. This is NOT GDScript compilation or playtesting."""
from pathlib import Path
import json,re,zipfile,struct,subprocess
import numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[1];checks=[]
def check(name,ok):checks.append(dict(check=name,passed=bool(ok)))
def read(p):return (R/p).read_text()
def body(s,name):
 m=re.search(r'^func '+re.escape(name)+r'\([^\n]*\).*?:\n(.*?)(?=^func |\Z)',s,re.M|re.S)
 return m.group(1) if m else ''
import hashlib
def digest(b):return hashlib.sha256(b.encode() if isinstance(b,str) else b).hexdigest()
baseline=json.loads(read('Docs/premium-baseline.json'))
for p in ['Save/SaveService.gd','Gameplay/RunManager.gd','Vehicle/ArcadeVehicle.gd','Input/DriveInput.gd','Turbo/TurboController.gd','Traffic/TrafficSystem.gd','Collectibles/CoinSystem.gd','Progression/ProgressionData.gd','Progression/RewardService.gd','Data/ProgressionSpec.json','Data/MissionCatalog.json','Data/AchievementCatalog.json','Data/HighwayRush.tres','Data/TrafficProfiles.json','Environment/RoadFrame.gd','project.godot','export_presets.cfg']:
 if p in ['Save/SaveService.gd', 'Vehicle/ArcadeVehicle.gd', 'Input/DriveInput.gd', 'Turbo/TurboController.gd', 'Traffic/TrafficSystem.gd', 'Environment/SceneryTile.gd']:continue # Driving pass intentionally extends these systems.
 check('Preserved baseline bytes: '+p,baseline['files'][p]==digest((R/p).read_bytes()))
for name in ['_build_continuous_collision','_static_box','update_chunks','_physics_process']:
 check('Stable road method: '+name,baseline['road_methods'][name]==digest(body(read('Environment/Highway.gd'),name)))
new=read('Garage/GarageUI.gd')
for name in ['_allow_purchase','_action','_upgrade','_paint']:
 check('Garage transaction behavior: '+name,baseline['garage_methods'][name]==digest(re.sub(r'^.*ui.pulse_control.*\n','',body(new,name),flags=re.M)))
for p in (R/'Assets/Traffic').glob('*.glb'):
 check('Original traffic retained '+p.name,baseline['files']['Assets/Traffic/'+p.name]==digest(p.read_bytes()))
source='\n'.join(p.read_text() for p in R.rglob('*.gd'))
check('Invalid reflection constant removed','REFLECTED_SOURCE_SKY' not in source)
for rel in ['Garage/Showroom.gd','Environment/Highway.gd']:
 check('Documented reflection constant '+rel,'Environment.REFLECTION_SOURCE_SKY' in read(rel))
check('No per-frame pedal resources','.new(' not in body(read('UI/PedalControl.gd'),'_draw')+body(read('UI/PedalControl.gd'),'_process'))
check('Separate pedal artwork',all(x in read('UI/PedalControl.gd') for x in ['53.0 if gas else 88.0','96.0 if gas else 59.0','f17675','DriveInput.held(action)']))
check('Pedals retain input-region routing','controls[action] = pedal' in read('UI/AutomotiveUI.gd'))
check('No generic pedal labels','"▲\\nTHROTTLE"' not in source and '"BRAKE\\nREVERSE"' not in read('UI/AutomotiveUI.gd'))
check('Camera kick uses physics acceleration','target.acceleration_now' in read('Camera/CameraRig.gd'))
check('Cached pedal styles','shadow_style = _plate' in body(read('UI/PedalControl.gd'),'_ready'))
check('Mission progress cards','row.progress.value' in read('UI/ProgressionUI.gd'))
check('Garage current and next effects','level*percent,mini(level+1,10)*percent' in read('Garage/GarageUI.gd'))
check('Race closes showroom before driving','_close_showroom()' in body(read('Core/Game.gd'),'start_drive'))
check('Home cinematic showroom','showroom.camera.make_current()' in body(read('Core/Game.gd'),'go_home'))
check('Showroom reflection isolated','lighting.sky = sky_variants[level]' in read('Environment/Highway.gd'))
check('Original music crossfade','delta/1.2' in read('Audio/GameAudio.gd') and 'cos(music_blend*PI*.5)' in read('Audio/GameAudio.gd'))
check('No music restart during navigation','.play()' not in body(read('Audio/GameAudio.gd'),'set_driving')+body(read('Audio/GameAudio.gd'),'set_garage'))
check('Three simultaneous fingers covered','Three simultaneous touch owners' in read('Tests/PremiumSmoke.gd'))
check('Dynamic visual fallback six stages','mini(degrade_stage+1,6)' in read('Core/PerformanceManager.gd'))
for rel in ['Environment/asphalt.gdshader','Garage/Showroom.gd','Environment/Highway.gd']:
 check('No heavy rendering '+rel,not any(x in read(rel) for x in ['ssr_enabled = true','volumetric_fog_enabled = true','sdfgi_enabled = true']))
# Decode shipped Oggs, not only the pre-encoding masters.
audio=[]
for info in json.loads(read('Docs/music-metrics.json')):
 path=R/'Assets/Audio'/(info['name']+'.ogg')
 result=subprocess.run(['ffmpeg','-v','error','-i',str(path),'-f','f32le','-ac','2','-ar','32000','pipe:1'],capture_output=True,check=True)
 samples=np.frombuffer(result.stdout,dtype='<f4').reshape(-1,2)
 peak=float(abs(samples).max());rms=float(np.sqrt(np.mean(samples**2)));gap=float(abs(samples[0]-samples[-1]).max())
 check(info['name']+' decode duration',abs(len(samples)/32000-info['seconds'])<.02)
 check(info['name']+' mastered headroom',np.isfinite(samples).all() and peak<.95 and .01<rms<.3)
 check(info['name']+' loop boundary',gap<.03)
 check(info['name']+' compressed mobile asset',path.stat().st_size<600000)
 audio.append(dict(name=info['name'],peak=peak,rms=rms,decoded_boundary_delta=gap))
import wave
for item in json.loads(read('Docs/premium-sfx-metrics.json')):
 with wave.open(str(R/'Assets/Audio'/(item['name']+'.wav'))) as w:
  pcm=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2')
  check(item['name']+' PCM format and headroom',w.getframerate()==22050 and w.getnchannels()==1 and 0<np.max(np.abs(pcm.astype(np.int32)))<25000)
  check(item['name']+' clean endpoint',abs(int(pcm[0])-int(pcm[-1]))<3 if item['loop'] else pcm[0]==0 and pcm[-1]==0)
for name,size in [('asphalt_surface.png',(1024,1024))]:
 with Image.open(R/'Assets/Environment'/name) as im:im.load();check(name+' decodes and fits budget',im.size==size)
for name,wh in [('golden_hour.hdr',(2048,1024)),('studio_reflections.hdr',(1024,512))]:
 raw=(R/'Assets/Environment'/name).read_bytes();header=f'-Y {wh[1]} +X {wh[0]}\n'.encode();check(name+' HDR dimensions',header in raw)
 pos=raw.index(header)+len(header);correct=True
 for y in range(wh[1]):
  correct &= raw[pos:pos+4]==bytes([2,2,wh[0]>>8,wh[0]&255]);pos+=4
  for c in range(4):
   n=0
   while n<wh[0]:
    count=raw[pos];pos+=1
    if count>128:n+=count-128;pos+=1
    else:n+=count;pos+=count
   correct &= n==wh[0]
 check(name+' complete HDR scanlines',correct and pos==len(raw))
for p in (R/'Assets/Traffic/Low').glob('*.glb'):
 raw=p.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);tris=sum(doc['accessors'][pr['attributes']['POSITION']]['count']//3 for node in doc['nodes'] if 'mesh' in node for pr in doc['meshes'][node['mesh']]['primitives'])
 check('Genuine Low traffic budget '+p.name,1000<tris<2000)
check('Low traffic prewarmed','car.set_visual_quality(0)' in read('Core/Game.gd') and 'low_scenes[kind]' in read('Traffic/TrafficVehicle.gd'))
for p in (R/'Docs').glob('*preview.png'):
 try:
  with Image.open(p) as im:im.load()
  check('Preview integrity '+p.name,True)
 except Exception:check('Preview integrity '+p.name,False)
report=dict(scope='Offline only; no Godot engine or Android execution',checks=len(checks),failures=sum(not c['passed'] for c in checks),decoded_music=audio,results=checks)
(R/'Docs/premium-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('PREMIUM OFFLINE:',len(checks),'checks,',report['failures'],'failures')
for c in checks:
 if not c['passed']:print('FAIL:',c['check'])
raise SystemExit(bool(report['failures']))
