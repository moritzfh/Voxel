"""Top-down debug map of the village area (top voxel colour + height shading + grid)."""
import sys
import numpy as np
from PIL import Image, ImageDraw
import world, structures, common as C
from minimap import COL

def main(out, x0=-70, x1=10, z0=-80, z1=12, scale=8):
    g = world.Grid('near', **world.LODS['near']); world.fill_terrain(g)
    gm = world.Grid('mid', **world.LODS['mid']); world.fill_terrain(gm, ((-96, 96, -160, 48),))
    man = {}
    structures.build_all({'near': g, 'mid': gm}, man)
    i0, i1 = int((x0 - g.origin[0]) / g.vs), int((x1 - g.origin[0]) / g.vs)
    k0, k1 = int((z0 - g.origin[2]) / g.vs), int((z1 - g.origin[2]) / g.vs)
    sub = g.vox[i0:i1, :, k0:k1]
    nz = (sub != 0) & (sub != C.WATER) & (sub != C.HOLE)
    yy = np.arange(sub.shape[1])[None, :, None]
    hi = np.where(nz, yy, -1).max(1)
    blk = np.take_along_axis(sub, np.clip(hi, 0, None)[:, None, :], 1)[:, 0, :]
    img = np.zeros(hi.shape + (3,), np.float32)
    for b, c in COL.items():
        img[blk == b] = c
    img[(img.sum(-1) == 0)] = (150, 60, 150)
    img[(sub == C.WATER).any(1)] = (50, 110, 200)
    h = g.origin[1] + (hi + 1) * g.vs
    shade = 0.55 + 0.45 * np.clip((h + 2) / 24, 0, 1)
    img = (img * shade[..., None]).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(img.transpose(1, 0, 2)).resize(((i1 - i0) * scale, (k1 - k0) * scale), Image.NEAREST)
    d = ImageDraw.Draw(im)
    for x in range(int(x0), int(x1) + 1, 5):
        px = (x - x0) / g.vs * scale
        d.line([(px, 0), (px, im.size[1])], fill=(0, 0, 0) if x % 10 == 0 else (90, 90, 90), width=1)
        if x % 10 == 0: d.text((px + 2, 2), str(x), fill=(255, 255, 255))
    for z in range(int(z0), int(z1) + 1, 5):
        pz = (z - z0) / g.vs * scale
        d.line([(0, pz), (im.size[0], pz)], fill=(0, 0, 0) if z % 10 == 0 else (90, 90, 90), width=1)
        if z % 10 == 0: d.text((2, pz + 2), str(z), fill=(255, 255, 255))
    # height labels every 5 m
    for x in range(int(x0) + 2, int(x1), 5):
        for z in range(int(z0) + 2, int(z1), 5):
            i, k = int((x - x0) / g.vs), int((z - z0) / g.vs)
            d.text(((x - x0) / g.vs * scale - 6, (z - z0) / g.vs * scale - 4), f'{h[i, k]:.0f}', fill=(255, 255, 0))
    # camera + view cone
    cx, cz = (0 - x0) / g.vs * scale, (4.6 - z0) / g.vs * scale
    for ang in (-52.5 + 0, 47.5 - 5):
        a = np.radians(ang)
        L = 900
        d.line([(cx, cz), (cx - np.sin(np.radians(52.5)) * L if ang < 0 else cx + np.sin(np.radians(42.5)) * L, cz - np.cos(np.radians(abs(ang))) * L)], fill=(255, 0, 0), width=2)
    im.save(out)
    print(im.size)

if __name__ == '__main__':
    main(sys.argv[1])
