"""Height field + surface materials for Grünweiten.

World axes: x = east, y = up, z = south (camera looks north = -z at start).
Player spawn at (0, 0, 0).
"""
import numpy as np
from common import Noise2D, smoothstep, dist_polyline
import common as C

N1 = Noise2D(11)
N2 = Noise2D(22)
N3 = Noise2D(33)
N4 = Noise2D(44)

# ------------------------------------------------------------------ river
# (x, z, water level) downstream order. Levels change abruptly at cascades.
RIVER = np.array([
    (95, -300, 0.0),
    (84, -272, 0.0),
    (75, -250, 0.0),
    (70, -236, 0.0),
    (67, -224, 0.0),
    (65, -212, 0.0),
    (64, -196, 0.0),
    (64, -176, 0.0),
    (63, -152, 0.0),
    (60, -130, 0.0),
    (57, -114, 0.0),
    (52, -103, 0.0),
    (45, -88, 0.0),
    (39, -73, 0.0),
    (34, -62, 0.0),
    (31.5, -56, 0.0),
    (29, -50, 0.0),
    (21.5, -42, 0.0),
    (12.0, -31, 0.0),
    (9.6, -20, 0.0),
    (10.0, -8, 0.0),
    (7.5, 2, 0.0),
    (4, 14, 0.0),
    (-2, 28, 0.0),
    (-9, 44, 0.0),
    (-18, 64, 0.0),
    (-34, 100, 0.0),
    (-56, 150, 0.0),
    (-90, 220, 0.0),
])
RIVER_XZ = RIVER[:, :2]
_seg = np.hypot(*np.diff(RIVER_XZ, axis=0).T)
RIVER_S = np.concatenate([[0], np.cumsum(_seg)])
_PROFILE = None


def _build_profile():
    """Water level along the river: follows the terrain floor downstream, never rising."""
    L = RIVER_S[-1]
    ss = np.arange(0, L, 0.5)
    xs = np.interp(ss, RIVER_S, RIVER_XZ[:, 0])
    zs = np.interp(ss, RIVER_S, RIVER_XZ[:, 1])
    tx = np.gradient(xs)
    tz = np.gradient(zs)
    tl = np.hypot(tx, tz) + 1e-9
    nx, nz = -tz / tl, tx / tl
    fl = np.full(ss.shape, 1e9)
    for off in (-3.0, -1.5, 0.0, 1.5, 3.0):
        fl = np.minimum(fl, height(xs + nx * off, zs + nz * off))
    lvl = fl - 0.6
    lvl = np.minimum.accumulate(lvl)
    lvl = np.floor(lvl * 2) / 2
    # lower river (from just above the bridge) exactly one metre below the meadow
    s_low = float(np.interp(-48.0, RIVER_XZ[:, 1], RIVER_S))
    lvl = np.where(ss >= s_low, -1.0, np.maximum(lvl, -1.0))
    return ss, lvl


def river_level(s):
    global _PROFILE
    if _PROFILE is None:
        _PROFILE = _build_profile()
    ss, lv = _PROFILE
    i = np.clip(np.searchsorted(ss, s), 0, len(ss) - 1)
    return lv[i]


def river_halfwidth(s, x=None, z=None):
    # narrow upstream, wide at the bridge, moderate near the camera
    pts_s = [0, RIVER_S[4], RIVER_S[6], RIVER_S[14], RIVER_S[16], RIVER_S[18], RIVER_S[20], RIVER_S[22], RIVER_S[-1]]
    pts_w = [3.0, 4.0, 5.5, 5.0, 6.0, 7.2, 5.2, 5.0, 6.0]
    return np.interp(s, pts_s, pts_w)


