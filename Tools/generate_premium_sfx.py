"""Original synthesized sound-design pass. No third-party samples.
Retains clip names, sample rates and gameplay event contracts.
"""
from pathlib import Path
import numpy as np, wave,json
from scipy.signal import butter,sosfilt
R=Path(__file__).resolve().parents[1];D=R/'Assets/Audio';SR=22050;rng=np.random.default_rng(154630)
metrics=[]
def write(name,a,loop=False):
 a=np.asarray(a,float)
 if loop:
  ramp=np.linspace(0,1,128);ramp=ramp*ramp*(3-2*ramp)
  a[-128:]+=ramp*(a[0]-a[-1])
 else:
  a*=np.minimum(np.arange(len(a))/180,1)*np.minimum((len(a)-1-np.arange(len(a)))/550,1)
 a=np.clip(a,-.72,.72)
 with wave.open(str(D/(name+'.wav')),'wb') as f:
  f.setparams((1,2,SR,0,'NONE','not compressed'));f.writeframes((a*32767).astype('<i2').tobytes())
 metrics.append(dict(name=name,seconds=len(a)/SR,peak=float(abs(a).max()),rms=float(np.sqrt(np.mean(a*a))),loop=loop))
t=np.arange(SR*2)/SR
engine=sum(np.sin(2*np.pi*60*k*t+.05*k)*amp for k,amp in [(1,.23),(2,.10),(3,.055),(4,.03),(6,.015),(9,.009)])
engine*=.92+.06*np.sin(2*np.pi*12*t)+.02*np.sin(2*np.pi*31*t)
write('engine',engine,True)
noise=rng.normal(0,1,len(t));filtered=sosfilt(butter(3,[90,2400],fs=SR,btype='bandpass',output='sos'),noise);filtered/=max(abs(filtered))
write('wind',filtered*.24,True)
write('skid',filtered*.15+.105*np.sin(2*np.pi*910*t+1.4*np.sin(2*np.pi*17*t)),True)
write('turbo_spool',filtered*.08+.08*np.sin(2*np.pi*280*t)+.025*np.sin(2*np.pi*560*t),True)
t=np.arange(int(.5*SR))/SR
impact=sosfilt(butter(2,1800,fs=SR,output='sos'),rng.normal(0,1,len(t)))*.60*np.exp(-t*17)+.30*np.sin(2*np.pi*(74*t-35*t*t))*np.exp(-t*19)
write('collision',impact)
# Compact interaction/reward motifs: restrained partials and soft attacks.
notes={
 'ui':([820],.12),'coin':([1175,1568],.24),'near_miss':([392,587],.34),
 'turbo_ready':([659,988],.5),'turbo_ignition':([110,220,440],.65),
 'turbo_flare':([82,164],.32),'turbo_end':([440,294,147],.75),
 'car_select':([330,494],.28),'purchase':([262,330,392,524],.55),
 'upgrade':([392,494,659],.45),'xp_gain':([587,784],.28),
 'level_up':([330,440,554,880],.65),'mission_complete':([494,659,988],.4),
 'reward_claim':([440,659],.3),'achievement':([294,440,587,880],.55),
 'daily_reward':([392,523,784],.5)}
for name,(pitches,duration) in notes.items():
 t=np.arange(int(duration*SR))/SR;a=np.zeros(len(t))
 for j,f in enumerate(pitches):
  local=np.maximum(t-j*duration/(len(pitches)+2),0)
  e=(1-np.exp(-local*260))*np.exp(-local*(14 if name=='ui' else 9))
  a+=e*(np.sin(2*np.pi*f*local)+.18*np.sin(2*np.pi*f*2.003*local)+.045*np.sin(2*np.pi*f*3.98*local))*.28/len(pitches)
 if name in ['turbo_ignition','turbo_flare','turbo_end','near_miss']:
  airy=sosfilt(butter(2,1800,fs=SR,output='sos'),rng.normal(0,1,len(t)))
  a+=airy*np.sin(np.pi*t/duration)**2*.13
 write(name,a)
(R/'Docs/premium-sfx-metrics.json').write_text(json.dumps(metrics,indent=2)+'\n');print('Authored',len(metrics),'original replacement SFX/engine clips')
