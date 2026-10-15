"""Procedural sound effects for mining, chopping, building and UI (16-bit mono WAV, 32 kHz)."""
import os
import sys
import wave
import numpy as np
from scipy.signal import lfilter

SR = 32000
RNG = np.random.default_rng(12)


def lp(x, a):
    return lfilter([a], [1, -(1 - a)], x)


def hp(x, a):
    return x - lp(x, a)


def env(n, attack=0.002, decay=0.12):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-t / decay)
    return e


def save(path, x, gain=0.9):
    x = np.asarray(x, np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    # short fade out
    f = min(len(x), int(SR * 0.01))
    x[-f:] *= np.linspace(1, 0, f)
    data = (x * 32767).astype(np.int16)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def noise(n):
    return RNG.standard_normal(n)


def tone(n, f, f_end=None):
    t = np.arange(n) / SR
    if f_end is None:
        f_end = f
    ph = 2 * np.pi * np.cumsum(np.linspace(f, f_end, n)) / SR
    return np.sin(ph)


def dig(seed):
    """soft earth scoop: low thud + gravelly crumble"""
    rng = np.random.default_rng(seed)
    n = int(SR * 0.45)
    thud = lp(noise(n), 0.03) * env(n, 0.003, 0.07) * 4.0
    crumble = np.zeros(n)
    for _ in range(40):
        p = rng.integers(int(SR * 0.02), int(SR * 0.32))
        L = rng.integers(80, 400)
        c = hp(rng.standard_normal(L), 0.3) * env(L, 0.0005, L / SR / 3)
        crumble[p:p + L] += c * rng.uniform(0.1, 0.4) * np.exp(-p / (SR * 0.2))
    return lp(thud + crumble * 0.8, 0.5)


def chip(seed):
    """stone chip: sharp click + ringing + rubble"""
    rng = np.random.default_rng(seed)
    n = int(SR * 0.6)
    click = hp(noise(n), 0.4) * env(n, 0.0003, 0.012) * 2.5
    ring = (tone(n, rng.uniform(1800, 2600)) * 0.5 + tone(n, rng.uniform(3100, 4200)) * 0.3) * env(n, 0.0005, 0.05)
    rubble = np.zeros(n)
    for _ in range(30):
        p = rng.integers(int(SR * 0.04), int(SR * 0.45))
        L = rng.integers(60, 260)
        rubble[p:p + L] += hp(rng.standard_normal(L), 0.35) * env(L, 0.0003, L / SR / 4) * rng.uniform(0.1, 0.35)
    body = lp(noise(n), 0.05) * env(n, 0.002, 0.05) * 1.5
    return click + ring * 0.6 + rubble + body


def chop(seed):
    """axe into wood: hollow thock"""
    rng = np.random.default_rng(seed)
    n = int(SR * 0.4)
    f = rng.uniform(170, 230)
    thock = (tone(n, f * 1.6, f) * 0.8 + tone(n, f * 2.7, f * 2.2) * 0.4) * env(n, 0.001, 0.06)
    hit = lp(hp(noise(n), 0.2), 0.6) * env(n, 0.0005, 0.015) * 2.0
    return thock + hit


def crack():
    """tree trunk breaking + falling creak"""
    n = int(SR * 1.6)
    t = np.arange(n) / SR
    snaps = np.zeros(n)
    for i in range(14):
        p = int(SR * (0.02 + i * 0.045 + RNG.uniform(0, 0.02)))
        L = 500
        snaps[p:p + L] += hp(noise(L), 0.25) * env(L, 0.0003, 0.008) * RNG.uniform(0.4, 1.0)
    creak = tone(n, 140, 60) * env(n, 0.05, 0.6) * (0.5 + 0.5 * np.sin(2 * np.pi * 23 * t)) * 0.4
    return snaps + creak


def crash():
    """big impact: tree / rock chunk hitting the ground"""
    n = int(SR * 1.4)
    boom = lp(noise(n), 0.012) * env(n, 0.004, 0.25) * 8.0
    leaves = lp(hp(noise(n), 0.15), 0.4) * env(n, 0.01, 0.45) * 0.7
    tail = np.zeros(n)
    for _ in range(60):
        p = RNG.integers(int(SR * 0.05), int(SR * 0.9))
        L = RNG.integers(100, 600)
        tail[p:p + L] += hp(RNG.standard_normal(L), 0.3) * env(L, 0.0005, L / SR / 4) * RNG.uniform(0.05, 0.25)
    return boom + leaves + tail


def crumble():
    n = int(SR * 0.9)
    out = lp(noise(n), 0.03) * env(n, 0.003, 0.18) * 3.0
    for _ in range(80):
        p = RNG.integers(0, int(SR * 0.7))
        L = RNG.integers(60, 300)
        out[p:p + L] += hp(RNG.standard_normal(L), 0.35) * env(L, 0.0003, L / SR / 4) * RNG.uniform(0.1, 0.4)
    return out


def pickup():
    n = int(SR * 0.18)
    return (tone(n, 880, 1320) * 0.6 + tone(n, 1760, 2640) * 0.2) * env(n, 0.002, 0.05)


def place():
    n = int(SR * 0.35)
    thump = lp(noise(n), 0.04) * env(n, 0.002, 0.05) * 3.0
    tick = tone(n, 520, 380) * env(n, 0.001, 0.04) * 0.6
    return thump + tick


def remove():
    n = int(SR * 0.3)
    return lp(hp(noise(n), 0.1), 0.35) * env(n, 0.003, 0.07) + tone(n, 400, 220) * env(n, 0.002, 0.05) * 0.4


def clink():
    n = int(SR * 0.5)
    return (tone(n, 2400) + tone(n, 3700) * 0.6 + tone(n, 5200) * 0.3) * env(n, 0.0005, 0.09) + hp(noise(n), 0.4) * env(n, 0.0003, 0.006)


def levelup():
    n = int(SR * 1.2)
    out = np.zeros(n)
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        p = int(SR * 0.11 * i)
        L = n - p
        out[p:] += (tone(L, f) + tone(L, f * 2) * 0.3) * env(L, 0.004, 0.35) * 0.6
    return out


def ui_click():
    n = int(SR * 0.07)
    return tone(n, 1400, 900) * env(n, 0.001, 0.015)


def whoosh():
    n = int(SR * 0.35)
    t = np.arange(n) / SR
    x = noise(n)
    a = 0.02 + 0.3 * np.sin(np.pi * t / t[-1])
    y = np.zeros(n)
    acc = 0.0
    for i in range(n):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y * np.sin(np.pi * t / t[-1])


def treasure():
    n = int(SR * 1.6)
    out = np.zeros(n)
    for i, f in enumerate((784, 988, 1175, 1568, 1976)):
        p = int(SR * 0.08 * i)
        L = n - p
        out[p:] += tone(L, f) * env(L, 0.003, 0.5) * 0.5
    sparkle = hp(noise(n), 0.5) * env(n, 0.01, 0.6) * 0.15
    return out + sparkle


def build_all(outdir):
    os.makedirs(outdir, exist_ok=True)
    for i in range(3):
        save(os.path.join(outdir, f'sfx_dig{i}.wav'), dig(10 + i))
        save(os.path.join(outdir, f'sfx_chip{i}.wav'), chip(20 + i), 0.8)
        save(os.path.join(outdir, f'sfx_chop{i}.wav'), chop(30 + i))
    save(os.path.join(outdir, 'sfx_crack.wav'), crack())
    save(os.path.join(outdir, 'sfx_crash.wav'), crash())
    save(os.path.join(outdir, 'sfx_crumble.wav'), crumble())
    save(os.path.join(outdir, 'sfx_pickup.wav'), pickup(), 0.5)
    save(os.path.join(outdir, 'sfx_place.wav'), place(), 0.8)
    save(os.path.join(outdir, 'sfx_remove.wav'), remove(), 0.7)
    save(os.path.join(outdir, 'sfx_clink.wav'), clink(), 0.6)
    save(os.path.join(outdir, 'sfx_levelup.wav'), levelup(), 0.7)
    save(os.path.join(outdir, 'sfx_click.wav'), ui_click(), 0.5)
    save(os.path.join(outdir, 'sfx_whoosh.wav'), whoosh(), 0.6)
    save(os.path.join(outdir, 'sfx_treasure.wav'), treasure(), 0.7)


if __name__ == '__main__':
    build_all(sys.argv[1] if len(sys.argv) > 1 else '../../assets/audio')
