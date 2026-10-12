"""Shared helpers: block table, noise, geometry."""
import numpy as np

# ------------------------------------------------------------------ block ids
AIR = 0
GRASS = 1
DIRT = 2
PATH = 3
STONE = 4
CLIFF = 5
BRICKS = 6
BRICKS_DARK = 7
COBBLE = 8
COBBLE_MOSSY = 9
PLASTER = 10
TIMBER = 11
PLANKS = 12
PLANKS_DARK = 13
SLATE = 14
LOG = 15
PINE_LEAVES = 16
OAK_LEAVES = 17
SNOW = 18
SNOW_FULL = 19
GRAVEL = 20
SAND = 21
RIVERBED = 22
CLOTH_WHITE = 23
CLOTH_BLUE = 24
CLOTH_GREEN = 25
BANNER = 26
IRON = 27
LANTERN = 28
WINDOW_LIT = 29
WINDOW_DARK = 30
HAY = 31
CRATE = 32
WATER = 33
CLOTH_RED = 34
PINE_LEAVES_LIGHT = 35
GRASS_CLIFF = 36   # grass top, cliff side (mid/far terrain)
WATER_FALL = 37    # water in a cascade column
GRASS_SLOPE = 38   # far terrain: grass top, green sides
BOULDER = 39
BOULDER_MOSS = 40
MOUNTAIN_ROCK = 41
PEBBLE = 42
HOLE = 255         # occludes but never renders (LOD hand-over)

# tile name per face: (top, side, bottom), emission
BLOCK_DEFS = {
    GRASS: ('grass_top', 'grass_side', 'dirt', 0),
    DIRT: ('dirt', 'dirt', 'dirt', 0),
    PATH: ('path', 'dirt', 'dirt', 0),
    STONE: ('stone', 'stone', 'stone', 0),
    CLIFF: ('cliff', 'cliff', 'cliff', 0),
    BRICKS: ('stone_bricks', 'stone_bricks', 'stone_bricks', 0),
    BRICKS_DARK: ('stone_bricks_dark', 'stone_bricks_dark', 'stone_bricks_dark', 0),
    COBBLE: ('cobble', 'cobble', 'cobble', 0),
    COBBLE_MOSSY: ('cobble_mossy', 'cobble_mossy', 'cobble', 0),
    PLASTER: ('plaster', 'plaster', 'plaster', 0),
    TIMBER: ('timber', 'timber', 'timber', 0),
    PLANKS: ('planks', 'planks', 'planks', 0),
    PLANKS_DARK: ('planks_dark', 'planks_dark', 'planks_dark', 0),
    SLATE: ('slate', 'slate', 'slate', 0),
    LOG: ('log_top', 'log_side', 'log_top', 0),
    PINE_LEAVES: ('pine_leaves', 'pine_leaves', 'pine_leaves', 0),
    OAK_LEAVES: ('oak_leaves', 'oak_leaves', 'oak_leaves', 0),
    SNOW: ('snow', 'snow_side', 'cliff', 0),
    SNOW_FULL: ('snow', 'snow', 'snow', 0),
    GRAVEL: ('gravel', 'gravel', 'gravel', 0),
    SAND: ('sand', 'sand', 'sand', 0),
    RIVERBED: ('riverbed', 'riverbed', 'riverbed', 0),
    CLOTH_WHITE: ('cloth_white', 'cloth_white', 'cloth_white', 0),
    CLOTH_BLUE: ('cloth_blue', 'cloth_blue', 'cloth_blue', 0),
    CLOTH_GREEN: ('cloth_green', 'cloth_green', 'cloth_green', 0),
    BANNER: ('cloth_green', 'banner_green', 'cloth_green', 0),
    IRON: ('iron', 'iron', 'iron', 0),
    LANTERN: ('lantern', 'lantern', 'lantern', 3.0),
    WINDOW_LIT: ('window_lit', 'window_lit', 'window_lit', 1.2),
    WINDOW_DARK: ('window_dark', 'window_dark', 'window_dark', 0),
    HAY: ('hay', 'hay', 'hay', 0),
    CRATE: ('crate', 'crate', 'crate', 0),
    CLOTH_RED: ('cloth_red', 'cloth_red', 'cloth_red', 0),
    PINE_LEAVES_LIGHT: ('pine_leaves_light', 'pine_leaves_light', 'pine_leaves_light', 0),
    GRASS_CLIFF: ('grass_top', 'cliff', 'cliff', 0),
    GRASS_SLOPE: ('grass_top', 'grass_side_full', 'grass_side_full', 0),
    BOULDER: ('boulder_top', 'boulder', 'boulder', 0),
    BOULDER_MOSS: ('boulder_moss', 'boulder', 'boulder', 0),
    MOUNTAIN_ROCK: ('mountain_rock', 'mountain_rock', 'mountain_rock', 0),
    PEBBLE: ('boulder_top', 'boulder_top', 'boulder_top', 0),
}


