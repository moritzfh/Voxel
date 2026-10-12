"""Hand-designed structures stamped into the near grid (0.5 m voxels) + prop/light placements."""
import numpy as np
import common as C
import terrain as T
import props as PR

AIR = C.AIR


class Stamper:
    def __init__(self, g):
        self.g = g
        self.vs = g.vs
        self.o = g.origin
        self.nogo = np.zeros((g.dims[0], g.dims[2]), bool)
        self.props = []      # (name, x, y, z, yaw)
        self.lights = []     # dict
        self.colliders = []  # boxes: (cx, cy, cz, sx, sy, sz, yaw)
        self.fields = []
        self.markers = {}
        self.windows = []    # (axis, sign, x, y, z) of house windows, outer wall surface
        self.custom = {}     # name -> (vox, origin) one-off prop meshes (bunting)

    # --- index helpers (metres -> voxel index ranges, half open)
    def ix(self, x):
        return int(np.floor((x - self.o[0]) / self.vs + 1e-6))

    def iy(self, y):
        return int(np.floor((y - self.o[1]) / self.vs + 1e-6))

    def iz(self, z):
        return int(np.floor((z - self.o[2]) / self.vs + 1e-6))

    def box(self, x0, y0, z0, x1, y1, z1, b, only_air=False, nogo=True):
        g = self.g
        i0, i1 = sorted((self.ix(x0), self.ix(x1)))
        j0, j1 = sorted((self.iy(y0), self.iy(y1)))
        k0, k1 = sorted((self.iz(z0), self.iz(z1)))
        i0, j0, k0 = max(0, i0), max(0, j0), max(0, k0)
        i1, j1, k1 = min(g.dims[0], i1), min(g.dims[1], j1), min(g.dims[2], k1)
        if i1 <= i0 or j1 <= j0 or k1 <= k0:
            return
        if only_air:
            sub = g.vox[i0:i1, j0:j1, k0:k1]
            sub[sub == AIR] = b
        else:
            g.vox[i0:i1, j0:j1, k0:k1] = b
        if nogo and b != AIR:
            self.nogo[i0:i1, k0:k1] = True

    def set(self, x, y, z, b):
        i, j, k = self.ix(x), self.iy(y), self.iz(z)
        g = self.g
        if 0 <= i < g.dims[0] and 0 <= j < g.dims[1] and 0 <= k < g.dims[2]:
            g.vox[i, j, k] = b

    def column_top(self, x, z):
        g = self.g
        i, k = self.ix(x), self.iz(z)
        return self.o[1] + (g.top[i, k] + 1) * self.vs

    def flatten(self, x0, z0, x1, z1, h, top=C.GRASS, below=C.DIRT, deep=C.STONE, wall=None):
        """Make terrain in rect exactly height h."""
        g = self.g
        i0, i1 = self.ix(x0), self.ix(x1)
        k0, k1 = self.iz(z0), self.iz(z1)
        jt = self.iy(h) - 1
        g.vox[i0:i1, jt + 1:, k0:k1] = AIR
        g.vox[i0:i1, :jt + 1, k0:k1] = deep
        g.vox[i0:i1, max(0, jt - 2):jt, k0:k1] = below if wall is None else wall
        g.vox[i0:i1, jt, k0:k1] = top
        g.top[i0:i1, k0:k1] = jt
        g.flat_mask[max(0, i0):max(0, i1), max(0, k0):max(0, k1)] = True

    def prop(self, name, x, y, z, yaw=0.0, collide=None):
        self.props.append((name, float(x), float(y), float(z), float(yaw)))
        if name in PR.LIGHT_OFFSETS:
            lx, ly, lz = PR.LIGHT_OFFSETS[name]
            c, s = np.cos(yaw), np.sin(yaw)
            wx = x + c * lx + s * lz
            wz = z - s * lx + c * lz
            self.lights.append({'pos': [float(wx), float(y + ly), float(wz)], 'color': [1.0, 0.72, 0.38], 'energy': 2.2, 'range': 7.5})
        if collide is not None:
            sx, sy, sz, ox, oz = collide
            c, s = np.cos(yaw), np.sin(yaw)
            self.colliders.append([float(x + c * ox + s * oz), float(y + sy / 2), float(z - s * ox + c * oz), sx, sy, sz, float(yaw)])
        i, k = self.ix(x), self.iz(z)
        if 0 <= i < self.g.dims[0] and 0 <= k < self.g.dims[2]:
            self.nogo[max(0, i - 1):i + 2, max(0, k - 1):k + 2] = True

    def fence_line(self, pts, y=None, kind='fence', seg=2.0):
        """Fence along a polyline (posts every 2 m). y=None: follow terrain."""
        pts = np.asarray(pts, float)
        for a, b in zip(pts[:-1], pts[1:]):
            d = b - a
            L = np.hypot(*d)
            n = max(1, int(round(L / seg)))
            yaw = -np.arctan2(d[1], d[0])
            for i in range(n):
                p = a + d * (i / n)
                yy = y if y is not None else self.column_top(p[0], p[1])
                self.props.append((kind, float(p[0]), float(yy), float(p[1]), float(yaw)))
                mid = a + d * ((i + 0.5) / n)
                self.colliders.append([float(mid[0]), float(yy + 0.6), float(mid[1]), L / n, 1.2, 0.25, float(yaw)])
                ii, kk = self.ix(p[0]), self.iz(p[1])
                if 0 <= ii < self.g.dims[0] and 0 <= kk < self.g.dims[2]:
                    self.nogo[ii, kk] = True
        last = pts[-1]
        yy = y if y is not None else self.column_top(last[0], last[1])
        self.props.append(('fence_post', float(last[0]), float(yy), float(last[1]), 0.0))


