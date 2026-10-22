"""Original showroom music bed and concise interaction cues; no external samples."""
from pathlib import Path
import math,struct,wave
r=Path(__file__).resolve().parents[1]/'Assets/Audio';rate=22050
for name,duration in [('garage',4),('car_select',.2),('purchase',.6),('upgrade',.5)]:
    samples=[]
    for i in range(int(rate*duration)):
        t=i/rate
        if name=='garage':v=.12*math.sin(math.tau*55*t)+.04*math.sin(math.tau*82.5*t)+.025*math.sin(math.tau*110*t)
        else:
            f={'car_select':550,'purchase':660,'upgrade':780}[name]
            envelope=min(1,t/.015)*min(1,(duration-t)/.08)*math.exp(-t*4)
            v=(.19*math.sin(math.tau*f*t)+.06*math.sin(math.tau*f*1.5*t))*envelope
        samples.append(int(v*32767))
    with wave.open(str(r/(name+'.wav')),'wb') as w:
        w.setparams((1,2,rate,0,'NONE','not compressed'));w.writeframes(struct.pack('<'+'h'*len(samples),*samples))
print('Four original garage audio clips generated')
