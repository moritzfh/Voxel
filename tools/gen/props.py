"""Fine voxel props (0.125 m voxels, 32 px per metre texture density)."""
import numpy as np
import common as C

PV = 0.125  # prop voxel size


def grid(sx, sy, sz):
    """size in metres -> empty grid"""
    return np.zeros((int(round(sx / PV)), int(round(sy / PV)), int(round(sz / PV))), np.uint8)


def box(v, x0, y0, z0, x1, y1, z1, b):
    """metre coords inside the model grid"""
    i0, j0, k0 = [int(round(a / PV)) for a in (x0, y0, z0)]
    i1, j1, k1 = [int(round(a / PV)) for a in (x1, y1, z1)]
    v[max(0, i0):i1, max(0, j0):j1, max(0, k0):k1] = b


def fence(length=2.0):
    """Fence segment along +x from 0..length, posts at both ends; origin at (0,0,center)."""
    v = grid(length + 0.25, 1.25, 0.25)
    box(v, 0, 0, 0, 0.25, 1.25, 0.25, C.LOG)
    box(v, length, 0, 0, length + 0.25, 1.25, 0.25, C.LOG)
    box(v, 0.25, 0.75, 0.0625, length, 0.95, 0.1875, C.PLANKS)
    box(v, 0.25, 0.3, 0.0625, length, 0.5, 0.1875, C.PLANKS)
    return v, (0.0, 0.0, -0.125)


def fence_post():
    v = grid(0.25, 1.375, 0.25)
    box(v, 0, 0, 0, 0.25, 1.375, 0.25, C.LOG)
    return v, (-0.125, 0, -0.125)


def lantern_post(height=3.25, arm=1.0):
    """Post with an arm towards +x and a hanging lantern. Origin at post base centre."""
    v = grid(arm + 0.875, height + 0.5, 0.75)
    box(v, 0, 0, 0.125, 0.375, 0.25, 0.625, C.COBBLE)
    box(v, 0.0625, 0, 0.1875, 0.3125, height, 0.4375 + 0.125, C.LOG)
    # cross arm
    box(v, 0.0, height - 0.375, 0.25, arm + 0.375, height - 0.125, 0.5, C.TIMBER)
    box(v, 0.3125, height - 0.75, 0.3125, 0.4375, height - 0.375, 0.4375, C.TIMBER)  # brace
    # hanging lantern
    lx = arm + 0.0625
    box(v, lx + 0.0625, height - 0.6, 0.3125, lx + 0.1875, height - 0.375, 0.4375, C.IRON)
    box(v, lx - 0.1875, height - 1.25, 0.0625, lx + 0.4375, height - 0.625, 0.6875, C.LANTERN)
    box(v, lx - 0.25, height - 0.625, 0.0, lx + 0.5, height - 0.5, 0.75, C.IRON)
    box(v, lx - 0.125, height - 0.5, 0.125, lx + 0.375, height - 0.4375, 0.625, C.IRON)
    box(v, lx - 0.25, height - 1.375, 0.0, lx + 0.5, height - 1.25, 0.75, C.IRON)
    light = (lx + 0.125 - 0.1875, height - 0.875, 0.375 - 0.375)
    return v, (-0.1875, 0, -0.375), light


def lantern_pole(height=2.75):
    """Simple pole with a lantern box on top (bridge / square)."""
    v = grid(0.5, height + 0.75, 0.5)
    box(v, 0.125, 0, 0.125, 0.375, height, 0.375, C.LOG)
    box(v, 0.0625, height, 0.0625, 0.4375, height + 0.0625, 0.4375, C.IRON)
    box(v, 0.0625, height + 0.0625, 0.0625, 0.4375, height + 0.5, 0.4375, C.LANTERN)
    box(v, 0.0, height + 0.5, 0.0, 0.5, height + 0.625, 0.5, C.IRON)
    return v, (-0.25, 0, -0.25), (0.0, height + 0.3, 0.0)


def wall_lantern():
    """Bracket + lantern sticking out along +z from a wall at z=0."""
    v = grid(0.5, 0.875, 0.625)
    box(v, 0.1875, 0.625, 0.0, 0.3125, 0.75, 0.375, C.IRON)
    box(v, 0.0625, 0.125, 0.25, 0.4375, 0.5625, 0.5625, C.LANTERN)
    box(v, 0.0, 0.5625, 0.1875, 0.5, 0.6875, 0.625, C.IRON)
    box(v, 0.0, 0.0, 0.1875, 0.5, 0.125, 0.625, C.IRON)
    return v, (-0.25, 0, 0.0), (0.0, 0.35, 0.42)


