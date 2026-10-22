"""Original six-engine synth bank and positional driving effects; no samples."""
from pathlib import Path
import numpy as np,wave,json
from scipy.signal import butter,sosfilt
R=Path(__file__).resolve().parents[1];D=R/'Assets/Audio';SR=22050;rng=np.random.default_rng(919)
def save(name,a,loop=False):
 if loop:
  t=np.linspace(0,1,128);a[-128:]+=t*t*(3-2*t)*(a[0]-a[-1])
 else:a*=np.minimum(np.arange(len(a))/120,1)*np.minimum((len(a)-1-np.arange(len(a)))/500,1)
 a=np.clip(a,-.78,.78)
 with wave.open(str(D/(name+'.wav')),'wb') as w:w.setparams((1,2,SR,0,'NONE','not compressed'));w.writeframes((a*32767).astype('<i2').tobytes())
ids=['vortex_s','falcon_s1','apex_rs','inferno_r','phantom_x','titan_v12'];t=np.arange(SR*2)/SR
for i,id in enumerate(ids):
 f=[60,78,70,90,110,48][i]
 for layer in range(4):
  a=sum(np.sin(2*np.pi*f*k*t+.07*k*i)*(.20/(k**(1.4 if layer==0 else .95))) for k in range(1,5+layer))
  a*=.90+.10*np.sin(2*np.pi*(11+i)*t)
  if layer==2:a+=.05*np.sin(2*np.pi*(f*5+8)*t)
  if layer==3:a*=.6+.15*np.sin(2*np.pi*7*t)
  save('engine_'+id+'_'+str(layer),a,True)
for name,secs in [('horn',.42),('shift',.17),('blowoff',.42),('passby',.65),('scrape',.4),('heavy_impact',.6),('explosion',1.6),('fire',2),('damage_warning',.55),('road_noise',2)]:
 t=np.arange(int(SR*secs))/SR;noise=sosfilt(butter(2,[80,2400],fs=SR,btype='bandpass',output='sos'),rng.normal(0,1,len(t)))
 if name=='horn':a=.20*np.sin(2*np.pi*392*t)+.18*np.sin(2*np.pi*494*t)+.04*np.sin(2*np.pi*784*t)
 elif name=='shift':a=(.35*np.sin(2*np.pi*95*t)+noise*.18)*np.exp(-t*23)
 elif name=='explosion':a=(.40*np.sin(2*np.pi*(52*t-7*t*t))+noise*.58)*np.exp(-t*2.8)
 elif name=='damage_warning':a=.15*np.sin(2*np.pi*660*t)*np.sin(np.pi*t/secs)**2
 elif name in ['fire','road_noise']:a=noise*(.12 if name=='fire' else .075)
 elif name=='heavy_impact':a=(.4*np.sin(2*np.pi*65*t)+noise*.5)*np.exp(-t*9)
 else:a=noise*np.sin(np.pi*t/secs)**2*(.4 if name=='passby' else .28)
 save(name,a,name in ['fire','road_noise'])
print('Authored 24 engine layers and 10 driving effects')
