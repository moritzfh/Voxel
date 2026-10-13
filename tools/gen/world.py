"""Build voxel grids for all LODs, stamp structures, export meshes + instances."""
import json
import os
import sys
import time
import numpy as np

import common as C
from common import Noise2D, smoothstep
import terrain as T
import mesher
import textures

OUT = sys.argv[1] if len(sys.argv) > 1 else '../out'

LODS = {
    'near': dict(vs=0.5, origin=(-96.0, -8.0, -160.0), dims=(384, 128, 416), chunk=64, uv_unit=0.5),
    'mid': dict(vs=1.0, origin=(-416.0, -8.0, -560.0), dims=(832, 232, 840), chunk=128, uv_unit=1.0),
    'back': dict(vs=2.0, origin=(-420.0, -8.0, -1340.0), dims=(660, 320, 390), chunk=110, uv_unit=4.0),
    'far': dict(vs=4.0, origin=(-1800.0, -8.0, -2000.0), dims=(900, 160, 850), chunk=128, uv_unit=4.0),
}

NS = Noise2D(77)


class Grid:
    def __init__(self, name, vs, origin, dims, chunk, uv_unit):
        self.name = name
        self.vs = vs
        self.origin = np.array(origin, np.float64)
        self.dims = dims
        self.chunk = chunk
        self.uv_unit = uv_unit
        self.vox = np.zeros(dims, np.uint8)  # [x, y, z]
        self.top = None

    def col_centers(self):
        X, _, Z = self.dims
        xs = self.origin[0] + (np.arange(X) + 0.5) * self.vs
        zs = self.origin[2] + (np.arange(Z) + 0.5) * self.vs
        return np.meshgrid(xs, zs, indexing='ij')  # [x, z]

    def yi(self, y):
        """voxel index whose bottom is at world y."""
        return int(np.floor((y - self.origin[1]) / self.vs + 1e-6))

    def world_to_index(self, x, y, z):
        return (int(np.floor((x - self.origin[0]) / self.vs)), int(np.floor((y - self.origin[1]) / self.vs)),
                int(np.floor((z - self.origin[2]) / self.vs)))


