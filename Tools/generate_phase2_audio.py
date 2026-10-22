"""Original Phase 2 feedback. Leaves every Phase 1 asset unchanged."""
import math
from generate_audio import write


def tone(t, frequency, duration, amplitude=0.36):
    envelope = min(t*200, 1) * max(0, 1-t/duration)**2
    return amplitude*math.sin(math.tau*frequency*t)*envelope


def main():
    write('coin.wav', 0.22, lambda t: tone(t, 1320, .22)+tone(t, 1980, .22, .16))
    write('near_miss.wav', .38, lambda t: tone(t, 660+t*900, .38))
    write('countdown.wav', .18, lambda t: tone(t, 440, .18))
    write('go.wav', .4, lambda t: tone(t, 880, .4)+tone(t, 1320, .4, .16))
    write('finish.wav', 1.1, lambda t: sum(tone(max(0,t-i*.14), f, .65, .18)
          if t>=i*.14 else 0 for i,f in enumerate([523.25,659.25,783.99,1046.5])))


if __name__ == '__main__':
    main()
