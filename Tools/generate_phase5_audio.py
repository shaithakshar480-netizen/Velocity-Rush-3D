"""Original, deterministic synthesized UI chimes; no sampled third-party audio."""
from pathlib import Path
import math, struct, wave
ROOT=Path(__file__).resolve().parents[1]
CLIPS={'xp_gain':([660,880],.28),'level_up':([440,554.37,659.25,880],.65),'mission_complete':([523.25,659.25,783.99],.4),'reward_claim':([587.33,880],.3),'achievement':([392,587.33,783.99],.55),'daily_reward':([523.25,698.46,1046.5],.5)}
for name,(notes,duration) in CLIPS.items():
    rate=22050; values=[]; n=int(rate*duration)
    for i in range(n):
        t=i/rate; v=0
        for j,hz in enumerate(notes):
            local=t-j*duration/(len(notes)+2)
            if local>=0:
                env=min(local/.008,1)*math.exp(-local*11)*min((duration-t)/.03,1)
                v+=env*(math.sin(2*math.pi*hz*local)+.15*math.sin(4*math.pi*hz*local))
        values.append(int(6500*v/len(notes)))
    with wave.open(str(ROOT/'Assets/Audio'/f'{name}.wav'),'wb') as w:
        w.setparams((1,2,rate,0,'NONE','not compressed'))
        w.writeframes(struct.pack('<'+'h'*n,*values))