def barrel():
    v = grid(0.625, 0.875, 0.625)
    c = 0.3125
    for i in range(v.shape[0]):
        for k in range(v.shape[2]):
            x = (i + 0.5) * PV - c
            z = (k + 0.5) * PV - c
            r = np.hypot(x, z)
            for j in range(v.shape[1]):
                y = (j + 0.5) * PV
                rr = 0.27 + 0.04 * np.sin(np.pi * y / 0.875)
                if r < rr:
                    v[i, j, k] = C.PLANKS
                    if j in (1, 5) and r > rr - 0.13:
                        v[i, j, k] = C.IRON
    return v, (-c, 0, -c)


def crate():
    v = grid(0.5, 0.5, 0.5)
    box(v, 0, 0, 0, 0.5, 0.5, 0.5, C.CRATE)
    return v, (-0.25, 0, -0.25)


def stall(awning=(C.CLOTH_BLUE, C.CLOTH_WHITE), width=4.0, depth=2.5):
    """Market stall facing +z. Origin at front-centre on the ground."""
    v = grid(width + 0.5, 3.5, depth + 0.75)
    W, D = width, depth
    for px in (0.0, W):
        for pz in (0.0, D - 0.25):
            box(v, px, 0, pz, px + 0.25, 2.75 if pz == 0 else 3.0, pz + 0.25, C.LOG)
    # counter
    box(v, 0.25, 0, 0.25, W, 1.0, 1.0, C.PLANKS)
    box(v, 0.125, 1.0, 0.125, W + 0.125, 1.125, 1.125, C.PLANKS_DARK)
    # goods on the counter
    rng = np.random.default_rng(3)
    x = 0.4
    while x < W - 0.4:
        col = rng.choice([C.CLOTH_RED, C.HAY, C.OAK_LEAVES, C.CRATE, C.CLOTH_GREEN])
        box(v, x, 1.125, 0.375, x + 0.375, 1.375 if col != C.CRATE else 1.5, 0.875, col)
        x += 0.5
    # back shelf
    box(v, 0.25, 0, D - 0.75, W, 1.5, D - 0.25, C.PLANKS)
    box(v, 0.5, 1.5, D - 0.6, 1.1, 1.85, D - 0.3, C.HAY)
    box(v, 2.6, 1.5, D - 0.6, 3.1, 1.75, D - 0.3, C.CRATE)
    # awning sloping towards the front, stripes along x
    stripe = 0.5
    for i in range(int(round((W + 0.5) / PV))):
        xm = i * PV
        b = awning[int(xm / stripe) % 2]
        for k in range(int(round((D + 0.75) / PV))):
            zm = k * PV - 0.5
            y = 3.25 - 0.4 * (D + 0.25 - zm) / (D + 0.75) - 0.35 * max(0.0, (0.75 - zm)) / 1.25
            j = int(y / PV)
            if 0 <= j < v.shape[1] and 0 <= k < v.shape[2]:
                v[i, j, k] = b
                v[i, j - 1, k] = b
    # valance at the front edge
    for i in range(int(round((W + 0.5) / PV))):
        xm = i * PV
        b = awning[int(xm / stripe) % 2]
        if (i % 4) != 3:
            v[i, int(2.5 / PV):int(2.75 / PV), 0] = b
    return v, (-(W + 0.25) / 2, 0, 0.0)


def well():
    v = grid(2.25, 3.25, 2.25)
    c = 1.125
    for i in range(v.shape[0]):
        for k in range(v.shape[2]):
            x = (i + 0.5) * PV - c
            z = (k + 0.5) * PV - c
            r = np.hypot(x, z)
            if 0.62 < r < 1.0:
                v[i, :int(0.875 / PV), k] = C.COBBLE
            if r <= 0.62:
                v[i, :int(0.3 / PV), k] = C.COBBLE
    for px in (0.15, 1.85):
        box(v, px, 0.875, 1.0, px + 0.25, 2.5, 1.25, C.LOG)
    box(v, 0.15, 2.25, 1.0625, 2.1, 2.375, 1.1875, C.LOG)
    # little roof
    for j, (z0, z1) in enumerate([(0.25, 2.0), (0.5, 1.75), (0.75, 1.5), (1.0, 1.25)]):
        box(v, 0.0, 2.5 + j * 0.125 * 2, z0, 2.25, 2.75 + j * 0.25, z1, C.PLANKS_DARK if j < 3 else C.LOG)
    box(v, 0.95, 1.4, 1.0, 1.3, 1.8, 1.25, C.PLANKS)  # bucket
    return v, (-c, 0, -c)


