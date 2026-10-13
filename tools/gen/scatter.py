"""Trees and plants as instanced meshes (MultiMesh buffers)."""
import time
import numpy as np
import common as C
from common import Noise2D, smoothstep
import terrain as T
import models
import textures

NP = Noise2D(91)
NQ = Noise2D(92)
NR = Noise2D(93)

PINE_HEIGHTS = [13.0, 15.0, 17.0, 19.0, 21.0, 23.0]   # metres
OAK_SPECS = [(5.0, 3.0), (6.0, 3.5), (4.5, 2.5)]       # trunk height, canopy radius (m)
TREE_LODS = (1, 2, 4, 8, 16)                           # x 0.125 m
TREE_RANGES = [(0.0, 22.0), (22.0, 55.0), (55.0, 115.0), (115.0, 290.0), (290.0, 0.0)]


def xform_rows(px, py, pz, yaw, sx, sy=None, sz=None):
    """MultiMesh 3D transform buffer rows (12 floats per instance)."""
    if sy is None:
        sy = sx
    if sz is None:
        sz = sx
    c = np.cos(yaw)
    s = np.sin(yaw)
    n = len(px)
    out = np.zeros((n, 12), np.float32)
    out[:, 0] = c * sx
    out[:, 1] = 0
    out[:, 2] = s * sz
    out[:, 3] = px
    out[:, 4] = 0
    out[:, 5] = sy
    out[:, 6] = 0
    out[:, 7] = py
    out[:, 8] = -s * sx
    out[:, 9] = 0
    out[:, 10] = c * sz
    out[:, 11] = pz
    return out


def ground_height(grids, x, z):
    """Surface height from the finest grid that covers the position."""
    h = np.full(np.shape(x), np.nan)
    for gname in ('near', 'mid'):
        gn = grids[gname]
        Hf = getattr(gn, 'fine_top_h', None)
        if Hf is None:
            continue
        FS = gn.fine_vs
        i = np.floor((x - gn.origin[0]) / FS).astype(np.int64)
        k = np.floor((z - gn.origin[2]) / FS).astype(np.int64)
        ok = (i >= 0) & (k >= 0) & (i < Hf.shape[0]) & (k < Hf.shape[1]) & np.isnan(h)
        hv = Hf[np.clip(i, 0, Hf.shape[0] - 1), np.clip(k, 0, Hf.shape[1] - 1)]
        h = np.where(ok & ~np.isnan(hv), hv, h)
    for name in ('near', 'mid', 'back', 'far'):
        g = grids[name]
        i = np.floor((x - g.origin[0]) / g.vs).astype(np.int64)
        k = np.floor((z - g.origin[2]) / g.vs).astype(np.int64)
        ok = (i >= 0) & (k >= 0) & (i < g.dims[0]) & (k < g.dims[2]) & np.isnan(h)
        if name != 'far':
            # skip hole region of coarser grids: handled by order
            pass
        ii = np.clip(i, 0, g.dims[0] - 1)
        kk = np.clip(k, 0, g.dims[2] - 1)
        top = g.top[ii, kk]
        hy = g.origin[1] + (top + 1) * g.vs
        h = np.where(ok, hy, h)
    return h


def surface_block(grids, x, z):
    g = grids['near']
    i = np.floor((x - g.origin[0]) / g.vs).astype(np.int64)
    k = np.floor((z - g.origin[2]) / g.vs).astype(np.int64)
    ok = (i >= 0) & (k >= 0) & (i < g.dims[0]) & (k < g.dims[2])
    ii = np.clip(i, 0, g.dims[0] - 1)
    kk = np.clip(k, 0, g.dims[2] - 1)
    top = g.top[ii, kk]
    b = g.vox[ii, top, kk]
    above = g.vox[ii, np.clip(top + 1, 0, g.dims[1] - 1), kk]
    above2 = g.vox[ii, np.clip(top + 2, 0, g.dims[1] - 1), kk]
    return np.where(ok, b, 0), np.where(ok, above, 255), np.where(ok, above2, 255), ok


