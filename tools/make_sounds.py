# Generates app/App/Sounds/*.wav (synthesized tones, no third-party audio). Usage: python tools/make_sounds.py app/App/Sounds
import math, struct, wave, sys, os
out = sys.argv[1]
RATE = 44100
def write(name, samples):
    with wave.open(os.path.join(out, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767 * 0.8)) for s in samples))
def tone(freq, dur, attack=0.005, decay=None, partials=((1, 1.0),)):
    n = int(RATE * dur); res = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack) * (math.exp(-t / decay) if decay else 1.0)
        if not decay: env *= min(1.0, (dur - t) / 0.01)
        res.append(env * sum(a * math.sin(2 * math.pi * freq * k * t) for k, a in partials) / sum(a for _, a in partials))
    return res
def silence(dur): return [0.0] * int(RATE * dur)
# Last-5-seconds countdown: five short beeps one second apart (fires 5 s before the boundary).
beep = tone(1000, 0.09)
countdown = []
for i in range(5):
    countdown += beep + silence(1.0 - 0.09)
write("countdown.wav", countdown[: int(RATE * 4.95)])
# Step start (second 0): short two-note chime.
bell = ((1, 1.0), (2, 0.35), (3, 0.15))
write("chime.wav", tone(1318.5, 0.18, decay=0.25, partials=bell) + tone(1760, 0.6, decay=0.3, partials=bell))
# Workout finished: three rising notes.
write("finish.wav", tone(1046.5, 0.2, decay=0.25, partials=bell) + tone(1318.5, 0.2, decay=0.25, partials=bell) + tone(1568, 0.8, decay=0.35, partials=bell))
# Silent sound for scheduled Live Activity alerts (the notifications carry the audible chime).
write("silent.wav", silence(0.2))
print("ok")