def banner_pole(height=4.0):
    v = grid(1.25, height + 0.25, 0.25)
    box(v, 0, 0, 0, 0.25, height + 0.25, 0.25, C.LOG)
    box(v, 0.25, height - 0.25, 0, 1.25, height, 0.25, C.TIMBER)
    box(v, 0.375, height - 2.5, 0.0625, 1.125, height - 0.25, 0.1875, C.BANNER)
    box(v, 0.375, height - 2.75, 0.0625, 0.625, height - 2.5, 0.1875, C.CLOTH_GREEN)
    box(v, 0.875, height - 2.75, 0.0625, 1.125, height - 2.5, 0.1875, C.CLOTH_GREEN)
    return v, (-0.125, 0, -0.125)


def wall_banner(h=2.5):
    """Hanging cloth banner on a wall (faces +z)."""
    v = grid(1.0, h + 0.25, 0.125)
    box(v, 0, h, 0, 1.0, h + 0.25, 0.125, C.TIMBER)
    box(v, 0.125, 0.25, 0, 0.875, h, 0.125, C.BANNER)
    box(v, 0.125, 0.0, 0, 0.375, 0.25, 0.125, C.CLOTH_GREEN)
    box(v, 0.625, 0.0, 0, 0.875, 0.25, 0.125, C.CLOTH_GREEN)
    return v, (-0.5, 0, 0)


def bench():
    v = grid(1.75, 0.625, 0.5)
    box(v, 0, 0.375, 0, 1.75, 0.5, 0.5, C.PLANKS)
    for px in (0.125, 1.375):
        box(v, px, 0, 0.125, px + 0.25, 0.375, 0.375, C.LOG)
    return v, (-0.875, 0, -0.25)


def signpost():
    v = grid(1.0, 2.25, 0.25)
    box(v, 0.375, 0, 0, 0.625, 2.25, 0.25, C.LOG)
    box(v, 0.0, 1.5, 0.0625, 1.0, 1.875, 0.1875, C.PLANKS)
    return v, (-0.5, 0, -0.125)


def rail_segment(length=2.0):
    """Bridge railing: post + two rails (thicker than a fence)."""
    v = grid(length + 0.375, 1.25, 0.375)
    box(v, 0, 0, 0, 0.375, 1.25, 0.375, C.LOG)
    box(v, length, 0, 0, length + 0.375, 1.25, 0.375, C.LOG)
    box(v, 0.375, 0.875, 0.0625, length, 1.125, 0.3125, C.PLANKS_DARK)
    box(v, 0.375, 0.375, 0.0625, length, 0.5625, 0.3125, C.PLANKS_DARK)
    return v, (0.0, 0.0, -0.1875)


def rock(seed, size=1.0):
    rng = np.random.default_rng(seed)
    n = int(round(size / PV / 2)) * 2 + 2
    v = np.zeros((n, n, n), np.uint8)
    c = (n - 1) / 2
    g = np.indices(v.shape).astype(np.float64)
    d = np.sqrt(((g[0] - c) / (n / 2)) ** 2 + ((g[1] - 0.2 * n) / (n * 0.42)) ** 2 + ((g[2] - c) / (n / 2.2)) ** 2)
    d += (rng.random(v.shape) - 0.5) * 0.12
    v[(d < 0.95) & (g[1] >= 0)] = C.STONE
    return v, (-c * PV, 0, -c * PV)


def flowerbox(seed=0):
    """Window flower box sticking out along +z from a wall at z=0."""
    rng = np.random.default_rng(seed)
    v = grid(1.25, 0.625, 0.375)
    box(v, 0.0, 0.0, 0.0, 1.25, 0.25, 0.375, C.PLANKS_DARK)
    box(v, 0.125, 0.125, 0.0, 1.125, 0.25, 0.25, C.DIRT)
    cols = [C.CLOTH_RED, C.HAY, C.CLOTH_WHITE, C.CLOTH_RED, C.CLOTH_BLUE]
    for i in range(10):
        for k in range(3):
            if rng.random() < 0.85:
                b = C.OAK_LEAVES if rng.random() < 0.45 else cols[rng.integers(0, len(cols))]
                h = 1 + (rng.random() < 0.4)
                v[i, 2:2 + h, k] = b
    # trailing leaves over the front edge
    for i in range(0, 10, 3):
        if rng.random() < 0.7:
            v[i, 0:2, 2] = C.OAK_LEAVES
    return v, (-0.625, 0, 0.0)