# ------------------------------------------------------------------ paths
PATH_MAIN = [(0.5, 60), (0.3, 30), (0.0, 12), (-0.4, 0), (-0.8, -10), (-2.0, -20), (-3.5, -28), (-4.5, -33)]
PATH_BRIDGE = [(-2.8, -24.5), (-1.0, -23.2)]
PATH_EAST = [(21.5, -23.0), (28.0, -22.2), (36.0, -20.5), (44.0, -17.0), (56.0, -11.0), (70.0, -2.0)]
PATH_NORTH = [(-4.5, -33), (-4.0, -42), (-2.5, -54), (0.0, -66), (3.0, -80), (2.0, -96), (-2.0, -112)]
PATH_VILLAGE = [(-1.0, -6.5), (-5.0, -8.5), (-9.0, -10.5), (-13.0, -12.5), (-15.0, -15.5), (-15.2, -22.0), (-16.0, -29.0), (-19.5, -31.5), (-23.0, -32.0)]
PATH_VILLAGE2 = [(-16.0, -29.0), (-17.6, -38.0), (-17.4, -44.0), (-12.0, -44.0), (-6.0, -40.0)]
PATH_VILLAGE3 = [(-15.2, -17.0), (-19.5, -17.2), (-21.0, -16.0)]
PATH_CASTLE = [(-23.0, -32.0), (-25.5, -37.0), (-28.0, -42.0), (-29.5, -52.0), (-28.3, -61.0)]
PATHS = [(PATH_MAIN, 1.5), (PATH_BRIDGE, 1.3), (PATH_EAST, 1.3), (PATH_NORTH, 1.2), (PATH_VILLAGE, 1.2), (PATH_VILLAGE2, 1.2), (PATH_VILLAGE3, 1.0), (PATH_CASTLE, 1.0)]

# square (market place)
SQUARE = (-5.0, -32.0, 7.5)  # cx, cz, radius

CASTLE_HILL = (-30.0, -72.0)


def terrace(h, step, sharp=0.12, jitter=None):
    """Quantise into flat terraces with steep faces."""
    if jitter is not None:
        h = h + jitter * step
    k = np.floor(h / step)
    f = h / step - k
    return (k + smoothstep(1 - sharp, 1.0, f)) * step


def village_height(x, z):
    """West bank terraces where the village sits (relative heights)."""
    # u: distance west of the terrace base line (slanted so terraces follow the valley)
    u = -x - 3.6 - np.clip(-(z + 8) * 0.10, -1.5, 3.0)
    h = np.zeros_like(x)
    h = np.where(u > 0, 1.0, h)
    h = np.where(u > 4.5, 2.0, h)
    h = np.where(u > 8.5, 3.5, h)
    h = np.where(u > 21.0, 5.0, h)
    h = np.where(u > 30.0, 6.5, h)
    # beyond: rising hill
    h = h + np.clip(u - 34, 0, None) * 0.12
    # fade the terraces out to the south (meadow) and north
    fade_s = 1 - smoothstep(6, 26, z)
    return h * fade_s


def castle_hill(x, z):
    cx, cz = CASTLE_HILL
    d = np.hypot((x - cx) * 1.0, (z - cz) * 0.85)
    h = 14.5 * (1 - smoothstep(10, 34, d))
    return terrace(h, 2.0, 0.25)


VALLEY_AXIS = np.array([(-60.0, 260.0), (-30.0, 150.0), (-6.0, 60.0), (0.0, 0.0), (4.0, -60.0),
                        (24.0, -125.0), (50.0, -178.0), (66.0, -210.0), (82.0, -252.0)])
_axis_seg = np.hypot(*np.diff(VALLEY_AXIS, axis=0).T)
AXIS_S0 = float(np.sum(_axis_seg[:3]))  # arc length at the origin point


def axis_coords(x, z):
    """Arc length along valley axis (relative to spawn) and signed lateral distance (east > 0)."""
    pts = VALLEY_AXIS
    best = np.full(np.shape(x), 1e9)
    bs = np.zeros(np.shape(x))
    sgn = np.ones(np.shape(x))
    acc = 0.0
    for i in range(len(pts) - 1):
        ax, az = pts[i]
        bx, bz = pts[i + 1]
        dx, dz = bx - ax, bz - az
        L2 = dx * dx + dz * dz
        L = np.sqrt(L2)
        t = (( x - ax) * dx + (z - az) * dz) / L2
        tc = np.clip(t, 0, 1)
        if i == 0:
            tc = np.minimum(t, 1)
        if i == len(pts) - 2:
            tc = np.maximum(tc, np.where(t > 1, t, tc))
        qx = ax + tc * dx
        qz = az + tc * dz
        d = np.hypot(x - qx, z - qz)
        m = d < best
        best = np.where(m, d, best)
        bs = np.where(m, acc + tc * L, bs)
        # direction from a to b; east side = cross(dir, p-a).y < 0 ? compute sign
        cr = dx * (z - az) - dz * (x - ax)
        sgn = np.where(m, np.where(cr < 0, 1.0, -1.0), sgn)
        acc += L
    return bs - AXIS_S0, best * sgn


