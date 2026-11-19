#!/usr/bin/env python3
# make_synth_sounds.py
#
# PURPOSE
#   Generates the two synthesized plant loops used by the app (they are our
#   own work, not downloaded): an electric-motor whine and a heater hiss.
#   Run from the project root:  python3 tools/make_synth_sounds.py
#
# HOW THEY LOOP SEAMLESSLY
#   motor_whine: every partial has a whole number of cycles in LOOP_S, so the
#     end joins the start exactly. The game changes pitch with pitch_scale.
#   heater_hiss: filtered noise made periodic by circular filtering (FFT), so
#     it has no seam either.
import wave
import numpy as np

RATE = 22050          # TUNABLE: sample rate (Hz); low keeps the files small
LOOP_S = 1.0          # loop length (s)


def save(path, samples):
    data = np.clip(samples, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())


def motor_whine():
    t = np.arange(int(RATE * LOOP_S)) / RATE
    base = 110.0  # Hz at pitch_scale 1 (whole cycles per loop)
    # (harmonic, amplitude): a buzzy motor fundamental plus a faint high
    # "PWM" whine, like a small DC motor under a driver.
    partials = [(1, 0.55), (2, 0.30), (3, 0.18), (4, 0.10), (6, 0.06), (8, 0.04), (17, 0.035)]
    signal = sum(a * np.sin(2 * np.pi * base * h * t + h) for h, a in partials)
    # Brush noise, periodic over the loop.
    rng = np.random.default_rng(7)
    spectrum = np.fft.rfft(rng.standard_normal(t.size))
    freqs = np.fft.rfftfreq(t.size, 1 / RATE)
    spectrum *= np.exp(-((freqs - 3000.0) / 1500.0) ** 2)
    noise = np.fft.irfft(spectrum, t.size)
    noise /= np.max(np.abs(noise))
    signal = signal / np.max(np.abs(signal)) * 0.8 + 0.08 * noise
    return signal * 0.7


def heater_hiss():
    n = int(RATE * LOOP_S)
    rng = np.random.default_rng(11)
    spectrum = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    # Soft hiss: band around 1.5-6 kHz, nothing harsh above.
    spectrum *= np.exp(-((freqs - 3500.0) / 2200.0) ** 2)
    signal = np.fft.irfft(spectrum, n)
    return signal / np.max(np.abs(signal)) * 0.5


save("assets/audio/plant/motor_whine.wav", motor_whine())
save("assets/audio/plant/heater_hiss.wav", heater_hiss())
print("wrote assets/audio/plant/motor_whine.wav, heater_hiss.wav")