def fill_terrain(g, holes=()):
    t0 = time.time()
    X, Z = g.col_centers()
    h = T.height(X, Z)
    h, water, s, d, hw = T.carve(X, Z, h)
    pd, phw = T.path_field(X, Z)
    vs = g.vs
    # quantise
    top = np.round((h - g.origin[1]) / vs).astype(np.int64) - 1  # index of top solid voxel
    top = np.clip(top, 0, g.dims[1] - 1)
    g.top = top
    g.top_orig = top.copy()
    g.flat_mask = np.zeros(top.shape, bool)
    g.height = h
    g.water = water
    g.river_d = d
    g.river_hw = hw
    g.path_d = pd
    g.path_hw = phw
    Y = g.dims[1]
    iy = np.arange(Y)[None, :, None]
    t3 = top[:, None, :]
    vox = g.vox
    solid = iy <= t3
    # base material: stone deep down, dirt below top
    dirt_depth = 2 if vs <= 0.5 else 0
    mountain = vs >= 2.0
    vox[solid] = C.STONE if vs <= 0.5 else (C.MOUNTAIN_ROCK if mountain else C.CLIFF)
    if dirt_depth:
        vox[(iy <= t3) & (iy > t3 - 1 - dirt_depth)] = C.DIRT
    # steepness: compare to neighbours
    tp = np.pad(top, 1, mode='edge')
    nb_min = np.minimum.reduce([tp[:-2, 1:-1], tp[2:, 1:-1], tp[1:-1, :-2], tp[1:-1, 2:]])
    drop = top - nb_min  # voxels of cliff below this column
    # surface material
    surf = np.full(top.shape, C.GRASS, np.uint8)
    wy = (h - g.origin[1]) / vs
    world_h = h
    jn = NS.fbm(X, Z, 9, 2)
    # snow
    snow_line = 150 + (NS.fbm(X * 0.3, Z * 0.3, 40, 3) - 0.5) * 60
    if mountain:
        snow_line = 175 + (NS.fbm(X * 0.6, Z * 0.6, 30, 3) - 0.5) * 70
    surf = np.where(world_h > snow_line, C.SNOW, surf)
    # cliffs get bare rock tops in high mountains
    steep_rock = (drop * vs > (8 if mountain else 20)) & (world_h > 120)
    surf = np.where(steep_rock & (world_h <= snow_line), C.MOUNTAIN_ROCK if mountain else C.CLIFF, surf)
    # river beds and banks
    in_river = ~np.isnan(water)
    bank = (~in_river) & (d < hw + 1.2) & (world_h < np.nan_to_num(T.river_level(s), nan=-99) + 1.3)
    surf = np.where(bank & (jn > 0.45), C.GRAVEL, surf)
    surf = np.where(bank & (jn <= 0.45), C.SAND if vs >= 1 else C.GRAVEL, surf)
    surf = np.where(in_river, np.where(jn > 0.5, C.RIVERBED, C.GRAVEL), surf)
    # paths
    if vs <= 1.0:
        on_path = pd < phw
        surf = np.where(on_path & ~in_river, C.PATH, surf)
        edge = (pd >= phw) & (pd < phw + 0.6) & (jn > 0.55)
        surf = np.where(edge & ~in_river & (surf == C.GRASS), C.PATH, surf)
    if vs >= 1.0:
        gentle = drop <= (2 if vs <= 1.0 else 1)
        surf = np.where(surf == C.GRASS, np.where(gentle, C.GRASS_SLOPE, C.GRASS_CLIFF), surf)
    # write surface voxel
    xi, zi = np.indices(top.shape)
    vox[xi, top, zi] = surf
    # snow: cover rock faces above the snow line (patchy near the line, solid higher up)
    if vs >= 1.0 and not mountain:
        sn = NS.fbm(X * 0.7, Z * 0.7, 18, 3)
        for_y = g.origin[1] + (np.arange(g.dims[1]) + 0.5) * vs
        lo = np.searchsorted(for_y, 110.0)
        for j in range(lo, g.dims[1]):
            yw = for_y[j]
            col = vox[:, j, :]
            rock = (col == C.CLIFF) | (col == C.GRASS_CLIFF) | (col == C.GRASS_SLOPE) | (col == C.STONE)
            thr = np.clip((snow_line + 90 - yw) / 110.0, 0.0, 1.0) * 0.35 + 0.52
            cover = rock & (sn + (yw - snow_line) * 0.0016 > thr)
            col[cover] = C.SNOW_FULL
        # surface top above the line is always snow
        top_snow = (world_h > snow_line + 15) & ((surf == C.CLIFF) | (surf == C.GRASS_CLIFF) | (surf == C.GRASS_SLOPE) | (surf == C.SNOW))
        vox[xi, top, zi] = np.where(top_snow, C.SNOW, vox[xi, top, zi])
    if mountain:
        # rock walls stay rock; only light snow streaks high up, ledges (tops) are snowy
        sn = NS.fbm(X * 1.3, Z * 1.3, 10, 3)
        for_y = g.origin[1] + (np.arange(g.dims[1]) + 0.5) * vs
        lo = np.searchsorted(for_y, 170.0)
        streak = NS.fbm(X * 3.1, Z * 3.1, 6, 2)
        for j in range(lo, g.dims[1]):
            yw = for_y[j]
            col = vox[:, j, :]
            rock = col == C.MOUNTAIN_ROCK
            # vertical snow streaks / gullies down the faces, denser higher up
            cover = rock & (streak * 0.6 + sn * 0.4 + (yw - snow_line - 30) * 0.0035 > 0.69)
            col[cover] = C.SNOW_FULL
            # snow lip: the voxel row right under each ledge top
        lip = (world_h > snow_line - 20)
        vox[xi, np.clip(top - 1, 0, None), zi] = np.where(lip & (vox[xi, np.clip(top - 1, 0, None), zi] == C.MOUNTAIN_ROCK) & (sn > 0.45), C.SNOW_FULL, vox[xi, np.clip(top - 1, 0, None), zi])
        top_snow = (world_h > snow_line) & ((surf == C.MOUNTAIN_ROCK) | (surf == C.GRASS_CLIFF) | (surf == C.GRASS_SLOPE) | (surf == C.SNOW))
        vox[xi, top, zi] = np.where(top_snow, C.SNOW, vox[xi, top, zi])
    # water
    if in_river.any():
        lvl = np.where(in_river, water, np.nan)
        wtop = np.round((lvl - g.origin[1]) / vs).astype(np.float64) - 1
        wtop = np.where(in_river, wtop, -1).astype(np.int64)
        wm = (iy > t3) & (iy <= wtop[:, None, :])
        vox[wm] = C.WATER
        # cascades: columns just below a level drop get a water curtain up to the upper level
        from scipy.ndimage import maximum_filter
        wt = np.where(in_river, wtop, -999)
        rad = max(1, int(round(2.0 / vs)))
        wmax = maximum_filter(wt, size=2 * rad + 1, mode='nearest')
        lim = max(2, int(round(1.4 / vs)))
        fall = in_river & (wmax - wt >= lim)
        # also mark the lip (upper columns next to the drop) as falling water so the surface reads as rapids
        wmin = -maximum_filter(np.where(in_river, -wtop, -999), size=3, mode='nearest')
        lip = in_river & (wt - wmin >= lim)
        cm = (iy > t3) & (iy <= wmax[:, None, :]) & fall[:, None, :]
        vox[cm] = C.WATER_FALL
        lm = wm & lip[:, None, :]
        vox[lm] = C.WATER_FALL
    for hole in holes:
        hx0, hx1, hz0, hz1 = hole
        i0 = int(round((hx0 - g.origin[0]) / vs))
        i1 = int(round((hx1 - g.origin[0]) / vs))
        k0 = int(round((hz0 - g.origin[2]) / vs))
        k1 = int(round((hz1 - g.origin[2]) / vs))
        vox[max(0, i0):max(0, i1), :, max(0, k0):max(0, k1)] = C.HOLE
    print(f'[{g.name}] terrain filled in {time.time() - t0:.1f}s, top max {top.max()}')