def block_tables(tile_index):
    top = np.zeros(256, np.int64)
    side = np.zeros(256, np.int64)
    bottom = np.zeros(256, np.int64)
    emis = np.zeros(256, np.float32)
    solid = np.zeros(256, np.bool_)
    occluder = np.zeros(256, np.bool_)
    collide = np.zeros(256, np.bool_)
    for b, (t, s, bo, e) in BLOCK_DEFS.items():
        top[b] = tile_index[t]
        side[b] = tile_index[s]
        bottom[b] = tile_index[bo]
        emis[b] = e
        solid[b] = True
        occluder[b] = True
        collide[b] = True
    occluder[HOLE] = False
    # leaves do not hide faces behind them? keep them opaque (cheaper, looks chunky)
    return dict(top=top, side=side, bottom=bottom, emis=emis, solid=solid, occluder=occluder, collide=collide)


# ------------------------------------------------------------------ noise
class Noise2D:
    """Value noise with fbm, vectorised, deterministic."""

    def __init__(self, seed, size=512):
        rng = np.random.default_rng(seed)
        self.size = size
        self.g = rng.random((size, size)).astype(np.float64)

    def value(self, x, z):
        s = self.size
        xi = np.floor(x).astype(np.int64)
        zi = np.floor(z).astype(np.int64)
        fx = x - xi
        fz = z - zi
        fx = fx * fx * (3 - 2 * fx)
        fz = fz * fz * (3 - 2 * fz)
        x0 = xi % s
        z0 = zi % s
        x1 = (xi + 1) % s
        z1 = (zi + 1) % s
        g = self.g
        a = g[z0, x0]
        b = g[z0, x1]
        c = g[z1, x0]
        d = g[z1, x1]
        return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fz

    def fbm(self, x, z, scale, octaves=4, lac=2.0, gain=0.5):
        amp = 1.0
        freq = 1.0 / scale
        tot = 0.0
        norm = 0.0
        for o in range(octaves):
            tot = tot + self.value(x * freq + o * 31.7, z * freq - o * 17.3) * amp
            norm += amp
            amp *= gain
            freq *= lac
        return tot / norm

    def ridged(self, x, z, scale, octaves=5):
        amp = 1.0
        freq = 1.0 / scale
        tot = 0.0
        norm = 0.0
        w = 1.0
        for o in range(octaves):
            n = self.value(x * freq + o * 13.1, z * freq + o * 7.7)
            n = 1.0 - np.abs(n * 2 - 1)
            n = n * n * w
            w = np.clip(n * 1.6, 0, 1)
            tot = tot + n * amp
            norm += amp
            amp *= 0.5
            freq *= 2.03
        return tot / norm


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def dist_polyline(px, pz, pts):
    """Distance from points (arrays) to polyline; also returns param t along the line (in metres)."""
    pts = np.asarray(pts, np.float64)
    best = np.full(np.shape(px), 1e9)
    best_s = np.zeros(np.shape(px))
    acc = 0.0
    for i in range(len(pts) - 1):
        ax, az = pts[i]
        bx, bz = pts[i + 1]
        dx, dz = bx - ax, bz - az
        L2 = dx * dx + dz * dz
        L = np.sqrt(L2)
        t = np.clip(((px - ax) * dx + (pz - az) * dz) / L2, 0, 1)
        qx = ax + t * dx
        qz = az + t * dz
        d = np.hypot(px - qx, pz - qz)
        m = d < best
        best = np.where(m, d, best)
        best_s = np.where(m, acc + t * L, best_s)
        acc += L
    return best, best_s


def polyline_length(pts):
    pts = np.asarray(pts, np.float64)
    return float(np.sum(np.hypot(*np.diff(pts, axis=0).T)))
