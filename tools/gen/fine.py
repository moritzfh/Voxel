"""Column-based colour-voxel builds at a finer resolution than the coarse layout grids.

The coarse grids (structures.py) stay the source of truth for layout and buildings. This module
re-creates the ground from the analytic height field at the target voxel size and up-samples every
building voxel into F^3 finer voxels with geometric detail (sloped shingles, recessed windows,
uneven masonry). Each chunk also gets 2x and 4x down-sampled meshes for distance LOD.

Used for the playable area (near grid 0.5 m -> 12.5 cm) and the surrounding hills (mid grid 1 m -> 50 cm).
"""
import time
import numpy as np
from numba import njit
from scipy.ndimage import maximum_filter, minimum_filter

import common as C
import terrain as T
import vox as VX
import mesher
from common import Noise2D

Y0 = -8.0                  # world y of index 0 (same origin as the coarse grids)
NJ = Noise2D(515)
NS = Noise2D(77)           # same noise as world.fill_terrain (snow line)

NATURAL_IDS = np.zeros(256, np.bool_)
for _m in (C.AIR, C.GRASS, C.DIRT, C.PATH, C.STONE, C.CLIFF, C.SNOW, C.SNOW_FULL, C.GRAVEL, C.SAND, C.RIVERBED,
           C.WATER, C.WATER_FALL, C.GRASS_CLIFF, C.GRASS_SLOPE, C.MOUNTAIN_ROCK):
    NATURAL_IDS[_m] = True
STRUCT_IDS = ~NATURAL_IDS
STRUCT_IDS[C.HOLE] = False


class Spec:
    def __init__(self, key, fs, ch, pad, ranges, grass_depth, dirt_depth, fuzz, collision):
        self.key = key
        self.FS = fs
        self.CH = ch               # columns per chunk side
        self.PAD = pad             # padding columns (2 down-sample levels need 4)
        self.ranges = ranges       # visibility ranges per LOD level (fs, 2fs, 4fs)
        self.grass_depth = grass_depth
        self.dirt_depth = dirt_depth
        self.fuzz = fuzz           # grass / pebble bumps on the surface
        self.collision = collision


NEAR = Spec('near', 0.125, 128, 4, [(0.0, 42.0), (42.0, 100.0), (100.0, 0.0)], 2, 4, True, True)
MID = Spec('mid', 0.5, 64, 4, [(0.0, 170.0), (170.0, 420.0), (420.0, 0.0)], 0, 2, False, False)


# ------------------------------------------------------------------ numba kernels
@njit(cache=True)
def fill_natural(ids, ti, surf, sub, wtop, fall, snowy, y0, gx0, gz0, grass_depth, dirt_depth, fuzz, ores):
    """ids[x, y, z] (local), per local column: top index ti, surface id, sub-surface id, water top, cascade flag,
    snowy = index above which exposed rock gets snow patches. y0 = global index of ids[:, 0]."""
    X, Y, Z = ids.shape
    for i in range(X):
        for k in range(Z):
            t = ti[i, k] - y0
            s = surf[i, k]
            sb = sub[i, k]
            sy = snowy[i, k]
            for j in range(0, min(t + 1, Y)):
                d = t - j
                if d == 0:
                    m = s
                elif s == C.GRASS and d <= grass_depth:
                    m = C.GRASS
                elif s == C.SNOW and d <= 1:
                    m = C.SNOW
                elif d <= dirt_depth:
                    if s == C.GRASS or s == C.PATH or s == C.DIRT:
                        m = C.DIRT
                    elif s == C.SNOW or s == C.CLIFF or s == C.MOUNTAIN_ROCK:
                        m = sb
                    else:
                        m = s if d <= 2 else C.DIRT
                else:
                    m = sb
                if (m == C.CLIFF or m == C.STONE) and y0 + j > sy:
                    # snow clinging to high rock faces
                    if VX.vnoise3(gx0 + i, y0 + j, gz0 + k, 6, 77) > 0.55:
                        m = C.SNOW
                if ores and m == C.STONE:
                    # ore veins: copper near the top of the rock, iron deeper, crystal pockets deepest
                    if d > 26 and VX.vnoise3(gx0 + i, y0 + j, gz0 + k, 6, 303) > 0.83:
                        m = VX.CRYSTAL
                    elif d > 14 and VX.vnoise3(gx0 + i, y0 + j, gz0 + k, 9, 302) > 0.79:
                        m = VX.ORE_IRON
                    elif d > 6 and VX.vnoise3(gx0 + i, y0 + j, gz0 + k, 8, 301) > 0.76:
                        m = VX.ORE_COPPER
                ids[i, j, k] = m
            if fuzz and 0 <= t + 1 < Y:
                h = VX.hfrac(gx0 + i, ti[i, k], gz0 + k, 901)
                if s == C.GRASS and h < 0.003:
                    ids[i, t + 1, k] = C.GRASS
                elif s == C.PATH and h < 0.006:
                    ids[i, t + 1, k] = C.PEBBLE
            w = wtop[i, k] - y0
            if w > t:
                wid = C.WATER_FALL if fall[i, k] else C.WATER
                for j in range(max(t + 1, 0), min(w + 1, Y)):
                    ids[i, j, k] = wid


