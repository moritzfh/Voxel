"""Painted top-down minimap of the playable area."""
import numpy as np
from PIL import Image, ImageFilter
import common as C
import terrain as T

COL = {
    C.GRASS: (98, 150, 58), C.GRASS_CLIFF: (92, 140, 56), C.PATH: (196, 166, 112), C.GRAVEL: (150, 144, 130),
    C.SAND: (206, 190, 140), C.RIVERBED: (70, 130, 170), C.STONE: (140, 136, 128), C.CLIFF: (130, 126, 120),
    C.SNOW: (236, 240, 245), C.COBBLE: (128, 126, 122), C.COBBLE_MOSSY: (110, 124, 96), C.BRICKS: (140, 138, 134),
    C.BRICKS_DARK: (100, 100, 98), C.SLATE: (78, 86, 96), C.PLANKS: (150, 104, 62), C.PLANKS_DARK: (90, 62, 38),
    C.TIMBER: (100, 66, 40), C.PLASTER: (220, 210, 190), C.LOG: (100, 70, 44),
}


def build(grids, manifest, out_path, x0=-160.0, x1=160.0, z0=-220.0, z1=100.0, res=0.5):
    xs = np.arange(x0, x1, res) + res / 2
    zs = np.arange(z0, z1, res) + res / 2
    X, Z = np.meshgrid(xs, zs, indexing='xy')  # image rows = z
    img = np.zeros(X.shape + (3,), np.float32)
    H = np.zeros(X.shape, np.float32)
    filled = np.zeros(X.shape, bool)
    for name in ('near', 'mid'):
        g = grids[name]
        i = np.floor((X - g.origin[0]) / g.vs).astype(int)
        k = np.floor((Z - g.origin[2]) / g.vs).astype(int)
        ok = (i >= 0) & (k >= 0) & (i < g.dims[0]) & (k < g.dims[2]) & ~filled
        ii = np.clip(i, 0, g.dims[0] - 1)
        kk = np.clip(k, 0, g.dims[2] - 1)
        top = g.top[ii, kk]
        # highest non-air voxel (houses etc.)
        b = g.vox[ii, top, kk]
        hh = g.origin[1] + (top + 1) * g.vs
        # houses: scan upwards a few metres for roofs
        if name == 'near':
            colv = g.vox[ii, :, kk]
            nz = (colv != 0) & (colv != C.WATER) & (colv != C.HOLE)
            yy = np.arange(g.dims[1])[None, None, :]
            highest = np.where(nz, yy, -1).max(-1)
            hb = np.take_along_axis(colv, np.clip(highest, 0, None)[..., None], -1)[..., 0]
            b = np.where(highest > top, hb, b)
            hh = np.where(highest > top, g.origin[1] + (highest + 1) * g.vs, hh)
            water = (colv == C.WATER).any(-1)
        else:
            water = np.zeros(X.shape, bool)
        c = np.zeros(X.shape + (3,), np.float32)
        for blk, rgb in COL.items():
            c[b == blk] = rgb
        c[(c.sum(-1) == 0)] = (110, 110, 100)
        c[water] = (52, 120, 196)
        img = np.where(ok[..., None], c, img)
        H = np.where(ok, hh, H)
        filled |= ok
    # water from the river field for the mid region too
    d, s, lvl, hw = T.river_field(X, Z)
    riv = d < hw
    img[riv] = (52, 120, 196)
    edge = (d >= hw - 0.8) & (d < hw)
    img[edge] = (120, 180, 220)
    # hillshade
    gx = np.gradient(H, axis=1) / res
    gz = np.gradient(H, axis=0) / res
    shade = np.clip(1.0 + (-gx * 0.35 - gz * 0.25), 0.55, 1.35)
    img = img * shade[..., None]
    # trees: dark canopy blobs
    trees = manifest.get('trees', {})
    layer = np.zeros(X.shape, np.float32)
    # (tree positions were not kept; use density from multimesh buffers is complex) -> mark forest via noise of tree map below
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    out = out.filter(ImageFilter.SMOOTH)
    out.save(out_path)
    manifest['minimap'] = {'x0': x0, 'z0': z0, 'x1': x1, 'z1': z1, 'res': res}


def draw_trees(img_path, tree_positions, manifest):
    mm = manifest['minimap']
    im = Image.open(img_path).convert('RGB')
    a = np.array(im).astype(np.float32)
    res = mm['res']
    for (x, z, is_oak, s) in tree_positions:
        px = (x - mm['x0']) / res
        pz = (z - mm['z0']) / res
        r = (5.0 if not is_oak else 6.0) * s / res * 0.55
        i0, i1 = int(max(0, px - r - 1)), int(min(a.shape[1], px + r + 2))
        k0, k1 = int(max(0, pz - r - 1)), int(min(a.shape[0], pz + r + 2))
        if i1 <= i0 or k1 <= k0:
            continue
        yy, xx = np.mgrid[k0:k1, i0:i1]
        dd = np.hypot(xx - px, yy - pz)
        m = dd < r
        base = np.array([38, 82, 40]) if not is_oak else np.array([60, 110, 46])
        hi = np.array([70, 120, 60]) if not is_oak else np.array([96, 150, 70])
        t = np.clip(1 - dd / r, 0, 1)[..., None]
        light = ((xx - px) < 0) & ((yy - pz) < 0)
        col = base + (hi - base) * (t * 0.6 + light[..., None] * 0.3)
        a[k0:k1, i0:i1][m] = col[m]
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(img_path)
