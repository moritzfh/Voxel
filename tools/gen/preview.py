"""Fast composition preview: numba heightfield ray-caster from the reference camera."""
import sys
import numpy as np
from numba import njit, prange
from PIL import Image
import terrain as T

W, H = 836, 470
CAM = np.array([0.0, 2.35, 4.6])
PITCH = -4.0
YAW = 0.0
VFOV = 62.0


def build_lod(x0, x1, z0, z1, res):
    xs = np.arange(x0, x1, res) + res / 2
    zs = np.arange(z0, z1, res) + res / 2
    X, Z = np.meshgrid(xs, zs)
    h = T.height(X, Z)
    h, water, s, d, hw = T.carve(X, Z, h)
    pd, _ = T.path_field(X, Z)
    mat = np.zeros(h.shape, np.int64)
    mat[pd < 1.4] = 1
    w = np.where(np.isnan(water), -1e9, water)
    return dict(h=np.round(h / res * 0 + h * 2) / 2 if res < 1 else h, w=w, mat=mat, x0=x0, z0=z0, res=res)


@njit(cache=True)
def sample(h, x0, z0, res, x, z):
    i = int((x - x0) / res)
    k = int((z - z0) / res)
    if i < 0 or k < 0 or k >= h.shape[0] or i >= h.shape[1]:
        return -1e9
    return h[k, i]


@njit(parallel=True, cache=True)
def trace(img, cam, fwd, right, up, tanv, tanh, hs, ws, ms, x0s, z0s, ress, nl, sun):
    Hh, Ww = img.shape[0], img.shape[1]
    for py in prange(Hh):
        for px in range(Ww):
            sx = (px + 0.5) / Ww * 2 - 1
            sy = 1 - (py + 0.5) / Hh * 2
            dx = fwd[0] + right[0] * sx * tanh + up[0] * sy * tanv
            dy = fwd[1] + right[1] * sx * tanh + up[1] * sy * tanv
            dz = fwd[2] + right[2] * sx * tanh + up[2] * sy * tanv
            L = np.sqrt(dx * dx + dy * dy + dz * dz)
            dx /= L
            dy /= L
            dz /= L
            t = 0.2
            hit = False
            col = np.zeros(3)
            while t < 2600:
                x = cam[0] + dx * t
                y = cam[1] + dy * t
                z = cam[2] + dz * t
                # choose lod
                for l in range(nl):
                    hh = sample(hs[l], x0s[l], z0s[l], ress[l], x, z)
                    if hh > -1e8:
                        break
                if hh < -1e8:
                    break
                wv = sample(ws[l], x0s[l], z0s[l], ress[l], x, z)
                if y < wv and wv > hh:
                    col[0] = 0.18
                    col[1] = 0.48
                    col[2] = 0.72
                    hit = True
                    break
                if y < hh:
                    r = ress[l]
                    gx = (sample(hs[l], x0s[l], z0s[l], r, x + r, z) - sample(hs[l], x0s[l], z0s[l], r, x - r, z)) / (2 * r)
                    gz = (sample(hs[l], x0s[l], z0s[l], r, x, z + r) - sample(hs[l], x0s[l], z0s[l], r, x, z - r)) / (2 * r)
                    nx, ny, nz = -gx, 1.0, -gz
                    nn = np.sqrt(nx * nx + ny * ny + nz * nz)
                    nx /= nn
                    ny /= nn
                    nz /= nn
                    ndl = max(0.0, nx * sun[0] + ny * sun[1] + nz * sun[2])
                    m = ms[l][int((z - z0s[l]) / r), int((x - x0s[l]) / r)]
                    steep = ny < 0.75
                    if hh > 260 + 30 * np.sin(x * 0.01):
                        b = (0.92, 0.94, 0.97)
                    elif steep:
                        b = (0.55, 0.53, 0.5)
                    elif m == 1:
                        b = (0.75, 0.62, 0.42)
                    else:
                        b = (0.38, 0.62, 0.22)
                    li = 0.35 + 0.85 * ndl
                    col[0] = b[0] * li
                    col[1] = b[1] * li
                    col[2] = b[2] * li
                    hit = True
                    break
                t += max(0.05, t * 0.004)
            if hit:
                f = 1 - np.exp(-t / 1400.0)
                img[py, px, 0] = col[0] * (1 - f) + 0.62 * f
                img[py, px, 1] = col[1] * (1 - f) + 0.75 * f
                img[py, px, 2] = col[2] * (1 - f) + 0.9 * f
            else:
                img[py, px, 0] = 0.35 + 0.2 * (1 - sy)
                img[py, px, 1] = 0.6 + 0.15 * (1 - sy)
                img[py, px, 2] = 0.95


def render(out, overlay=None):
    lods = [build_lod(-96, 96, -160, 48, 0.5), build_lod(-400, 400, -560, 280, 2.0), build_lod(-2400, 2400, -2400, 1800, 8.0)]
    yaw = np.radians(YAW)
    pitch = np.radians(PITCH)
    fwd = np.array([-np.sin(yaw) * np.cos(pitch), np.sin(pitch), -np.cos(yaw) * np.cos(pitch)])
    right = np.array([np.cos(yaw), 0, -np.sin(yaw)])
    up = np.cross(right, fwd)
    tanv = np.tan(np.radians(VFOV / 2))
    tanh = tanv * W / H
    img = np.zeros((H, W, 3))
    sun = np.array([-0.75, 0.6, 0.27])
    sun /= np.linalg.norm(sun)
    from numba.typed import List
    hs = List([l['h'].astype(np.float64) for l in lods])
    ws = List([l['w'].astype(np.float64) for l in lods])
    ms = List([l['mat'] for l in lods])
    x0s = np.array([l['x0'] for l in lods], np.float64)
    z0s = np.array([l['z0'] for l in lods], np.float64)
    ress = np.array([l['res'] for l in lods], np.float64)
    trace(img, CAM, fwd, right, up, tanv, tanh, hs, ws, ms, x0s, z0s, ress, len(lods), sun)
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    if overlay:
        ref = Image.open(overlay).convert('RGB').resize((W, H))
        im = Image.blend(im, ref, 0.45)
    im.save(out)


if __name__ == '__main__':
    render(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
