"""Generate original CC0 placeholder audio using only Python's standard library.
Deterministic seed, bounded amplitude, mono 22.05 kHz signed 16-bit PCM.
Run from any directory. WAV files are already included in the project.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / 'Assets' / 'Audio'


def write(name, duration, fn):
    OUT.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for i in range(round(duration * RATE)):
        value = max(-0.95, min(0.95, fn(i / RATE)))
        frames.extend(struct.pack('<h', round(value * 32767)))
    with wave.open(str(OUT / name), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)


def main():
    rng = random.Random(20260905)
    tau = math.tau
    write('engine.wav', 2, lambda t: 0.34 * math.sin(tau*60*t)
          + 0.16*math.sin(tau*120*t) + 0.08*math.sin(tau*180*t)
          + 0.035*math.sin(tau*360*t))
    write('skid.wav', 2, lambda t: 0.26*math.sin(tau*870*t + 2*math.sin(tau*13*t))
          + 0.09*rng.uniform(-1, 1))
    write('collision.wav', 0.5, lambda t: (0.6*rng.uniform(-1, 1)
          + 0.25*math.sin(tau*72*t))*math.exp(-13*t)*min(1, t*500))
    write('ui.wav', 0.12, lambda t: 0.3*math.sin(tau*920*t)*math.exp(-35*t)*min(1, t*600))
    # Frequencies are integer periods over 8 seconds, giving a seamless loop.
    write('ambience.wav', 8, lambda t: sum(0.075*math.sin(tau*f*t)
          for f in (110, 164.875, 220, 261.625, 329.625))
          * (0.75+0.25*math.sin(tau*t/8)) + 0.025*math.sin(tau*55*t))


if __name__ == '__main__':
    main()