def build_tree_models(blocks=None):
    import flora
    rng = np.random.default_rng(7)
    out = {}
    for vi, h in enumerate(PINE_HEIGHTS):
        out[f'pine{vi}'] = flora.pine(rng, h)
    for vi, (h, r) in enumerate(OAK_SPECS):
        out[f'oak{vi}'] = flora.oak(rng, h, r)
    meshes = {}
    for name, (vox, org) in out.items():
        lods = []
        for lod, f in enumerate(TREE_LODS):
            v = vox if f == 1 else models.downsample(vox, f)
            arr = models.mesh_model(v, None, flora.TV * f, origin=org, use_ao=(lod < 3), paint_vs=flora.TV, detail=(f == 1),
                                    register=('tree_' + name) if f == 1 else None)
            lods.append(arr)
        meshes[name] = lods
        print('tree', name, vox.shape, [len(a['idx']) // 6 for a in lods])
    return meshes


def tree_density(grids, X, Z, H, sblock, drop):
    d_r, s_r, lvl, hw = T.river_field(X, Z)
    pd, phw = T.path_field(X, Z)
    n = NP.fbm(X, Z, 45, 3)
    dens = np.zeros_like(X)
    # forest everywhere outside the valley floor
    s_ax, lat = T.axis_coords(X, Z)
    valley_core = (np.abs(lat) < 26) & (s_ax < 40) & (s_ax > -60)
    dens = 0.55 * smoothstep(0.35, 0.6, n) + 0.25
    # east bank forest near the camera view (tall pines right of bridge)
    eastbank = (X > 27) & (Z < 10) & (Z > -120)
    dens = np.where(eastbank, np.maximum(dens, 0.75), dens)
    dens = np.where(valley_core, 0.0, dens)
    # village: keep open
    vil = (X < -3) & (X > -60) & (Z > -62) & (Z < 12)
    dens = np.where(vil, 0.05 * (n > 0.6), dens)
    # keep the view corridor from the spawn point open (valley, waterfall, mountains)
    ang = np.degrees(np.arctan2(X - 0.4, 4.6 - Z)) + 3.0
    dist = np.hypot(X, Z - 4.6)
    corridor = (ang > -12) & (ang < 33) & (dist > 18) & (dist < 190)
    dens = np.where(corridor, dens * np.where(dist < 110, 0.02, 0.35), dens)
    fall_sight = (ang > 11) & (ang < 21) & (dist > 60) & (dist < 245)
    dens = np.where(fall_sight, 0.0, dens)
    dens = np.where(d_r < hw + 3.0, 0.0, dens)
    dens = np.where(pd < phw + 2.0, 0.0, dens)
    # treeline and snow
    dens = dens * (1 - smoothstep(170, 240, H))
    dens = np.where(drop > 4, 0.0, dens)
    return np.clip(dens, 0, 1)


def scatter_trees(grids, manifest, writer, tree_meshes, nogo):
    t0 = time.time()
    rng = np.random.default_rng(31)
    records = []

    def region(x0, x1, z0, z1, cell, exclude=None, lod_min=0):
        xs = np.arange(x0, x1, cell)
        zs = np.arange(z0, z1, cell)
        X, Z = np.meshgrid(xs, zs, indexing='ij')
        X = X + rng.uniform(0.15, 0.85, X.shape) * cell
        Z = Z + rng.uniform(0.15, 0.85, Z.shape) * cell
        X = X.ravel()
        Z = Z.ravel()
        if exclude is not None:
            ex0, ex1, ez0, ez1 = exclude
            m = ~((X >= ex0) & (X < ex1) & (Z >= ez0) & (Z < ez1))
            X, Z = X[m], Z[m]
        H = ground_height(grids, X, Z)
        # steepness: sample around
        e = cell * 0.5
        hs = [ground_height(grids, X + dx, Z + dz) for dx, dz in ((e, 0), (-e, 0), (0, e), (0, -e))]
        drop = np.nanmax(np.stack(hs), 0) - np.nanmin(np.stack(hs), 0)
        dens = tree_density(grids, X, Z, H, None, drop)
        keep = rng.random(len(X)) < dens
        keep &= ~np.isnan(H)
        X, Z, H = X[keep], Z[keep], H[keep]
        if nogo is not None and len(X):
            g = grids['near']
            i = np.floor((X - g.origin[0]) / g.vs).astype(int)
            k = np.floor((Z - g.origin[2]) / g.vs).astype(int)
            inn = (i >= 0) & (k >= 0) & (i < g.dims[0]) & (k < g.dims[2])
            bad = np.zeros(len(X), bool)
            bad[inn] = nogo[i[inn], k[inn]]
            X, Z, H = X[~bad], Z[~bad], H[~bad]
        return X, Z, H

    near = region(-96, 96, -160, 48, 4.5)
    mid = region(-416, 416, -560, 280, 6.0, exclude=(-96, 96, -160, 48))
    far = region(-1800, 1800, -2000, 1400, 13.0, exclude=(-416, 416, -560, 280))
    groups = {}
    allpos = []
    for label, (X, Z, H) in (('near', near), ('mid', mid), ('far', far)):
        n = len(X)
        # choose variant: low areas mix oaks
        is_oak = (rng.random(n) < np.where(H < 25, 0.12, 0.0))
        pv = rng.integers(0, len(PINE_HEIGHTS), n)
        ov = rng.integers(0, len(OAK_SPECS), n)
        yaw = rng.integers(0, 4, n) * (np.pi / 2) + rng.uniform(-0.12, 0.12, n)
        sc = rng.uniform(0.85, 1.25, n)
        if label == 'far':
            sc = sc * 1.3
        # trees deep inside the spawn view corridor are kept small so the valley reads as distant
        ang = np.degrees(np.arctan2(X, 4.6 - Z))
        dist = np.hypot(X, Z - 4.6)
        corr = (ang > -12) & (ang < 30) & (dist > 90) & (dist < 400)
        sc = np.where(corr, sc * 0.62, sc)
        for i in range(n):
            name = f'oak{ov[i]}' if is_oak[i] else f'pine{pv[i]}'
            groups.setdefault(name, []).append((X[i], H[i] - 0.3, Z[i], yaw[i], sc[i]))
            allpos.append((X[i], Z[i], name.startswith('oak'), sc[i]))
    print(f'trees: near {len(near[0])}, mid {len(mid[0])}, far {len(far[0])} in {time.time() - t0:.1f}s')
    return groups, allpos


def add_designed_trees(groups, grids):
    """Hand placed trees that frame the reference view."""
    placed = [
        ('oak1', -6.6, -1.6, 0.3, 1.05),     # left foreground tree behind the lantern post
        ('pine5', 31.0, -44.0, 0.0, 1.15),   # tall pine right of the bridge
        ('pine4', 35.5, -38.0, 1.6, 1.1),
        ('pine3', 37.0, -50.0, 0.7, 1.0),
        ('pine5', 42.0, -33.0, 2.2, 1.2),
        ('oak0', -10.5, -27.0, 1.0, 0.9),    # village trees
        ('oak2', -9.0, -40.0, 0.2, 0.9),
        ('pine2', -36.0, -60.0, 0.0, 1.0),
        ('pine4', -46.0, -22.0, 0.0, 1.1),
        ('pine3', -48.0, -44.0, 0.0, 1.0),
        ('pine4', -3.5, -48.0, 0.0, 1.1),     # tall pine right behind the market
        ('pine2', -8.0, -56.0, 0.0, 1.0),
        ('pine3', -3.0, -64.0, 0.0, 1.05),
    ]
    for name, x, z, yaw, s in placed:
        h = float(ground_height(grids, np.array([x]), np.array([z]))[0])
        groups.setdefault(name, []).append((x, h - 0.3, z, yaw, s))


def write_trees(groups, tree_meshes, manifest, writer):
    """Chunk instances; write meshes + buffers."""
    out = {'meshes': {}, 'chunks': [], 'ranges': TREE_RANGES}
    for name, lods in tree_meshes.items():
        out['meshes'][name] = [{k: writer.put(v) for k, v in arr.items()} for arr in lods]
    for name, inst in groups.items():
        a = np.array(inst, np.float64)
        if len(a) == 0:
            continue
        in_near = (a[:, 0] > -96) & (a[:, 0] < 96) & (a[:, 2] > -160) & (a[:, 2] < 48)
        in_mid = (a[:, 0] > -416) & (a[:, 0] < 416) & (a[:, 2] > -560) & (a[:, 2] < 280) & ~in_near
        tier = np.where(in_near, 0, np.where(in_mid, 1, 2))
        for t, CH in ((0, 16.0), (1, 48.0), (2, 400.0)):
            at = a[tier == t]
            if len(at) == 0:
                continue
            cxk = np.floor(at[:, 0] / CH).astype(int)
            czk = np.floor(at[:, 2] / CH).astype(int)
            keys = cxk * 100000 + czk
            for key in np.unique(keys):
                m = keys == key
                b = at[m]
                buf = xform_rows(b[:, 0], b[:, 1], b[:, 2], b[:, 3], b[:, 4])
                cx = float(np.floor(b[0, 0] / CH) * CH + CH / 2)
                cz = float(np.floor(b[0, 2] / CH) * CH + CH / 2)
                out['chunks'].append({'mesh': name, 'n': int(m.sum()), 'buf': writer.put(buf), 'center': [cx, cz], 'tier': t, 'size': CH,
                                      '_inst': [tuple(row) for row in b.tolist()]})
    # trunk colliders for trees in the playable area: carry the instance identity for chopping
    cols = []
    for ch in out['chunks']:
        if ch['tier'] != 0:
            continue
        name = ch['mesh']
        for i, (x, y, z, yaw, sc) in enumerate(ch['_inst']):
            r = (0.35 if name.startswith('pine') and int(name[-1]) < 4 else 0.6) * sc
            if name.startswith('oak'):
                r = 0.35 * sc
            cols.append([float(x), float(y), float(z), float(r), name, '%s_%d_%d' % (name, int(ch['center'][0]), int(ch['center'][1])),
                         i, float(yaw), float(sc)])
    for ch in out['chunks']:
        ch.pop('_inst', None)
    out['colliders'] = cols
    manifest['trees'] = out
    print('tree chunks', len(out['chunks']), 'colliders', len(cols))


# ------------------------------------------------------------------ plants
PLANT_NAMES = ['grass_a', 'grass_b', 'grass_c', 'grass_tall_a', 'grass_tall_b', 'daisy', 'daisy_b', 'daisy_big',
               'daisy_big_b', 'buttercup', 'buttercup_b', 'yellow_big', 'poppy', 'bluebell', 'lavender', 'wheat', 'reeds',
               'fern', 'bush', 'lily']
PLANT_RANGES = [(0.0, 20.0), (20.0, 38.0)]


def downsample_any(vox, f):
    """Keep thin plant parts at lower resolution: a cell is solid if any voxel is; flowers win over leaves."""
    import vox as VX
    X, Y, Z = vox.shape
    X2, Y2, Z2 = (X + f - 1) // f, (Y + f - 1) // f, (Z + f - 1) // f
    pad = np.zeros((X2 * f, Y2 * f, Z2 * f), np.uint8)
    pad[:X, :Y, :Z] = vox
    b = pad.reshape(X2, f, Y2, f, Z2, f).transpose(0, 2, 4, 1, 3, 5).reshape(X2, Y2, Z2, f ** 3)
    out = np.zeros((X2, Y2, Z2), np.uint8)
    best = np.zeros((X2, Y2, Z2), np.int64)
    for m in np.unique(b):
        if m == 0:
            continue
        w = 1 if m in (VX.PLANT_GREEN, C.OAK_LEAVES) else 3
        cnt = (b == m).sum(-1) * w
        better = cnt > best
        out = np.where(better, m, out)
        best = np.where(better, cnt, best)
    return out


def plant_meshes():
    import flora
    pm = flora.plant_models()
    meshes = {}
    for name in PLANT_NAMES:
        v, o = pm[name]
        vs = flora.PLANT_VS.get(name, flora.PV2)
        l0 = models.mesh_model(v, None, vs, origin=o)
        l1 = models.mesh_model(downsample_any(v, 2), None, vs * 2, origin=o, use_ao=False, paint_vs=vs, detail=False)
        meshes[name] = [l0, l1]
    return meshes


def scatter_plants(grids, manifest, writer, fields, nogo):
    t0 = time.time()
    rng = np.random.default_rng(55)
    P = {n: i for i, n in enumerate(PLANT_NAMES)}
    g = grids['near']
    # candidate points: jittered sub-grid (4 per block = 16 per m2), thinned by density
    step = 0.25
    xs = np.arange(-96, 96, step)
    zs = np.arange(-160, 48, step)
    X, Z = np.meshgrid(xs, zs, indexing='ij')
    X = (X + rng.uniform(0, step, X.shape)).ravel()
    Z = (Z + rng.uniform(0, step, Z.shape)).ravel()
    b, above, above2, ok = surface_block(grids, X, Z)
    H = ground_height(grids, X, Z)
    grass_ok = ok & (b == C.GRASS) & (above == 0)
    pd, phw = T.path_field(X, Z)
    d_r, s_r, lvl, hw = T.river_field(X, Z)
    n1 = NP.fbm(X, Z, 7, 3)
    n2 = NQ.fbm(X, Z, 11, 3)
    n3 = NR.fbm(X, Z, 5, 2)
    dist_cam = np.hypot(X - 0, Z - 4)
    kind = np.full(len(X), -1)
    r = rng.random(len(X))
    # base grass density (per candidate); dense near the view, lighter far away
    base = (0.30 + 0.25 * smoothstep(0.3, 0.7, n1)) * 0.32
    base = base * (1 - 0.45 * smoothstep(40, 110, dist_cam))
    on_path = pd < phw - 0.15
    path_edge = (pd >= phw - 0.15) & (pd < phw + 0.35)
    base = np.where(on_path, 0.0, base)
    base = np.where(path_edge, base * 0.5, base)
    if nogo is not None:
        i = np.floor((X - g.origin[0]) / g.vs).astype(int)
        k = np.floor((Z - g.origin[2]) / g.vs).astype(int)
        inn = (i >= 0) & (k >= 0) & (i < g.dims[0]) & (k < g.dims[2])
        bad = np.zeros(len(X), bool)
        bad[inn] = nogo[i[inn], k[inn]]
        base = np.where(bad, 0.0, base)
    sel = grass_ok & (r < base)
    # assign kinds
    rk = rng.random(len(X))
    short = rng.choice([P['grass_a'], P['grass_b'], P['grass_c']], len(X))
    tall = rng.choice([P['grass_tall_a'], P['grass_tall_b']], len(X))
    kind = np.where(sel, short, -1)
    tall_zone = (n2 > 0.55) | ((d_r < hw + 4) & (d_r > hw)) | (dist_cam < 14)
    kind = np.where(sel & tall_zone & (rk < 0.35), tall, kind)
    # flowers in patches
    daisy_zone = (n3 > 0.50) | (dist_cam < 26)
    butter_zone = (n2 < 0.46) | (dist_cam < 26)
    fl = sel & (rk >= 0.35)
    kind = np.where(fl & daisy_zone & (rk < 0.62), rng.choice([P['daisy'], P['daisy_b']], len(X)), kind)
    kind = np.where(fl & butter_zone & (rk >= 0.62) & (rk < 0.85), rng.choice([P['buttercup'], P['buttercup_b']], len(X)), kind)
    kind = np.where(fl & (rk > 0.985), P['poppy'], kind)
    kind = np.where(fl & (rk > 0.97) & (rk <= 0.985) & (n1 > 0.5), P['bluebell'], kind)
    # foreground: extra flowers left and right of the path, big chunky daisies close to the camera
    fg = sel & (dist_cam < 24) & (rk > 0.40) & (rk < 0.82)
    kind = np.where(fg, rng.choice([P['daisy'], P['buttercup'], P['daisy_b'], P['daisy_big'], P['yellow_big']], len(X)), kind)
    big_zone = sel & (dist_cam < 16) & (rk > 0.82) & (rk < 0.93)
    kind = np.where(big_zone, rng.choice([P['daisy_big'], P['daisy_big_b'], P['yellow_big']], len(X)), kind)
    # flower borders along the path edges (as in the concept: daisies and buttercups lining the way)
    border = grass_ok & ~on_path & (pd >= phw - 0.1) & (pd < phw + 0.9) & (dist_cam < 60) & (r < 0.25)
    kind = np.where(border & (rk < 0.5), rng.choice([P['daisy_b'], P['daisy_big_b'], P['buttercup'], P['yellow_big']], len(X)), kind)
    # scattered big daisies in all meadows
    kind = np.where(sel & daisy_zone & (rk > 0.93) & (rk < 0.97), P['daisy_big'], kind)
    # designed fields
    for (fx0, fx1, fz0, fz1, fname, dens) in fields:
        inside = grass_ok & (X >= fx0) & (X < fx1) & (Z >= fz0) & (Z < fz1) & ~on_path
        kind = np.where(inside & (r < dens * 0.4), P[fname], kind)
    # reeds on river banks
    bankz = ok & ((b == C.GRASS) | (b == C.GRAVEL)) & (above == 0) & (d_r > hw - 0.2) & (d_r < hw + 1.6) & (lvl < 3)
    kind = np.where(bankz & (r < 0.09) & (n1 > 0.42), P['reeds'], kind)
    # ferns and bushes under trees / at terrace edges
    kind = np.where(sel & (n2 > 0.7) & (rk > 0.9), P['fern'], kind)
    kind = np.where(sel & (n1 > 0.72) & (rk > 0.95), P['bush'], kind)
    m = kind >= 0
    X, Z, H, kind = X[m], Z[m], H[m], kind[m]
    n = len(X)
    yaw = rng.uniform(0, np.pi, n)
    sc = rng.uniform(0.85, 1.15, n)
    tallk = np.isin(kind, [P['grass_tall_a'], P['grass_tall_b'], P['wheat'], P['reeds'], P['lavender']])
    sc = np.where(tallk, sc * 1.1, sc)
    sc = np.where(kind == P['wheat'], rng.uniform(0.95, 1.15, n), sc)
    bigk = np.isin(kind, [P['daisy_big'], P['daisy_big_b'], P['yellow_big']])
    sc = np.where(bigk, rng.uniform(0.9, 1.35, n), sc)
    # lily pads on water near banks
    lx = np.arange(-96, 96, 0.5)
    lz = np.arange(-160, 48, 0.5)
    LX, LZ = np.meshgrid(lx, lz, indexing='ij')
    LX = (LX + rng.uniform(0, 0.5, LX.shape)).ravel()
    LZ = (LZ + rng.uniform(0, 0.5, LZ.shape)).ravel()
    ld, ls, llv, lhw = T.river_field(LX, LZ)
    lm = (ld < lhw - 0.8) & (ld > lhw - 3.2) & (llv < 0) & (rng.random(len(LX)) < 0.05) & (NQ.fbm(LX, LZ, 6, 2) > 0.5)
    LX, LZ = LX[lm], LZ[lm]
    LH = -8.0 + np.round((llv[lm] + 8.0) / 0.125) * 0.125 + 0.005
    print(f'plants: {n} sprites, {len(LX)} lily pads in {time.time() - t0:.1f}s')
    # write chunks: one MultiMesh per plant kind and 16 m chunk (two LOD meshes share the buffer)
    CH = 16.0
    pm = plant_meshes()
    out = {'chunks': [], 'ranges': PLANT_RANGES,
           'meshes': {k: [{kk: writer.put(vv) for kk, vv in a.items()} for a in lods] for k, lods in pm.items()}}

    def emit(X, Y, Z, yaw, sc, kind, tint):
        if len(X) == 0:
            return
        cxk = np.floor(X / CH).astype(int)
        czk = np.floor(Z / CH).astype(int)
        keys = (cxk * 100000 + czk) * 64 + kind
        order = np.argsort(keys, kind='stable')
        keys_s = keys[order]
        uniq, start = np.unique(keys_s, return_index=True)
        ends = list(start[1:]) + [len(keys_s)]
        for u, s0, e0 in zip(uniq, start, ends):
            ids = order[s0:e0]
            xf = xform_rows(X[ids], Y[ids], Z[ids], yaw[ids], sc[ids])
            custom = np.zeros((len(ids), 4), np.float32)
            custom[:, 1] = tint[ids]
            custom[:, 2] = rng.uniform(0, 6.28, len(ids))
            buf = np.concatenate([xf, custom], axis=1).astype(np.float32)
            cx = float(np.floor(X[ids[0]] / CH) * CH + CH / 2)
            cz = float(np.floor(Z[ids[0]] / CH) * CH + CH / 2)
            out['chunks'].append({'mesh': PLANT_NAMES[int(kind[ids[0]])], 'n': int(len(ids)), 'buf': writer.put(buf),
                                  'center': [cx, cz]})

    tint = rng.uniform(-1, 1, n).astype(np.float32)
    # voxel plants stay on the grid: quarter turns with a little jitter
    yaw = rng.integers(0, 4, n) * (np.pi / 2) + rng.uniform(-0.14, 0.14, n)
    emit(X, H, Z, yaw, sc, kind.astype(np.int64), tint)
    nl = len(LX)
    emit(LX, LH, LZ, rng.uniform(0, 6.28, nl), rng.uniform(0.8, 1.25, nl), np.full(nl, P['lily'], np.int64),
         rng.uniform(-1, 1, nl).astype(np.float32))
    manifest['plants_inst'] = out
    print(f'plant chunks {len(out["chunks"])}')


def scatter_all(grids, manifest, writer, blocks=None, fields=(), nogo=None):
    tree_meshes = build_tree_models(blocks)
    groups, allpos = scatter_trees(grids, manifest, writer, tree_meshes, nogo)
    add_designed_trees(groups, grids)
    write_trees(groups, tree_meshes, manifest, writer)
    scatter_plants(grids, manifest, writer, fields, nogo)
    pos = []
    for name, inst in groups.items():
        for (x, y, z, yaw, sc) in inst:
            if -170 < x < 170 and -230 < z < 110:
                pos.append((x, z, name.startswith('oak'), sc))
    return pos
