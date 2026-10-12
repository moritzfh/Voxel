"""Procedural 16x16 pixel textures for the voxel world (Grünweiten).

All block tiles are 16x16 RGBA. Plant sprites are 16x32 RGBA.
Output: a vertical strip PNG per array + a JSON index.
"""
import json
import numpy as np
from PIL import Image

T = 16


def hexc(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def pal(*hs):
    return np.stack([hexc(h) for h in hs])


def value_noise(rng, w, h, cell, tile=True):
    """Tileable smooth value noise in [0,1]."""
    gw, gh = max(1, w // cell), max(1, h // cell)
    g = rng.random((gh, gw))
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = ys - y0
    fx = xs - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    y1 = (y0 + 1) % gh
    x1 = (x0 + 1) % gw
    y0 %= gh
    x0 %= gw
    a = g[np.ix_(y0, x0)]
    b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]
    d = g[np.ix_(y1, x1)]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(rng, w, h, cells=(8, 4, 2), weights=(0.5, 0.3, 0.2)):
    out = np.zeros((h, w))
    for c, wt in zip(cells, weights):
        out += value_noise(rng, w, h, c) * wt
    return out / sum(weights)


def from_palette(p, v):
    """Map v in [0,1] onto palette entries (nearest, pixel-art look)."""
    idx = np.clip((v * len(p)).astype(int), 0, len(p) - 1)
    return p[idx]


def finish(rgb, alpha=None):
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    if alpha is None:
        alpha = np.full(rgb.shape[:2], 255, np.uint8)
    return np.dstack([rgb, alpha.astype(np.uint8)])


def jitter(rng, shape, amt):
    return (rng.random(shape) - 0.5) * amt


# ---------------------------------------------------------------- tiles

def t_grass_top(rng):
    p = pal('#3f7a26', '#4c8c2c', '#5a9f33', '#69b13b', '#7bc046', '#90cf55')
    v = fbm(rng, T, T, (8, 4, 2), (0.35, 0.35, 0.3)) * 0.75 + rng.random((T, T)) * 0.25
    img = from_palette(p, v)
    # little bright blade tips
    for _ in range(10):
        x, y = rng.integers(0, T, 2)
        img[y, x] = hexc('#a6dc66')
    for _ in range(6):
        x, y = rng.integers(0, T, 2)
        img[y, x] = hexc('#35691f')
    return finish(img)


def grass_fringe(rng, img, grass_pal, depth=(2, 5)):
    for x in range(T):
        d = rng.integers(depth[0], depth[1] + 1)
        for y in range(d):
            img[y, x] = grass_pal[min(len(grass_pal) - 1, rng.integers(1, len(grass_pal)))] if y < d - 1 else grass_pal[0]
    return img


DIRT = pal('#5e3b22', '#6d4529', '#7c5030', '#8b5c37', '#99683f')


def t_dirt(rng):
    v = fbm(rng, T, T, (8, 4, 2)) * 0.6 + rng.random((T, T)) * 0.4
    img = from_palette(DIRT, v)
    for _ in range(5):
        x, y = rng.integers(0, T, 2)
        img[y, x] = hexc('#9a8a78') if rng.random() < 0.5 else hexc('#4b2f1b')
    return finish(img)


def t_grass_side(rng):
    img = t_dirt(rng)[:, :, :3].astype(np.float32)
    gp = pal('#3d7625', '#4f8f2e', '#5fa335', '#70b53e', '#83c64a')
    for x in range(T):
        d = rng.integers(3, 6)
        for y in range(d):
            img[y, x] = gp[rng.integers(1, len(gp))] if y < d - 1 else gp[0]
    return finish(img)


def t_grass_side_full(rng):
    # side of grassy slopes seen from afar: green with darker horizontal streaks and a few soil specks
    p = pal('#3a6d24', '#447b2a', '#4f8a30', '#5a9a37', '#67aa3e')
    v = fbm(rng, T, T, (8, 4, 2), (0.4, 0.35, 0.25)) * 0.7 + rng.random((T, T)) * 0.3
    img = from_palette(p, v)
    img[-3:, :] = img[-3:, :] * 0.8
    for _ in range(6):
        x, y = rng.integers(0, T, 2)
        img[y, x] = hexc('#6d4a2c')
    return finish(img)


def t_boulder(rng, top=False):
    # chunky boulder stone: light grey, soft large features, a few cracks, lighter upper rows
    p = pal('#6e6b66', '#7b7872', '#89857e', '#96928a', '#a39f96', '#b0aca2') if not top else \
        pal('#7d7a74', '#8b8780', '#99958c', '#a6a298', '#b3afa4', '#bfbbb0')
    v = fbm(rng, T, T, (8, 4, 2), (0.5, 0.3, 0.2)) * 0.75 + rng.random((T, T)) * 0.25
    if not top:
        v = v + np.linspace(0.12, -0.12, T)[:, None]
    img = from_palette(p, np.clip(v, 0, 0.999))
    for _ in range(2):
        x, y = rng.integers(0, T, 2)
        for _ in range(rng.integers(2, 6)):
            img[y % T, x % T] = hexc('#6a675f')
            x += rng.integers(-1, 2)
            y += rng.integers(0, 2)
    for _ in range(5):
        x, y = rng.integers(0, T, 2)
        img[y, x] = hexc('#d9d5cb')
    return finish(img)


def t_boulder_moss(rng):
    img = t_boulder(rng, True)[:, :, :3].astype(np.float32)
    moss = fbm(rng, T, T, (8, 4, 2), (0.5, 0.3, 0.2)) > 0.43
    mp = pal('#4c7a2c', '#5a8d33', '#6aa03c', '#7cb247')
    img[moss] = from_palette(mp, rng.random(moss.sum()))
    return finish(img)


def t_mountain_rock(rng):
    # big strata for far cliffs: light grey-tan bands with dark seams
    p = pal('#4f535b', '#5c6069', '#6a6e77', '#787c85', '#878b93', '#979aa1')
    img = np.zeros((T, T, 3), np.float32)
    bands = np.repeat(rng.random(T // 2), 2)
    for y in range(T):
        for x in range(T):
            v = bands[y] * 0.55 + rng.random() * 0.25 + 0.2 * (np.sin(x * 0.6 + y * 1.7) * 0.5 + 0.5)
            img[y, x] = from_palette(p, np.array([min(0.999, v)]))[0]
    for y in (rng.integers(2, 6), rng.integers(9, 14)):
        img[y, :] = hexc('#3d4047')
    for _ in range(3):
        x = rng.integers(0, T)
        y0 = rng.integers(0, T - 4)
        img[y0:y0 + rng.integers(2, 5), x] = hexc('#42454c')
    for _ in range(4):
        x, y = rng.integers(0, T, 2)
        img[y, x] = hexc('#b4b7bd')
    return finish(img)


def t_path(rng):
    p = pal('#9a7d58', '#a98b64', '#b6996f', '#c2a67b', '#ceb388', '#d9c096')
    v = fbm(rng, T, T, (4, 2), (0.6, 0.4)) * 0.55 + rng.random((T, T)) * 0.45
    img = from_palette(p, v)
    # pebbles: 2x1 / 1x1 light or dark
    for _ in range(9):
        x, y = rng.integers(0, T, 2)
        c = hexc('#dcc49a') if rng.random() < 0.55 else hexc('#7b5c3c')
        img[y, x] = c
        if rng.random() < 0.5:
            img[y, (x + 1) % T] = c * 0.92
    return finish(img)


def t_stone(rng):
    p = pal('#77746e', '#86837c', '#959189', '#a5a198', '#b4b0a6', '#c1bdb3')
    v = fbm(rng, T, T, (8, 4, 2), (0.45, 0.35, 0.2)) * 0.8 + rng.random((T, T)) * 0.2
    img = from_palette(p, v)
    # cracks
    for _ in range(2):
        x, y = rng.integers(0, T, 2)
        for _ in range(rng.integers(3, 7)):
            img[y % T, x % T] = hexc('#66635d')
            x += rng.integers(-1, 2)
            y += 1
    return finish(img)


def t_cliff(rng):
    # stratified rock for cliffs / mountains: darker, more contrast, occasional moss
    p = pal('#55534f', '#64625d', '#73706a', '#827f78', '#918e86', '#a29f97')
    base = np.zeros((T, T))
    band = rng.random(T)
    for y in range(T):
        base[y, :] = band[y] * 0.45
    v = base + fbm(rng, T, T, (8, 4), (0.6, 0.4)) * 0.4 + rng.random((T, T)) * 0.15
    img = from_palette(p, v / v.max())
    for y in rng.choice(T, 3, replace=False):
        img[y, :] = img[y, :] * 0.78
    for _ in range(4):
        x, y = rng.integers(0, T, 2)
        img[y, x:x + 2] = hexc('#bdb9b0')
    moss = fbm(rng, T, T, (8, 4), (0.5, 0.5)) > 0.68
    img[moss] = from_palette(pal('#4a6b30', '#587d38', '#3f5e2a'), rng.random(moss.sum()))
    return finish(img)


def t_stone_bricks(rng, dark=False):
    p = pal('#7f7e7a', '#8d8c88', '#9b9a95', '#a8a7a2', '#b4b3ad') if not dark else pal('#6b6a68', '#777674', '#83827f', '#8f8e8a')
    mortar = hexc('#5d5c59') if not dark else hexc('#4c4b49')
    img = np.zeros((T, T, 3), np.float32)
    for row in range(4):
        y0 = row * 4
        off = 0 if row % 2 == 0 else 4
        for bx in range(-1, 3):
            x0 = bx * 8 + off
            shade = rng.random()
            for y in range(y0, y0 + 4):
                for x in range(x0, x0 + 8):
                    if 0 <= x < T:
                        v = shade * 0.6 + rng.random() * 0.4
                        img[y, x] = from_palette(p, np.array([v]))[0]
        img[y0 + 3, :] = mortar
        for bx in range(-1, 3):
            x0 = bx * 8 + off
            if 0 <= x0 < T:
                img[y0:y0 + 4, x0] = mortar
    # top highlight on each brick
    for row in range(4):
        img[row * 4, :] = img[row * 4, :] * 1.08
    return finish(img)


def t_cobble(rng, mossy=False):
    p = pal('#6e6d69', '#7f7e79', '#8f8d88', '#a19e98', '#b0ada6')
    img = np.zeros((T, T, 3), np.float32)
    img[:] = hexc('#4f4e4b')
    # irregular stones via random rects
    stones = []
    y = 0
    while y < T:
        h = rng.integers(3, 6)
        x = rng.integers(-3, 0)
        while x < T:
            w = rng.integers(3, 7)
            stones.append((x, y, w, h))
            x += w
        y += h
    for (x, y, w, h) in stones:
        shade = rng.random()
        for yy in range(y, min(T, y + h - 1)):
            for xx in range(max(0, x), min(T, x + w - 1)):
                v = shade * 0.65 + rng.random() * 0.35
                c = from_palette(p, np.array([v]))[0]
                if yy == y:
                    c = c * 1.1
                if xx == min(T, x + w - 1) - 1 or yy == min(T, y + h - 1) - 1:
                    c = c * 0.86
                img[yy, xx] = c
    if mossy:
        mv = fbm(rng, T, T, (8, 4), (0.6, 0.4))
        moss = pal('#4b7a2e', '#5b8d36', '#6aa03e')
        m = mv > 0.55
        img[m] = from_palette(moss, rng.random(m.sum()))
    return finish(img)


def t_plaster(rng):
    p = pal('#d8ccb6', '#e0d5c1', '#e8dfcd', '#efe8d9')
    v = fbm(rng, T, T, (8, 4, 2)) * 0.5 + rng.random((T, T)) * 0.5
    img = from_palette(p, v)
    return finish(img)


def t_timber(rng):
    p = pal('#4e321c', '#5c3b21', '#6a4527', '#78502e', '#855a34')
    img = np.zeros((T, T, 3), np.float32)
    for x in range(T):
        col = rng.random()
        for y in range(T):
            v = col * 0.55 + rng.random() * 0.25 + 0.2 * (np.sin(y * 0.7 + x * 3) * 0.5 + 0.5)
            img[y, x] = from_palette(p, np.array([min(0.999, v)]))[0]
    img[:, 0] *= 0.85
    img[:, -1] *= 0.85
    img[0, :] *= 1.08
    return finish(img)


def t_planks(rng, dark=False):
    p = pal('#7c512d', '#8c5d35', '#9a693d', '#a77446', '#b2804f') if not dark else pal('#47301c', '#523821', '#5e4026', '#69482b')
    seam = hexc('#5a3a20') if not dark else hexc('#2f1f12')
    img = np.zeros((T, T, 3), np.float32)
    for row in range(4):
        y0 = row * 4
        shade = rng.random()
        cut = rng.integers(4, 13)
        for y in range(y0, y0 + 4):
            for x in range(T):
                v = shade * 0.55 + rng.random() * 0.2 + 0.25 * (np.sin(x * 0.9 + row * 2.1) * 0.5 + 0.5)
                img[y, x] = from_palette(p, np.array([min(0.999, v)]))[0]
        img[y0 + 3, :] = seam
        img[y0:y0 + 3, cut] = seam * 1.1
        img[y0, :] *= 1.07
    return finish(img)


def t_slate(rng):
    p = pal('#3a4048', '#444b54', '#4f5760', '#5b636d', '#68717c')
    img = np.zeros((T, T, 3), np.float32)
    for row in range(4):
        y0 = row * 4
        off = 0 if row % 2 == 0 else 2
        for bx in range(-1, 5):
            x0 = bx * 4 + off
            shade = rng.random()
            for y in range(y0, y0 + 4):
                for x in range(x0, x0 + 4):
                    if 0 <= x < T:
                        v = shade * 0.7 + rng.random() * 0.3
                        c = from_palette(p, np.array([v]))[0]
                        if y == y0 + 3:
                            c = c * 0.7
                        if x == x0:
                            c = c * 0.82
                        img[y, x] = c
    return finish(img)


def t_log_side(rng):
    p = pal('#3f2a19', '#4d341f', '#5b3e25', '#6a492c', '#795434')
    img = np.zeros((T, T, 3), np.float32)
    colv = rng.random(T)
    for x in range(T):
        for y in range(T):
            v = colv[x] * 0.6 + rng.random() * 0.4
            img[y, x] = from_palette(p, np.array([v]))[0]
    for x in rng.choice(T, 4, replace=False):
        img[:, x] *= 0.75
    return finish(img)


def t_log_top(rng):
    img = np.zeros((T, T, 3), np.float32)
    ring = pal('#8a6238', '#a0754a', '#b58a5a')
    for y in range(T):
        for x in range(T):
            r = np.hypot(x - 7.5, y - 7.5)
            v = (np.sin(r * 1.6) * 0.5 + 0.5) * 0.8 + rng.random() * 0.2
            img[y, x] = from_palette(ring, np.array([v]))[0]
    bark = hexc('#4d341f')
    img[0, :] = bark
    img[-1, :] = bark
    img[:, 0] = bark
    img[:, -1] = bark
    return finish(img)


def t_leaves(rng, kind='pine'):
    if kind == 'pine':
        p = pal('#173320', '#1e3f25', '#264b2a', '#2f5a30', '#3a6a35', '#4a7d3d')
    elif kind == 'pine_light':
        p = pal('#24472a', '#2d5630', '#386636', '#46783d', '#578b45', '#6a9e4f')
    else:
        p = pal('#2f5e22', '#3b6f2a', '#477f31', '#549138', '#62a240', '#77b54d')
    v = fbm(rng, T, T, (4, 2), (0.5, 0.5)) * 0.55 + rng.random((T, T)) * 0.45
    img = from_palette(p, v)
    # dark holes
    for _ in range(14):
        x, y = rng.integers(0, T, 2)
        img[y, x] = p[0] * 0.75
    for _ in range(8):
        x, y = rng.integers(0, T, 2)
        img[y, x] = p[-1] * 1.08
    return finish(img)


def t_snow(rng):
    p = pal('#dde5ee', '#e7edf3', '#f0f4f8', '#f7f9fb', '#ffffff')
    v = fbm(rng, T, T, (8, 4, 2)) * 0.6 + rng.random((T, T)) * 0.4
    return finish(from_palette(p, v))


def t_snow_side(rng):
    img = t_cliff(rng)[:, :, :3].astype(np.float32)
    sp = pal('#dfe6ee', '#e9eef4', '#f4f7fa')
    for x in range(T):
        d = rng.integers(3, 7)
        for y in range(d):
            img[y, x] = sp[rng.integers(0, 3)]
    return finish(img)


def t_gravel(rng):
    p = pal('#6b6560', '#7b746d', '#8a837b', '#9b948b', '#a9a299')
    v = rng.random((T, T)) * 0.7 + fbm(rng, T, T, (4, 2)) * 0.3
    return finish(from_palette(p, v))


def t_sand(rng):
    p = pal('#c6b386', '#d0bd90', '#d9c79b', '#e3d3a8')
    v = rng.random((T, T)) * 0.6 + fbm(rng, T, T, (8, 4)) * 0.4
    return finish(from_palette(p, v))


def t_riverbed(rng):
    p = pal('#6d6658', '#7a7363', '#87806f', '#958d7b', '#a59d89')
    img = from_palette(p, rng.random((T, T)) * 0.6 + fbm(rng, T, T, (4, 2)) * 0.4)
    for _ in range(6):
        x, y = rng.integers(0, T - 1, 2)
        img[y:y + 2, x:x + 2] = hexc('#b1aa98')
    return finish(img)


def t_cloth(rng, base):
    b = hexc(base)
    img = np.zeros((T, T, 3), np.float32)
    for y in range(T):
        for x in range(T):
            weave = 1.0 + (0.05 if (x + y) % 2 == 0 else -0.04) + (rng.random() - 0.5) * 0.06
            img[y, x] = b * weave
    return finish(img)


def t_iron(rng):
    p = pal('#2a2b2f', '#33353a', '#3d3f45', '#474a51')
    img = from_palette(p, rng.random((T, T)))
    img[0, :] = hexc('#5a5d65')
    return finish(img)


def t_lantern(rng):
    img = np.zeros((T, T, 3), np.float32)
    glow = pal('#ffb84a', '#ffc65e', '#ffd577', '#ffe39a', '#fff0c2')
    for y in range(T):
        for x in range(T):
            r = np.hypot(x - 7.5, y - 7.5) / 10.6
            v = 1 - r + (rng.random() - 0.5) * 0.15
            img[y, x] = from_palette(glow, np.array([np.clip(v, 0, 0.999)]))[0]
    frame = hexc('#2f2a26')
    img[0:2, :] = frame
    img[-2:, :] = frame
    img[:, 0:2] = frame
    img[:, -2:] = frame
    img[:, 7:9] = img[:, 7:9] * 0.55 + frame * 0.45
    return finish(img)


def t_window(rng, lit=True):
    img = np.zeros((T, T, 3), np.float32)
    if lit:
        glass = pal('#e89b3a', '#f0ad4a', '#f7c062', '#fcd37d')
    else:
        glass = pal('#2b3442', '#33404f', '#3d4c5d', '#4a5b6e')
    for y in range(T):
        for x in range(T):
            v = 0.3 + 0.7 * (1 - y / T) * 0.6 + rng.random() * 0.4
            img[y, x] = from_palette(glass, np.array([min(0.999, v)]))[0]
    frame = hexc('#4a2f1a')
    img[0:2, :] = frame
    img[-2:, :] = frame
    img[:, 0:2] = frame
    img[:, -2:] = frame
    img[7:9, :] = frame
    img[:, 7:9] = frame
    return finish(img)


def t_hay(rng):
    p = pal('#b8862e', '#c99a3a', '#d8ad48', '#e6c25e', '#f0d475')
    img = np.zeros((T, T, 3), np.float32)
    for y in range(T):
        for x in range(T):
            v = rng.random() * 0.6 + 0.4 * (np.sin(x * 2.2 + y * 0.3) * 0.5 + 0.5)
            img[y, x] = from_palette(p, np.array([min(.999, v)]))[0]
    img[5, :] *= 0.8
    img[11, :] *= 0.8
    return finish(img)


def t_crate(rng):
    img = t_planks(rng)[:, :, :3].astype(np.float32)
    frame = hexc('#5a3a1f')
    img[0:2, :] = frame
    img[-2:, :] = frame
    img[:, 0:2] = frame
    img[:, -2:] = frame
    for i in range(T):
        img[i, i] = frame
        if i + 1 < T:
            img[i, i + 1] = frame * 1.1
    return finish(img)


def t_wheat_block(rng):
    return t_hay(rng)


def t_banner_green(rng):
    img = t_cloth(rng, '#2f7036')[:, :, :3].astype(np.float32)
    # small white emblem (stylised tree) in the middle
    em = hexc('#e9e4d4')
    for y in range(4, 12):
        w = (y - 3) // 2
        img[y, 8 - w:8 + w] = em
    img[12:14, 7:9] = em
    return finish(img)


TILES = [
    ('grass_top', t_grass_top),
    ('grass_side', t_grass_side),
    ('dirt', t_dirt),
    ('path', t_path),
    ('stone', t_stone),
    ('cliff', t_cliff),
    ('stone_bricks', lambda r: t_stone_bricks(r)),
    ('stone_bricks_dark', lambda r: t_stone_bricks(r, True)),
    ('cobble', lambda r: t_cobble(r)),
    ('cobble_mossy', lambda r: t_cobble(r, True)),
    ('plaster', t_plaster),
    ('timber', t_timber),
    ('planks', lambda r: t_planks(r)),
    ('planks_dark', lambda r: t_planks(r, True)),
    ('slate', t_slate),
    ('log_side', t_log_side),
    ('log_top', t_log_top),
    ('pine_leaves', lambda r: t_leaves(r, 'pine')),
    ('pine_leaves_light', lambda r: t_leaves(r, 'pine_light')),
    ('oak_leaves', lambda r: t_leaves(r, 'oak')),
    ('snow', t_snow),
    ('snow_side', t_snow_side),
    ('gravel', t_gravel),
    ('sand', t_sand),
    ('riverbed', t_riverbed),
    ('cloth_white', lambda r: t_cloth(r, '#e6e4dc')),
    ('cloth_blue', lambda r: t_cloth(r, '#2d5ea6')),
    ('cloth_green', lambda r: t_cloth(r, '#2f7036')),
    ('banner_green', t_banner_green),
    ('iron', t_iron),
    ('lantern', t_lantern),
    ('window_lit', lambda r: t_window(r, True)),
    ('window_dark', lambda r: t_window(r, False)),
    ('hay', t_hay),
    ('crate', t_crate),
    ('cloth_red', lambda r: t_cloth(r, '#9c3b2c')),
    ('grass_side_full', t_grass_side_full),
    ('boulder', lambda r: t_boulder(r)),
    ('boulder_top', lambda r: t_boulder(r, True)),
    ('boulder_moss', t_boulder_moss),
    ('mountain_rock', t_mountain_rock),
]

TILE_INDEX = {n: i for i, (n, _) in enumerate(TILES)}

# ---------------------------------------------------------------- plants (16 x 32)

PW, PH = 16, 32


def blank_plant():
    return np.zeros((PH, PW, 4), np.float32)


def put(img, x, y, c, a=255):
    if 0 <= x < PW and 0 <= y < PH:
        img[y, x, :3] = c
        img[y, x, 3] = a


def blade(img, rng, x, h, pal_, lean=0.0):
    """Draw a single grass blade from the bottom up."""
    fx = float(x)
    for i in range(h):
        y = PH - 1 - i
        t = i / max(1, h - 1)
        c = pal_[min(len(pal_) - 1, int(t * len(pal_)))]
        c = c * (0.92 + rng.random() * 0.16)
        put(img, int(round(fx)), y, c)
        fx += lean * (0.4 + t)


GRASS_PAL = pal('#3a6f22', '#4a842b', '#5b9a33', '#6daf3c', '#82c24a', '#9bd25e')


def p_grass(rng, tall=False, density=7):
    img = blank_plant()
    n = density + (4 if tall else 0)
    for _ in range(n):
        x = rng.integers(1, PW - 1)
        h = rng.integers(10, 26) if tall else rng.integers(4, 12)
        lean = (rng.random() - 0.5) * 0.35
        blade(img, rng, x, h, GRASS_PAL, lean)
    return img


def p_flower(rng, petal, center, n=2, hmin=9, hmax=17, petal2=None):
    img = blank_plant()
    stem = pal('#3d7326', '#4b8a2e', '#5aa035')
    # a few grass blades at the base
    for _ in range(4):
        blade(img, rng, rng.integers(1, PW - 1), rng.integers(3, 8), GRASS_PAL, (rng.random() - 0.5) * 0.3)
    for k in range(n):
        x = 3 + k * 9 // max(1, n - 1) + rng.integers(-1, 2) if n > 1 else 7 + rng.integers(-1, 2)
        x = int(np.clip(x, 2, PW - 3))
        h = rng.integers(hmin, hmax)
        for i in range(h):
            put(img, x, PH - 1 - i, stem[min(2, i // 4)])
        cy = PH - 1 - h
        # leaves on stem
        put(img, x - 1, PH - 1 - h // 3, stem[1])
        put(img, x + 1, PH - 1 - h // 2, stem[2])
        # petals: plus shape
        pc = hexc(petal)
        p2 = hexc(petal2) if petal2 else pc * 0.85
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (1, -1), (-1, 1)]:
            put(img, x + dx, cy + dy, pc if abs(dx) + abs(dy) == 1 else p2)
        put(img, x - 2, cy, p2)
        put(img, x + 2, cy, p2)
        put(img, x, cy - 2, p2)
        put(img, x, cy, hexc(center))
    return img


def p_big_flowers(rng, petal, center, petal2, n=3, r=3, hmin=8, hmax=16):
    img = blank_plant()
    stem = pal('#3d7326', '#4b8a2e', '#5aa035')
    for _ in range(5):
        blade(img, rng, rng.integers(1, PW - 1), rng.integers(4, 10), GRASS_PAL, (rng.random() - 0.5) * 0.3)
    xs = np.linspace(3, PW - 4, n) + rng.uniform(-1, 1, n)
    for k in range(n):
        x = int(np.clip(round(xs[k]), r, PW - 1 - r))
        h = rng.integers(hmin, hmax)
        for i in range(h):
            put(img, x, PH - 1 - i, stem[min(2, i // 4)])
        put(img, x - 1, PH - 1 - h // 3, stem[1])
        put(img, x + 1, PH - 2 - h // 2, stem[2])
        cy = PH - 1 - h - r
        pc = hexc(petal)
        p2 = hexc(petal2)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                d = np.hypot(dx, dy)
                if d <= r + 0.3:
                    ang = np.arctan2(dy, dx)
                    if d > 1.2 and (np.cos(ang * 5) < -0.55):
                        continue  # notches between petals
                    put(img, x + dx, cy + dy, p2 if d > r - 0.6 else pc)
        put(img, x, cy, hexc(center))
        put(img, x + 1, cy, hexc(center))
        put(img, x, cy + 1, hexc(center))
        put(img, x + 1, cy + 1, hexc(center) * 0.85)
    return img


def p_lavender(rng):
    img = blank_plant()
    stem = pal('#4b7a3a', '#5a8c44')
    purp = pal('#6a4fa8', '#7d5fbf', '#9174d2', '#a68ae0')
    for _ in range(3):
        blade(img, rng, rng.integers(1, PW - 1), rng.integers(4, 9), GRASS_PAL, 0)
    for k in range(4):
        x = 2 + k * 4 + rng.integers(-1, 2)
        h = rng.integers(16, 27)
        for i in range(h):
            put(img, x, PH - 1 - i, stem[i % 2])
        for i in range(rng.integers(6, 10)):
            y = PH - 1 - h + i
            put(img, x, y, purp[rng.integers(0, 4)])
            if i % 2 == 0:
                put(img, x - 1, y, purp[rng.integers(0, 3)])
                put(img, x + 1, y + 1, purp[rng.integers(0, 3)])
    return img


def p_wheat(rng):
    img = blank_plant()
    stalk = pal('#b99a3e', '#c9a947', '#d8b952')
    head = pal('#d6a83c', '#e3b84a', '#efca5f', '#f6da7c')
    for k in range(5):
        x = 1 + k * 3 + rng.integers(0, 2)
        h = rng.integers(22, 31)
        for i in range(h):
            put(img, x, PH - 1 - i, stalk[rng.integers(0, 3)])
        for i in range(7):
            y = PH - 1 - h + i
            put(img, x, y, head[rng.integers(1, 4)])
            if i % 2 == 1:
                put(img, x - 1, y, head[rng.integers(0, 3)])
                put(img, x + 1, y, head[rng.integers(0, 3)])
    return img


def p_reeds(rng):
    img = blank_plant()
    rp = pal('#4e7a35', '#5f8f3e', '#71a248', '#86b356')
    for _ in range(6):
        x = rng.integers(1, PW - 1)
        blade(img, rng, x, rng.integers(16, 31), rp, (rng.random() - 0.5) * 0.25)
    for _ in range(2):
        x = rng.integers(3, PW - 3)
        h = rng.integers(20, 28)
        for i in range(h):
            put(img, x, PH - 1 - i, rp[1])
        for i in range(4):
            put(img, x, PH - 1 - h + i, hexc('#6b4226'))
    return img


def p_fern(rng):
    img = blank_plant()
    fp = pal('#2e5a24', '#3a6d2c', '#478235', '#56963f')
    for k in range(5):
        x0 = 8 + rng.integers(-2, 3)
        lean = (k - 2) * 0.55
        h = rng.integers(8, 15)
        fx = float(x0)
        for i in range(h):
            y = PH - 1 - i
            put(img, int(round(fx)), y, fp[min(3, i // 4)])
            if i % 2 == 0 and i > 2:
                put(img, int(round(fx)) - 1, y, fp[1])
                put(img, int(round(fx)) + 1, y, fp[2])
            fx += lean * 0.35
    return img


def p_lily(rng):
    """Lily pad drawn top-down into the upper 16x16 of the sprite (used flat)."""
    img = blank_plant()
    lp = pal('#3f7a2a', '#4c8f33', '#5aa33c')
    for y in range(16):
        for x in range(16):
            r = np.hypot(x - 7.5, y - 7.5)
            ang = np.arctan2(y - 7.5, x - 7.5)
            if r < 6.8 and not (-0.35 < ang < 0.35 and r > 1.5):
                c = lp[min(2, int((r / 7) * 3 + rng.random() * 0.8))]
                put(img, x, y, c)
    if rng.random() < 0.6:
        for dx, dy in [(0, 0), (1, 0), (0, 1), (-1, 0), (0, -1)]:
            put(img, 5 + dx, 5 + dy, hexc('#f1e6f0') if (dx, dy) != (0, 0) else hexc('#f2cf4a'))
    return img


def p_bush_small(rng):
    img = blank_plant()
    lp = pal('#2f5e22', '#3b6f2a', '#477f31', '#549138', '#62a240')
    for y in range(18, 32):
        for x in range(16):
            r = np.hypot((x - 7.5) / 7.5, (y - 25) / 7.0)
            if r < 1 - rng.random() * 0.25:
                put(img, x, y, lp[rng.integers(0, 5)])
    return img


PLANTS = [
    ('grass_a', lambda r: p_grass(r)),
    ('grass_b', lambda r: p_grass(r, density=9)),
    ('grass_c', lambda r: p_grass(r, density=5)),
    ('grass_tall_a', lambda r: p_grass(r, True)),
    ('grass_tall_b', lambda r: p_grass(r, True, 9)),
    ('daisy', lambda r: p_flower(r, '#f6f4ee', '#f2c53d', n=2)),
    ('daisy_b', lambda r: p_flower(r, '#ffffff', '#f2c53d', n=3, hmin=6, hmax=12)),
    ('buttercup', lambda r: p_flower(r, '#f5cf2e', '#e09b1a', n=3, hmin=7, hmax=14, petal2='#f0b820')),
    ('buttercup_b', lambda r: p_flower(r, '#ffd84a', '#d78c16', n=2, hmin=10, hmax=18, petal2='#f2c030')),
    ('poppy', lambda r: p_flower(r, '#e0542e', '#3a1d14', n=1, hmin=10, hmax=16, petal2='#c7401f')),
    ('lavender', p_lavender),
    ('wheat', p_wheat),
    ('reeds', p_reeds),
    ('fern', p_fern),
    ('lily', p_lily),
    ('bush', p_bush_small),
    ('bluebell', lambda r: p_flower(r, '#6f8fe0', '#e8eefc', n=2, hmin=7, hmax=13, petal2='#5a74c8')),
    ('daisy_big', lambda r: p_big_flowers(r, '#ffffff', '#f2c53d', '#e4e2da', n=2, r=3)),
    ('daisy_big_b', lambda r: p_big_flowers(r, '#fbfaf5', '#f0b72c', '#dddbd2', n=3, r=2, hmin=6, hmax=13)),
    ('yellow_big', lambda r: p_big_flowers(r, '#ffd23a', '#d9831a', '#f2b51f', n=3, r=2, hmin=7, hmax=14)),
]
PLANT_INDEX = {n: i for i, (n, _) in enumerate(PLANTS)}


def build(out_dir):
    rng = np.random.default_rng(1234)
    tiles = [fn(np.random.default_rng(1000 + i)) for i, (_, fn) in enumerate(TILES)]
    strip = np.concatenate(tiles, axis=0)
    Image.fromarray(strip, 'RGBA').save(f'{out_dir}/tiles.png')
    plants = [np.clip(fn(np.random.default_rng(5000 + i)), 0, 255).astype(np.uint8) for i, (_, fn) in enumerate(PLANTS)]
    # bleed colour into transparent pixels to avoid dark fringes with mip-maps
    fixed = []
    for p in plants:
        a = p[:, :, 3] > 0
        rgb = p[:, :, :3].astype(np.float32)
        if a.any():
            mean = rgb[a].mean(axis=0)
            rgb[~a] = mean
        fixed.append(np.dstack([rgb.astype(np.uint8), p[:, :, 3]]))
    Image.fromarray(np.concatenate(fixed, axis=0), 'RGBA').save(f'{out_dir}/plants.png')
    with open(f'{out_dir}/tiles.json', 'w') as f:
        json.dump({'tiles': [n for n, _ in TILES], 'plants': [n for n, _ in PLANTS], 'tile_size': T, 'plant_size': [PW, PH]}, f, indent=1)
    # preview sheet
    prev = np.zeros((T * 6, T * 8, 4), np.uint8)
    for i, t in enumerate(tiles[:48]):
        r, c = divmod(i, 8)
        prev[r * T:(r + 1) * T, c * T:(c + 1) * T] = t
    Image.fromarray(prev, 'RGBA').resize((T * 8 * 6, T * 6 * 6), Image.NEAREST).save(f'{out_dir}/_tiles_preview.png')
    pp = np.zeros((PH * 2, PW * 9, 4), np.uint8)
    pp[:, :, :3] = 120
    pp[:, :, 3] = 255
    for i, p in enumerate(plants[:18]):
        r, c = divmod(i, 9)
        sub = pp[r * PH:(r + 1) * PH, c * PW:(c + 1) * PW]
        a = p[:, :, 3:4] / 255.0
        sub[:, :, :3] = (p[:, :, :3] * a + sub[:, :, :3] * (1 - a)).astype(np.uint8)
    Image.fromarray(pp, 'RGBA').resize((PW * 9 * 6, PH * 2 * 6), Image.NEAREST).save(f'{out_dir}/_plants_preview.png')


if __name__ == '__main__':
    import sys
    build(sys.argv[1] if len(sys.argv) > 1 else '.')