def warp(x, z, amp=14.0, scale=70.0):
    wx = (N3.fbm(x, z, scale, 3) - 0.5) * 2 * amp
    wz = (N4.fbm(x + 77, z - 33, scale, 3) - 0.5) * 2 * amp
    return x + wx, z + wz


def valley_height(x, z):
    xw, zw = warp(x, z, 12.0, 60.0)
    s, d = axis_coords(xw, zw)
    j1 = N1.fbm(x, z, 35, 3) - 0.5
    j2 = N2.fbm(x, z, 22, 3) - 0.5
    # valley floor along the axis
    fl = np.where(s > 32, (s - 32) * 0.072, 0.0)
    fl = np.where(s < -70, (-70 - s) * 0.07, fl)
    fl_t = terrace(fl, 3.5, 0.16, j1 * 0.7)
    soft = 1 - smoothstep(32, 46, s)
    fl = np.where(s > 0, fl_t * (1 - soft) + np.round(fl * 2) / 2 * soft, np.round(fl * 2) / 2)
    # lateral walls (east positive)
    east0 = 42 + 12 * j2 + np.clip(-s, 0, None) * 0.05
    west0 = 62 + 12 * j1
    e = np.clip(d - east0, 0, None)
    w = np.clip(-d - west0, 0, None)
    wall = e * 0.26 + np.clip(e - 60, 0, None) * 0.25 + w * 0.30 + np.clip(w - 50, 0, None) * 0.4
    # the far (north) part of the valley rims stays low so the snowy range shows above it
    cap = np.where(s > 120, 48.0, 70.0) + 25 * j2
    wall = cap * (1 - np.exp(-wall / cap))
    wall = terrace(wall, 6.0, 0.07, j2 * 0.8) * 0.8 + wall * 0.2
    # end wall (big waterfall cliff)
    endw = np.clip(s - 236 - 14 * j1, 0, None)
    # terraced, forested slopes ... except a sheer face around the waterfall
    dr, _ = dist_polyline(x, z, RIVER_XZ)
    sheer = 1 - smoothstep(7, 22, dr)
    cliff_t = 40 * smoothstep(0, 60, endw) ** 0.8 + 18 * (1 - np.exp(-endw / 160))
    cliff_t = terrace(cliff_t, 7.0, 0.08, j1 * 0.6) * 0.8 + cliff_t * 0.2
    cliff_s = 40 * smoothstep(0, 5, endw) + 16 * (1 - np.exp(-endw / 120))
    cliff_s = terrace(cliff_s, 8.0, 0.08, j1 * 0.6)
    cliff = cliff_t * (1 - sheer) + cliff_s * sheer
    return fl + np.maximum(wall, cliff)


def ring_mountains(x, z):
    """Large mountains around everything (far LOD)."""
    r = np.hypot(x * 0.9, (z + 140) * 1.0)
    base = smoothstep(330, 900, r)
    ridge = N1.ridged(x + 3000, z + 3000, 520, 5)
    hn = N2.fbm(x, z, 300, 4)
    h = base * (ridge * 300 + hn * 110 - 40)
    north = smoothstep(-500, -900, z)
    h = h + north * (N3.ridged(x, z, 380, 5) * 180 + 30)
    h = np.clip(h, 0, None)
    return terrace(h, 10.0, 0.22, (N4.fbm(x, z, 60, 3) - 0.5) * 0.6)


def cascade_ledge(x, z):
    """Terrace north-east of the bridge that creates the small cascade behind it."""
    j = (N2.fbm(x, z, 12, 3) - 0.5) * 3.0
    line = -55.0 + 0.30 * (x - 32) + j
    on = (z < line) & (x > 13 + j)
    fade = smoothstep(10, 18, x) * (1 - smoothstep(75, 95, x))
    h1 = np.where(on, 3.5, 0.0)
    line2 = line - 9 - j * 0.5
    h1 = np.where(on & (z < line2) & (x > 20), 6.0, h1)
    return h1 * fade


