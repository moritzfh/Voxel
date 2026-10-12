"""Voxel flora: trees at 12.5 cm, plants and flowers at 6.25 cm (material id grids for models.mesh_model)."""
import numpy as np
import common as C
import vox as VX

TV = 0.125      # tree voxel size
PV2 = 0.03125   # plant voxel size


def clump_noise(rng, shape, cell):
    """Blocky random field in [0,1): independent values per cell^3 block (nearest upsampling)."""
    cs = [max(1, (s + cell - 1) // cell) for s in shape]
    g = rng.random(cs)
    for ax, s in enumerate(shape):
        g = np.repeat(g, cell, axis=ax)
        g = np.take(g, np.arange(s), axis=ax)
    return g


def smooth_noise(rng, shape, cell):
    """Trilinear value noise in [0,1]."""
    cs = [s // cell + 2 for s in shape]
    g = rng.random(cs)
    idx = [np.arange(s) / cell for s in shape]
    i0 = [np.floor(a).astype(int) for a in idx]
    f = [a - b for a, b in zip(idx, i0)]
    f = [t * t * (3 - 2 * t) for t in f]
    X0, Y0, Z0 = np.meshgrid(*i0, indexing='ij')
    FX, FY, FZ = np.meshgrid(*f, indexing='ij')
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (FX if dx else 1 - FX) * (FY if dy else 1 - FY) * (FZ if dz else 1 - FZ)
                out = out + g[X0 + dx, Y0 + dy, Z0 + dz] * w
    return out


def _disc_trunk(vox, cx, cz, y0, y1, r0, r1, mat):
    X, Y, Z = vox.shape
    xs = np.arange(X)[:, None] + 0.5
    zs = np.arange(Z)[None, :] + 0.5
    for y in range(max(0, y0), min(Y, y1)):
        t = (y - y0) / max(1, y1 - y0)
        r = r0 + (r1 - r0) * t
        m = (xs - cx) ** 2 + (zs - cz) ** 2 <= r * r
        vox[:, y, :][m] = mat


def _line(vox, p0, p1, r, mat, only_air=False):
    """Thick voxel line (branches)."""
    p0 = np.asarray(p0, float)
    p1 = np.asarray(p1, float)
    L = np.linalg.norm(p1 - p0)
    n = max(2, int(L * 2))
    X, Y, Z = vox.shape
    ri = int(np.ceil(r))
    for t in np.linspace(0, 1, n):
        c = p0 + (p1 - p0) * t
        rr = r * (1 - 0.4 * t)
        for dx in range(-ri, ri + 1):
            for dy in range(-ri, ri + 1):
                for dz in range(-ri, ri + 1):
                    if dx * dx + dy * dy + dz * dz > rr * rr + 0.3:
                        continue
                    x, y, z = int(c[0] + dx), int(c[1] + dy), int(c[2] + dz)
                    if 0 <= x < X and 0 <= y < Y and 0 <= z < Z:
                        if not only_air or vox[x, y, z] == 0:
                            vox[x, y, z] = mat


# ------------------------------------------------------------------ trees (12.5 cm)
def pine(rng, height_m):
    """Layered conifer: drooping tiers of branch clumps, light needle tips, round trunk with root flare."""
    H = int(round(height_m / TV))
    R = H * 0.2
    size = int(2 * R + 10)
    Y = H + 6
    vox = np.zeros((size, Y, size), np.uint8)
    cx = cz = size / 2.0
    rt = max(1.6, H * 0.017)
    trunk_h = int(H * 0.86)
    _disc_trunk(vox, cx, cz, 0, trunk_h, rt * 1.0, rt * 0.45, C.LOG)
    _disc_trunk(vox, cx, cz, 0, 4, rt * 1.9, rt * 1.1, C.LOG)       # root flare
    xs = np.arange(size)[:, None] + 0.5 - cx
    zs = np.arange(size)[None, :] + 0.5 - cz
    d = np.hypot(xs, zs)
    ang = np.arctan2(zs, xs)
    clump = clump_noise(rng, (size, Y, size), 2)
    tipn = clump_noise(rng, (size, Y, size), 3)
    leaf0 = int(H * rng.uniform(0.2, 0.28))
    nb = rng.integers(6, 9)
    y = leaf0
    while y < H:
        t = (y - leaf0) / max(1, H - leaf0)
        rmax = R * (1 - t) ** 1.05 + 2.5
        tier = max(6, int(round(H * rng.uniform(0.075, 0.105))))
        phase = rng.uniform(0, 2 * np.pi)
        amp = rng.uniform(0.25, 0.45, nb)
        lob_amp = amp[((((ang + phase) % (2 * np.pi)) / (2 * np.pi)) * nb).astype(int) % nb]
        lobes = 1.0 + np.cos((ang + phase) * nb) * 0.35 * lob_amp + np.cos((ang + phase) * nb * 2.3) * 0.08
        for k in range(tier):
            yy = y + k
            if yy >= H:
                break
            frac = 1 - k / tier
            # tier cross-section: wide skirt at the bottom, tapering up, branch tips droop down
            r = rmax * (0.30 + 0.70 * frac ** 0.8)
            rr = r * lobes
            jitter = (clump[:, yy, :] - 0.5) * 2.2
            inside = d <= rr + jitter
            # hollow-ish underside near the trunk keeps the silhouette airy
            if k < 2:
                inside &= d > rmax * 0.25
            layer = vox[:, yy, :]
            edge = d > rr - 2.4
            mat = np.where(edge & (tipn[:, yy, :] < (0.55 if k <= 1 else 0.35)), C.PINE_LEAVES_LIGHT, C.PINE_LEAVES)
            put = inside & (layer != C.LOG)
            layer[put] = mat[put]
        # drooping tips below the tier
        for k in range(1, 4):
            yy = y - k
            if yy < 1:
                break
            r = rmax * (1.0 - 0.06 * k)
            ring = (d <= r * lobes + (clump[:, yy, :] - 0.5) * 2) & (d > r * lobes - 2.2 - k * 0.6)
            ring &= (np.cos((ang + phase) * nb) > 0.15 * k)
            layer = vox[:, yy, :]
            put = ring & (layer == 0)
            layer[put] = C.PINE_LEAVES_LIGHT if k < 2 else C.PINE_LEAVES
        y += tier - int(tier * 0.25)
    # leader at the top
    for k in range(8):
        yy = H - 2 + k
        if 0 <= yy < Y:
            r = 1.6 * (1 - k / 8) + 0.5
            m = d <= r
            vox[:, yy, :][m] = C.PINE_LEAVES if k < 5 else C.PINE_LEAVES_LIGHT
    origin = (-cx * TV, 0.0, -cz * TV)
    return vox, origin


def oak(rng, height_m, radius_m):
    """Broadleaf tree: flared trunk, a few thick branches and a lumpy canopy of leaf clumps."""
    H = int(round(height_m / TV))
    R = int(round(radius_m / TV))
    size = 2 * R + 14
    Y = H + int(R * 1.6) + 6
    vox = np.zeros((size, Y, size), np.uint8)
    cx = cz = size / 2.0
    rt = max(1.8, R * 0.11)
    _disc_trunk(vox, cx, cz, 0, H, rt, rt * 0.75, C.LOG)
    _disc_trunk(vox, cx, cz, 0, 5, rt * 2.0, rt * 1.1, C.LOG)
    blobs = [(0.0, H + R * 0.35, 0.0, R * 1.0)]
    nbl = rng.integers(5, 8)
    for i in range(nbl):
        a = i * 2 * np.pi / nbl + rng.uniform(-0.4, 0.4)
        rd = R * rng.uniform(0.45, 0.75)
        blobs.append((np.cos(a) * rd, H + rng.uniform(-0.05, 0.55) * R, np.sin(a) * rd, R * rng.uniform(0.5, 0.72)))
    for (bx, by, bz, br) in blobs[1:]:
        _line(vox, (cx, H * rng.uniform(0.6, 0.85), cz), (cx + bx * 0.8, by - br * 0.2, cz + bz * 0.8),
              max(1.0, rt * 0.6), C.LOG)
    gx, gy, gz = np.meshgrid(np.arange(size) + 0.5, np.arange(Y) + 0.5, np.arange(size) + 0.5, indexing='ij')
    n1 = smooth_noise(rng, (size, Y, size), 4)
    n2 = clump_noise(rng, (size, Y, size), 2)
    dmin = np.full(vox.shape, 9.0)
    for (bx, by, bz, br) in blobs:
        dd = np.sqrt(((gx - cx - bx) / br) ** 2 + ((gy - by) / (br * 0.78)) ** 2 + ((gz - cz - bz) / br) ** 2)
        dmin = np.minimum(dmin, dd)
    inside = dmin + (n1 - 0.5) * 0.45 + (n2 - 0.5) * 0.12 < 1.0
    # a few deep pockets so the canopy reads as clumps, not a ball
    inside &= ~((n1 < 0.22) & (dmin > 0.7))
    vox[inside & (vox == 0)] = C.OAK_LEAVES
    origin = (-cx * TV, 0.0, -cz * TV)
    return vox, origin


def bush(rng, radius_m, mat=C.OAK_LEAVES):
    R = int(round(radius_m / TV))
    size = 2 * R + 4
    Y = int(R * 1.5) + 3
    vox = np.zeros((size, Y, size), np.uint8)
    c = size / 2.0
    gx, gy, gz = np.meshgrid(np.arange(size) + 0.5, np.arange(Y) + 0.5, np.arange(size) + 0.5, indexing='ij')
    n1 = smooth_noise(rng, (size, Y, size), 3)
    d = np.sqrt(((gx - c) / R) ** 2 + ((gy - R * 0.55) / (R * 0.75)) ** 2 + ((gz - c) / R) ** 2)
    vox[(d + (n1 - 0.5) * 0.5 < 1.0) & (gy >= 0)] = mat
    return vox, (-c * TV, 0.0, -c * TV)


# ------------------------------------------------------------------ plants (6.25 cm)
def _blade(v, x, z, h, lean=(0, 0), mat=VX.PLANT_GREEN, y0=0):
    """Single voxel-wide grass blade from y0 up to h voxels, leaning by (dx, dz) at the top."""
    X, Y, Z = v.shape
    for y in range(h):
        t = y / max(1, h - 1)
        xx = int(round(x + lean[0] * t * t))
        zz = int(round(z + lean[1] * t * t))
        if 0 <= xx < X and 0 <= y0 + y < Y and 0 <= zz < Z:
            v[xx, y0 + y, zz] = mat


def grass_tuft(rng, n_blades, hmin, hmax, size=15, light=0.25):
    v = np.zeros((size, hmax + 2, size), np.uint8)
    c = size // 2
    for _ in range(n_blades):
        x = c + rng.integers(-3, 4)
        z = c + rng.integers(-3, 4)
        h = rng.integers(hmin, hmax + 1)
        lean = (rng.integers(-2, 3), rng.integers(-2, 3))
        _blade(v, x, z, h, lean)
    # tips a touch lighter (the shader handles the darker base)
    top = np.zeros(v.shape, bool)
    top[:, :-1, :] = (v[:, :-1, :] != 0) & (v[:, 1:, :] == 0)
    v[top & (rng.random(v.shape) < light * 0.3)] = VX.WHEAT
    return v, (-(c + 0.5) * PV2, 0.0, -(c + 0.5) * PV2)


def flower(rng, petal, center=VX.FLOWER_CENTER, n=3, hmin=6, hmax=10, size=11, big=False):
    """Small cluster of stems with cross-shaped blossoms, plus a few leaves."""
    v = np.zeros((size, hmax + 4, size), np.uint8)
    c = size // 2
    for i in range(n):
        x = c + (0 if i == 0 else rng.integers(-5, 6))
        z = c + (0 if i == 0 else rng.integers(-5, 6))
        h = rng.integers(hmin, hmax + 1)
        _blade(v, x, z, h)
        # blossom
        y = h
        if big:
            for dx in range(-2, 3):
                for dz in range(-2, 3):
                    if abs(dx) + abs(dz) <= 2 and 0 <= x + dx < size and 0 <= z + dz < size:
                        v[x + dx, y, z + dz] = petal
            v[x, y, z] = center
            if y + 1 < v.shape[1]:
                v[x, y + 1, z] = center
        else:
            for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < size and 0 <= z + dz < size:
                    v[x + dx, y, z + dz] = petal
            v[x, y, z] = center
        # leaves
        for _ in range(2):
            ly = rng.integers(2, max(3, h // 2))
            dx, dz = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.integers(0, 4)]
            for q in (1, 2):
                if 0 <= x + dx * q < size and 0 <= z + dz * q < size:
                    v[x + dx * q, ly + q - 1, z + dz * q] = VX.PLANT_GREEN
    # base grass
    for _ in range(7):
        _blade(v, c + rng.integers(-5, 6), c + rng.integers(-5, 6), rng.integers(3, 9),
               lean=(rng.integers(-2, 3), rng.integers(-2, 3)))
    return v, (-(c + 0.5) * PV2, 0.0, -(c + 0.5) * PV2)


def bell_flower(rng, petal, n=3, hmin=7, hmax=11, size=9):
    """Bluebell / lavender: stems with stacked blossoms along the upper part."""
    v = np.zeros((size, hmax + 3, size), np.uint8)
    c = size // 2
    for i in range(n):
        x = c + (0 if i == 0 else rng.integers(-4, 5))
        z = c + (0 if i == 0 else rng.integers(-4, 5))
        h = rng.integers(hmin, hmax + 1)
        _blade(v, x, z, h)
        for y in range(int(h * 0.55), h + 1):
            v[x, y, z] = petal
            if (y - h) % 2 == 0:
                dx, dz = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.integers(0, 4)]
                if 0 <= x + dx < size and 0 <= z + dz < size:
                    v[x + dx, y, z + dz] = petal
    for _ in range(6):
        _blade(v, c + rng.integers(-4, 5), c + rng.integers(-4, 5), rng.integers(3, 9))
    return v, (-(c + 0.5) * PV2, 0.0, -(c + 0.5) * PV2)


def wheat(rng, n=8, size=13):
    v = np.zeros((size, 40, size), np.uint8)
    c = size // 2
    for i in range(n):
        x = c + rng.integers(-5, 6)
        z = c + rng.integers(-5, 6)
        h = rng.integers(24, 34)
        _blade(v, x, z, h, mat=VX.WHEAT)
        for y in range(h - 8, h + 1):
            v[x, y, z] = VX.WHEAT
            if y % 2 == 0 and 0 <= x + 1 < size:
                v[x + 1, y, z] = VX.WHEAT
            if y % 2 == 1 and 0 <= x - 1 < size:
                v[x - 1, y, z] = VX.WHEAT
    return v, (-(c + 0.5) * PV2, 0.0, -(c + 0.5) * PV2)


def reeds(rng, n=9, size=13):
    v = np.zeros((size, 60, size), np.uint8)
    c = size // 2
    for i in range(n):
        x = c + rng.integers(-5, 6)
        z = c + rng.integers(-5, 6)
        h = rng.integers(32, 54)
        _blade(v, x, z, h, lean=(rng.integers(-2, 3), rng.integers(-2, 3)))
        if rng.random() < 0.6:
            lx = int(round(x))
            for y in range(h - 12, h - 2):
                for dx in (0, 1):
                    if 0 <= lx + dx < size:
                        v[lx + dx, y, z] = VX.REED
    return v, (-(c + 0.5) * PV2, 0.0, -(c + 0.5) * PV2)


def fern(rng, size=25):
    v = np.zeros((size, 16, size), np.uint8)
    c = size // 2
    for a in range(7):
        ang = a * 2 * np.pi / 7 + rng.uniform(-0.3, 0.3)
        L = rng.uniform(9, 12)
        for s_ in np.linspace(0, L, 40):
            x = int(round(c + np.cos(ang) * s_))
            z = int(round(c + np.sin(ang) * s_))
            y = int(round(1 + s_ * 0.95 - 0.07 * s_ * s_))
            if 0 <= x < size and 0 <= z < size and 0 <= y < 16:
                v[x, y, z] = VX.PLANT_GREEN
                # leaflets sideways
                if int(s_ * 3) % 2 == 0 and s_ > 2:
                    for side in (-1, 1):
                        xx = int(round(x - np.sin(ang) * side))
                        zz = int(round(z + np.cos(ang) * side))
                        if 0 <= xx < size and 0 <= zz < size:
                            v[xx, y, zz] = VX.PLANT_GREEN
    v[c, 0, c] = VX.PLANT_GREEN
    return v, (-(c + 0.5) * PV2, 0.0, -(c + 0.5) * PV2)


def lily(rng, size=22):
    v = np.zeros((size, 2, size), np.uint8)
    c = size / 2
    xs = np.arange(size)[:, None] + 0.5 - c
    zs = np.arange(size)[None, :] + 0.5 - c
    d = np.hypot(xs, zs)
    ang = np.arctan2(zs, xs)
    pad = (d < c - 0.6) & ~((np.abs(ang - 0.4) < 0.3) & (d > 1))
    v[:, 0, :][pad] = VX.LILY
    if rng.random() < 0.7:
        for dx, dz in ((0, 0), (1, 0), (0, 1), (1, 1), (-1, 0), (0, -1)):
            v[int(c) + dx, 1, int(c) + dz] = VX.FLOWER_WHITE
    return v, (-c * PV2, 0.0, -c * PV2)


def plant_models():
    """name -> (vox, origin). Names match the old sprite kinds used by scatter.py. Voxels are 1/32 m."""
    rng = np.random.default_rng(404)
    out = {}
    out['grass_a'] = grass_tuft(rng, 12, 6, 12, size=15)
    out['grass_b'] = grass_tuft(rng, 15, 8, 15, size=15)
    out['grass_c'] = grass_tuft(rng, 10, 4, 9, size=13)
    out['grass_tall_a'] = grass_tuft(rng, 14, 16, 28, size=17)
    out['grass_tall_b'] = grass_tuft(rng, 16, 18, 32, size=17)
    out['daisy'] = flower(rng, VX.FLOWER_WHITE, n=4, hmin=10, hmax=18, size=17)
    out['daisy_b'] = flower(rng, VX.FLOWER_WHITE, n=5, hmin=9, hmax=15, size=17)
    out['daisy_big'] = flower(rng, VX.FLOWER_WHITE, n=3, hmin=14, hmax=22, size=19, big=True)
    out['daisy_big_b'] = flower(rng, VX.FLOWER_WHITE, n=4, hmin=12, hmax=20, size=19, big=True)
    out['buttercup'] = flower(rng, VX.FLOWER_YELLOW, center=VX.FLOWER_YELLOW, n=4, hmin=10, hmax=18, size=17)
    out['buttercup_b'] = flower(rng, VX.FLOWER_YELLOW, center=VX.FLOWER_CENTER, n=5, hmin=9, hmax=16, size=17)
    out['yellow_big'] = flower(rng, VX.FLOWER_YELLOW, n=3, hmin=14, hmax=22, size=19, big=True)
    out['poppy'] = flower(rng, VX.FLOWER_RED, center=C.IRON, n=3, hmin=14, hmax=22, size=17, big=True)
    out['bluebell'] = bell_flower(rng, VX.FLOWER_BLUE, n=4, hmin=12, hmax=20, size=13)
    out['lavender'] = bell_flower(rng, VX.FLOWER_PURPLE, n=7, hmin=16, hmax=24, size=13)
    out['wheat'] = wheat(rng, n=8, size=13)
    out['reeds'] = reeds(rng, n=9, size=13)
    out['fern'] = fern(rng, size=25)
    out['bush'] = bush(rng, 0.45)
    out['lily'] = lily(rng, size=22)
    return out


PLANT_VS = {'bush': TV}


# ------------------------------------------------------------------ clouds (2 m voxels)
CLOUD_VS = 2.0


def cloud(rng, w_m, d_m):
    """Flat-bottomed cumulus made of blobs; origin at the bottom centre."""
    W = int(w_m / CLOUD_VS)
    D = int(d_m / CLOUD_VS)
    Hh = int(max(W, D) * 0.45) + 4
    v = np.zeros((W + 4, Hh, D + 4), np.uint8)
    gx, gy, gz = np.meshgrid(np.arange(W + 4) + 0.5, np.arange(Hh) + 0.5, np.arange(D + 4) + 0.5, indexing='ij')
    n = smooth_noise(rng, v.shape, 3)
    inside = np.zeros(v.shape, bool)
    nb = rng.integers(5, 9)
    for i in range(nb):
        t = (i + 0.5) / nb
        bx = 2 + W * (0.15 + 0.7 * t) + rng.uniform(-2, 2)
        bz = 2 + D * 0.5 + rng.uniform(-D * 0.22, D * 0.22)
        r = min(W, D) * rng.uniform(0.28, 0.42) * (1.25 - abs(t - 0.5))
        by = r * 0.35
        d = np.sqrt(((gx - bx) / r) ** 2 + ((gy - by) / (r * 0.8)) ** 2 + ((gz - bz) / (r * 1.1)) ** 2)
        inside |= d + (n - 0.5) * 0.35 < 1.0
    inside &= gy >= 1.0
    v[inside] = VX.CLOUD
    return v, (-(W + 4) / 2 * CLOUD_VS, -CLOUD_VS, -(D + 4) / 2 * CLOUD_VS)
