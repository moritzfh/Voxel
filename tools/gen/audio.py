"""Procedural ambience: river murmur + wind + occasional birds, seamless 40 s loop (16-bit WAV)."""
import sys
import wave
import numpy as np

SR = 32000


def lowpass(x, a):
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def lowpass_fast(x, a):
    # vectorised one-pole via scipy if available
    try:
        from scipy.signal import lfilter
        return lfilter([a], [1, -(1 - a)], x)
    except Exception:
        return lowpass(x, a)


def make(path, seconds=40.0, seed=3):
    rng = np.random.default_rng(seed)
    n = int(SR * seconds)
    t = np.arange(n) / SR
    # river: band-limited noise with slow amplitude wobble
    white = rng.standard_normal(n + SR)
    river = lowpass_fast(white, 0.18) - lowpass_fast(white, 0.02)
    river = river[SR:]
    wob = 0.75 + 0.25 * np.sin(2 * np.pi * t / seconds * 3) * np.sin(2 * np.pi * t / seconds * 7 + 1.3)
    river *= wob
    # bubbling: sparse short filtered clicks
    bub = np.zeros(n)
    for _ in range(int(seconds * 18)):
        p = rng.integers(0, n - 2000)
        f = rng.uniform(300, 900)
        L = rng.integers(300, 1200)
        env = np.exp(-np.arange(L) / (L / 4))
        bub[p:p + L] += np.sin(2 * np.pi * f * np.arange(L) / SR * (1 + np.arange(L) / L * 0.6)) * env * rng.uniform(0.05, 0.15)
    # wind: very low noise swelling
    wind = lowpass_fast(rng.standard_normal(n), 0.004)
    wind *= (0.5 + 0.5 * np.sin(2 * np.pi * t / seconds * 2 + 0.4)) * 6.0
    # birds
    birds = np.zeros(n)
    for _ in range(int(seconds / 2.2)):
        p = int(rng.uniform(0.5, seconds - 2.0) * SR)
        kind = rng.integers(0, 3)
        notes = rng.integers(2, 6)
        f0 = rng.uniform(2600, 4200)
        for k in range(notes):
            L = int(SR * rng.uniform(0.06, 0.14))
            tt = np.arange(L) / SR
            if kind == 0:
                f = f0 + 900 * np.sin(np.pi * tt / tt[-1])
            elif kind == 1:
                f = f0 * (1.25 - 0.35 * tt / tt[-1])
            else:
                f = f0 + 400 * np.sin(2 * np.pi * 28 * tt)
            ph = 2 * np.pi * np.cumsum(f) / SR
            env = np.sin(np.pi * np.arange(L) / L) ** 2
            q = p + k * int(SR * rng.uniform(0.12, 0.2))
            if q + L < n:
                birds[q:q + L] += np.sin(ph) * env * rng.uniform(0.05, 0.11)
    mix = river * 0.9 + bub + wind * 0.25 + birds
    # seamless loop: crossfade the last second into the start
    fade = SR
    w = np.linspace(0, 1, fade)
    mix[:fade] = mix[:fade] * w + mix[-fade:] * (1 - w)
    mix = mix[:-fade]
    mix = mix / np.max(np.abs(mix)) * 0.6
    data = (mix * 32767).astype(np.int16)
    with wave.open(path, 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())


if __name__ == '__main__':
    make(sys.argv[1])