PEAKS = [  # x, z, height, radius
    (230.0, -1050.0, 560.0, 420.0),
    (520.0, -980.0, 480.0, 330.0),
    (20.0, -900.0, 380.0, 300.0),
    (-200.0, -860.0, 300.0, 280.0),
    (760.0, -760.0, 380.0, 280.0),
    (380.0, -720.0, 330.0, 240.0),
    (-30.0, -740.0, 330.0, 240.0),
    (130.0, -790.0, 420.0, 260.0),
]


def snow_massif(x, z):
    """Massive rock range: broad summits cut into tall vertical cliff bands with ledges."""
    h = np.zeros_like(x)
    rid = N3.ridged(x + 500, z + 500, 160, 4)
    rid2 = N1.ridged(x - 900, z + 300, 70, 4)
    for (px, pz, ph, pr) in PEAKS:
        d = np.hypot(x - px, (z - pz) * 1.1) / pr
        cone = ph * np.clip(1 - d, 0, None) ** 0.75
        h = np.maximum(h, cone * (0.6 + 0.3 * rid + 0.15 * rid2))
    # connecting range
    rng_base = smoothstep(-600, -800, z) * (200 + 120 * rid)
    h = np.maximum(h, rng_base)
    j = N4.fbm(x, z, 60, 3) - 0.5
    hc = terrace(h, 26.0, 0.06, j * 0.9)
    h2 = hc * 0.82 + h * 0.18 + rid2 * 5.0 * smoothstep(40, 120, h)
    return h2


CRAG = (150.0, -385.0, 150.0, 75.0)


def crag(x, z):
    cx, cz, ch, cr = CRAG
    d = np.hypot(x - cx, (z - cz) * 1.15) / cr
    rid = N2.ridged(x + 70, z - 40, 40, 4)
    h = ch * np.clip(1 - d, 0, None) ** 0.55 * (0.8 + 0.3 * rid)
    top = ch * 0.98
    h = np.minimum(h, top)
    return terrace(h, 6.0, 0.15, (N3.fbm(x, z, 18, 3) - 0.5) * 0.6)


def height(x, z, detail=True):
    """Terrain height (metres) before river/path/plot carving."""
    base = (N1.fbm(x, z, 14, 3) - 0.5) * 0.9
    h = valley_height(x, z) + base
    h = np.maximum(h, cascade_ledge(x, z) + base * 0.3)
    h = h + village_height(x, z)
    h = np.maximum(h, castle_hill(x, z) + base * 0.5)
    h = np.maximum(h, ring_mountains(x, z))
    h = np.maximum(h, snow_massif(x, z))
    h = np.maximum(h, crag(x, z))
    return h


def river_field(x, z):
    d, s = dist_polyline(x, z, RIVER_XZ)
    return d, s, river_level(s), river_halfwidth(s)


def path_field(x, z):
    best = np.full(np.shape(x), 1e9)
    hw = np.zeros(np.shape(x))
    for pts, w in PATHS:
        d, _ = dist_polyline(x, z, pts)
        m = d < best
        best = np.where(m, d, best)
        hw = np.where(m, w, hw)
    return best, hw


def carve(x, z, h):
    """Apply river channel, banks and the square. Returns (h, water_level or nan, kind)."""
    d, s, lvl, hw = river_field(x, z)
    water = np.full(np.shape(x), np.nan)
    # channel
    inside = d < hw
    depth = 1.6 * (1 - (d / hw) ** 2) + 0.35
    bed = lvl - depth
    # banks: terrain may not rise much above water close to the river
    bank_h = lvl + 0.6 + np.clip(d - hw, 0, None) * np.where(lvl > 3, 1.2, 0.55)
    near = d < hw + 14
    h2 = np.where(near, np.minimum(h, bank_h), h)
    # never let the bank drop below the water surface right next to the channel
    h2 = np.where((d >= hw) & (d < hw + 3.0), np.maximum(h2, lvl + 0.5), h2)
    h2 = np.where(inside, np.minimum(h2, bed), h2)
    water = np.where(inside, lvl, water)
    # square flattened
    cx, cz, r = SQUARE
    dq = np.hypot(x - cx, z - cz)
    h2 = np.where(dq < r, np.where(dq < r - 2, 0.5, np.minimum(h2, 1.0)), h2)
    return h2, water, s, d, hw
