"""Generate the short, original dispel cue; convert the WAV to OGG with ffmpeg."""
import math
import struct
import sys
import wave

rate = 44100
with wave.open(sys.argv[1], "wb") as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(rate)
    samples = []
    for i in range(int(rate * 0.25)):
        t = i / rate
        start, hz = (0.0, 880) if t < 0.115 else (0.115, 1175)
        local = t - start
        envelope = min(1, local / 0.008) * max(0, 1 - local / 0.125) ** 2
        value = math.sin(2 * math.pi * hz * local) * envelope * 0.32
        samples.append(struct.pack("<h", round(value * 32767)))
    output.writeframes(b"".join(samples))
