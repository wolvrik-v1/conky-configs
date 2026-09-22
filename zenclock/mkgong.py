#!/usr/bin/env python3
"""Synthesize a zen gong WAV (additive synthesis) - no external assets."""

import numpy as np
import wave

SR = 44100

def gong(duration=6.0, f0=208.0, attack=0.004, decay=4.5,
         noise_ms=30, partials=None, amp=0.85):
    """A struck metallic bowl/gong: inharmonic partials, strike transient, long ring."""
    if partials is None:
        # Inharmonic ratios typical of an Asian gong/bell
        partials = [(1.00, 1.00), (2.76, 0.42), (5.40, 0.20),
                    (8.93, 0.08), (0.67, 0.35), (1.41, 0.50), (4.01, 0.12)]
    n = int(SR * duration)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    # strike transient burst
    nt = min(int(SR * noise_ms / 1000.0), n)
    strike = np.random.default_rng(42).normal(0, 1, nt)
    env0 = np.exp(-t[:nt] / 0.006) * np.exp(-(t[:nt] - 0.0015) ** 2 / (2 * 0.001 ** 2))
    sig[:nt] += 0.30 * strike * env0 * amp

    # each partial: fast attack, long exponential decay, slight pitch-bend shimmer down
    for ratio, a in partials:
        f = f0 * ratio
        pref = 0.9995  # slight downward drift for warmth
        phase = 2 * np.pi * f * (t * pref + (1 - pref) * (t ** 2) / (2 * duration))
        env = (1 - np.exp(-t / (attack * 4 + 0.001))) * np.exp(-t / decay)
        sig += amp * a * np.sin(phase) * env
    # gentle fade at the very end to avoid a click
    fade = min(int(SR * 0.05), n)
    if fade:
        sig[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(sig)) or 1.0
    return (sig / peak * 0.9 * 32767).astype(np.int16)

def chime(duration=2.2, f0=520.0):
    """A lighter bowl strike for periodic chimes."""
    g = gong(duration=duration, f0=f0, decay=1.8, noise_ms=15,
             partials=[(1.00, 1.00), (2.42, 0.35), (4.10, 0.12), (6.2, 0.05)],
             amp=0.5)
    return g

def write_wav(path, data):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())

if __name__ == '__main__':
    write_wav('gong.wav', gong(6.0))          # start / finish strikes
    write_wav('chime.wav', chime(2.2))        # periodic chime
    print('wrote gong.wav + chime.wav')