# ------------------------------------------------------------------ export
class Writer:
    def __init__(self, path):
        self.f = open(path, 'wb')
        self.off = 0

    def put(self, arr):
        b = np.ascontiguousarray(arr).tobytes()
        o = self.off
        self.f.write(b)
        self.off += len(b)
        return [o, len(b)]

    def close(self):
        self.f.close()


def export_grid(g, blocks, writer, manifest, kind='terrain'):
    t0 = time.time()
    X, Y, Z = g.dims
    cs = g.chunk
    entries = []
    nq_total = 0
    water_blocks = dict(blocks)
    wsolid = np.zeros(256, np.bool_)
    wsolid[C.WATER] = True
    wsolid[C.WATER_FALL] = True
    wocc = blocks['occluder'].copy()
    wocc[C.WATER] = True
    wocc[C.WATER_FALL] = True
    for cx in range(0, X, cs):
        for cz in range(0, Z, cs):
            x1 = min(X, cx + cs)
            z1 = min(Z, cz + cs)
            sub = g.vox[cx:x1, :, cz:z1]
            if not np.any((sub > 0) & (sub < 255)):
                continue
            ent = {'cx': cx, 'cz': cz}
            arr = mesher.mesh_grid(g.vox, blocks, g.vs, g.origin, cx, x1, cz, z1, g.uv_unit, use_ao=(g.name != 'far'))
            if arr is not None:
                nq_total += len(arr['idx']) // 6
                ent['vis'] = {k: writer.put(v) for k, v in arr.items()}
                ent['nv'] = int(len(arr['pos']))
                ent['ni'] = int(len(arr['idx']))
            if g.name == 'near':
                col = mesher.mesh_grid(g.vox, blocks, g.vs, g.origin, cx, x1, cz, z1, g.uv_unit, collision=True)
                if col is not None:
                    tri = col['pos'][col['idx']].astype(np.float32)
                    ent['col'] = writer.put(tri)
                    ent['ncol'] = int(len(tri))
            # water
            if np.any((sub == C.WATER) | (sub == C.WATER_FALL)):
                wb = dict(blocks)
                wb['solid'] = wsolid
                wb['occluder'] = wocc
                for key in ('top', 'side', 'bottom'):
                    arr = blocks[key].copy()
                    arr[C.WATER] = 62
                    arr[C.WATER_FALL] = 63
                    wb[key] = arr
                wa = mesher.mesh_grid(g.vox, wb, g.vs, g.origin, cx, x1, cz, z1, g.uv_unit, use_ao=False)
                if wa is not None:
                    ent['water'] = {k: writer.put(v) for k, v in wa.items()}
                    ent['nwv'] = int(len(wa['pos']))
            if len(ent) > 2:
                entries.append(ent)
    manifest[g.name] = {'vs': g.vs, 'origin': list(g.origin), 'chunks': entries}
    print(f'[{g.name}] meshed {len(entries)} chunks, {nq_total} quads in {time.time() - t0:.1f}s')


