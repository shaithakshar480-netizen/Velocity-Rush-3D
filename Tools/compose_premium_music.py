"""Original deterministic stereo synth compositions. No samples or song references.
Offline only: numpy, scipy and ffmpeg; exported Ogg Vorbis is shipped to Godot.
"""
from pathlib import Path
import numpy as np, subprocess, tempfile, wave, json
from scipy.signal import butter,sosfilt
R=Path(__file__).resolve().parents[1];SR=32000
rng=np.random.default_rng(90626)
def compose(name,bpm,energy):
 beat=60/bpm;seconds=beat*64;n=round(seconds*SR);out=np.zeros((n,2),np.float64)
 def add(sound,start,pan=0):
  ids=(np.arange(len(sound))+round(start*SR))%n
  np.add.at(out[:,0],ids,sound*np.sqrt((1-pan)/2));np.add.at(out[:,1],ids,sound*np.sqrt((1+pan)/2))
 def note(midi,dur,kind='pad'):
  t=np.arange(round(dur*SR))/SR;f=440*2**((midi-69)/12)
  if kind=='pad':
   y=(np.sin(2*np.pi*f*t)+.3*np.sin(2*np.pi*f*1.003*t)+.12*np.sin(4*np.pi*f*t));e=np.minimum(t/.35,1)*np.minimum((dur-t)/.7,1)*.06
  else:
   y=np.sin(2*np.pi*f*t)+.22*np.sin(4*np.pi*f*t)+.08*np.sin(6*np.pi*f*t);e=(1-np.exp(-t*180))*np.exp(-t*(6 if kind=='arp' else 3))*np.minimum((dur-t)/.06,1)*(.11 if kind=='arp' else .22)
  return y*e
 # Original minor/add9 progression across sixteen bars.
 roots=[45,41,48,43]
 for bar in range(16):
  root=roots[(bar//2)%4];start=bar*4*beat
  for j,interval in enumerate([12,15,19,26]):add(note(root+interval,4*beat+.7),start,(j-1.5)*.35)
  for step in range(8):
   if energy or step%2==0:add(note(root if step%4 else root-12,.8*beat,'bass'),start+step*.5*beat)
  pattern=[0,7,12,10,3,14,7,19] if energy else [0,7,14,10,3,12,7,14]
  for k,pitch in enumerate(pattern):
   sound=note(root+24+pitch,beat*.8,'arp')*(.64 if energy else .38)
   add(sound,start+k*.5*beat,(-1 if k%2 else 1)*.4)
   add(sound*.23,start+(k*.5+.75)*beat,(-1 if k%2 else 1)*-.5)
  for b in range(4):
   t=np.arange(round(.32*SR))/SR;freq=48+105*np.exp(-t*32);kick=np.sin(2*np.pi*np.cumsum(freq)/SR)*np.exp(-t*17)*(.48 if energy else .30);add(kick,start+b*beat)
   if b%2:
    t=np.arange(round(.22*SR))/SR;noise=rng.normal(0,1,len(t));sn=sosfilt(butter(2,1500,fs=SR,btype='high',output='sos'),noise)*np.exp(-t*26)*.1;add(sn,start+b*beat,.08)
  for k in range(16 if energy else 8):
   t=np.arange(round(.08*SR))/SR;hat=sosfilt(butter(2,6500,fs=SR,btype='high',output='sos'),rng.normal(0,1,len(t)))*np.exp(-t*75)*(.045 if k%2 else .07);add(hat,start+k*(.25 if energy else .5)*beat,(-1 if k%2 else 1)*.5)
 # Circular summation carries tails across loop boundary. Soft mastering with headroom.
 out=np.tanh(out*1.2);out*=.77/max(np.max(np.abs(out)),.01)
 # Eight-millisecond smooth boundary correction, no audible hard waveform jump.
 blend=np.linspace(0,1,256);blend=blend*blend*(3-2*blend)
 out[-256:]+=blend[:,None]*(out[0]-out[-1])[None,:]
 path=R/'Assets/Audio'/f'{name}.ogg'
 with tempfile.TemporaryDirectory() as tmp:
  wav=Path(tmp)/'master.wav'
  with wave.open(str(wav),'wb') as f:f.setnchannels(2);f.setsampwidth(2);f.setframerate(SR);f.writeframes((out*32767).astype('<i2').tobytes())
  subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','4',str(path)],check=True)
 return dict(name=name,bpm=bpm,seconds=seconds,bytes=path.stat().st_size,peak=float(abs(out).max()),loop_endpoint_delta=float(abs(out[0]-out[-1]).max()))
if __name__=='__main__':
 rows=[compose('home_music',104,False),compose('race_music',128,True)]
 (R/'Docs/music-metrics.json').write_text(json.dumps(rows,indent=2)+'\n');print(rows)
