"""Original periodic engine/tire synthesis, offline only. No third-party samples."""
from pathlib import Path
import json, wave
import numpy as np
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'Assets/Audio'; SR=22050; N=SR*3
ids=[c['id'] for c in json.loads((ROOT/'Data/VehicleCatalog.json').read_text())['cars']]
profiles={}; t=np.arange(N)/SR; rng=np.random.default_rng(47329)
def noise(low,high):
 f=np.fft.rfftfreq(N,1/SR); spectrum=np.fft.rfft(rng.standard_normal(N))
 envelope=np.exp(-.5*((f-(low+high)/2)/((high-low)/3))**2)
 envelope[f<low*.5]=0; a=np.fft.irfft(spectrum*envelope,n=N)
 return a/max(np.std(a),1e-6)
def save(name,a):
 a=np.tanh(a); a*=.72/max(np.max(np.abs(a)),.72)
 # All components are periodic FFT/integer-cycle signals; no fade/restart seams.
 with wave.open(str(OUT/(name+'.wav')),'wb') as w:
  w.setparams((1,2,SR,0,'NONE','not compressed'));w.writeframes((a*32767).astype('<i2').tobytes())
for i,id in enumerate(ids):
 base=[56,72,66,84,102,44,61,94,79,76,69,49][i]
 harmonic=[1.25,1.10,1.04,.93,1.35,.90,1.12,1.28,.86,1.03,.98,1.08][i]
 for layer in range(4):
  pulse=np.zeros(N)
  for h in range(1,15):
   weight=1/(h**(harmonic+(.4 if layer==0 else 0)))
   if h%2==0: weight*=.55+.04*i
   pulse+=weight*np.sin(2*np.pi*base*h*t+.17*h*i)
  pulse*=.85+.10*np.cos(2*np.pi*(5+i)*t)+.05*np.sin(2*np.pi*(13+i)*t)
  breath=noise(100+layer*90,1700+100*i)
  a=.19*pulse+(.018 if layer==0 else .042)*breath
  if layer==2:a+=.045*np.sin(2*np.pi*(base*7+3)*t)
  if layer==3:a=.12*pulse+.035*noise(60,900)
  save('engine_'+id+'_'+str(layer),a)
 friction=.10*noise(90+12*i,1900+65*i)+.025*noise(50,260)
 save('brake_'+id,friction)
 squeal=.085*noise(800,4200)
 for f,g in [(690+i*29,.12),(1180+i*37,.065),(1810+i*19,.035)]:
  squeal+=g*np.sin(2*np.pi*f*t+.4*np.sin(2*np.pi*(5+i)*t))
 save('tire_'+id,squeal)
 profiles[id]={'engine_id':id,'pitch':round(.94+i*.012,3),'load_gain':round(.91+(i%4)*.06,3),'brake_path':'res://Assets/Audio/brake_'+id+'.wav','tire_path':'res://Assets/Audio/tire_'+id+'.wav','brake_pitch':round(.90+i*.019,3)}
(ROOT/'Data/VehicleAudioProfiles.json').write_text(json.dumps(profiles,indent=2)+'\n')
print('Generated 12 distinct engine banks and 24 brake/tire loops')
