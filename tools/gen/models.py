"""Small voxel models (trees, props, characters) meshed into standalone meshes."""
import numpy as np
import common as C
import mesher


def mesh_model(vox, blocks=None, vs=0.125, uv_unit=None, origin=(0, 0, 0), use_ao=True, seed=0, paint_vs=None,
               detail=None):
    """vox[x,y,z] material ids -> colour-voxel arrays with positions relative to origin (metres).
    The grid is padded with air so faces on the model's bounding box are not culled.
    The origin (in voxels) is rounded so the voxel grid stays aligned with model space (shader bevels)."""
    import vox as VX
    v = np.pad(vox, ((1, 1), (1, 0), (1, 1)))
    X, Y, Z = v.shape
    o_vox = np.round(np.asarray(origin, np.float64) / vs)  # origin is given in metres
    o = (o_vox - 1) * vs
    enc = VX.paint_grid(v, seed * 7 + int(o_vox[0]), int(o_vox[1]), int(o_vox[2]), paint_vs or vs,
                        (vs <= 0.13) if detail is None else detail)
    tables = VX.mesher_tables()
    return mesher.mesh_vox(enc, tables, vs, o, 0, X, 0, Z, use_ao=use_ao)


# ------------------------------------------------------------------ trees
def pine(rng, height_vox, trunk=1, light_tips=True, lod=1):
    """Layered conifer with jagged, drooping tiers. Trunk base at (0,0,0)."""
    H = height_vox
    R = max(3, int(H * 0.21))
    size = 2 * R + trunk + 4
    vox = np.zeros((size, H + 4, size), np.uint8)
    cx = size // 2 - trunk // 2
    cz = size // 2 - trunk // 2
    trunk_h = int(H * 0.85)
    vox[cx:cx + trunk, 0:trunk_h, cz:cz + trunk] = C.LOG
    leaf0 = max(2, int(H * rng.uniform(0.2, 0.3)))
    nb = 7  # branch directions per tier
    y = leaf0
    tier_i = 0
    while y < H:
        t = (y - leaf0) / max(1, H - leaf0)
        rmax = R * (1 - t) ** 1.05 + 0.9
        tier = max(2, int(round(H * rng.uniform(0.07, 0.11))))
        phase = rng.uniform(0, 2 * np.pi)
        amp = rng.uniform(0.18, 0.32, nb)
        for k in range(tier):
            yy = y + k
            if yy >= H:
                break
            frac = 1 - k / tier
            r = rmax * (0.42 + 0.58 * frac)
            ri = int(np.ceil(r * 1.3)) + 1
            for dx in range(-ri, ri + trunk):
                for dz in range(-ri, ri + trunk):
                    ex = dx - (trunk - 1) / 2
                    ez = dz - (trunk - 1) / 2
                    d = np.hypot(ex, ez)
                    ang = np.arctan2(ez, ex) + phase
                    # branchy outline: radius varies with angle
                    lobes = 1.0 + np.cos(ang * nb / 2.0) * 0.5 * amp[int((ang % (2 * np.pi)) / (2 * np.pi) * nb) % nb]
                    rr = r * lobes
                    if d <= rr + rng.uniform(-0.5, 0.3):
                        xx, zz = cx + dx, cz + dz
                        if 0 <= xx < size and 0 <= zz < size:
                            edge = d > rr - 1.2
                            b = C.PINE_LEAVES
                            if light_tips and edge and (k == 0 or rng.random() < 0.35):
                                b = C.PINE_LEAVES_LIGHT
                            if vox[xx, yy, zz] != C.LOG:
                                vox[xx, yy, zz] = b
            # drooping branch tips one voxel below the tier bottom
            if k == 0 and yy > leaf0:
                for a in range(nb):
                    ang = a * 2 * np.pi / nb - phase + rng.uniform(-0.2, 0.2)
                    rr = r * rng.uniform(0.8, 1.05)
                    xx = int(round(cx + (trunk - 1) / 2 + np.cos(ang) * rr))
                    zz = int(round(cz + (trunk - 1) / 2 + np.sin(ang) * rr))
                    if 0 <= xx < size and 0 <= zz < size and yy - 1 >= 0:
                        vox[xx, yy - 1, zz] = C.PINE_LEAVES_LIGHT
        y += tier
        tier_i += 1
    for k in range(3):
        yy = H + k - 1
        if 0 <= yy < vox.shape[1]:
            vox[cx:cx + trunk, yy, cz:cz + trunk] = C.PINE_LEAVES if k < 2 else C.PINE_LEAVES_LIGHT
    origin = (-(cx + trunk / 2), 0, -(cz + trunk / 2))
    return vox, origin


def oak(rng, height_vox, radius_vox, trunk=1):
    H = height_vox
    R = radius_vox
    size = 2 * R + 4
    vox = np.zeros((size, H + R + 3, size), np.uint8)
    cx = size // 2 - trunk // 2
    cz = size // 2 - trunk // 2
    vox[cx:cx + trunk, 0:H, cz:cz + trunk] = C.LOG
    # a couple of branches
    for _ in range(3):
        a = rng.uniform(0, 2 * np.pi)
        by = int(H * rng.uniform(0.6, 0.9))
        for k in range(1, int(R * 0.6)):
            x = int(round(cx + np.cos(a) * k))
            z = int(round(cz + np.sin(a) * k))
            yy = by + k // 2
            if 0 <= x < size and 0 <= z < size and yy < vox.shape[1]:
                vox[x, yy, z] = C.LOG
    # canopy: union of blobs
    blobs = [(0, H + R * 0.25, 0, R)]
    for _ in range(4):
        blobs.append((rng.uniform(-R * 0.5, R * 0.5), H + rng.uniform(-R * 0.1, R * 0.6), rng.uniform(-R * 0.5, R * 0.5), R * rng.uniform(0.55, 0.8)))
    Y = vox.shape[1]
    gx, gy, gz = np.meshgrid(np.arange(size), np.arange(Y), np.arange(size), indexing='ij')
    inside = np.zeros(vox.shape, bool)
    for (bx, by, bz, br) in blobs:
        d = np.sqrt(((gx - cx - bx) / br) ** 2 + ((gy - by) / (br * 0.8)) ** 2 + ((gz - cz - bz) / br) ** 2)
        inside |= d < 1 + rng.uniform(-0.05, 0.05)
    noise = rng.random(vox.shape)
    inside &= ~((noise < 0.12) & (inside))
    vox[(inside) & (vox == 0)] = C.OAK_LEAVES
    origin = (-(cx + trunk / 2), 0, -(cz + trunk / 2))
    return vox, origin


def downsample(vox, f):
    """Majority-ish downsample for LOD (solid if >= 3/8 filled, keeps most common block)."""
    X, Y, Z = vox.shape
    X2, Y2, Z2 = (X + f - 1) // f, (Y + f - 1) // f, (Z + f - 1) // f
    pad = np.zeros((X2 * f, Y2 * f, Z2 * f), np.uint8)
    pad[:X, :Y, :Z] = vox
    blocks = pad.reshape(X2, f, Y2, f, Z2, f).transpose(0, 2, 4, 1, 3, 5).reshape(X2, Y2, Z2, f ** 3)
    filled = (blocks > 0).sum(-1)
    out = np.zeros((X2, Y2, Z2), np.uint8)
    # most common non-zero
    for b in np.unique(blocks):
        if b == 0:
            continue
        cnt = (blocks == b).sum(-1)
        better = cnt > 0
        out = np.where((filled * 8 >= 3 * f ** 3) & better & ((out == 0) | (cnt * 2 > filled)), b, out)
    return out
