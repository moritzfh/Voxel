"""Isometric voxel icons for the build shapes, modes and the blueprint slot (PIL, supersampled)."""
import math
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 512
OUT = 128
TOP = (238, 224, 190)
LEFT = (198, 178, 140)
RIGHT = (146, 124, 92)


def shape(kind, X, Y, Z, hollow=False, th=1, open_top=False, open_bottom=False, half=False, step=1, crenel=0):
    """same formulas as VoxelObject::fill_shape (C++), small resolution"""
    g = np.zeros((X, Y, Z), bool)
    cx, cz = X * 0.5, Z * 0.5
    for i in range(X):
        for j in range(Y):
            for k in range(Z):
                x, y, z = i + 0.5, j + 0.5, k + 0.5
                if kind == 0:
                    inn = True
                    if hollow:
                        inn = i < th or i >= X - th or k < th or k >= Z - th or (not open_bottom and j < th) or (not open_top and j >= Y - th)
                elif kind == 1:
                    rx, rz = X * 0.5, Z * 0.5
                    ry = Y if half else Y * 0.5
                    cy = 0.0 if half else Y * 0.5
                    q = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2
                    inn = q <= 1.0
                    if inn and hollow:
                        ix, iy, iz = max(0.5, rx - th), max(0.5, ry - th), max(0.5, rz - th)
                        inn = ((x - cx) / ix) ** 2 + ((y - cy) / iy) ** 2 + ((z - cz) / iz) ** 2 > 1.0
                elif kind == 2:
                    rx, rz = X * 0.5, Z * 0.5
                    q = ((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2
                    inn = q <= 1.0
                    if inn and hollow:
                        ix, iz = max(0.5, rx - th), max(0.5, rz - th)
                        inn = ((x - cx) / ix) ** 2 + ((z - cz) / iz) ** 2 > 1.0 or (not open_bottom and j < th) or (not open_top and j >= Y - th)
                elif kind == 3:
                    ow = max(1.0, X - 2.0 * th)
                    r = ow * 0.5
                    hs = max(0.0, Y - th - r)
                    dx = x - cx
                    op = False
                    if abs(dx) < r:
                        op = True if y < hs else dx * dx + (y - hs) ** 2 < r * r
                    inn = not op
                elif kind == 4:
                    n = max(1, (Y + step - 1) // step)
                    depth = Z / n
                    si = min(n - 1, int(z / depth))
                    inn = j < min(Y, (si + 1) * step)
                elif kind == 5:
                    h = (z / Z * Y) if half else min(z, Z - z) / (Z * 0.5) * Y
                    inn = y <= h + 0.25
                    if inn and hollow:
                        inn = y > h - th * 1.4
                elif kind == 6:
                    if j < th or j >= Y - th:
                        inn = True
                    else:
                        inn = ((x - cx) / (X * 0.36)) ** 2 + ((z - cz) / (Z * 0.36)) ** 2 <= 1.0
                elif kind == 8:
                    inn = y <= z / Z * Y + 0.25
                else:
                    inn = True
                if inn and crenel > 0 and j >= Y - crenel and Y > crenel * 2:
                    if kind == 2:
                        circ = math.pi * (X + Z) * 0.5
                        nseg = max(4, int(round(circ / (crenel * 2.0))) * 2)
                        a = math.atan2(z - cz, x - cx) + math.pi
                        inn = (min(nseg - 1, int(a / (2 * math.pi) * nseg)) & 1) == 0
                    else:
                        inn = ((i // crenel + k // crenel) & 1) == 0
                g[i, j, k] = inn
    return g


def render(g, colors=None, scale=None):
    """painter's algorithm isometric voxels; camera looks from +x +z, up"""
    nz = np.nonzero(g)
    if colors is None and len(nz[0]):
        g = g[nz[0].min():nz[0].max() + 1, nz[1].min():nz[1].max() + 1, nz[2].min():nz[2].max() + 1]
    X, Y, Z = g.shape
    span = max(X + Z, Y * 1.25 + (X + Z) * 0.5)
    w = (S * 0.84) / ((X + Z) * 0.866) if scale is None else scale
    w = min(w, (S * 0.84) / (Y + (X + Z) * 0.5))
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # screen projection of a point
    def P(x, y, z):
        sx = (x - z) * 0.866 * w
        sy = (x + z) * 0.5 * w - y * w
        return sx, sy
    # bounds for centring
    pts = [P(x, y, z) for x in (0, X) for y in (0, Y) for z in (0, Z)]
    minx = min(p[0] for p in pts); maxx = max(p[0] for p in pts)
    miny = min(p[1] for p in pts); maxy = max(p[1] for p in pts)
    ox = S * 0.5 - (minx + maxx) * 0.5
    oy = S * 0.5 - (miny + maxy) * 0.5

    def Q(x, y, z):
        a, b = P(x, y, z)
        return (a + ox, b + oy)

    def solid(i, j, k):
        return 0 <= i < X and 0 <= j < Y and 0 <= k < Z and g[i, j, k]
    order = sorted(((i, j, k) for i in range(X) for j in range(Y) for k in range(Z) if g[i, j, k]),
                   key=lambda t: (t[0] + t[2], t[1]))
    for i, j, k in order:
        ct, cl, cr = (TOP, LEFT, RIGHT) if colors is None else colors(i, j, k)
        if not solid(i, j + 1, k):
            d.polygon([Q(i, j + 1, k), Q(i + 1, j + 1, k), Q(i + 1, j + 1, k + 1), Q(i, j + 1, k + 1)], fill=ct)
        if not solid(i, j, k + 1):
            d.polygon([Q(i, j, k + 1), Q(i + 1, j, k + 1), Q(i + 1, j + 1, k + 1), Q(i, j + 1, k + 1)], fill=cl)
        if not solid(i + 1, j, k):
            d.polygon([Q(i + 1, j, k), Q(i + 1, j, k + 1), Q(i + 1, j + 1, k + 1), Q(i + 1, j + 1, k)], fill=cr)
    return im


def outline(im, color=(20, 14, 10, 255), grow=9):
    a = im.split()[3]
    big = a.filter(ImageFilter.MaxFilter(grow * 2 + 1))
    base = Image.new('RGBA', im.size, color)
    base.putalpha(big)
    base.alpha_composite(im)
    return base


def save(im, path):
    outline(im).resize((OUT, OUT), Image.LANCZOS).save(path)


def tinted(top, left, right):
    return lambda i, j, k: (top, left, right)


ROOF = ((196, 92, 70), (160, 70, 52), (118, 50, 38))
WOOD = ((214, 166, 112), (176, 128, 80), (128, 90, 56))
GLASS = ((190, 228, 245), (150, 200, 225), (110, 160, 190))


def house():
    W, H, D = 10, 6, 8
    RH = 5
    g = np.zeros((W + 2, H + RH, D + 2), bool)
    col = {}
    walls = shape(0, W, H, D, hollow=True, th=1, open_top=True, open_bottom=True)
    g[1:W + 1, 0:H, 1:D + 1] |= walls
    gable = shape(5, W, RH, D)
    for i in range(W):
        if i < 1 or i >= W - 1:
            g[1 + i, H:H + RH, 1:D + 1] |= gable[i]
    roof = shape(5, W + 2, RH, D + 2, hollow=True, th=1)
    for (i, j, k) in zip(*np.nonzero(roof)):
        g[i, H + j, k] = True
        col[(i, H + j, k)] = ROOF
    # door + windows (front face at k = D: camera sees +z side as "left")
    for j in range(0, 4):
        for i in range(5, 7):
            g[i, j, D] = False
    for (i, j, k) in [(2, 3, D), (3, 3, D), (8, 3, D), (9, 3, D)]:
        col[(i, j, k)] = GLASS
    for (i, j, k) in [(W, 3, 3), (W, 3, 4), (W, 3, 6), (W, 3, 7)]:
        col[(i, j, k)] = GLASS

    def c(i, j, k):
        return col.get((i, j, k), (TOP, LEFT, RIGHT))
    return render(g, c)


def brush():
    X = Y = Z = 12
    g = np.zeros((X, Y, Z), bool)
    for (cx, cy, cz, r) in [(4, 4, 6, 3.6), (7.5, 6, 6, 3.2), (9.5, 8.5, 6, 2.4)]:
        for i in range(X):
            for j in range(Y):
                for k in range(Z):
                    if (i + 0.5 - cx) ** 2 + (j + 0.5 - cy) ** 2 + (k + 0.5 - cz) ** 2 <= r * r:
                        g[i, j, k] = True
    nz = np.nonzero(g)
    j0 = nz[1].min()
    g = g[nz[0].min():nz[0].max() + 1, j0:nz[1].max() + 1, nz[2].min():nz[2].max() + 1]
    return render(g, lambda i, j, k: ((150, 205, 110), (110, 170, 80), (80, 128, 60)) if j + j0 >= 5 else (TOP, LEFT, RIGHT))


def blueprint():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([60, 70, 452, 442], 18, fill=(46, 96, 168, 255))
    for t in range(0, 9):
        x = 60 + t * 49
        d.line([(x, 70), (x, 442)], fill=(90, 140, 205, 255), width=3)
        y = 70 + t * 46.5
        d.line([(60, y), (452, y)], fill=(90, 140, 205, 255), width=3)
    pts = [(150, 380), (150, 250), (256, 160), (362, 250), (362, 380)]
    d.line(pts + [pts[0]], fill=(240, 246, 255, 255), width=14, joint='curve')
    d.rectangle([232, 300, 280, 380], outline=(240, 246, 255, 255), width=10)
    return im


def paint():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # brush handle + ferrule + bristles dipped in colour
    d.polygon([(330, 70), (372, 112), (238, 262), (196, 220)], fill=(150, 96, 52, 255))
    d.polygon([(196, 220), (238, 262), (214, 290), (168, 246)], fill=(200, 206, 214, 255))
    d.polygon([(168, 246), (214, 290), (150, 380), (96, 412), (118, 320)], fill=(226, 82, 60, 255))
    d.ellipse([90, 400, 160, 440], fill=(226, 82, 60, 255))
    return im


def copy_icon():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([90, 90, 330, 330], 16, outline=(238, 224, 190, 255), width=22)
    d.rounded_rectangle([182, 182, 422, 422], 16, fill=(90, 150, 220, 255), outline=(238, 224, 190, 255), width=22)
    return im


def build(out):
    os.makedirs(out, exist_ok=True)
    icons = {
        'quader': render(shape(0, 7, 7, 7)),
        'wand': render(shape(0, 12, 8, 2, crenel=2)),
        'boden': render(shape(0, 11, 1, 11), tinted(*WOOD)),
        'raum': render(shape(0, 11, 6, 9, hollow=True, open_top=True)),
        'haus': house(),
        'pinsel': brush(),
        'kugel': render(shape(1, 12, 7, 12, half=True)),
        'turm': render(shape(2, 13, 13, 13, hollow=True, th=1, crenel=2)),
        'treppe': render(shape(4, 7, 8, 10, step=1)[:, :, ::-1].copy()),
        'dach': render(shape(5, 16, 7, 14)[:, :, :].copy(), tinted(*ROOF)),
        'bogen': render(shape(3, 11, 11, 3, th=2)),
        'bauplan': blueprint(),
        'faerben': paint(),
        'kopieren': copy_icon(),
    }
    for k, im in icons.items():
        save(im, os.path.join(out, 'shape_%s.png' % k))
    print('shape icons', len(icons))


if __name__ == '__main__':
    build(sys.argv[1] if len(sys.argv) > 1 else '../../assets/ui')