@njit(cache=True)
def _csolid(cv, ci, cj, ck):
    X, Y, Z = cv.shape
    if ci < 0 or cj < 0 or ck < 0 or ci >= X or cj >= Y or ck >= Z:
        return False
    v = cv[ci, cj, ck]
    return v != 0 and v != C.WATER and v != C.WATER_FALL and v != 255


@njit(cache=True)
def upsample_struct(ids, cv, is_struct, fx0, fy0, fz0, F):
    """Write building voxels of the coarse grid cv into the fine local grid ids.
    (fx0, fy0, fz0) = global fine index of ids[0, 0, 0]; coarse cell c covers fine F*c .. F*c+F-1.
    Detail (window frames, masonry recesses) only for F == 4."""
    X, Y, Z = ids.shape
    CX, CY, CZ = cv.shape
    ci0 = max(0, fx0 // F - 1)
    ci1 = min(CX, (fx0 + X) // F + 2)
    cj0 = max(0, fy0 // F - 1)
    cj1 = min(CY, (fy0 + Y) // F + 2)
    ck0 = max(0, fz0 // F - 1)
    ck1 = min(CZ, (fz0 + Z) // F + 2)
    dxs = (1, -1, 0, 0)
    dzs = (0, 0, 1, -1)
    L = F - 1
    detail = F == 4
    for ci in range(ci0, ci1):
        for ck in range(ck0, ck1):
            for cj in range(cj0, cj1):
                m = cv[ci, cj, ck]
                if not is_struct[m]:
                    continue
                above = _csolid(cv, ci, cj + 1, ck)
                ex = np.zeros(4, np.bool_)
                for d in range(4):
                    ex[d] = not _csolid(cv, ci + dxs[d], cj, ck + dzs[d])
                slope = np.zeros(4, np.bool_)
                if m == C.SLATE and not above:
                    for d in range(4):
                        if ex[d] and _csolid(cv, ci - dxs[d], cj + 1, ck - dzs[d]) and \
                                not _csolid(cv, ci - dxs[d], cj, ck - dzs[d]):
                            slope[d] = True
                is_win = detail and (m == C.WINDOW_LIT or m == C.WINDOW_DARK)
                is_mason = detail and (m == C.BRICKS or m == C.BRICKS_DARK or m == C.COBBLE or m == C.COBBLE_MOSSY)
                is_rock = detail and (m == C.BOULDER or m == C.BOULDER_MOSS)
                for a in range(F):
                    gx = ci * F + a
                    li = gx - fx0
                    if li < 0 or li >= X:
                        continue
                    for c in range(F):
                        gz = ck * F + c
                        lk = gz - fz0
                        if lk < 0 or lk >= Z:
                            continue
                        # roof: 45 degree fine stair inside the coarse step
                        lim = L
                        for d in range(4):
                            if slope[d]:
                                if d == 0:
                                    sd = a
                                elif d == 1:
                                    sd = L - a
                                elif d == 2:
                                    sd = c
                                else:
                                    sd = L - c
                                if L - sd < lim:
                                    lim = L - sd
                        outer = -1
                        if ex[0] and a == L:
                            outer = 0
                        elif ex[1] and a == 0:
                            outer = 1
                        elif ex[2] and c == L:
                            outer = 2
                        elif ex[3] and c == 0:
                            outer = 3
                        second = -1
                        if ex[0] and a == L - 1:
                            second = 0
                        elif ex[1] and a == 1:
                            second = 1
                        elif ex[2] and c == L - 1:
                            second = 2
                        elif ex[3] and c == 1:
                            second = 3
                        for b in range(F):
                            gy = cj * F + b
                            lj = gy - fy0
                            if lj < 0 or lj >= Y:
                                continue
                            if b > lim:
                                continue
                            val = m
                            if is_rock:
                                # round off exposed edges and corners of big stones (no sharp boxes)
                                ne = 0
                                if (ex[0] and a == L) or (ex[1] and a == 0):
                                    ne += 1
                                if (ex[2] and c == L) or (ex[3] and c == 0):
                                    ne += 1
                                if b == L and not above:
                                    ne += 1
                                hh = VX.hfrac(gx, gy, gz, 181)
                                if ne >= 3 or (ne == 2 and hh < 0.8) or (ne == 1 and hh < 0.07):
                                    continue
                            if is_win:
                                u = c if (outer == 0 or outer == 1 or second == 0 or second == 1) else a
                                frame = u == 0 or u == L or b == 0 or b == L
                                if outer >= 0:
                                    val = C.TIMBER if frame else 0
                                elif second >= 0 and frame:
                                    val = C.TIMBER
                            elif is_mason and outer >= 0:
                                if m == C.BRICKS or m == C.BRICKS_DARK:
                                    row, blk = VX.brick_block(gx, gy, gz, 0.125)
                                    if VX.hfrac(row, blk, 7, 171) < 0.2:
                                        val = 0
                                else:
                                    row, aa, la, ly = VX.cobble_cell(gx, gy, gz, 0.125)
                                    if VX.hfrac(row, aa, 9, 172) < 0.16:
                                        val = 0
                            ids[li, lj, lk] = val


@njit(cache=True)
def struct_top(cv, is_struct):
    X, Y, Z = cv.shape
    out = np.full((X, Z), -1, np.int64)
    for i in range(X):
        for k in range(Z):
            for j in range(Y - 1, -1, -1):
                if is_struct[cv[i, j, k]]:
                    out[i, k] = j
                    break
    return out


@njit(cache=True)
def downsample2(ids, water_a, water_b):
    """2x2x2 majority downsample of material ids (solid wins at >= 4/8, else water at >= 4/8)."""
    X, Y, Z = ids.shape
    X2, Y2, Z2 = X // 2, Y // 2, Z // 2
    out = np.zeros((X2, Y2, Z2), np.uint8)
    vals = np.zeros(8, np.uint8)
    for i in range(X2):
        for k in range(Z2):
            for j in range(Y2):
                nw = 0
                fallw = False
                n = 0
                for a in range(2):
                    for b in range(2):
                        for c in range(2):
                            v = ids[2 * i + a, 2 * j + b, 2 * k + c]
                            if v == 0:
                                continue
                            if v == water_a or v == water_b:
                                nw += 1
                                if v == water_b:
                                    fallw = True
                                continue
                            vals[n] = v
                            n += 1
                if n >= 4:
                    best = vals[0]
                    bc = 0
                    for q in range(n):
                        cnt = 0
                        for r in range(n):
                            if vals[r] == vals[q]:
                                cnt += 1
                        if cnt >= bc:           # ties prefer the upper voxels (later in the list)
                            bc = cnt
                            best = vals[q]
                    out[i, j, k] = best
                elif n + nw >= 4 and nw > 0:
                    out[i, j, k] = water_b if fallw else water_a
    return out


# ------------------------------------------------------------------ 2D fields
def rect_mask(xs, zs, rects):
    m = np.zeros((len(xs), len(zs)), bool)
    for (x0, x1, z0, z1) in rects:
        m |= ((xs >= x0) & (xs < x1))[:, None] & ((zs >= z0) & (zs < z1))[None, :]
    return m


def fine_fields(g, sp, holes=()):
    """Heights / surface / water for the whole grid area (+PAD columns) at the spec resolution."""
    t0 = time.time()
    FS, PAD = sp.FS, sp.PAD
    F = int(round(g.vs / FS))
    nx = int(round(g.dims[0] * g.vs / FS))
    nz = int(round(g.dims[2] * g.vs / FS))
    gx = np.arange(-PAD, nx + PAD)
    gz = np.arange(-PAD, nz + PAD)
    xs = g.origin[0] + (gx + 0.5) * FS
    zs = g.origin[2] + (gz + 0.5) * FS
    X, Z = np.meshgrid(xs, zs, indexing='ij')
    h = T.height(X, Z)
    h, water, s, d, hw = T.carve(X, Z, h)
    pd, phw = T.path_field(X, Z)
    jn = NJ.fbm(X, Z, 3.0, 3)
    ti = np.floor((h - Y0) / FS + 0.5).astype(np.int64) - 1
    in_river = ~np.isnan(water)
    lvl = T.river_level(s)
    surf = np.full(ti.shape, C.GRASS, np.uint8)
    sub = np.full(ti.shape, C.STONE if FS < 0.5 else C.CLIFF, np.uint8)
    snowy = np.full(ti.shape, 1 << 40, np.int64)
    # high ground: snow above the (noisy) snow line, bare rock on very steep faces
    snow_line = 150 + (NS.fbm(X * 0.3, Z * 0.3, 40, 3) - 0.5) * 60
    tp = np.pad(ti, 1, mode='edge')
    nb_min = np.minimum.reduce([tp[:-2, 1:-1], tp[2:, 1:-1], tp[1:-1, :-2], tp[1:-1, 2:]])
    drop = (ti - nb_min) * FS
    rock = (drop > 2.5) & (h > 105)
    surf[rock] = C.CLIFF
    surf[h > snow_line] = C.SNOW
    snowy = np.where(h > 110, np.floor((np.maximum(snow_line - 25, 110) - Y0) / FS).astype(np.int64), snowy)
    bank = (~in_river) & (d < hw + 1.2 + (jn - 0.5) * 0.8) & (h < np.nan_to_num(lvl, nan=-99) + 1.3)
    surf[bank] = np.where(jn[bank] > 0.4, C.GRAVEL, C.SAND)
    surf[in_river] = np.where(jn[in_river] > 0.5, C.RIVERBED, C.GRAVEL)
    on_path = (pd < phw + (jn - 0.5) * 0.5) & ~in_river
    surf[on_path] = C.PATH
    # coarse overrides where structures.py reshaped the ground (plots, stairs, squares, buildings)
    ci = np.clip(gx // F, 0, g.dims[0] - 1)
    ck = np.clip(gz // F, 0, g.dims[2] - 1)
    CI, CK = np.meshgrid(ci, ck, indexing='ij')
    xi, zi = np.indices(g.top.shape)
    near_struct = STRUCT_IDS[g.vox[xi, np.minimum(g.top + 1, g.dims[1] - 1), zi]] | STRUCT_IDS[g.vox[xi, g.top, zi]]
    cmod = (g.top != g.top_orig) | g.flat_mask | near_struct
    mod = cmod[CI, CK]
    ctop = g.top[CI, CK]
    ti = np.where(mod, (ctop + 1) * F - 1, ti)
    csurf = g.vox[CI, ctop, CK]
    nat = NATURAL_IDS[csurf]
    surf = np.where(mod, np.where(nat & (csurf != C.WATER) & (csurf != C.WATER_FALL), csurf, C.DIRT), surf).astype(np.uint8)
    surf[(surf == C.GRASS_CLIFF) | (surf == C.GRASS_SLOPE)] = C.GRASS
    surf[surf == C.SNOW_FULL] = C.SNOW
    # water + cascades
    wl = np.where(in_river, water, Y0)
    wt = np.where(in_river & ~mod, np.floor((wl - Y0) / FS + 0.5).astype(np.int64) - 1, -999)
    rad = max(1, int(round(2.0 / FS)))
    lim = max(2, int(round(1.25 / FS)))
    wmax = maximum_filter(wt, size=2 * rad + 1, mode='nearest')
    fall = in_river & (wmax - wt >= lim)
    # the lip above a drop reads as rapids
    wmin = -maximum_filter(np.where(in_river, -wt, -999), size=3, mode='nearest')
    fall |= in_river & (wt - wmin >= lim)
    wtop = np.where(fall, np.maximum(wt, wmax), wt)
    wtop = np.where(in_river & ~mod, wtop, -999)
    hole = rect_mask(xs, zs, holes) if holes else np.zeros(ti.shape, bool)
    ti = np.where(hole, -(1 << 40), ti)
    wtop = np.where(hole, -999, wtop)
    print(f'[{sp.key}] fields {ti.shape} at {FS} m in {time.time() - t0:.1f}s')
    return dict(ti=ti, surf=surf, sub=sub, wtop=wtop, fall=fall, snowy=snowy, nx=nx, nz=nz, mod=mod, hole=hole, F=F)


def chunk_ids(g, sp, fd, stop, cx, cz):
    """Material ids for the chunk at column (cx, cz) incl. PAD columns; returns (ids, y_lo) or None."""
    CH, PAD, F = sp.CH, sp.PAD, fd['F']
    a0, a1 = cx, cx + CH + 2 * PAD          # padded-array index = global + PAD
    b0, b1 = cz, cz + CH + 2 * PAD
    hole = fd['hole'][a0 + PAD:a1 - PAD, b0 + PAD:b1 - PAD]
    if hole.all():
        return None
    tsub = fd['ti'][a0:a1, b0:b1]
    wsub = fd['wtop'][a0:a1, b0:b1]
    valid = tsub > -(1 << 39)
    if not valid.any():
        return None
    ci0, ci1 = max(0, (cx - PAD) // F), min(g.dims[0], (cx + CH + PAD) // F + 1)
    ck0, ck1 = max(0, (cz - PAD) // F), min(g.dims[2], (cz + CH + PAD) // F + 1)
    smax = stop[ci0:ci1, ck0:ck1].max()
    y_lo = (int(tsub[valid].min()) - 6) // 4 * 4
    y_hi = int(max(tsub.max(), wsub.max(), (smax + 1) * F if smax >= 0 else -1)) + 4
    CY = (y_hi - y_lo + 3) // 4 * 4
    ids = np.zeros((CH + 2 * PAD, CY, CH + 2 * PAD), np.uint8)
    fill_natural(ids, tsub, fd['surf'][a0:a1, b0:b1], fd['sub'][a0:a1, b0:b1], wsub, fd['fall'][a0:a1, b0:b1],
                 fd['snowy'][a0:a1, b0:b1], y_lo, cx - PAD, cz - PAD, sp.grass_depth, sp.dirt_depth, sp.fuzz, sp.collision)
    if smax >= 0:
        upsample_struct(ids, g.vox, STRUCT_IDS, cx - PAD, y_lo, cz - PAD, F)
    for (fx, fy, fz, grid) in fd.get('features', ()):
        _stamp(ids, grid, fx - (cx - PAD), fy - y_lo, fz - (cz - PAD))
    return ids, y_lo


def _stamp(ids, grid, ox, oy, oz):
    X, Y, Z = ids.shape
    gx, gy, gz = grid.shape
    x0, x1 = max(0, ox), min(X, ox + gx)
    y0, y1 = max(0, oy), min(Y, oy + gy)
    z0, z1 = max(0, oz), min(Z, oz + gz)
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        return
    sub = grid[x0 - ox:x1 - ox, y0 - oy:y1 - oy, z0 - oz:z1 - oz]
    dst = ids[x0:x1, y0:y1, z0:z1]
    m = sub > 0
    dst[m] = sub[m]
    clear = sub == 254          # 254 = carve to air (treasure pit fill stays soil)
    dst[clear] = 0


def mesh_level(ids, gx0, gy0, gz0, vs, pad, n, tables, wt, origin, use_ao=True):
    """Paint + mesh one LOD level; (gx0, gy0, gz0) = global index (at this vs) of ids[0, 0, 0]."""
    enc = VX.paint_grid(ids, gx0, gy0, gz0, vs, vs <= 0.13)
    out = {}
    arr = mesher.mesh_vox(enc, tables, vs, origin, pad, pad + n, pad, pad + n, use_ao=use_ao)
    if arr is not None:
        out['vis'] = arr
    if tables['water'][enc].any():
        wa = mesher.mesh_vox(enc, wt, vs, origin, pad, pad + n, pad, pad + n, use_ao=False, solid=tables['water'])
        if wa is not None:
            out['water'] = wa
    return out


def build_chunk(g, sp, fd, stop, cx, cz, tables, wt, levels=(0, 1, 2)):
    r = chunk_ids(g, sp, fd, stop, cx, cz)
    if r is None:
        return None
    ids, y_lo = r
    FS, CH, PAD = sp.FS, sp.CH, sp.PAD
    # mesh positions relative to the chunk centre (node position) - keeps the voxel grid aligned in model space
    cxw = float(g.origin[0] + (cx + CH / 2) * FS)
    czw = float(g.origin[2] + (cz + CH / 2) * FS)
    res = []
    cur = ids
    for lvl in range(3):
        f = 1 << lvl
        vs = FS * f
        if lvl > 0:
            cur = downsample2(cur, C.WATER, C.WATER_FALL)
        if lvl not in levels:
            res.append({})
            continue
        origin = (g.origin[0] + (cx - PAD) * FS - cxw, Y0 + y_lo * FS, g.origin[2] + (cz - PAD) * FS - czw)
        res.append(mesh_level(cur, (cx - PAD) // f, y_lo // f, (cz - PAD) // f, vs, PAD // f, CH // f, tables, wt,
                              origin, use_ao=vs < 2.0))
    return res, (cxw, czw), ids, y_lo


VOX_OUT = None   # path of the runtime voxel data file (near chunks), set by world.py


def _rune_grid(rng):
    """Standing rune stone (6 x 18 x 5 voxels, 2 below ground) with glowing crystal glyphs."""
    W, H, D = 6, 18, 5
    v = np.zeros((W, H, D), np.uint8)
    for j in range(H):
        t = max(0, j - 2) / (H - 2)
        inset = 1 if t > 0.82 else 0
        v[inset:W - inset, j, (1 if t > 0.9 else 0):D - (1 if t > 0.9 else 0)] = C.STONE
    v[0, H - 1, :] = 0
    v[W - 1, H - 2:, 0] = 0
    # glyphs on both broad faces
    glyph = rng.integers(0, 3)
    for z in (0, D - 1):
        for j in range(5, H - 3):
            if glyph == 0 and (j % 4 != 0):
                v[2, j, z] = VX.CRYSTAL
            elif glyph == 1 and ((j - 5) % 5 in (0, 1, 2)):
                v[2 + (j % 2), j, z] = VX.CRYSTAL
            elif glyph == 2 and j % 3 != 1:
                v[1 + (j // 3) % 4, j, z] = VX.CRYSTAL
        v[2:4, H - 4, z] = VX.CRYSTAL
    # mossy rubble at the foot
    for a in range(-2, W + 2):
        for c in range(-2, D + 2):
            pass
    return v


def _treasure_grid(depth):
    """Buried chest (6 x 4 x 4) 'depth' voxels below the surface plus a pebble X on top. Origin = surface-relative."""
    W, D = 7, 7
    H = depth + 5
    v = np.zeros((W, H, D), np.uint8)
    chest = np.full((6, 4, 4), C.CRATE, np.uint8)
    chest[:, 3, :] = C.PLANKS_DARK
    chest[0, :, :] = VX.GOLD
    chest[5, :, :] = VX.GOLD
    chest[:, 2, 0] = VX.GOLD
    v[0:6, 0:4, 1:5] = chest
    # pebble X marks the spot (one voxel above the surface)
    for k in range(7):
        v[k, H - 1, k] = C.PEBBLE
        v[6 - k, H - 1, k] = C.PEBBLE
    return v


def make_features(g, fd, sp, manifest):
    """Rune stones and buried treasure for exploring (near area only)."""
    rng = np.random.default_rng(2024)
    ti, surf, mod, wtop = fd['ti'], fd['surf'], fd['mod'], fd['wtop']
    PAD, FS = sp.PAD, sp.FS
    nx, nz = fd['nx'], fd['nz']
    cands = []
    for gx in range(64, nx - 64, 12):
        for gz in range(64, nz - 64, 12):
            a, b = gx + PAD, gz + PAD
            if mod[a - 8:a + 9, b - 8:b + 9].any() or (wtop[a - 16:a + 17, b - 16:b + 17] > -999).any():
                continue
            if surf[a, b] != C.GRASS:
                continue
            win = ti[a - 4:a + 5, b - 4:b + 5]
            if win.max() - win.min() > 5:
                continue
            x = g.origin[0] + (gx + 0.5) * FS
            z = g.origin[2] + (gz + 0.5) * FS
            if np.hypot(x + 12, z + 32) < 30 or np.hypot(x, z) < 14:
                continue
            pd, phw = T.path_field(np.array([x]), np.array([z]))
            if pd[0] < phw[0] + 2.0:
                continue
            cands.append((gx, gz, x, z))
    order = rng.permutation(len(cands))
    runes, treasures = [], []
    for i in order:
        gx, gz, x, z = cands[i]
        if len(runes) < 8 and all(np.hypot(x - r[0], z - r[2]) > 30 for r in runes):
            runes.append((x, gx, z, gz))
        elif len(treasures) < 6 and all(np.hypot(x - r[0], z - r[2]) > 14 for r in runes) and \
                all(np.hypot(x - t_[0], z - t_[2]) > 22 for t_ in treasures):
            treasures.append((x, gx, z, gz))
    feats = []
    mk = manifest.setdefault('markers', {})
    mk['runes'] = []
    mk['treasures'] = []
    cols = manifest.setdefault('colliders', [])
    for (x, gx, z, gz) in runes:
        grid = _rune_grid(rng)
        top = int(ti[gx + PAD, gz + PAD])
        fx, fz = gx - 3, gz - 2
        feats.append((fx, top - 1, fz, grid))
        wy = Y0 + (top + 1) * FS
        mk['runes'].append([float(x), float(wy), float(z)])
        cols.append([float(x), float(wy + 1.0), float(z), 0.75, 2.0, 0.62, 0.0])
    for (x, gx, z, gz) in treasures:
        depth = int(rng.integers(8, 13))
        grid = _treasure_grid(depth)
        top = int(ti[gx + PAD, gz + PAD])
        fx, fz = gx - 3, gz - 3
        feats.append((fx, top + 2 - grid.shape[1], fz, grid))
        wy = Y0 + (top + 2 - grid.shape[1] + 2) * FS
        mk['treasures'].append([float(x), float(wy), float(z)])
    print(f'[{sp.key}] features: {len(runes)} runes, {len(treasures)} treasures')
    return feats


def build_columns(g, sp, manifest, writer, holes=()):
    import zlib
    t0 = time.time()
    fd = fine_fields(g, sp, holes)
    if sp.collision:
        fd['features'] = make_features(g, fd, sp, manifest)
    ti = fd['ti']
    nx, nz = fd['nx'], fd['nz']
    FS, CH, PAD = sp.FS, sp.CH, sp.PAD
    F = fd['F']
    tables = VX.mesher_tables()
    wt = dict(tables)
    wt['occ_water'] = tables['occluder'] | tables['water']
    stop = struct_top(g.vox, STRUCT_IDS)
    entries = []
    nq = [0, 0, 0]
    nwq = 0
    if sp.collision:
        sv = np.where(STRUCT_IDS[g.vox], g.vox, 0).astype(np.uint8)
        ssolid = STRUCT_IDS.copy()
        socc = STRUCT_IDS.copy()
    vox_f = open(VOX_OUT, 'wb') if (sp.collision and VOX_OUT) else None
    vox_index = []
    vox_off = 0
    raw_total = 0
    for cx in range(0, nx, CH):
        for cz in range(0, nz, CH):
            r = build_chunk(g, sp, fd, stop, cx, cz, tables, wt)
            if r is None:
                continue
            res, (cxw, czw), ids, y_lo = r
            ent = {'cx': cx, 'cz': cz, 'center': [cxw, czw], 'lods': []}
            for lvl, rr in enumerate(res):
                e = {}
                if 'vis' in rr:
                    nq[lvl] += len(rr['vis']['idx']) // 6
                    e['vis'] = {k: writer.put(v) for k, v in rr['vis'].items()}
                if 'water' in rr:
                    if lvl == 0:
                        nwq += len(rr['water']['idx']) // 6
                    e['water'] = {k: writer.put(v) for k, v in rr['water'].items()}
                e['range'] = list(sp.ranges[lvl])
                ent['lods'].append(e)
            if sp.collision:
                # height map (corner samples = max of the touching columns), heights in voxel units
                a0, b0 = cx + PAD - 1, cz + PAD - 1
                colh = (ti[a0:a0 + CH + 2, b0:b0 + CH + 2] + 1).astype(np.float32)
                hm = np.maximum.reduce([colh[0:CH + 1, 0:CH + 1], colh[1:CH + 2, 0:CH + 1],
                                        colh[0:CH + 1, 1:CH + 2], colh[1:CH + 2, 1:CH + 2]])
                ent['hm'] = writer.put(np.ascontiguousarray(hm.T).astype(np.float32))  # rows = z
                ent['hm_size'] = CH + 1
                ent['hm_center'] = [cxw, float(Y0), czw]
                # coarse building collision for this chunk only (replaced by exact voxels when the chunk goes live)
                ci0, ci1 = cx // F, min(g.dims[0], (cx + CH) // F)
                ck0, ck1 = cz // F, min(g.dims[2], (cz + CH) // F)
                col = mesher.mesh_collision(sv, ssolid, socc, g.vs, g.origin, ci0, ci1, ck0, ck1)
                if col is not None:
                    tri = col['pos'][col['idx']].astype(np.float32)
                    ent['scol'] = writer.put(tri)
                if vox_f is not None:
                    enc = VX.paint_grid(ids, cx - PAD, y_lo, cz - PAD, FS, True)
                    inner = np.ascontiguousarray(enc[PAD:PAD + CH, :, PAD:PAD + CH])
                    comp = zlib.compress(inner.tobytes(), 6)
                    vox_f.write(comp)
                    vox_index.append({'ix': cx // CH, 'iz': cz // CH, 'y_lo': int(y_lo), 'cy': int(inner.shape[1]),
                                      'off': vox_off, 'size': len(comp), 'raw': int(inner.size)})
                    vox_off += len(comp)
                    raw_total += inner.size
            entries.append(ent)
    if vox_f is not None:
        vox_f.close()
        manifest['near_vox'] = {'chunks': vox_index, 'cs': CH, 'vs': FS,
                                'origin': [float(g.origin[0]), Y0, float(g.origin[2])]}
        print(f'[{sp.key}] voxel data: {raw_total / 1e6:.0f} MB raw -> {vox_off / 1e6:.1f} MB compressed')
    manifest[sp.key] = {'vs': FS, 'origin': [float(g.origin[0]), Y0, float(g.origin[2])], 'chunks': entries,
                        'struct_col': [], 'fine': True}
    # surface data for scatter (strip padding)
    g.fine_vs = FS
    g.fine_top_h = np.where(fd['hole'], np.nan, Y0 + (ti + 1) * FS)[PAD:-PAD, PAD:-PAD].astype(np.float32)
    g.fine_surf = fd['surf'][PAD:-PAD, PAD:-PAD]
    g.fine_mod = fd['mod'][PAD:-PAD, PAD:-PAD]
    w = fd['wtop'][PAD:-PAD, PAD:-PAD]
    g.fine_water_h = np.where(w > -999, Y0 + (w + 1) * FS, -100.0).astype(np.float32)
    print(f'[{sp.key}] {len(entries)} chunks, quads per LOD {nq} (+{nwq} water) in {time.time() - t0:.1f}s')


def build_near(g, manifest, writer):
    build_columns(g, NEAR, manifest, writer)


def build_mid(g, manifest, writer, holes):
    build_columns(g, MID, manifest, writer, holes)


def fine_height(g, x, z, r=1):
    """Fine ground height (top surface) at world x, z; max over (2r+1)^2 columns."""
    FS = g.fine_vs
    fx = int(np.floor((x - g.origin[0]) / FS))
    fz = int(np.floor((z - g.origin[2]) / FS))
    H = g.fine_top_h
    a0, a1 = max(0, fx - r), min(H.shape[0], fx + r + 1)
    b0, b1 = max(0, fz - r), min(H.shape[1], fz + r + 1)
    if a1 <= a0 or b1 <= b0:
        return None
    return float(np.nanmax(H[a0:a1, b0:b1]))


def snap_props(g, manifest):
    """Props that stood on natural coarse ground are moved onto the fine ground."""
    moved = 0
    out = []
    FS = g.fine_vs
    for (name, x, y, z, yaw) in manifest['props']:
        i = int(np.floor((x - g.origin[0]) / g.vs))
        k = int(np.floor((z - g.origin[2]) / g.vs))
        if 0 <= i < g.dims[0] and 0 <= k < g.dims[2]:
            ct = g.origin[1] + (g.top[i, k] + 1) * g.vs
            fx = int(np.floor((x - g.origin[0]) / FS))
            fz = int(np.floor((z - g.origin[2]) / FS))
            if abs(y - ct) < 0.02 and not g.fine_mod[min(fx, g.fine_mod.shape[0] - 1), min(fz, g.fine_mod.shape[1] - 1)]:
                fh = fine_height(g, x, z, 1)
                if fh is not None and abs(fh - y) < 0.6:
                    for c in manifest['colliders']:
                        if abs(c[0] - x) < 1.5 and abs(c[2] - z) < 1.5 and abs(c[1] - c[4] / 2 - y) < 0.02:
                            c[1] += fh - y
                    for L in manifest['lights']:
                        if abs(L['pos'][0] - x) < 0.8 and abs(L['pos'][2] - z) < 0.8:
                            L['pos'][1] += fh - y
                    y = fh
                    moved += 1
        out.append((name, x, y, z, yaw))
    manifest['props'] = out
    print(f'[fine] snapped {moved} props to fine ground')