# ------------------------------------------------------------------ buildings
def timber_house(S, x0, z0, w, d, base, floors=2, ridge='x', stone_floors=1, rng=None,
                 balcony=None, lanterns=(), door=('+x', 0.5), chimney=True, jetty=True, lit=0.7,
                 roof=C.SLATE, plaster=C.PLASTER, banner=None):
    """Half-timbered house. x0,z0 = min corner, w (x) / d (z) in metres, base = ground height.
    Ground floor(s) in stone, upper floors plaster + timber frame, gable roof."""
    if rng is None:
        rng = np.random.default_rng(int(abs(x0 * 13 + z0 * 7)))
    v = 0.5
    fh = 3.0  # floor height
    x1, z1 = x0 + w, z0 + d
    # foundation down to terrain
    S.box(x0 - 0.5, base - 3.0, z0 - 0.5, x1 + 0.5, base, z1 + 0.5, C.COBBLE)
    S.box(x0 - 0.5, base, z0 - 0.5, x1 + 0.5, base + 0.5, z1 + 0.5, C.COBBLE_MOSSY)
    y = base + 0.5
    top_y = y + floors * fh
    off = 0.0
    for f in range(floors):
        fy0 = y + f * fh
        fy1 = fy0 + fh
        e = 0.5 if (jetty and f > 0) else 0.0
        ax0, ax1, az0, az1 = x0 - e, x1 + e, z0 - e, z1 + e
        if f < stone_floors:
            S.box(ax0, fy0, az0, ax1, fy1, az1, C.COBBLE if f == 0 else C.BRICKS)
            S.box(ax0 + v, fy0, az0 + v, ax1 - v, fy1, az1 - v, AIR)
            # corner quoins
            for cx in (ax0, ax1 - v):
                for cz in (az0, az1 - v):
                    S.box(cx, fy0, cz, cx + v, fy1, cz + v, C.BRICKS)
        else:
            S.box(ax0, fy0, az0, ax1, fy1, az1, plaster)
            S.box(ax0 + v, fy0, az0 + v, ax1 - v, fy1, az1 - v, AIR)
            # timber: posts at corners and every 2 m, sill & head beams
            S.box(ax0, fy0, az0, ax1, fy0 + v, az1, C.TIMBER)
            S.box(ax0, fy1 - v, az0, ax1, fy1, az1, C.TIMBER)
            S.box(ax0 + v, fy0, az0 + v, ax1 - v, fy1, az1 - v, AIR)
            for xx in np.arange(ax0, ax1 - 0.01, 2.0):
                S.box(xx, fy0, az0, xx + v, fy1, az0 + v, C.TIMBER)
                S.box(xx, fy0, az1 - v, xx + v, fy1, az1, C.TIMBER)
            S.box(ax1 - v, fy0, az0, ax1, fy1, az1, C.TIMBER) if False else None
            for zz in np.arange(az0, az1 - 0.01, 2.0):
                S.box(ax0, fy0, zz, ax0 + v, fy1, zz + v, C.TIMBER)
                S.box(ax1 - v, fy0, zz, ax1, fy1, zz + v, C.TIMBER)
            for cx in (ax0, ax1 - v):
                for cz in (az0, az1 - v):
                    S.box(cx, fy0, cz, cx + v, fy1, cz + v, C.TIMBER)
            # diagonal braces in end panels (stair pattern)
            for (bx, bz, dx, dz) in ((ax0 + v, az0, 1, 0), (ax1 - 2 * v, az0, -1, 0), (ax0 + v, az1 - v, 1, 0), (ax1 - 2 * v, az1 - v, -1, 0)):
                for k in range(3):
                    S.set(bx + dx * k * v + 0.01, fy0 + v + k * v + 0.01, bz + 0.01, C.TIMBER)
        # windows on each wall (2x2 voxel = 1 m) every 2 m, skipping corners
        wy = fy0 + (1.0 if f > 0 or f >= stone_floors else 1.0)
        for xx in np.arange(ax0 + 1.0, ax1 - 1.4, 2.0):
            for zz, face in ((az0, -1), (az1 - v, 1)):
                if rng.random() < 0.8:
                    wb = C.WINDOW_LIT if rng.random() < lit else C.WINDOW_DARK
                    S.box(xx, wy, zz, xx + 1.0, wy + 1.0, zz + v, wb)
                    S.box(xx - 0.0, wy - v, zz, xx + 1.0, wy, zz + v, C.TIMBER if f >= stone_floors else C.BRICKS)
                    S.windows.append(('z', face, xx + 0.5, wy, az0 if face < 0 else az1))
        for zz in np.arange(az0 + 1.0, az1 - 1.4, 2.0):
            for xx, face in ((ax0, -1), (ax1 - v, 1)):
                if rng.random() < 0.8:
                    wb = C.WINDOW_LIT if rng.random() < lit else C.WINDOW_DARK
                    S.box(xx, wy, zz, xx + v, wy + 1.0, zz + 1.0, wb)
                    S.box(xx, wy - v, zz, xx + v, wy, zz + 1.0, C.TIMBER if f >= stone_floors else C.BRICKS)
                    S.windows.append(('x', face, ax0 if face < 0 else ax1, wy, zz + 0.5))
        # floor
        S.box(ax0 + v, fy0 - v, az0 + v, ax1 - v, fy0, az1 - v, C.PLANKS)
    # door
    side, pos = door
    dy = base + 0.5
    if side == '+x':
        dz = z0 + pos * d - 0.5
        S.box(x1 - v, dy, dz, x1, dy + 2.0, dz + 1.0, C.PLANKS_DARK)
        S.box(x1 - v, dy + 2.0, dz - v, x1, dy + 2.5, dz + 1.5, C.TIMBER)
        S.box(x1, base, dz - 0.5, x1 + 1.0, base + 0.5, dz + 1.5, C.COBBLE)
    elif side == '+z':
        dx = x0 + pos * w - 0.5
        S.box(dx, dy, z1 - v, dx + 1.0, dy + 2.0, z1, C.PLANKS_DARK)
        S.box(dx - v, dy + 2.0, z1 - v, dx + 1.5, dy + 2.5, z1, C.TIMBER)
        S.box(dx - 0.5, base, z1, dx + 1.5, base + 0.5, z1 + 1.0, C.COBBLE)
    elif side == '-x':
        dz = z0 + pos * d - 0.5
        S.box(x0, dy, dz, x0 + v, dy + 2.0, dz + 1.0, C.PLANKS_DARK)
        S.box(x0, dy + 2.0, dz - v, x0 + v, dy + 2.5, dz + 1.5, C.TIMBER)
    # roof
    e = 0.5 if (jetty and floors > 1) else 0.0
    rx0, rx1, rz0, rz1 = x0 - e - 0.5, x1 + e + 0.5, z0 - e - 0.5, z1 + e + 0.5
    ry = top_y
    if ridge == 'x':
        span = rz1 - rz0
        n = int(np.ceil(span / 2 / v)) + 1
        for k in range(n):
            za, zb = rz0 + k * v, rz1 - k * v
            if zb <= za:
                break
            yy = ry + k * v - 0.5
            S.box(rx0, yy, za, rx1, yy + v, za + v, roof)
            S.box(rx0, yy, zb - v, rx1, yy + v, zb, roof)
            # gable walls (plaster + timber) under the roof
            if zb - za > 2 * v:
                gx0, gx1 = x0 - e, x1 + e
                S.box(gx0, yy, za + v, gx0 + v, yy + v, zb - v, plaster)
                S.box(gx1 - v, yy, za + v, gx1, yy + v, zb - v, plaster)
                S.box(gx0 + v, yy, za + v, gx1 - v, yy + v, zb - v, AIR)
        # gable timber: centre post + barge boards
        midz = (rz0 + rz1) / 2
        for gx in (x0 - e, x1 + e - v):
            S.box(gx, ry, midz - 0.25, gx + v, ry + (n - 2) * v, midz + 0.25, C.TIMBER)
            S.box(gx, ry + 1.5, rz0 + 1.0, gx + v, ry + 2.0, rz1 - 1.0, C.TIMBER) if span > 6 else None
            # small gable window
            S.box(gx, ry + 0.5, midz - 1.25, gx + v, ry + 1.5, midz - 0.25, C.WINDOW_LIT if rng.random() < lit else C.WINDOW_DARK)
            S.box(gx, ry + 0.5, midz + 0.25, gx + v, ry + 1.5, midz + 1.25, C.WINDOW_LIT if rng.random() < lit else C.WINDOW_DARK)
        for k in range(n):
            za, zb = rz0 + k * v, rz1 - k * v
            if zb <= za:
                break
            yy = ry + k * v - 0.5
            for gx in (rx0, rx1 - v):
                S.set(gx + 0.01, yy + 0.01, za + 0.01, C.PLANKS_DARK)
                S.set(gx + 0.01, yy + 0.01, zb - v + 0.01, C.PLANKS_DARK)
        ridge_y = ry + (n - 1) * v - 0.5
        S.box(rx0, ridge_y, midz - 0.5, rx1, ridge_y + v, midz + 0.5, C.BRICKS_DARK)
    else:
        span = rx1 - rx0
        n = int(np.ceil(span / 2 / v)) + 1
        for k in range(n):
            xa, xb = rx0 + k * v, rx1 - k * v
            if xb <= xa:
                break
            yy = ry + k * v - 0.5
            S.box(xa, yy, rz0, xa + v, yy + v, rz1, roof)
            S.box(xb - v, yy, rz0, xb, yy + v, rz1, roof)
            if xb - xa > 2 * v:
                gz0, gz1 = z0 - e, z1 + e
                S.box(xa + v, yy, gz0, xb - v, yy + v, gz0 + v, plaster)
                S.box(xa + v, yy, gz1 - v, xb - v, yy + v, gz1, plaster)
                S.box(xa + v, yy, gz0 + v, xb - v, yy + v, gz1 - v, AIR)
        midx = (rx0 + rx1) / 2
        for gz in (z0 - e, z1 + e - v):
            S.box(midx - 0.25, ry, gz, midx + 0.25, ry + (n - 2) * v, gz + v, C.TIMBER)
            S.box(midx - 1.25, ry + 0.5, gz, midx - 0.25, ry + 1.5, gz + v, C.WINDOW_LIT if rng.random() < lit else C.WINDOW_DARK)
            S.box(midx + 0.25, ry + 0.5, gz, midx + 1.25, ry + 1.5, gz + v, C.WINDOW_LIT if rng.random() < lit else C.WINDOW_DARK)
        for k in range(n):
            xa, xb = rx0 + k * v, rx1 - k * v
            if xb <= xa:
                break
            yy = ry + k * v - 0.5
            for gz in (rz0, rz1 - v):
                S.set(xa + 0.01, yy + 0.01, gz + 0.01, C.PLANKS_DARK)
                S.set(xb - v + 0.01, yy + 0.01, gz + 0.01, C.PLANKS_DARK)
        ridge_y = ry + (n - 1) * v - 0.5
        S.box(midx - 0.5, ridge_y, rz0, midx + 0.5, ridge_y + v, rz1, C.BRICKS_DARK)
    if chimney:
        cx = x0 + w * 0.25
        cz = z0 + d * 0.3
        S.box(cx, base, cz, cx + 1.0, ridge_y + 2.0, cz + 1.0, C.BRICKS)
        S.box(cx - 0.25, ridge_y + 2.0, cz - 0.25, cx + 1.25, ridge_y + 2.5, cz + 1.25, C.BRICKS_DARK) if False else S.box(cx, ridge_y + 2.0, cz, cx + 1.0, ridge_y + 2.5, cz + 1.0, C.BRICKS_DARK)
    # balcony
    if balcony:
        side, fl = balcony
        by = base + 0.5 + fl * fh
        if side == '+x':
            bx = x1 + e
            S.box(bx, by - v, z0 + 1.0, bx + 1.5, by, z1 - 1.0, C.PLANKS)
            S.box(bx, by - 1.0, z0 + 1.0, bx + 0.5, by - v, z0 + 1.5, C.TIMBER)
            S.box(bx, by - 1.0, z1 - 1.5, bx + 0.5, by - v, z1 - 1.0, C.TIMBER)
            S.fence_line([(bx + 1.375, z0 + 1.125), (bx + 1.375, z1 - 1.125)], y=by, kind='rail')
            S.fence_line([(bx + 0.1, z0 + 1.125), (bx + 1.375, z0 + 1.125)], y=by, kind='rail')
            S.fence_line([(bx + 0.1, z1 - 1.125), (bx + 1.375, z1 - 1.125)], y=by, kind='rail')
            # door to balcony
            mz = (z0 + z1) / 2
            S.box(bx - v, by, mz - 0.5, bx, by + 2.0, mz + 0.5, C.PLANKS_DARK)
        elif side == '+z':
            bz = z1 + e
            S.box(x0 + 1.0, by - v, bz, x1 - 1.0, by, bz + 1.5, C.PLANKS)
            S.fence_line([(x0 + 1.125, bz + 1.375), (x1 - 1.125, bz + 1.375)], y=by, kind='rail')
    for (lx, ly, lz, yaw) in lanterns:
        S.prop('wall_lantern', lx, ly, lz, yaw)
    if banner:
        bx, by, bz, yaw = banner
        S.prop('wall_banner', bx, by, bz, yaw)
    S.nogo[S.ix(x0 - 1):S.ix(x1 + 1), S.iz(z0 - 1):S.iz(z1 + 1)] = True


