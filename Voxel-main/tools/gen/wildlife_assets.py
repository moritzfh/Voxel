"""Original voxel wildlife models and synthesized positional sound assets.

Run with Python + numpy. Does not rebuild or change the existing terrain.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SR = 22050
RNG = np.random.default_rng(817)


class Model:
    def __init__(self, voxel):
        self.voxel = voxel
        self.parts = {}
        self.pivots = {}

    def shape(self, part, center, radius, colors, box=False, stripes=False):
        cells = self.parts.setdefault(part, {})
        center, radius = np.array(center), np.array(radius)
        for x in range(int(np.floor(center[0] - radius[0])), int(np.ceil(center[0] + radius[0]))):
            for y in range(int(np.floor(center[1] - radius[1])), int(np.ceil(center[1] + radius[1]))):
                for z in range(int(np.floor(center[2] - radius[2])), int(np.ceil(center[2] + radius[2]))):
                    p = np.array([x, y, z]) + .5
                    if box or np.sum(((p - center) / radius) ** 2) <= 1.0:
                        index = (z // 2) % len(colors) if stripes else int(RNG.integers(len(colors)))
                        cells[(x, y, z)] = colors[index]

    def pivot(self, part, xyz):
        self.pivots[part] = xyz

    def eyes(self, x, y, z, part='head'):
        for side in [-1, 1]:
            self.shape(part, (side * x, y, z), (.65, .7, .7), ['171c1c'], box=True)
            self.shape(part, (side * (x + .1), y + .35, z - .35), (.25, .25, .25), ['f7e8cf'], box=True)

    def export(self):
        return {'voxel': self.voxel, 'parts': [
            {'name': name, 'pivot': self.pivots.get(name, [0, 0, 0]),
             'cells': [[*xyz, color] for xyz, color in cells.items()]}
            for name, cells in self.parts.items()]}


def models():
    out = {}
    m = Model(.075)
    fur = ['67432b', '704a30', '785036', '614029']
    m.shape('body', (0, 12, 1), (7, 7, 11), fur)
    m.shape('body', (0, 15, -5), (7, 7, 6), fur)
    m.pivot('head', [0, 16, -9])
    m.shape('head', (0, 17, -12), (5.5, 5.5, 5), fur)
    m.shape('head', (0, 15, -16), (3.4, 2.4, 3), ['b49669', 'aa8a60'])
    m.shape('head', (0, 16, -18), (1.5, 1, 1), ['211d1b'], True)
    for side in [-1, 1]:
        m.shape('head', (side * 4, 22, -11), (2, 2.3, 1.7), fur)
        m.shape('head', (side * 4, 22, -12), (1, 1.2, .7), ['3a2922'])
    m.eyes(4, 18, -15)
    for i, (x, z) in enumerate([(-4, -6), (4, -6), (-4, 7), (4, 7)]):
        p = 'leg%d' % i
        m.pivot(p, [x, 10, z])
        m.shape(p, (x, 6, z), (2.8, 5.8, 3.2), fur)
        m.shape(p, (x, 1.4, z - .6), (3, 1.5, 3.7), ['4b3324'])
    m.shape('body', (0, 14, 11), (2, 2, 2), fur)
    out['bear'] = m.export()

    m = Model(.065)
    fur = ['777e80', '858e90', '91999b', '6b7478']
    m.shape('body', (0, 12, 1), (4.5, 5.5, 9), fur)
    m.shape('body', (0, 15, -5), (4.8, 6, 5), fur)
    m.pivot('head', [0, 17, -8])
    m.shape('head', (0, 19, -10), (4.4, 4.7, 4.6), fur)
    m.shape('head', (0, 17, -14), (2.4, 2.3, 4), ['b9b9ac', 'd2cdb8'])
    m.shape('head', (0, 18, -17), (1.4, 1.1, 1), ['22272a'], True)
    for side in [-1, 1]:
        m.shape('head', (side * 2.9, 23.7, -9), (1.8, 3.9, 2), fur)
        m.shape('head', (side * 2.9, 24, -10), (.8, 2.2, .6), ['bb9a93'])
    m.eyes(3.3, 20, -12.5)
    for i, (x, z) in enumerate([(-3, -5), (3, -5), (-3, 6), (3, 6)]):
        p = 'leg%d' % i
        m.pivot(p, [x, 10, z])
        m.shape(p, (x, 5.5, z), (1.5, 5.5, 1.9), fur)
        m.shape(p, (x, 1, z - 1), (1.8, 1.1, 2.4), ['c1bda8'])
    m.pivot('tail', [0, 13, 8])
    m.shape('tail', (0, 10, 13), (2.2, 2.8, 6.4), fur)
    m.shape('tail', (0, 9, 18), (1.6, 2, 2), ['464d50'])
    out['wolf'] = m.export()

    m = Model(.04)
    fur = ['b9ab94', 'c7bba6', 'a99d89']
    m.shape('body', (0, 5, 2), (4.5, 5.2, 6.5), fur)
    m.pivot('head', [0, 8, -3])
    m.shape('head', (0, 8, -5), (3.5, 3.5, 3.5), fur)
    m.shape('head', (0, 6.5, -8), (1, .8, 1), ['dcaaa5'], True)
    m.eyes(2.7, 9, -7)
    for i, side in enumerate([-1, 1]):
        p = 'ear%d' % i
        m.pivot(p, [side * 1.8, 10, -4.5])
        m.shape(p, (side * 1.8, 15, -4), (1.4, 5.2, 1.2), fur)
        m.shape(p, (side * 1.8, 15, -5), (.7, 3.8, .4), ['d6a5a1'], True)
    for i, (x, z) in enumerate([(-2.5, -3), (2.5, -3), (-3, 5), (3, 5)]):
        p = 'leg%d' % i
        m.pivot(p, [x, 4, z])
        m.shape(p, (x, 1.5, z - .8), (1.6, 1.8, 2.8), fur)
    m.shape('body', (0, 5, 8), (2.1, 2.1, 2.1), ['eae6d6'])
    out['rabbit'] = m.export()

    m = Model(.045)
    m.shape('body', (0, 4, 0), (5.5, 4, 7.2), ['556d38', '657b40', '455a30'])
    # Dark seams and amber shell plates, all geometry remains voxel-native.
    cells = m.parts['body']
    for xyz in cells:
        x, y, z = xyz
        if y >= 5:
            cells[xyz] = '384b2a' if x % 4 == 0 or z % 4 == 0 else '87914b'
    m.pivot('head', [0, 3, -6])
    m.shape('head', (0, 3, -8), (2.2, 2, 3), ['8e9e5b', '9ba762'])
    m.eyes(1.5, 4, -10)
    for i, (x, z) in enumerate([(-5, -4), (5, -4), (-5, 4), (5, 4)]):
        p = 'leg%d' % i
        m.pivot(p, [x, 2, z])
        m.shape(p, (x, 1.4, z), (2, 1.3, 2.3), ['7c914c'])
    m.shape('body', (0, 2, 7), (1, 1, 2.6), ['7c914c'])
    out['turtle'] = m.export()

    m = Model(.03)
    m.shape('body', (0, 4, 1), (2.5, 3.4, 4.6), ['799aae', '628da4', '91aabb'])
    m.shape('body', (0, 3.3, -1.4), (2, 2.4, 2.5), ['d9914d', 'e1a05a'])
    m.pivot('head', [0, 6, -3])
    m.shape('head', (0, 7, -3.5), (2.4, 2.6, 2.6), ['6b8fa5', '83a6b7'])
    m.shape('head', (0, 6.5, -6.5), (.8, .7, 1.5), ['e4b74b'], True)
    m.eyes(1.8, 7.8, -5)
    for p, side in [('wing_l', -1), ('wing_r', 1)]:
        m.pivot(p, [side * 2, 5, 0])
        m.shape(p, (side * 5, 5, 1), (4, .8, 3), ['446c8a', '537f99'])
    m.pivot('tail', [0, 4, 4])
    m.shape('tail', (0, 4, 6), (1.8, .7, 3), ['446c8a'])
    out['bird'] = m.export()

    m = Model(.018)
    m.shape('body', (0, 3, 0), (3, 2.8, 5.5), ['e8b833', '34302a'], stripes=True)
    m.shape('head', (0, 3, -5), (2.5, 2.5, 2.2), ['edc448'])
    m.eyes(1.8, 4, -6)
    for p, side in [('wing_l', -1), ('wing_r', 1)]:
        m.pivot(p, [side * 1, 5, 0])
        m.shape(p, (side * 4, 5.5, 0), (3.5, .6, 3.2), ['c4e5e1', 'e2f1e9'])
    for i, side in enumerate([-1, 1]):
        m.shape('head', (side * 1.5, 6, -5), (.4, 1.8, .4), ['353029'], True)
    out['bee'] = m.export()

    m = Model(.04)
    m.shape('body', (0, 7, 1), (4.5, 5.3, 5.7), ['eee6cf', 'dcd3bb', 'f6efd9'])
    m.pivot('head', [0, 12, -3])
    m.shape('head', (0, 13, -4), (2.8, 3.5, 2.9), ['f7efdd', 'e5dac3'])
    m.shape('head', (0, 12, -7), (1.4, .9, 1.5), ['dda33d'], True)
    m.shape('head', (0, 17, -4), (.7, 1.7, 2), ['b93c30', 'cf4834'], True)
    m.shape('head', (0, 10.5, -6), (.8, 1.2, .9), ['c34635'])
    m.eyes(2.3, 14, -5.8)
    for i, side in enumerate([-1, 1]):
        p = 'leg%d' % i
        m.pivot(p, [side*2, 4, 0])
        m.shape(p, (side*2, 2, 0), (.65, 2.1, .65), ['ca943c'], True)
        m.shape(p, (side*2, .5, -1), (1.2, .55, 1.7), ['dda445'], True)
    for p, side in [('wing_l', -1), ('wing_r', 1)]:
        m.pivot(p, [side*3.5, 8, 0])
        m.shape(p, (side*4.2, 7, 1), (1.1, 2.8, 3.4), ['d5ccb4', 'e3dac4'])
    m.pivot('tail', [0, 8, 5])
    m.shape('tail', (0, 10, 7), (2, 3.7, 2), ['b0a486', 'c8bca0'])
    out['chicken'] = m.export()
    chick = json.loads(json.dumps(out['chicken']))
    for part in chick['parts']:
        part['cells'] = [cell for cell in part['cells'] if cell[3] not in ['b93c30', 'cf4834', 'c34635']]
        for cell in part['cells']:
            if cell[3] not in ['171c1c', 'f7e8cf', 'dda33d', 'ca943c', 'dda445']:
                cell[3] = ['edc757', 'f4d777', 'dfb84a'][int(RNG.integers(3))]
    out['chick'] = chick
    target = ROOT / 'assets/wildlife'
    target.mkdir(parents=True, exist_ok=True)
    (target / 'models.json').write_text(json.dumps(out, separators=(',', ':')), encoding='utf-8')
    print('Models:', ', '.join('%s=%d voxels' % (k, sum(len(p['cells']) for p in v['parts'])) for k, v in out.items()))


def noise(seconds, low, high):
    n = int(SR * seconds)
    frequencies = np.fft.rfftfreq(n, 1 / SR)
    spectrum = RNG.normal(size=len(frequencies)) + 1j * RNG.normal(size=len(frequencies))
    spectrum *= (1 - np.exp(-(frequencies / low) ** 2)) / (1 + (frequencies / high) ** 4)
    signal = np.fft.irfft(spectrum, n=n)
    return signal / max(np.std(signal), .0001)


def write(name, signal, peak=.6):
    signal = np.tanh(signal)
    signal *= peak / max(np.max(np.abs(signal)), .001)
    target = ROOT / 'assets/audio/wildlife'
    target.mkdir(parents=True, exist_ok=True)
    with wave.open(str(target / (name + '.wav')), 'wb') as f:
        f.setparams((1, 2, SR, len(signal), 'NONE', 'not compressed'))
        f.writeframes((signal * 32767).astype('<i2').tobytes())


def audio():
    seconds = 12
    t = np.arange(SR * seconds) / SR
    # Periodic FFT noise and integer-period modulation make the environmental beds loop cleanly.
    wind = noise(seconds, 35, 450) * (.15 + .06 * np.sin(2 * np.pi * t / seconds))
    leaves = noise(seconds, 650, 3400) * (.08 + .035 * np.sin(2 * np.pi * t * 3 / seconds))
    creek = noise(seconds, 180, 4200) * (.19 + .025 * np.sin(2 * np.pi * t * 5 / seconds))
    bubbles = np.zeros_like(t)
    for i in range(100):
        p = int(RNG.uniform(0, seconds - .15) * SR)
        tt = np.arange(int(SR * .12)) / SR
        bubbles[p:p+len(tt)] += .055 * np.sin(2 * np.pi * (550 * tt + 2500 * tt ** 2)) * np.sin(np.pi * tt / .12) ** 2
    write('wind', wind, .30)
    write('forest', leaves, .38)
    write('river', creek + bubbles, .62)
    write('waterfall', noise(seconds, 55, 7000) * .24, .75)
    for variation in range(3):
        t = np.arange(int(SR * 1.6)) / SR
        result = np.zeros_like(t)
        for note in range(3 + variation):
            start = .08 + note * .24
            u = np.clip((t - start) / .15, 0, 1)
            envelope = np.where((t >= start) & (t <= start + .15), np.sin(np.pi * u) ** 2, 0)
            phase = 2 * np.pi * ((2500 + variation * 350) * t + 50 * np.sin(t * 28))
            result += np.sin(phase) * envelope * .25
        write('bird%d' % variation, result, .55)
    t = np.arange(SR * 2) / SR
    buzz = np.sin(2 * np.pi * 185 * t) + .4 * np.sin(2 * np.pi * 370 * t) + .18 * np.sin(2 * np.pi * 740 * t)
    write('bee', buzz * (.10 + .018 * np.sin(2 * np.pi * t * 3)), .28)
    for name, duration, base in [('bear', 1.65, 83), ('wolf_growl', 1.2, 145), ('wolf_howl', 3.3, 390)]:
        t = np.arange(int(SR * duration)) / SR
        envelope = np.sin(np.pi * t / duration) ** 1.4
        if name == 'wolf_howl':
            frequency = base + 110 * np.sin(np.pi * t / duration) + 7 * np.sin(t * 31)
            phase = 2 * np.pi * np.cumsum(frequency) / SR
            sound = np.sin(phase) + .22 * np.sin(2 * phase) + .06 * noise(duration, 800, 3000)
        else:
            phase = 2 * np.pi * base * t + 4 * np.sin(t * 35)
            sound = (.5 * np.sin(phase) + .3 * np.sin(phase * 2) + .4 * noise(duration, 90, 1200)) * (.65 + .35 * np.sin(t * 48))
        write(name, sound * envelope * .3, .65)
    for name, duration, high in [('rabbit', .22, 4500), ('turtle', .48, 1800), ('step_grass', .18, 3200), ('step_stone', .14, 1800), ('splash', .32, 5000), ('hit', .16, 1200), ('hurt', .4, 900)]:
        t = np.arange(int(SR * duration)) / SR
        envelope = np.sin(np.pi * t / duration) ** 1.3 * np.exp(-t * 9)
        sound = noise(duration, 70, high) * envelope
        if name in ['step_stone', 'hit']:
            sound += np.sin(2 * np.pi * 130 * t) * np.exp(-t * 40)
        write(name, sound * .35, .45)
    t = np.arange(int(SR * 1.3)) / SR
    cluck = np.zeros_like(t)
    for start in [.06, .32, .64, .86]:
        u = np.clip((t-start)/.16, 0, 1)
        envelope = np.where((t>=start)&(t<start+.16), np.sin(np.pi*u)**1.4, 0)
        cluck += envelope * (np.sin(2*np.pi*(550*t+20*np.sin(t*25)))+.3*noise(1.3,500,1800))
    write('chicken', cluck*.3, .5)
    t = np.arange(int(SR * .8)) / SR
    peep = np.sin(2*np.pi*(2400*t+12*np.sin(t*50))) * np.sin(np.pi*t/.8)**2
    write('chick', peep*.2, .4)
    print('Audio:', len(list((ROOT / 'assets/audio/wildlife').glob('*.wav'))), 'original synthesized mono WAVs')


if __name__ == '__main__':
    models()
    audio()