def export_vox_grid(g, writer, manifest):
    """Colour-voxel export of a coarse LOD grid (mid / back / far)."""
    import vox as VX
    t0 = time.time()
    X, Y, Z = g.dims
    cs = g.chunk
    o = [int(round(g.origin[i] / g.vs)) for i in range(3)]
    enc = VX.paint_grid(g.vox, o[0], o[1], o[2], 0.5, False)   # large colour patches, no speckles: merges well
    tables = VX.mesher_tables()
    wt = dict(tables)
    wt['occ_water'] = tables['occluder'] | tables['water']
    entries = []
    nq_total = 0
    for cx in range(0, X, cs):
        for cz in range(0, Z, cs):
            x1 = min(X, cx + cs)
            z1 = min(Z, cz + cs)
            sub = g.vox[cx:x1, :, cz:z1]
            if not np.any((sub > 0) & (sub < 255)):
                continue
            ent = {'cx': cx, 'cz': cz}
            arr = mesher.mesh_vox(enc, tables, g.vs, g.origin, cx, x1, cz, z1, use_ao=(g.name != 'far'))
            if arr is not None:
                nq_total += len(arr['idx']) // 6
                ent['vis'] = {k: writer.put(v) for k, v in arr.items()}
            if np.any((sub == C.WATER) | (sub == C.WATER_FALL)):
                wa = mesher.mesh_vox(enc, wt, g.vs, g.origin, cx, x1, cz, z1, use_ao=False, solid=tables['water'])
                if wa is not None:
                    ent['water'] = {k: writer.put(v) for k, v in wa.items()}
            if len(ent) > 2:
                entries.append(ent)
    manifest[g.name] = {'vs': g.vs, 'origin': list(g.origin), 'chunks': entries}
    print(f'[{g.name}] vox meshed {len(entries)} chunks, {nq_total} quads in {time.time() - t0:.1f}s')


def export_props(manifest, writer, blocks, custom={}):
    import props as PR
    import models
    from scatter import xform_rows
    meshes = {}
    gens = dict(PR.PROPS)
    for name, vo in custom.items():
        gens[name] = (lambda vo=vo: vo)
    used = {p[0] for p in manifest['props']}
    for name, fn in gens.items():
        if name not in used:
            continue
        v, org = fn()
        arr = models.mesh_model(v, blocks, PR.PV, 0.5, origin=org)
        meshes[name] = {k: writer.put(a) for k, a in arr.items()}
    inst = {}
    for (name, x, y, z, yaw) in manifest['props']:
        inst.setdefault(name, []).append((x, y, z, yaw))
    out = {'meshes': meshes, 'groups': []}
    for name, lst in inst.items():
        a = np.array(lst, np.float64)
        buf = xform_rows(a[:, 0], a[:, 1], a[:, 2], a[:, 3], np.ones(len(a)))
        out['groups'].append({'mesh': name, 'n': len(a), 'buf': writer.put(buf)})
    manifest['props_inst'] = out
    print('props', {k: len(v) for k, v in inst.items()})