def castle(S, cx, cz):
    base = S.column_top(cx, cz)
    v = 0.5
    # hilltop plateau
    S.flatten(cx - 13, cz - 11, cx + 11, cz + 12, base, top=C.GRASS, below=C.DIRT)
    # main keep
    k0x, k0z = cx - 4.0, cz - 4.0
    W = 8.0
    H = 21.0
    S.box(k0x, base - 4, k0z, k0x + W, base + H, k0z + W, C.BRICKS)
    S.box(k0x + 1.0, base, k0z + 1.0, k0x + W - 1.0, base + H, k0z + W - 1.0, AIR)
    S.box(k0x - 0.5, base - 4, k0z - 0.5, k0x + W + 0.5, base + 2.0, k0z + W + 0.5, C.COBBLE_MOSSY)
    # string courses
    for yy in (base + 7.0, base + 14.0):
        S.box(k0x - 0.5, yy, k0z - 0.5, k0x + W + 0.5, yy + 0.5, k0z + W + 0.5, C.BRICKS_DARK)
    # corbelled parapet
    S.box(k0x - 0.5, base + H, k0z - 0.5, k0x + W + 0.5, base + H + 0.5, k0z + W + 0.5, C.BRICKS_DARK)
    S.box(k0x - 0.5, base + H + 0.5, k0z - 0.5, k0x + W + 0.5, base + H + 1.5, k0z + W + 0.5, C.BRICKS)
    S.box(k0x + 0.5, base + H + 0.5, k0z + 0.5, k0x + W - 0.5, base + H + 1.5, k0z + W - 0.5, AIR)
    for i, xx in enumerate(np.arange(k0x - 0.5, k0x + W + 0.5, 1.0)):
        if i % 2 == 0:
            S.box(xx, base + H + 1.5, k0z - 0.5, xx + v * 2, base + H + 2.5, k0z, C.BRICKS)
            S.box(xx, base + H + 1.5, k0z + W, xx + v * 2, base + H + 2.5, k0z + W + 0.5, C.BRICKS)
    for i, zz in enumerate(np.arange(k0z - 0.5, k0z + W + 0.5, 1.0)):
        if i % 2 == 0:
            S.box(k0x - 0.5, base + H + 1.5, zz, k0x, base + H + 2.5, zz + v * 2, C.BRICKS)
            S.box(k0x + W, base + H + 1.5, zz, k0x + W + 0.5, base + H + 2.5, zz + v * 2, C.BRICKS)
    # slit windows
    for yy in (base + 4.0, base + 10.0, base + 16.5):
        for t in (W * 0.3, W * 0.65):
            S.box(k0x + t, yy, k0z + W - v, k0x + t + v, yy + 1.5, k0z + W, C.WINDOW_DARK)
            S.box(k0x + W - v, yy, k0z + t, k0x + W, yy + 1.5, k0z + t + v, C.WINDOW_DARK)
            S.box(k0x + t, yy, k0z, k0x + t + v, yy + 1.5, k0z + v, C.WINDOW_DARK)
    # door
    S.box(k0x + W / 2 - 1.0, base, k0z + W - v, k0x + W / 2 + 1.0, base + 3.0, k0z + W, C.PLANKS_DARK)
    S.box(k0x + W / 2 - 1.5, base + 3.0, k0z + W - v, k0x + W / 2 + 1.5, base + 3.5, k0z + W, C.BRICKS_DARK)
    # banners on south and east face
    S.prop('wall_banner_long', k0x + W / 2, base + 13.5, k0z + W + 0.02, 0.0)
    S.prop('wall_banner', k0x + W + 0.02, base + 11.0, k0z + W / 2, np.pi / 2)
    # small turret on top
    t0x, t0z = k0x + W - 3.5, k0z + 0.5
    S.box(t0x, base + H, t0z, t0x + 3.0, base + H + 5.0, t0z + 3.0, C.BRICKS)
    S.box(t0x - 0.5, base + H + 5.0, t0z - 0.5, t0x + 3.5, base + H + 5.5, t0z + 3.5, C.BRICKS_DARK)
    for i, xx in enumerate(np.arange(t0x - 0.5, t0x + 3.5, 1.0)):
        if i % 2 == 0:
            S.box(xx, base + H + 5.5, t0z - 0.5, xx + 0.5, base + H + 6.5, t0z + 3.5, C.BRICKS)
    S.box(t0x + 1.0, base + H + 1.5, t0z + 3.0 - v, t0x + 2.0, base + H + 3.0, t0z + 3.0, C.WINDOW_LIT)
    # curtain walls
    wall_h = 4.0

    def wall(xa, za, xb, zb):
        n = int(max(abs(xb - xa), abs(zb - za)) / v)
        for i in range(n + 1):
            x = xa + (xb - xa) * i / max(1, n)
            z = za + (zb - za) * i / max(1, n)
            gtop = S.column_top(x, z)
            S.box(x - 0.5, gtop - 2.0, z - 0.5, x + 0.5, base + wall_h, z + 0.5, C.COBBLE if (i // 6) % 3 else C.COBBLE_MOSSY)
            if i % 2 == 0:
                S.box(x - 0.5, base + wall_h, z - 0.5, x + 0.5, base + wall_h + 1.0, z + 0.5, C.BRICKS)
    wall(cx - 11, cz - 9, cx + 9, cz - 9)
    wall(cx + 9, cz - 9, cx + 9, cz + 10)
    wall(cx - 11, cz - 9, cx - 11, cz + 10)
    wall(cx - 11, cz + 10, cx - 3, cz + 10)
    wall(cx + 2, cz + 10, cx + 9, cz + 10)
    # gate towers
    for gx in (cx - 4.5, cx + 2.0):
        S.box(gx, base - 1, cz + 9.0, gx + 2.5, base + 7.0, cz + 11.5, C.BRICKS)
        for i in range(3):
            S.box(gx + i * 1.0, base + 7.0, cz + 9.0, gx + i * 1.0 + 0.5, base + 8.0, cz + 11.5, C.BRICKS)
    S.prop('lantern_pole', cx - 0.75, base, cz + 12.5, 0.0)
    S.markers['castle'] = [cx, base, cz]


def bridge(S, xa, xb, zc, deck_y=1.5, width=3.5):
    """Stone arch bridge along x from xa to xb centred at zc."""
    v = 0.5
    z0, z1 = zc - width / 2, zc + width / 2
    span_c = (xa + xb) / 2
    half = (xb - xa) / 2 - 1.5
    for x in np.arange(xa - 1.0, xb + 1.0, v):
        # arch underside height
        t = (x + v / 2 - span_c) / max(1.0, half)
        if abs(t) < 1:
            under = -1.4 + 3.8 * np.sqrt(max(0.0, 1 - t * t))
            under = max(-1.5, under)
        else:
            under = -4.0
        S.box(x, under, z0, x + v, deck_y - 0.5, z1, C.BRICKS)
        S.box(x, deck_y - 0.5, z0, x + v, deck_y, z1, C.COBBLE)
        # parapet kerb
        S.box(x, deck_y, z0, x + v, deck_y + 0.5, z0 + v, C.BRICKS_DARK)
        S.box(x, deck_y, z1 - v, x + v, deck_y + 0.5, z1, C.BRICKS_DARK)
    # keystone ring (darker) around the arch
    for x in np.arange(span_c - half, span_c + half, v):
        t = (x + v / 2 - span_c) / half
        under = -1.4 + 3.8 * np.sqrt(max(0.0, 1 - t * t))
        S.box(x, under, z0 - 0.0, x + v, under + 0.5, z0 + v, C.BRICKS_DARK)
        S.box(x, under, z1 - v, x + v, under + 0.5, z1, C.BRICKS_DARK)
    # ramps at both ends
    for (x, dirn) in ((xa - 1.0, -1), (xb + 1.0, 1)):
        for k in range(6):
            yy = deck_y - 0.5 * (k + 1)
            xx = x + dirn * k * 0.5 + (0 if dirn > 0 else -0.5)
            S.box(xx, yy - 2.0, z0, xx + v, yy, z1, C.COBBLE)
    S.fence_line([(xa - 0.5, z0 + 0.1), (xb + 0.5, z0 + 0.1)], y=deck_y + 0.5, kind='rail')
    S.fence_line([(xa - 0.5, z1 - 0.1), (xb + 0.5, z1 - 0.1)], y=deck_y + 0.5, kind='rail')
    S.prop('lantern_pole', xa - 0.5, deck_y + 0.5, z0 - 0.35, 0.0)
    S.prop('lantern_pole', (xa + xb) / 2 + 2.0, deck_y + 0.5, z0 - 0.35, 0.0)
    S.prop('lantern_pole', xb + 0.5, deck_y + 0.5, z1 + 0.35, 0.0)
    S.nogo[S.ix(xa - 2):S.ix(xb + 2), S.iz(z0 - 1):S.iz(z1 + 1)] = True


def stairs(S, pts, h0, h1, width=2.0, mat=C.COBBLE):
    """Stone stairs along a polyline rising from h0 to h1."""
    pts = np.asarray(pts, float)
    L = np.sum(np.hypot(*np.diff(pts, axis=0).T))
    acc = 0.0
    for a, b in zip(pts[:-1], pts[1:]):
        d = b - a
        l = np.hypot(*d)
        n = int(l / 0.25) + 1
        for i in range(n):
            p = a + d * i / n
            t = (acc + l * i / n) / L
            hh = np.round((h0 + (h1 - h0) * t) * 2) / 2
            nrm = np.array([-d[1], d[0]]) / l
            for o in np.arange(-width / 2, width / 2 + 0.01, 0.25):
                q = p + nrm * o
                g = S.g
                ii, kk = S.ix(q[0]), S.iz(q[1])
                if not (0 <= ii < g.dims[0] and 0 <= kk < g.dims[2]):
                    continue
                jt = S.iy(hh) - 1
                g.vox[ii, jt + 1:jt + 8, kk] = AIR
                g.vox[ii, max(0, jt - 4):jt + 1, kk] = mat
                g.top[ii, kk] = jt
                S.nogo[ii, kk] = True
        acc += l


def grand_stairs(S, pts, h0, h1, width=3.0, lantern_every=8.0):
    """Wide stone staircase with brick cheek walls and lantern poles."""
    g = S.g
    pts = np.asarray(pts, float)
    L = np.sum(np.hypot(*np.diff(pts, axis=0).T))
    steps = {}
    sides = []
    acc = 0.0
    for a, b in zip(pts[:-1], pts[1:]):
        d = b - a
        l = np.hypot(*d)
        n = int(l / 0.25) + 1
        nrm = np.array([-d[1], d[0]]) / l
        for i in range(n):
            p = a + d * i / n
            t = (acc + l * i / n) / L
            hh = np.round((h0 + (h1 - h0) * t) * 2) / 2
            jt = S.iy(hh) - 1
            for o in np.arange(-width / 2, width / 2 + 0.01, 0.25):
                q = p + nrm * o
                key = (S.ix(q[0]), S.iz(q[1]))
                steps[key] = max(steps.get(key, -1), jt)
            for o in (-width / 2 - 0.4, width / 2 + 0.4):
                q = p + nrm * o
                sides.append((S.ix(q[0]), S.iz(q[1]), jt, float(q[0]), float(q[1]), acc + l * i / n))
        acc += l
    for (ii, kk), jt in steps.items():
        if 0 <= ii < g.dims[0] and 0 <= kk < g.dims[2]:
            g.vox[ii, jt + 1:jt + 9, kk] = AIR
            g.vox[ii, max(0, jt - 6):jt + 1, kk] = C.COBBLE
            g.vox[ii, jt, kk] = C.BRICKS
            g.top[ii, kk] = jt
            S.nogo[ii, kk] = True
    last_lamp = -99.0
    for (ii, kk, jt, x, z, sdist) in sides:
        if (ii, kk) in steps or not (0 <= ii < g.dims[0] and 0 <= kk < g.dims[2]):
            continue
        gt = g.top[ii, kk]
        top = max(gt, jt + 1)
        if gt > jt + 3:
            continue  # cut into the hill: the hillside itself is the wall
        g.vox[ii, max(0, jt - 6):top + 1, kk] = C.COBBLE_MOSSY if (ii + kk) % 5 == 0 else C.COBBLE
        g.vox[ii, top, kk] = C.BRICKS_DARK
        g.top[ii, kk] = max(gt, top)
        S.nogo[ii, kk] = True
        if sdist - last_lamp > lantern_every and sdist > 1.0:
            last_lamp = sdist
            S.prop('lantern_pole', x, S.o[1] + (top + 1) * S.vs, z, 0.0)


def big_stone(S, x0, z0, x1, z1, h=0.5, mat=C.BOULDER, ground=None):
    gtop = S.column_top((x0 + x1) / 2, (z0 + z1) / 2) if ground is None else ground
    S.box(x0, gtop - 0.5, z0, x1, gtop + h, z1, mat)


def retaining_walls(S):
    """Turn terrace edges in the village into cobble retaining walls."""
    g = S.g
    top = g.top
    tp = np.pad(top, 1, mode='edge')
    nb_min = np.minimum.reduce([tp[:-2, 1:-1], tp[2:, 1:-1], tp[1:-1, :-2], tp[1:-1, 2:]])
    drop = top - nb_min
    X, Z = g.col_centers()
    vil = (X < -3.0) & (Z > -70) & (Z < 14)
    edge = vil & (drop >= 2)
    ii, kk = np.nonzero(edge)
    rng = np.random.default_rng(5)
    for i, k in zip(ii, kk):
        t = top[i, k]
        lo = max(0, t - drop[i, k] - 1)
        mat = C.COBBLE_MOSSY if rng.random() < 0.35 else C.COBBLE
        col = g.vox[i, lo:t, k]
        col[(col == C.DIRT) | (col == C.STONE)] = mat


def ruin(grids):
    g = grids['mid']
    S = Stamper(g)
    cx, cz = T.CRAG[0], T.CRAG[1]
    # find the highest column near the crag centre
    best = None
    for dx in range(-14, 15, 2):
        for dz in range(-14, 15, 2):
            h = S.column_top(cx + dx, cz + dz)
            if best is None or h > best[0]:
                best = (h, cx + dx, cz + dz)
    base, x, z = best
    rng = np.random.default_rng(9)
    S.box(x - 7, base - 8, z - 7, x + 7, base + 1, z + 7, C.COBBLE)
    # main tower (broken top)
    S.box(x - 4, base, z - 4, x + 4, base + 22, z + 4, C.BRICKS)
    S.box(x - 3, base + 1, z - 3, x + 3, base + 23, z + 3, AIR)
    for i, xx in enumerate(range(-4, 4)):
        if i % 2 == 0:
            S.box(x + xx, base + 22, z - 4, x + xx + 1, base + 23 + rng.integers(0, 2), z - 3, C.BRICKS)
            S.box(x + xx, base + 22, z + 3, x + xx + 1, base + 23, z + 4, C.BRICKS)
    S.box(x + 1, base + 17, z - 4, x + 4, base + 23, z - 3, AIR)  # broken corner
    S.box(x + 2, base + 14, z - 4, x + 4, base + 17, z - 3, AIR)
    for yy in (6, 12, 18):
        S.box(x - 1, base + yy, z + 3, x + 1, base + yy + 2, z + 4, C.WINDOW_DARK)
        S.box(x - 4, base + yy, z - 1, x - 3, base + yy + 2, z + 1, C.WINDOW_DARK)
    # second smaller tower + wall
    S.box(x + 6, base - 10, z + 2, x + 11, base + 13, z + 7, C.BRICKS)
    S.box(x + 7, base + 1, z + 3, x + 10, base + 14, z + 6, AIR)
    for i in range(5):
        if i % 2 == 0:
            S.box(x + 6 + i, base + 13, z + 2, x + 7 + i, base + 14, z + 7, C.BRICKS)
    S.box(x + 4, base - 2, z + 3, x + 7, base + 7, z + 5, C.COBBLE)
    S.box(x - 9, base - 6, z - 2, x - 4, base + 5, z, C.COBBLE)
    S.box(x - 8, base + 5, z - 2, x - 6, base + 6, z, C.COBBLE)
    return [x, base, z]


def path_steps(S, pts, width=1.6, step=0.5):
    """Make a path walkable: where it meets a terrace edge higher than one block, fill in stone steps."""
    g = S.g
    pts = np.asarray(pts, float)
    samples = []
    for a, b in zip(pts[:-1], pts[1:]):
        d = b - a
        l = np.hypot(*d)
        n = max(1, int(l / 0.5))
        nrm = np.array([-d[1], d[0]]) / l
        for i in range(n):
            samples.append((a + d * i / n, nrm))
    samples.append((pts[-1], samples[-1][1]))
    h = np.array([S.column_top(p[0], p[1]) for p, _ in samples])
    t = h.copy()
    for i in range(1, len(t)):
        t[i] = max(t[i], t[i - 1] - step)
    for i in range(len(t) - 2, -1, -1):
        t[i] = max(t[i], t[i + 1] - step)
    n_raised = 0
    for (p, nrm), target in zip(samples, t):
        for o in np.arange(-width / 2, width / 2 + 0.01, 0.25):
            q = p + nrm * o
            ii, kk = S.ix(q[0]), S.iz(q[1])
            if not (0 <= ii < g.dims[0] and 0 <= kk < g.dims[2]):
                continue
            jt = S.iy(target) - 1
            if g.top[ii, kk] < jt:
                g.vox[ii, g.top[ii, kk]:jt, kk] = C.COBBLE
                g.vox[ii, jt, kk] = C.BRICKS
                g.top[ii, kk] = jt
                S.nogo[ii, kk] = True
                n_raised += 1
    return n_raised


def add_bunting(S, p0, p1, sag=0.6):
    """String of pennants between two world points."""
    p0 = np.asarray(p0, float)
    p1 = np.asarray(p1, float)
    if p1[1] > p0[1]:
        p0, p1 = p1, p0
    dx, dz = p1[0] - p0[0], p1[2] - p0[2]
    L = float(np.hypot(dx, dz))
    drop = float(p0[1] - p1[1])
    name = 'bunting_%d' % len(S.custom)
    S.custom[name] = PR.bunting(L, drop, sag, seed=len(S.custom))
    S.props.append((name, float(p0[0]), float(p0[1]), float(p0[2]), float(-np.arctan2(dz, dx))))


def decorate_village(S, rng):
    ct = S.column_top
    # --- flower boxes under windows
    variants = ['flowerbox_a', 'flowerbox_b', 'flowerbox_c']
    yaw_of = {('z', 1): 0.0, ('z', -1): np.pi, ('x', 1): np.pi / 2, ('x', -1): -np.pi / 2}
    n_fb = 0
    for (axis, sign, x, y, z) in S.windows:
        pr = 0.65 if sign > 0 else 0.25
        if rng.random() > pr:
            continue
        S.props.append((variants[rng.integers(0, 3)], float(x), float(y - 0.375), float(z), yaw_of[(axis, sign)]))
        n_fb += 1
    # --- green banners on the house fronts facing the path / the camera
    banners = [(-17.49, 7.25, -20.5, np.pi / 2), (-25.0, 7.25, -19.49, 0.0), (-17.49, 7.25, -11.0, np.pi / 2),
               (-14.0, 5.75, -34.49, 0.0), (-30.49, 11.75, -26.5, np.pi / 2), (-27.99, 10.25, -34.5, np.pi / 2),
               (-22.0, 8.25, -40.49, 0.0), (-34.49, 13.25, -46.0, np.pi / 2), (-18.5, 14.75, -52.99, 0.0),
               (-10.5, 11.25, -59.49, 0.0), (-10.0, 6.75, -46.49, 0.0)]
    for (x, y, z, yaw) in banners:
        S.props.append(('wall_banner', x, y, z, yaw))
    # --- pennant strings across lanes and the market
    add_bunting(S, (-17.45, 9.3, -26.6), (-9.95, ct(-10.0, -24.0) + 4.0, -24.0))
    add_bunting(S, (1.4, 3.85, -28.6), (1.95, ct(2.0, -40.0) + 4.0, -40.0), sag=0.8)
    add_bunting(S, (-8.45, 7.8, -38.0), (1.95, ct(2.0, -40.0) + 4.0, -40.0))
    S.prop('lantern_pole', -12.6, 3.5, -15.2, 0.0, collide=(0.4, 3.2, 0.4, 0, 0))
    add_bunting(S, (-17.45, 8.8, -9.0), (-12.6, 3.5 + 3.3, -15.2), sag=0.5)
    add_bunting(S, (-17.45, 9.0, -14.0), (-17.45, 9.2, -20.0), sag=0.7)
    # --- village clutter
    clutter = [
        ('cart', -12.4, -20.8, 0.35, (2.6, 1.6, 1.4)),
        ('hay_bale', -10.2, -19.6, 0.1, (1.0, 0.8, 0.8)), ('hay_bale', -9.2, -20.4, 1.5, (1.0, 0.8, 0.8)),
        ('barrel', -17.2, -27.4, 0.0, (0.6, 0.9, 0.6)), ('barrel', -16.9, -28.2, 0.0, (0.6, 0.9, 0.6)),
        ('sacks', -15.8, -33.8, 0.2, None), ('crate', -9.6, -34.0, 0.1, (0.5, 0.5, 0.5)),
        ('crate', -9.0, -34.3, 0.5, (0.5, 0.5, 0.5)), ('barrel', -21.2, -30.6, 0.0, (0.6, 0.9, 0.6)),
        ('sacks', -6.0, -33.6, 1.0, None), ('barrel', -16.6, -12.0, 0.0, (0.6, 0.9, 0.6)),
        ('hay_bale', -22.0, -44.0, 0.4, (1.0, 0.8, 0.8)), ('barrel', -27.0, -38.6, 0.0, (0.6, 0.9, 0.6)),
        ('cart', -6.5, -45.5, -0.4, (2.6, 1.6, 1.4)),
    ]
    for (name, x, z, yaw, col) in clutter:
        y = ct(x, z)
        S.prop(name, x, y, z, yaw, collide=None if col is None else (col[0], col[1], col[2], 0.0, 0.0))
    print(f'village decor: {n_fb} flower boxes, {len(banners)} banners, {len(S.custom)} pennant strings')


def build_all(grids, manifest):
    g = grids['near']
    S = Stamper(g)
    rng = np.random.default_rng(42)
    retaining_walls(S)

    # ---------------- village houses (west terraces, climbing towards the castle)
    houses = [
        # x0, z0, w, d, base, floors, ridge, door, extra kwargs
        # front row (tier 3.5)
        (-27.0, -27.0, 9.0, 7.0, 3.5, 2, 'x', ('+x', 0.3), dict(balcony=('+x', 1), lit=0.85,
            lanterns=[(-17.5, 7.6, -25.0, np.pi / 2), (-17.5, 7.6, -22.0, np.pi / 2)])),
        (-25.0, -13.0, 7.0, 6.0, 3.5, 2, 'z', ('+x', 0.5), dict(lit=0.8, lanterns=[(-17.5, 5.6, -11.4, np.pi / 2)])),
        # behind the market
        (-16.0, -41.5, 7.0, 6.5, 2.0, 2, 'z', ('+z', 0.5), dict(lit=0.75, lanterns=[(-14.0, 4.8, -35.0, 0.0)])),
        (-12.0, -53.0, 7.5, 6.0, 3.0, 2, 'x', ('+z', 0.5), dict(lit=0.6)),
        # second row (tier 6-9)
        (-35.5, -36.5, 7.0, 7.0, 6.5, 2, 'x', ('+x', 0.5), dict(lit=0.6)),
        (-38.0, -28.5, 7.0, 6.0, 8.0, 2, 'z', ('+x', 0.5), dict(lit=0.6)),
        (-26.0, -53.0, 7.0, 7.0, 7.0, 2, 'z', ('+z', 0.5), dict(lit=0.5)),
        (-24.5, -45.5, 5.0, 5.0, 4.5, 2, 'z', ('+z', 0.5), dict(lit=0.7, jetty=False)),
        # upper row (tier 9-11) just below the castle
        (-42.0, -48.0, 7.0, 6.0, 9.5, 2, 'x', ('+x', 0.5), dict(lit=0.55)),
        (-44.0, -38.0, 7.0, 6.5, 9.0, 2, 'z', ('+z', 0.5), dict(lit=0.5)),
        (-20.5, -59.0, 6.5, 5.5, 11.0, 2, 'x', ('+z', 0.5), dict(lit=0.55)),
        (-12.5, -66.0, 6.0, 6.0, 7.5, 2, 'z', ('+z', 0.5), dict(lit=0.55)),
        # out of the start view (west)
        (-34.0, -19.0, 6.0, 7.0, 5.0, 1, 'z', ('+x', 0.4), dict(jetty=False, lit=0.6)),
        (-36.5, -9.0, 5.5, 7.0, 6.5, 1, 'z', ('+x', 0.5), dict(jetty=False, lit=0.5)),
    ]
    S.houses = []
    for (x0, z0, w, d, base, floors, ridge, door, kw) in houses:
        S.flatten(x0 - 1.5, z0 - 1.5, x0 + w + 1.5, z0 + d + 1.5, base, top=C.GRASS)
    for (x0, z0, w, d, base, floors, ridge, door, kw) in houses:
        timber_house(S, x0, z0, w, d, base, floors=floors, ridge=ridge, stone_floors=1, door=door, **kw)
        S.houses.append((x0, z0, w, d, base, floors))
    # east bank cottage
    ch = S.column_top(36, -10)
    S.flatten(32.0, -14.0, 40.0, -6.0, ch)
    timber_house(S, 33.0, -13.0, 6.0, 6.0, ch, floors=1, ridge='x', door=('-x', 0.5), jetty=False, lit=0.6)

    # ---------------- castle on the hill (+ stairs up from the village lane)
    castle(S, T.CASTLE_HILL[0] + 2.0, T.CASTLE_HILL[1])
    cb = S.markers['castle'][1]
    grand_stairs(S, [(-23.0, -32.5), (-25.5, -37.0), (-28.0, -42.0), (-29.5, -52.0), (-28.3, -61.8)], 3.5, cb, width=3.0)

    # ---------------- stairs from the main path up into the village (+ landing on the upper terrace)
    S.flatten(-15.0, -14.5, -11.0, -11.0, 3.5, top=C.PATH)
    grand_stairs(S, [(-2.2, -6.8), (-5.0, -8.3), (-8.0, -9.8), (-11.5, -11.6), (-12.5, -12.2)], 0.0, 3.5, width=2.5,
                 lantern_every=7.0)

    # ---------------- market square
    S.prop('stall_blue', -2.6, 0.5, -33.0, 0.25, collide=(4.2, 3.0, 2.6, 0.0, 1.3))
    S.prop('stall_red', -9.5, 0.5, -29.5, 1.35, collide=(3.2, 3.0, 2.4, 0.0, 1.2))
    S.prop('well', -6.5, 0.5, -36.5, 0.0, collide=(2.2, 2.5, 2.2, 0.0, 0.0))
    for (bx, bz) in ((-0.2, -35.8), (0.4, -34.9), (-11.5, -32.0)):
        S.prop('barrel', bx, 0.5, bz, rng.uniform(0, 6), collide=(0.6, 0.9, 0.6, 0, 0))
    for (bx, bz, yy) in ((-4.9, -35.3, 0.5), (-4.6, -35.9, 0.5), (-4.75, -35.6, 1.0)):
        S.prop('crate', bx, yy, bz, rng.uniform(0, 0.4), collide=(0.5, 0.5, 0.5, 0, 0))
    S.prop('lantern_pole', 1.4, 0.5, -28.6, 0.0, collide=(0.4, 3.2, 0.4, 0, 0))
    S.prop('lantern_pole', -9.0, 0.5, -38.5, 0.0, collide=(0.4, 3.2, 0.4, 0, 0))
    S.prop('banner_pole', -10.0, S.column_top(-10.0, -24.0), -24.0, 1.2)
    S.prop('banner_pole', 2.0, S.column_top(2.0, -40.0), -40.0, -0.3)
    S.prop('bench', -12.0, S.column_top(-12.0, -28.0), -28.0, np.pi / 2)

    # ---------------- bridge over the river (east of the square)
    S.flatten(-1.5, -25.0, 1.5, -21.0, 0.5, top=C.PATH)
    bridge(S, 3.0, 17.5, -23.0, deck_y=3.0, width=3.5)

    # ---------------- left foreground: lantern post, fence, stones, wheat and lavender
    S.prop('lantern_post', -4.35, S.column_top(-4.35, 1.1), 1.1, 0.0, collide=(0.4, 3.5, 0.4, 0, 0))
    S.fence_line([(-3.3, 6.0), (-3.4, 2.0), (-3.6, -2.5), (-3.7, -5.5)])
    big_stone(S, -3.0, 0.5, -1.5, 1.5, 0.5, C.BOULDER_MOSS)
    big_stone(S, -2.6, 4.5, -1.8, 5.5, 0.5, C.BOULDER)
    big_stone(S, -6.5, -4.0, -5.5, -3.0, 0.5, C.BOULDER)
    big_stone(S, 2.0, -3.0, 3.0, -2.0, 0.5, C.BOULDER)
    big_stone(S, 1.6, -12.0, 2.6, -11.0, 0.5, C.BOULDER)
    big_stone(S, -2.5, -19.5, -1.5, -18.5, 0.5, C.BOULDER)
    S.fields.append((-9.5, -5.5, -7.0, -2.0, 'wheat', 0.7))
    S.fields.append((-8.5, -4.2, -1.5, 3.0, 'lavender', 0.32))
    S.fields.append((-12.5, -9.5, -6.0, -2.0, 'lavender', 0.25))
    S.fields.append((1.5, 7.5, -40.5, -35.0, 'wheat', 0.75))
    S.fields.append((-6.0, 0.5, -46.0, -41.0, 'wheat', 0.7))
    S.fields.append((-11.0, -6.5, -18.5, -14.0, 'wheat', 0.6))
    # fence along the bridge approach and river bank
    S.fence_line([(-0.4, -19.6), (2.4, -20.6)])
    S.fence_line([(-0.4, -28.6), (2.4, -25.4)])
    S.fence_line([(21.5, -19.9), (30.0, -19.3), (36.0, -17.8)])
    S.fence_line([(-0.8, -24.0), (-1.2, -14.0)])

    # ---------------- river: dock + stepping stones
    lvl = -1.0
    S.box(13.0, lvl + 0.5, -10.5, 16.5, lvl + 1.0, -6.5, C.PLANKS)
    for (px, pz) in ((13.0, -10.5), (13.0, -7.0), (15.5, -10.5), (15.5, -7.0)):
        S.box(px, lvl - 1.5, pz, px + 0.5, lvl + 1.5, pz + 0.5, C.LOG)
    S.fence_line([(13.2, -10.2), (13.2, -6.8)], y=lvl + 1.0, kind='rail')
    for (sx, sz, w, d, hh) in ((6.0, -2.0, 1.0, 1.0, 0.5), (7.2, -6.5, 1.5, 1.0, 0.5), (5.0, -9.5, 1.0, 1.5, 0.5),
                              (9.5, 2.0, 1.0, 1.0, 0.0), (8.0, -14.0, 1.0, 1.0, 0.5), (11.0, -17.0, 1.5, 1.0, 0.0),
                              (5.5, 3.5, 1.5, 1.0, 0.0), (10.0, -3.0, 1.0, 1.0, 0.0)):
        S.box(sx, lvl - 1.5, sz, sx + w, lvl + hh, sz + d, C.BOULDER)

    # ---------------- more lanterns along the path
    S.prop('lantern_pole', 1.6, S.column_top(1.6, -14.0), -14.0, 0.0, collide=(0.4, 3.2, 0.4, 0, 0))
    S.prop('lantern_post', 3.0, S.column_top(3.0, -44.0), -44.0, np.pi, collide=(0.4, 3.5, 0.4, 0, 0))
    S.prop('signpost', 2.3, S.column_top(2.3, -24.5), -24.5, -0.6)

    # markers
    S.markers['spawn'] = [0.0, 0.0, 0.0]
    S.markers['npc_market'] = [-5.2, 0.5, -21.0]
    S.markers['npc_square'] = [-7.0, 0.5, -31.5]
    S.markers['npc_bridge'] = [23.0, 0.5, -25.3]
    S.markers['npc_castle'] = [-21.0, S.markers['castle'][1], -61.0]

    decorate_village(S, rng)
    raised = sum(path_steps(S, pts, width=2.0 * w) for pts, w in
                 ((T.PATH_VILLAGE, 1.2), (T.PATH_VILLAGE2, 1.2), (T.PATH_VILLAGE3, 1.0)))
    print('path steps filled:', raised)
    retaining_walls(S)
    # keep NPC spots and quest crates free of scattered rocks / plants
    for key in ('npc_market', 'npc_square', 'npc_bridge', 'npc_castle'):
        mx, _, mz = S.markers[key]
        S.nogo[max(0, S.ix(mx - 1.6)):S.ix(mx + 1.6), max(0, S.iz(mz - 1.6)):S.iz(mz + 1.6)] = True
    for (mx, mz) in ((-20.2, -16.8), (38.6, -16.4)):
        S.nogo[max(0, S.ix(mx - 1.2)):S.ix(mx + 1.2), max(0, S.iz(mz - 1.2)):S.iz(mz + 1.2)] = True
    S.markers['ruin'] = ruin(grids)
    manifest['props'] = S.props
    manifest['lights'] = S.lights
    manifest['colliders'] = S.colliders
    manifest['markers'] = S.markers
    manifest['bounds'] = [-90.0, 90.0, -150.0, 42.0]
    grids['near'].nogo = S.nogo
    grids['near'].fields = S.fields
    grids['near'].custom_props = S.custom
