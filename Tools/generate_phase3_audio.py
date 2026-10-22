"""Original deterministic synthesis. No sampled third-party audio."""
from pathlib import Path
import math, random, struct, wave
ROOT=Path(__file__).resolve().parents[1]/'Assets/Audio'
RATE=22050
rng=random.Random(303)
def write(name,seconds,fn,loop=False):
    count=int(seconds*RATE)
    samples=[]
    for i in range(count):
        t=i/RATE
        envelope=1.0 if loop else min(1,t/.015)*min(1,(seconds-t)/.08)
        samples.append(int(max(-.9,min(.9,fn(t)*envelope))*32767))
    with wave.open(str(ROOT/(name+'.wav')),'wb') as w:
        w.setparams((1,2,RATE,0,'NONE','not compressed'))
        w.writeframes(struct.pack('<'+'h'*len(samples),*samples))
phases=[rng.uniform(0,math.tau) for _ in range(48)]
def wind(t):
    return sum(math.sin(math.tau*(40+17*i)*t+phases[i]) for i in range(48))*.014
write('wind',2,wind,True)
write('turbo_spool',2,lambda t:.12*math.sin(math.tau*240*t)+.04*math.sin(math.tau*480*t)+wind(t)*.3,True)
write('turbo_ready',.5,lambda t:.18*math.sin(math.tau*(660 if t<.22 else 880)*t)*math.exp(-t*2))
write('turbo_ignition',.65,lambda t:.3*math.sin(math.tau*(95*t+110*t*t))*math.exp(-t*4)+wind(t)*1.1)
write('turbo_flare',.32,lambda t:wind(t)*2.1*math.exp(-t*7)+.14*math.sin(math.tau*70*t)*math.exp(-t*9))
write('turbo_end',.75,lambda t:.17*math.sin(math.tau*(480*t-160*t*t))*math.exp(-t*4)+wind(t)*.5)
print('Generated six original Phase 3 clips')
