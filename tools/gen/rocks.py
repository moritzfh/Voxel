"""Chunky boulders, stones and pebbles scattered over the playable area (instanced, chunked)."""
import time
import numpy as np
import common as C
from common import Noise2D, smoothstep
import terrain as T
import models
from scatter import xform_rows, ground_height, surface_block

PV = 0.125
NR = Noise2D(311)
NS = Noise2D(312)


def boulder(seed, w, h, d, moss=0.6, chip=0.35):
    """Rounded, faceted boulder in 12.5 cm voxels: super-ellipsoid + lumpy noise + a few flat fracture
    planes, flat base, moss on top. w/h/d in 0.25 m. Returns (vox, origin, size_m)."""
    import flora
    rng = np.random.default_rng(seed)
    a, b, c = w * 1.0 + 0.3, h * 2.0 + 0.4, d * 1.0 + 0.3      # semi-axes in voxels (height: full)
    X, Y, Z = int(2 * a + 4), int(b + 3), int(2 * c + 4)
    gx, gy, gz = np.meshgrid(np.arange(X) + 0.5 - X / 2, np.arange(Y) + 0.5, np.arange(Z) + 0.5 - Z / 2, indexing='ij')
    p = rng.uniform(2.2, 3.0)
    q = (np.abs(gx / a) ** p + np.abs(gy / b) ** p + np.abs(gz / c) ** p) ** (1 / p)
    small = w * d <= 9
    n1 = flora.smooth_noise(rng, (X, Y, Z), 3 if small else 4)
    n2 = flora.smooth_noise(rng, (X, Y, Z), 2)
    q = q + (n1 - 0.5) * (0.22 if small else 0.3) + (n2 - 0.5) * chip * 0.25
    inside = q < 1.0
    # fracture planes: flat facets like split stone
    for _ in range(rng.integers(3, 7)):
        nv = rng.normal(size=3)
        nv[1] = abs(nv[1]) * 0.8 + 0.2
        nv /= np.linalg.norm(nv)
        off = rng.uniform(0.62, 0.9)
        inside &= (gx / a * nv[0] + gy / b * nv[1] + gz / c * nv[2]) < off
    out = np.zeros((X, Y, Z), np.uint8)
    out[inside] = C.PEBBLE if moss == 0.0 else C.BOULDER
    if moss > 0.0:
        top = (out > 0) & np.concatenate([out[:, 1:, :] == 0, np.ones((X, 1, Z), bool)], axis=1)
        mn = flora.smooth_noise(rng, (X, Y, Z), 3)
        mossy = top & (mn > 1.0 - moss * 0.85)
        # moss creeps one voxel down the sides
        out[mossy] = C.BOULDER_MOSS
        below = np.zeros_like(mossy)
        below[:, :-1, :] = mossy[:, 1:, :]
        out[below & (out > 0) & (n2 > 0.45)] = C.BOULDER_MOSS
    # trim empty margins
    ys = np.nonzero(out.any(axis=(0, 2)))[0]
    out = out[:, :ys.max() + 1, :] if len(ys) else out
    X, Y, Z = out.shape
    org = (-(X * PV) / 2, -0.0, -(Z * PV) / 2)
    return out, org, (X * PV, Y * PV, Z * PV)


ROCK_SPECS = [
    # name, w, h, d (in 0.25 m)
    ('boulder_a', 4, 3, 4),
    ('boulder_b', 6, 3, 4),
    ('boulder_c', 5, 4, 5),
    ('boulder_d', 3, 2, 3),
    ('boulder_e', 7, 3, 5),
    ('boulder_f', 4, 2, 6),
    ('slab_a', 6, 2, 5),
    ('stone_a', 2, 2, 2),
    ('stone_b', 3, 1, 2),
    ('pebble_a', 1, 1, 1),
    ('pebble_b', 2, 1, 1),
]


def build_rock_meshes(blocks, writer):
    meshes = {}
    sizes = {}
    for i, (name, w, h, d) in enumerate(ROCK_SPECS):
        v, org, size = boulder(100 + i, w, h, d, moss=0.0 if name.startswith('pebble') else 0.6,
                               chip=0.15 if name.startswith('pebble') else 0.35)
        lods = []
        for f in (1, 2, 4):
            vv = v if f == 1 else models.downsample(v, f)
            arr = models.mesh_model(vv, None, PV * f, origin=org, paint_vs=PV, detail=(f == 1), use_ao=(f < 4),
                                    register=('rock_' + name) if f == 1 else None)
            if arr is None:          # tiny pebble vanished at this LOD: keep the previous mesh
                lods.append(lods[-1])
                continue
            lods.append({k: writer.put(a) for k, a in arr.items()})
        meshes[name] = lods
        sizes[name] = size
    return meshes, sizes