def build_clouds(manifest, writer):
    import flora
    import models
    from scatter import xform_rows
    rng = np.random.default_rng(808)
    shapes = {}
    for i, (w, d) in enumerate(((70, 40), (100, 54), (54, 34), (130, 64), (84, 46), (60, 50))):
        v, o = flora.cloud(rng, w, d)
        shapes[f'cloud{i}'] = models.mesh_model(v, None, flora.CLOUD_VS, origin=o, use_ao=True)
    groups = {}
    n = 0
    tries = 0
    pts = []
    while n < 64 and tries < 5000:
        tries += 1
        x = rng.uniform(-1700, 1700)
        z = rng.uniform(-2000, 1300)
        if any((x - px) ** 2 + (z - pz) ** 2 < 230 ** 2 for px, pz in pts):
            continue
        pts.append((x, z))
        y = rng.uniform(255, 335)
        name = f'cloud{rng.integers(0, len(shapes))}'
        groups.setdefault(name, []).append((x, y, z, 0.0))
        n += 1
    out = {'meshes': {k: {kk: writer.put(vv) for kk, vv in a.items()} for k, a in shapes.items()}, 'groups': []}
    for name, lst in groups.items():
        a = np.array(lst, np.float64)
        buf = xform_rows(a[:, 0], a[:, 1], a[:, 2], a[:, 3], np.ones(len(a)))
        out['groups'].append({'mesh': name, 'n': len(a), 'buf': writer.put(buf)})
    manifest['clouds'] = out
    print('clouds', n, {k: len(a['idx']) // 6 for k, a in shapes.items()})


def main():
    os.makedirs(OUT, exist_ok=True)
    blocks = C.block_tables(textures.TILE_INDEX)   # legacy tables (solid/occluder flags for collision helpers)
    manifest = {}
    writer = Writer(os.path.join(OUT, 'world.bin'))
    near_rect = (-96.0, 96.0, -160.0, 48.0)
    mid_rect = (-416.0, 416.0, -560.0, 280.0)
    back_rect = (-420.0, 900.0, -1340.0, -560.0)
    holes = {'near': (), 'mid': (near_rect,), 'back': (), 'far': (mid_rect, back_rect)}
    grids = {}
    for name, spec in LODS.items():
        g = Grid(name, **spec)
        fill_terrain(g, holes[name])
        grids[name] = g
    import structures
    structures.build_all(grids, manifest)
    import vox as VX
    import fine
    pal, em, rough, jit = VX.shader_tables()
    manifest['palette'] = {'pal': pal.reshape(-1).tolist(), 'em': em.tolist(), 'rough': rough.tolist(),
                           'jit': jit.tolist()}
    fine.VOX_OUT = os.path.join(OUT, 'near_vox.bin')
    fine.build_near(grids['near'], manifest, writer)
    fine.snap_props(grids['near'], manifest)
    fine.build_mid(grids['mid'], manifest, writer, holes['mid'])
    for name in ('back', 'far'):
        export_vox_grid(grids[name], writer, manifest)
    import scatter
    import rocks
    rock_mask = rocks.scatter_rocks(grids, manifest, writer, blocks, grids['near'].nogo)
    tree_pos = scatter.scatter_all(grids, manifest, writer, blocks=blocks, fields=grids['near'].fields, nogo=grids['near'].nogo | rock_mask)
    import minimap
    mm_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../assets/ui/minimap.png')
    minimap.build(grids, manifest, mm_path)
    minimap.draw_trees(mm_path, tree_pos, manifest)
    export_props(manifest, writer, blocks, getattr(grids['near'], 'custom_props', {}))
    import character
    manifest['characters'] = character.build_characters(writer)
    build_clouds(manifest, writer)
    # runtime voxel models (trees / rocks) + material table for mining and building
    import models as MD
    mf = open(os.path.join(OUT, 'models_vox.bin'), 'wb')
    idx = {}
    off = 0
    import zlib
    for name, m in MD.REGISTRY.items():
        comp = zlib.compress(np.ascontiguousarray(m['data']).tobytes(), 6)
        mf.write(comp)
        idx[name] = {'off': off, 'size': len(comp), 'raw': int(m['data'].size), 'dims': list(m['data'].shape),
                     'origin': m['origin'], 'vs': m['vs']}
        off += len(comp)
    mf.close()
    manifest['models_vox'] = idx
    mats = {}
    for mid, (mname, cols, em, rough, jit) in VX.MATERIALS.items():
        mats[str(mid)] = {'name': mname, 'hard': VX.HARD.get(mid, 255), 'res': VX.RES.get(mid, ''), 'color': cols[0]}
    manifest['materials'] = mats
    print('model voxels', len(idx), 'models,', off // 1024, 'KB')
    # water surface height map for the playable area (swimming)
    g = grids['near']
    fw = g.fine_water_h  # [x, z] at 0.125 m -> max per 0.5 m cell
    X4, Z4 = fw.shape[0] // 4, fw.shape[1] // 4
    wl = fw[:X4 * 4, :Z4 * 4].reshape(X4, 4, Z4, 4).max(axis=(1, 3)).T.astype(np.float32).copy()  # rows = z
    manifest['water_map'] = {'buf': writer.put(wl), 'w': int(g.dims[0]), 'h': int(g.dims[2]), 'x0': float(g.origin[0]), 'z0': float(g.origin[2]), 'res': float(g.vs)}
    # waterfalls: where the river level drops by more than 1.5 m within a few metres
    ss, lv = T._build_profile()
    falls = []
    i = 0
    while i < len(ss) - 1:
        j = i
        while j + 1 < len(ss) and ss[j + 1] - ss[i] < 6.0:
            j += 1
        drop = lv[i] - lv[j]
        if drop > 1.4:
            k = i
            while k < j and lv[k + 1] == lv[k]:
                k += 1
            x = float(np.interp(ss[j], T.RIVER_S, T.RIVER_XZ[:, 0]))
            z = float(np.interp(ss[j], T.RIVER_S, T.RIVER_XZ[:, 1]))
            falls.append([x, float(lv[j]), z, float(drop), float(T.river_halfwidth(np.array([ss[j]]))[0])])
            i = j + 1
        else:
            i += 1
    manifest['markers']['waterfalls'] = falls
    print('waterfalls', [(round(f[0]), round(f[1]), round(f[2]), round(f[3], 1)) for f in falls])
    writer.close()
    with open(os.path.join(OUT, 'world.json'), 'w') as f:
        json.dump(manifest, f)
    print('done')


if __name__ == '__main__':
    main()
