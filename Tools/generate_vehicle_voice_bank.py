"""Original synthetic vehicle voices; no recordings or manufacturer sound claims.
Offline asset authoring only. Runtime uses existing four-layer audio players.
Run from project root with Python + numpy to regenerate the eight banks.
"""
from pathlib import Path
import wave
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
RATE = 32000
# id: firing fundamental, pulse weights, exhaust formants, rasp, induction, horn chord
VOICES = {
 'vortex_s': (64, [1,.76,1,.86], [310,920], .27,.03,[370,465]),
 'falcon_s1': (84, [1,.92,.84,1,.89,.95], [440,1280], .18,.04,[405,510]),
 'apex_rs': (54, [1,.64,.88,.72,1,.68,.92,.78], [210,660], .11,.02,[310,390]),
 'inferno_r': (90, [1,.83,.96,.89,1,.86], [520,1560], .20,.19,[435,550]),
 'phantom_x': (62, [1,.52,.93,.65,.98,.59,.86,.70], [270,1080], .34,.06,[335,420]),
 'titan_v12': (112, [1,.96,.91,.98,.95,.92,1,.94,.97,.93,.99,.95], [650,1850], .12,.14,[355,450,565]),
 'tempest_gt': (132, [1,.92,.98,.94,.96,.90,1,.95,.97,.93,.99,.96], [820,2450], .24,.05,[470,595]),
 'aether_one': (144, [1,.96,.99,.93,.98,.95,1,.97,.94,.99,.96,.98], [960,2900], .17,.09,[445,560,670]),
}
def write(path, signal, loop=False):
    signal = signal - signal.mean()
    signal *= .82/max(float(np.max(np.abs(signal))),1e-9)
    if not loop:
        fade = min(640,len(signal)//4)
        signal[:fade] *= np.linspace(0,1,fade)
        signal[-fade:] *= np.linspace(1,0,fade)
    pcm = np.round(signal*32767).astype('<i2')
    with wave.open(str(path),'wb') as out:
        out.setnchannels(1); out.setsampwidth(2); out.setframerate(RATE); out.writeframes(pcm.tobytes())
def engine(base, weights, formants, rasp, induction, layer, seed):
    # Integer-cycle oscillators + periodic FFT noise make seamless loop boundaries.
    duration = 3.0; count = int(RATE*duration); t = np.arange(count)/RATE
    f = round(base*[.72,1.0,1.60,.88][layer]*duration)/duration
    rotor = f/len(weights)
    rotor = round(rotor*duration)/duration
    phase = rotor*t
    pulse = np.zeros(count)
    for i,w in enumerate(weights):
        angle = 2*np.pi*(phase-i/len(weights))
        pulse += w*np.exp((np.cos(angle)-1)*[34,55,75,42][layer])
    pulse -= pulse.mean()
    freq = np.fft.rfftfreq(count,1/RATE)
    curve = .32/(1+(freq/3200)**4)
    for center in formants:
        curve += np.exp(-.5*((freq-center)/max(center*.33,90))**2)
    pulse = np.fft.irfft(np.fft.rfft(pulse)*curve,n=count)
    rng = np.random.default_rng(seed)
    noise = rng.normal(size=count)
    band = (freq/500)**2/(1+(freq/500)**2)/(1+(freq/3900)**6)
    noise = np.fft.irfft(np.fft.rfft(noise)*band,n=count)
    noise /= max(np.std(noise),1e-9)
    signal = pulse/(np.std(pulse)+1e-9)
    signal += rasp*[.16,.55,.80,.32][layer]*noise*(.6+.4*np.cos(2*np.pi*f*t))
    signal += .25*np.sin(2*np.pi*rotor*2*t)
    whine = round((formants[1]*1.35)*duration)/duration
    signal += induction*[.1,.7,1,.32][layer]*np.sin(2*np.pi*whine*t)
    signal *= 1+.025*np.sin(2*np.pi*3*t)+.012*np.sin(2*np.pi*7*t)
    return np.tanh(signal*[.52,.74,.83,.46][layer])
def main():
    dest=ROOT/'Assets/Audio'; dest.mkdir(parents=True,exist_ok=True)
    for index,(id,v) in enumerate(VOICES.items()):
        for layer in range(4):
            write(dest/f'engine_{id}_{layer}.wav',engine(*v[:5],layer,1100+index*17+layer),True)
        t=np.arange(int(RATE*.68))/RATE
        horn=np.zeros_like(t)
        for voice,f in enumerate(v[5]):
            phase=2*np.pi*f*t + .045*np.sin(2*np.pi*(5+index*.2)*t)
            for h in range(1,9):
                horn += np.sin(h*phase+voice*.3)/(h**(1.15+index*.035)*len(v[5]))
        horn *= np.minimum(t/.045,1)*np.minimum((.68-t)/.09,1)
        write(dest/f'horn_{id}.wav',np.tanh(horn*.9))
if __name__=='__main__': main()