def bunting(length, drop, sag=0.6, seed=0):
    """String of pennants from (0,0,0) along +x to (length, -drop, 0)."""
    rng = np.random.default_rng(seed)
    N = int(round(length / PV)) + 1
    depth_total = drop + sag + 0.6
    Y = int(np.ceil(depth_total / PV)) + 2
    v = np.zeros((N, Y, 1), np.uint8)
    cols = [C.CLOTH_RED, C.HAY, C.CLOTH_BLUE, C.CLOTH_GREEN, C.CLOTH_WHITE]
    ys = []
    for i in range(N):
        t = i / max(1, N - 1)
        yy = drop * t + sag * 4 * t * (1 - t)
        j = Y - 1 - int(round(yy / PV))
        ys.append(j)
        v[i, j, 0] = C.TIMBER
        if i > 0 and abs(ys[i - 1] - j) > 1:
            lo, hi = sorted((ys[i - 1], j))
            v[i, lo:hi, 0] = C.TIMBER
    c = 0
    for i in range(2, N - 4, 5):
        col = cols[c % len(cols)]
        c += 1
        j = ys[i + 1]
        for dx in range(4):
            if 0 <= j - 1 < Y:
                v[i + dx, j - 1, 0] = col
        for dx in (1, 2):
            if 0 <= j - 2 < Y:
                v[i + dx, j - 2, 0] = col
        if 0 <= j - 3 < Y and rng.random() < 0.5:
            v[i + 1 + rng.integers(0, 2), j - 3, 0] = col
    return v, (-0.5 * PV, -(Y - 0.5) * PV, -0.5 * PV)


def cart():
    """Hand cart loaded with hay, handles towards +x."""
    v = grid(2.75, 1.75, 1.5)
    box(v, 0.25, 0.5, 0.25, 2.0, 0.75, 1.25, C.PLANKS)
    box(v, 0.25, 0.75, 0.25, 2.0, 1.125, 0.375, C.PLANKS_DARK)
    box(v, 0.25, 0.75, 1.125, 2.0, 1.125, 1.25, C.PLANKS_DARK)
    box(v, 0.25, 0.75, 0.25, 0.375, 1.125, 1.25, C.PLANKS_DARK)
    box(v, 0.5, 0.75, 0.375, 1.75, 1.5, 1.125, C.HAY)
    box(v, 2.0, 0.625, 0.375, 2.75, 0.75, 0.5, C.LOG)
    box(v, 2.0, 0.625, 1.0, 2.75, 0.75, 1.125, C.LOG)
    # wheels
    for zz in (0.0, 1.375):
        for i in range(v.shape[0]):
            for j in range(v.shape[1]):
                x = (i + 0.5) * PV - 1.125
                y = (j + 0.5) * PV - 0.45
                r = np.hypot(x, y)
                if r < 0.45:
                    v[i, j, int(zz / PV)] = C.PLANKS_DARK if r > 0.3 or r < 0.1 else C.PLANKS
    box(v, 0.75, 0.375, 0.125, 1.5, 0.5, 1.375, C.LOG)
    return v, (-1.375, 0, -0.75)


def hay_bale():
    v = grid(1.0, 0.75, 0.75)
    box(v, 0, 0, 0, 1.0, 0.75, 0.75, C.HAY)
    return v, (-0.5, 0, -0.375)


def sack_pile():
    v = grid(1.25, 0.75, 1.0)
    box(v, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, C.CLOTH_WHITE)
    box(v, 0.625, 0.0, 0.125, 1.125, 0.5, 0.625, C.CLOTH_WHITE)
    box(v, 0.25, 0.5, 0.125, 0.75, 0.75, 0.5, C.CLOTH_WHITE)
    box(v, 0.125, 0.0, 0.625, 0.625, 0.375, 1.0, C.HAY)
    return v, (-0.625, 0, -0.5)


PROPS = {
    'fence': fence,
    'fence_post': fence_post,
    'lantern_post': lambda: lantern_post(2.85)[:2],
    'lantern_pole': lambda: lantern_pole()[:2],
    'wall_lantern': lambda: wall_lantern()[:2],
    'barrel': barrel,
    'crate': crate,
    'stall_blue': lambda: stall((C.CLOTH_BLUE, C.CLOTH_WHITE)),
    'stall_red': lambda: stall((C.CLOTH_RED, C.CLOTH_WHITE), 3.0, 2.25),
    'well': well,
    'banner_pole': banner_pole,
    'wall_banner': wall_banner,
    'wall_banner_long': lambda: wall_banner(5.0),
    'bench': bench,
    'signpost': signpost,
    'rail': rail_segment,
    'flowerbox_a': lambda: flowerbox(1),
    'flowerbox_b': lambda: flowerbox(2),
    'flowerbox_c': lambda: flowerbox(3),
    'cart': cart,
    'hay_bale': hay_bale,
    'sacks': sack_pile,
}

# light offsets (model space, before origin shift) for lantern props
LIGHT_OFFSETS = {
    'lantern_post': lantern_post(2.85)[2],
    'lantern_pole': lantern_pole()[2],
    'wall_lantern': wall_lantern()[2],
}