def scatter_rocks(grids, manifest, writer, blocks, nogo):
    t0 = time.time()
    rng = np.random.default_rng(77)
    g = grids['near']
    meshes, sizes = build_rock_meshes(blocks, writer)
    big = ['boulder_a', 'boulder_b', 'boulder_c', 'boulder_e', 'boulder_f', 'slab_a']
    small = ['boulder_d', 'stone_a', 'stone_b', 'boulder_a']
    placed = []   # name, x, y, z, yaw, scale

    def cands(step, x0=-94, x1=94, z0=-150, z1=40):
        xs = np.arange(x0, x1, step)
        zs = np.arange(z0, z1, step)
        X, Z = np.meshgrid(xs, zs, indexing='ij')
        X = (X + rng.uniform(0, step, X.shape)).ravel()
        Z = (Z + rng.uniform(0, step, Z.shape)).ravel()
        return X, Z

    X, Z = cands(1.1)
    b, above, above2, ok = surface_block(grids, X, Z)
    H = ground_height(grids, X, Z)
    pd, phw = T.path_field(X, Z)
    d_r, s_r, lvl, hw = T.river_field(X, Z)
    dist_cam = np.hypot(X - 0.4, Z - 4.6)
    n1 = NR.fbm(X, Z, 9, 3)
    r = rng.random(len(X))
    i = np.floor((X - g.origin[0]) / g.vs).astype(int)
    k = np.floor((Z - g.origin[2]) / g.vs).astype(int)
    inn = (i >= 0) & (k >= 0) & (i < g.dims[0]) & (k < g.dims[2])
    bad = np.zeros(len(X), bool)
    bad[inn] = nogo[i[inn], k[inn]]
    land = ok & ((b == C.GRASS) | (b == C.GRAVEL) | (b == C.SAND) | (b == C.PATH)) & (above == 0) & ~bad
    land &= dist_cam > 6.0  # keep the start view open right in front of the camera
    near_view = 1.0 + 1.6 * (1 - smoothstep(10, 45, dist_cam))
    # 1) path edges
    edge = land & (pd > phw + 0.45) & (pd < phw + 1.9) & (d_r > hw + 0.3)
    p_edge = 0.10 * near_view
    # 2) meadows: sparse, clustered by noise
    meadow = land & (b == C.GRASS) & (pd > phw + 1.7) & (d_r > hw + 1.5)
    p_meadow = (0.012 + 0.07 * smoothstep(0.6, 0.78, n1)) * near_view
    # 3) river banks
    bank = ok & ~bad & (d_r > hw - 1.4) & (d_r < hw + 1.3) & (lvl < 3) & (dist_cam > 6.5)
    p_bank = 0.30 * (0.6 + 0.4 * near_view)
    sel_edge = edge & (r < p_edge)
    sel_meadow = meadow & (r < p_meadow)
    sel_bank = bank & (r < p_bank)
    for sel, kind in ((sel_edge, 'edge'), (sel_meadow, 'meadow'), (sel_bank, 'bank')):
        for idx in np.nonzero(sel)[0]:
            x, z = X[idx], Z[idx]
            if kind == 'edge':
                name = rng.choice(small + big[:2]) if rng.random() < 0.7 else rng.choice(big)
                sc = rng.uniform(0.7, 1.15)
            elif kind == 'meadow':
                name = rng.choice(big + small)
                sc = rng.uniform(0.8, 1.5)
            else:
                name = rng.choice(big + ['boulder_d', 'stone_a'])
                sc = rng.uniform(0.8, 1.35)
            sx, sy, sz = sizes[name]
            if kind == 'bank' and d_r[idx] < hw[idx]:
                y = float(lvl[idx]) - sy * sc * rng.uniform(0.35, 0.6)
                y = max(y, float(H[idx]) - 0.2)
            else:
                y = float(H[idx]) - sy * sc * rng.uniform(0.12, 0.25)
            yaw = rng.integers(0, 4) * (np.pi / 2) + rng.uniform(-0.25, 0.25)
            placed.append((name, x, y, z, yaw, sc))
    # 4) a few hand-placed hero rocks framing the reference view
    hero = [('boulder_b', 4.6, -1.6, 0.9), ('boulder_c', 6.2, 1.2, 1.25),
            ('boulder_b', 8.6, -3.0, 1.3), ('boulder_a', 9.4, 4.4, 1.15), ('boulder_e', 11.8, 1.6, 1.4),
            ('boulder_f', 7.2, -10.5, 1.2), ('boulder_c', -3.6, -11.0, 1.0), ('slab_a', 2.5, -15.0, 1.1),
            ('boulder_b', -6.2, 4.6, 1.3), ('stone_a', 2.9, -7.5, 1.0),
            ('boulder_a', 12.5, -4.0, 1.25), ('boulder_c', 13.0, 6.5, 1.35),
            ('boulder_c', -6.8, 5.2, 1.2), ('boulder_b', -9.6, 0.8, 1.1), ('boulder_a', -5.4, -6.2, 1.0),
            ('boulder_f', -10.5, -3.5, 1.1), ('stone_a', -7.6, 2.4, 1.2)]
    for (name, x, z, sc) in hero:
        h0 = float(ground_height(grids, np.array([x]), np.array([z]))[0])
        dd, ss, ll, hh = T.river_field(np.array([x]), np.array([z]))
        sx, sy, sz = sizes[name]
        if dd[0] < hh[0]:
            y = float(ll[0]) - sy * sc * 0.45
        else:
            y = h0 - sy * sc * 0.15
        placed.append((name, x, y, z, rng.integers(0, 4) * np.pi / 2 + rng.uniform(-0.2, 0.2), sc))
    # simple overlap rejection
    keep = []
    occ = {}
    for p in placed:
        name, x, y, z, yaw, sc = p
        rad = max(sizes[name][0], sizes[name][2]) * sc * 0.5
        key = (int(x // 2), int(z // 2))
        clash = False
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for (ox, oz, orad) in occ.get((key[0] + dx, key[1] + dz), []):
                    if np.hypot(ox - x, oz - z) < (orad + rad) * 0.8:
                        clash = True
        if not clash:
            occ.setdefault(key, []).append((x, z, rad))
            keep.append(p)
    placed = keep
    # 5) pebbles on paths near the view
    PX, PZ = cands(0.6, -40, 40, -70, 30)
    pdd, pph = T.path_field(PX, PZ)
    dc = np.hypot(PX - 0.4, PZ - 4.6)
    on = (pdd < pph + 0.2) & (rng.random(len(PX)) < 0.06 * (1 - smoothstep(20, 60, dc)) + 0.012)
    PH = ground_height(grids, PX, PZ)
    for x, z, h in zip(PX[on], PZ[on], PH[on]):
        name = 'pebble_a' if rng.random() < 0.6 else 'pebble_b'
        sc = rng.uniform(0.6, 1.1)
        placed.append((name, float(x), float(h) - 0.17 * sc, float(z), rng.uniform(0, 6.28), sc))
    # mask for plants / trees: inner part of each rock footprint
    mask = np.zeros_like(nogo)
    cols = []
    for (name, x, y, z, yaw, sc) in placed:
        sx, sy, sz = sizes[name]
        if name.startswith('pebble'):
            continue
        rx, rz = sx * sc * 0.32, sz * sc * 0.32
        i0, i1 = int((x - rx - g.origin[0]) / g.vs), int((x + rx - g.origin[0]) / g.vs) + 1
        k0, k1 = int((z - rz - g.origin[2]) / g.vs), int((z + rz - g.origin[2]) / g.vs) + 1
        mask[max(0, i0):max(0, i1), max(0, k0):max(0, k1)] = True
    # every rock gets a pick collider (mining); big ones also block the player
    # chunked instance export
    CH = 16.0
    out = {'meshes': meshes, 'chunks': [],
           'ranges': {'rock': [[0.0, 26.0], [26.0, 65.0], [65.0, 160.0]], 'pebble': [[0.0, 30.0], [30.0, 70.0]]}}
    by = {}
    for p in placed:
        by.setdefault(p[0], []).append(p[1:])
    for name, lst in by.items():
        a = np.array(lst, np.float64)
        keys = np.floor(a[:, 0] / CH).astype(int) * 100000 + np.floor(a[:, 2] / CH).astype(int)
        for key in np.unique(keys):
            m = keys == key
            bb = a[m]
            buf = xform_rows(bb[:, 0], bb[:, 1], bb[:, 2], bb[:, 3], bb[:, 4])
            cxm, czm = float(bb[:, 0].mean()), float(bb[:, 2].mean())
            out['chunks'].append({'mesh': name, 'n': int(m.sum()), 'buf': writer.put(buf),
                                  'center': [cxm, czm],
                                  'range': 70.0 if name.startswith('pebble') else 160.0})
            prefix = 'rocks_%s_%d_%d' % (name, int(cxm), int(czm))
            sx, sy, sz = sizes[name]
            for i, (x, y, z, yaw, sc) in enumerate(bb.tolist()):
                block = (not name.startswith('pebble')) and sx * sc > 0.9 and sy * sc > 0.35
                out.setdefault('items', []).append([x, y, z, yaw, sc, name, prefix, i, sx * sc, sy * sc, sz * sc, block])
    manifest['rocks_inst'] = out
    print(f'rocks: {len(placed)} placed ({sum(1 for p in placed if p[0].startswith("pebble"))} pebbles), '
          f'{len(cols)} colliders in {time.time() - t0:.1f}s')
    return mask
