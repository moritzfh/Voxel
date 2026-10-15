"""Voxel characters (vertex coloured) split into animatable parts.

Model space: character faces -Z, +X is the character's right hand, +Y up, feet at y=0.
Voxel size 1/16 m. Grid 16 (x) * 31 (y) * 10 (z); x centre = 8, z centre = 5 (back is +z).
"""
import numpy as np

V = 1.0 / 16.0
GX, GY, GZ = 18, 32, 13
CX, CZ = 9, 6


def hexc(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class Painter:
    def __init__(self, seed=1):
        self.col = np.zeros((GX, GY, GZ, 3), np.uint8)
        self.occ = np.zeros((GX, GY, GZ), bool)
        self.part = np.zeros((GX, GY, GZ), np.int8)
        self.rng = np.random.default_rng(seed)

    def box(self, x0, y0, z0, x1, y1, z1, colors, part, pattern='noise', erase=False):
        """inclusive-exclusive voxel coords relative to centre (x around CX, z around CZ)."""
        xs = range(CX + x0, CX + x1)
        zs = range(CZ + z0, CZ + z1)
        if isinstance(colors, str):
            colors = [colors]
        cols = [hexc(c) for c in colors]
        for x in xs:
            for y in range(y0, y1):
                for z in zs:
                    if not (0 <= x < GX and 0 <= y < GY and 0 <= z < GZ):
                        continue
                    if erase:
                        self.occ[x, y, z] = False
                        continue
                    if pattern == 'checker':
                        c = cols[((x + y + z) // 1) % len(cols)] if len(cols) > 1 else cols[0]
                        c = cols[(x // 2 + y // 2 + z // 2) % len(cols)]
                    elif pattern == 'rows':
                        c = cols[(y // 2) % len(cols)]
                    elif pattern == 'plates':
                        c = cols[((y // 2) + (x // 3)) % len(cols)]
                    else:
                        c = cols[self.rng.integers(0, len(cols))]
                    self.col[x, y, z] = c
                    self.occ[x, y, z] = True
                    self.part[x, y, z] = part

    def px(self, x, y, z, color, part=None):
        x += CX
        z += CZ
        if 0 <= x < GX and 0 <= y < GY and 0 <= z < GZ:
            self.col[x, y, z] = hexc(color)
            self.occ[x, y, z] = True
            if part is not None:
                self.part[x, y, z] = part


# parts
P_TORSO, P_HEAD, P_ARM_L, P_ARM_R, P_LEG_L, P_LEG_R, P_SCARF, P_SWORD = 1, 2, 3, 4, 5, 6, 7, 8
PART_NAMES = {P_TORSO: 'torso', P_HEAD: 'head', P_ARM_L: 'arm_l', P_ARM_R: 'arm_r', P_LEG_L: 'leg_l', P_LEG_R: 'leg_r', P_SCARF: 'scarf', P_SWORD: 'sword'}
# pivots in voxel coords (x rel. centre, y, z rel. centre)
PIVOTS = {
    P_TORSO: (0, 11, 0),
    P_HEAD: (0, 21, 0),
    P_ARM_L: (-6, 20, 0),
    P_ARM_R: (6, 20, 0),
    P_LEG_L: (-2, 11, 0),
    P_LEG_R: (2, 11, 0),
    P_SCARF: (-1, 20, 3),
    P_SWORD: (0, 16, 4),
}


def hero():
    p = Painter(7)
    HAIR = ['#5e3b20', '#6f4626', '#4e311a', '#86592f']
    SKIN = ['#e9b996', '#e3b08c']
    SCARF = ['#e8661f', '#f2782b', '#d85a19']
    SCARF_D = ['#c24d15', '#b8470f']
    STEEL = ['#d4d7dc', '#9fa5ad', '#bfc3c9', '#878d96']
    LEATHER = ['#6c4325', '#5d391f', '#774a2a']
    TUNIC = ['#4b3222', '#56392a', '#45301f']
    PANTS = ['#3c2b21', '#45322a']
    BOOT = ['#2c1f17', '#36261c']
    # ---- legs (y 0..11)
    for side, part in ((-1, P_LEG_L), (1, P_LEG_R)):
        x0 = -4 if side < 0 else 0
        p.box(x0, 0, -2, x0 + 4, 3, 3, BOOT, part)            # boots
        p.box(x0, 0, -3, x0 + 4, 2, -2, BOOT, part)           # toe
        p.box(x0, 3, -2, x0 + 4, 4, 2, ['#5a3a22'], part)      # boot cuff
        p.box(x0, 4, -2, x0 + 4, 11, 2, PANTS, part)
        p.box(x0, 6, -2, x0 + 4, 8, -1, ['#7d8189', '#a0a5ad'], part, 'checker')  # knee guard front
    # ---- torso (y 11..21), 10 wide incl. armour
    p.box(-5, 11, -2, 5, 21, 3, TUNIC, P_TORSO)
    # tunic skirt flaps over hips
    p.box(-5, 9, -2, 5, 11, 3, TUNIC, P_TORSO)
    p.box(-5, 8, 2, -1, 9, 3, ['#d9d4c8', '#c9c3b5'], P_TORSO)  # cloth tail (white) at back left
    # leather chest piece with straps
    p.box(-4, 13, -3, 4, 20, -2, LEATHER, P_TORSO)
    p.box(-4, 13, 3, 4, 20, 4, LEATHER, P_TORSO)
    # chainmail lower band
    p.box(-5, 11, -3, 5, 13, 4, ['#7e838b', '#9aa0a8', '#6d727a'], P_TORSO, 'checker')
    # belt
    p.box(-5, 12, -3, 5, 13, 4, ['#3a2416', '#33200f'], P_TORSO)
    p.box(-1, 12, -4, 1, 13, -3, ['#c9a24a'], P_TORSO)
    # back strap for sword (diagonal)
    for i in range(8):
        p.px(-3 + i, 13 + i, 3, '#3a2416', P_TORSO)
        p.px(-3 + i, 13 + i, 4, '#3a2416', P_TORSO)
    # ---- arms (y 11..20)
    for side, part in ((-1, P_ARM_L), (1, P_ARM_R)):
        x0 = -8 if side < 0 else 5
        p.box(x0, 15, -1, x0 + 3, 19, 2, LEATHER, part)          # upper arm
        p.box(x0, 11, -1, x0 + 3, 15, 2, STEEL, part, 'plates')  # bracer
        p.box(x0, 9, -1, x0 + 3, 11, 2, ['#4a2f1c', '#3e2716'], part)  # glove
        # pauldron (big, layered)
        px0 = -9 if side < 0 else 4
        p.box(px0, 18, -2, px0 + 5, 21, 3, STEEL, part, 'plates')
        p.box(px0 + (0 if side < 0 else 1), 17, -2, px0 + (4 if side < 0 else 5), 18, 3, ['#8a9099', '#b8bcc3'], part, 'checker')
        p.box(px0 + (1 if side < 0 else 0), 21, -1, px0 + (5 if side < 0 else 4), 22, 2, ['#e4e7ea', '#c5c9cf'], part)
    # ---- head (y 21..29) + hair
    p.box(-4, 21, -4, 4, 29, 4, SKIN, P_HEAD)
    # hair: back + top + sides, messy tufts
    p.box(-4, 23, 1, 4, 30, 5, HAIR, P_HEAD)
    p.box(-5, 23, -3, -4, 29, 4, HAIR, P_HEAD)
    p.box(4, 23, -3, 5, 29, 4, HAIR, P_HEAD)
    p.box(-4, 28, -5, 4, 31, 5, HAIR, P_HEAD)
    p.box(-4, 26, -5, 4, 28, -4, HAIR, P_HEAD)  # fringe
    for (tx, tz) in ((-3, 0), (1, -2), (3, 2), (-1, 3), (2, -4), (-4, -3)):
        p.px(tx, 31, tz, HAIR[0], P_HEAD)
    for (tx, ty, tz) in ((-5, 22, 2), (4, 22, 3), (-2, 22, 5), (2, 23, 5), (0, 22, 5)):
        p.px(tx, ty, tz, HAIR[2], P_HEAD)
    # face
    p.px(-3, 25, -5, '#1b1513', P_HEAD)
    p.px(-2, 25, -5, '#1b1513', P_HEAD)
    p.px(-3, 26, -5, '#1b1513', P_HEAD)
    p.px(-2, 26, -5, '#ffffff', P_HEAD)
    p.px(1, 25, -5, '#1b1513', P_HEAD)
    p.px(2, 25, -5, '#1b1513', P_HEAD)
    p.px(1, 26, -5, '#1b1513', P_HEAD)
    p.px(2, 26, -5, '#ffffff', P_HEAD)
    p.px(-3, 27, -5, '#4c3019', P_HEAD)
    p.px(-2, 27, -5, '#4c3019', P_HEAD)
    p.px(1, 27, -5, '#4c3019', P_HEAD)
    p.px(2, 27, -5, '#4c3019', P_HEAD)
    p.px(-1, 23, -5, '#b9806a', P_HEAD)
    p.px(0, 23, -5, '#b9806a', P_HEAD)
    p.px(-4, 24, -5, '#f0a99a', P_HEAD)
    p.px(3, 24, -5, '#f0a99a', P_HEAD)
    # ---- scarf: thick wrap around the neck + long tail on the back
    p.box(-5, 20, -5, 5, 23, 5, SCARF, P_HEAD)
    p.box(-4, 20, -5, 4, 21, 5, SCARF_D, P_HEAD)
    p.box(-2, 22, -5, 2, 23, -4, ['#ff9446'], P_HEAD)
    # tail hangs from the back of the neck down to the hips, slightly left
    for i in range(12):
        y = 20 - i
        w0 = -2 - (i // 5)
        p.box(w0, y, 4, w0 + 4, y + 1, 5, SCARF if i % 3 else SCARF_D, P_SCARF)
    # frayed end
    for x in range(-4, 1):
        if x % 2 == 0:
            p.px(x, 8, 4, SCARF_D[0], P_SCARF)
    # ---- sword on the back: pommel above the right shoulder, scabbard tip at the left hip
    pom = np.array([8.5, 26.5])
    tip = np.array([-6.5, 4.0])
    dv = tip - pom
    L = np.hypot(*dv)
    dn = dv / L
    perp = np.array([dn[1], -dn[0]])
    N = int(L * 1.6)
    for k in range(N + 1):
        t = k / N
        q = pom + dv * t
        x, y = int(round(q[0])), int(round(q[1]))
        if t < 0.05:
            cols = ['#d6d9de', '#aeb3ba']
        elif t < 0.22:
            cols = ['#5a3a22', '#7a5232'] if (y % 2) else ['#4a2e1a', '#6a4428']
        elif t < 0.26:
            cols = None
            for o in range(-3, 4):
                pp = q + perp * o
                p.px(int(round(pp[0])), int(round(pp[1])), 6, '#6e5426' if abs(o) < 3 else '#8a6b30', P_SWORD)
            continue
        elif t < 0.9:
            cols = ['#4a2e1a', '#5d3a21']
        else:
            cols = ['#cfd3d8', '#9ea3aa']
        p.px(x, y, 6, cols[0], P_SWORD)
        side = q + perp * 0.9
        p.px(int(round(side[0])), int(round(side[1])), 6, cols[1], P_SWORD)
        p.px(x, y, 5, cols[1], P_SWORD)
    return p


def villager(seed, tunic, hair, beard=None, apron=None, hood=None):
    p = Painter(seed)
    SKIN = ['#e3b08c', '#d9a07c']
    PANTS = ['#4a3a2c', '#54412f']
    BOOT = ['#2c1f17', '#36261c']
    for side, part in ((-1, P_LEG_L), (1, P_LEG_R)):
        x0 = -4 if side < 0 else 0
        p.box(x0, 0, -2, x0 + 4, 3, 2, BOOT, part)
        p.box(x0, 3, -2, x0 + 4, 11, 2, PANTS, part)
    p.box(-4, 11, -2, 4, 21, 2, tunic, P_TORSO)
    p.box(-4, 9, -2, 4, 11, 2, tunic, P_TORSO)
    p.box(-4, 12, -3, 4, 13, 3, ['#3a2416'], P_TORSO)
    if apron:
        p.box(-3, 8, -3, 3, 18, -2, apron, P_TORSO)
    for side, part in ((-1, P_ARM_L), (1, P_ARM_R)):
        x0 = -7 if side < 0 else 4
        p.box(x0, 11, -1, x0 + 3, 21, 2, tunic, part)
        p.box(x0, 9, -1, x0 + 3, 11, 2, SKIN, part)
    p.box(-4, 21, -4, 4, 29, 4, SKIN, P_HEAD)
    p.box(-4, 26, -1, 4, 30, 5, hair, P_HEAD)
    p.box(-4, 28, -5, 4, 30, 5, hair, P_HEAD)
    p.box(-5, 24, -3, -4, 29, 4, hair, P_HEAD)
    p.box(4, 24, -3, 5, 29, 4, hair, P_HEAD)
    p.box(-4, 21, 1, 4, 27, 5, hair, P_HEAD)
    if hood:
        p.box(-5, 26, -4, 5, 31, 5, hood, P_HEAD)
        p.box(-4, 26, -4, 4, 29, -3, SKIN, P_HEAD, erase=False)
    for (ex, c) in ((-3, '#1b1513'), (-2, '#1b1513'), (1, '#1b1513'), (2, '#1b1513')):
        p.px(ex, 25, -5, c, P_HEAD)
    p.px(-2, 26, -5, '#1b1513', P_HEAD)
    p.px(1, 26, -5, '#1b1513', P_HEAD)
    if beard:
        p.box(-4, 20, -5, 4, 24, -4, beard, P_HEAD)
        p.box(-3, 18, -5, 3, 20, -4, beard, P_HEAD)
        p.box(-4, 27, -5, 4, 28, -4, beard, P_HEAD)
        p.px(-3, 25, -5, '#1b1513', P_HEAD)
        p.px(2, 25, -5, '#1b1513', P_HEAD)
    else:
        p.px(-1, 23, -5, '#b9806a', P_HEAD)
        p.px(0, 23, -5, '#b9806a', P_HEAD)
    return p


def mesh_part(p, part_id, ao=True):
    """Face-culled mesh with vertex colours + simple AO for one part. Pivot at origin."""
    occ = p.occ & (p.part == part_id)
    pv = PIVOTS[part_id]
    piv = np.array([CX + pv[0], pv[1], CZ + pv[2]], np.float64)
    allocc = p.occ
    pos, nrm, col, idx, uvs = [], [], [], [], []
    dirs = [((1, 0, 0), (0, 0, 1), (0, 1, 0)), ((-1, 0, 0), (0, 0, -1), (0, 1, 0)),
            ((0, 1, 0), (1, 0, 0), (0, 0, 1)), ((0, -1, 0), (1, 0, 0), (0, 0, -1)),
            ((0, 0, 1), (-1, 0, 0), (0, 1, 0)), ((0, 0, -1), (1, 0, 0), (0, 1, 0))]

    def solid(x, y, z):
        if 0 <= x < GX and 0 <= y < GY and 0 <= z < GZ:
            return occ[x, y, z]
        return False
    xs, ys, zs = np.nonzero(occ)
    for x, y, z in zip(xs, ys, zs):
        c = p.col[x, y, z] / 255.0
        for (n, u, vv) in dirs:
            nx, ny, nz = x + n[0], y + n[1], z + n[2]
            if solid(nx, ny, nz):
                continue
            # face centre
            fc = np.array([x + 0.5 + n[0] * 0.5, y + 0.5 + n[1] * 0.5, z + 0.5 + n[2] * 0.5])
            u_ = np.array(u, float) * 0.5
            v_ = np.array(vv, float) * 0.5
            corners = [fc - u_ - v_, fc + u_ - v_, fc + u_ + v_, fc - u_ + v_]
            shade = []
            for (su, sv) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                a = solid(nx + su * u[0], ny + su * u[1], nz + su * u[2]) if ao else 0
                b = solid(nx + sv * vv[0], ny + sv * vv[1], nz + sv * vv[2]) if ao else 0
                cc = solid(nx + su * u[0] + sv * vv[0], ny + su * u[1] + sv * vv[1], nz + su * u[2] + sv * vv[2]) if ao else 0
                lvl = 0 if (a and b) else 3 - (a + b + cc)
                shade.append(0.62 + 0.38 * lvl / 3)
            base = len(pos)
            for k in range(4):
                uvs.append(((0, 0), (1, 0), (1, 1), (0, 1))[k])
                pos.append((corners[k] - piv) * V)
                nrm.append(n)
                lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
                col.append((lin[0] * shade[k], lin[1] * shade[k], lin[2] * shade[k], 1.0))
            # Godot front faces are clockwise: reverse when the corner loop is CCW around n
            if np.dot(np.cross(u, vv), n) > 0:
                idx += [base, base + 2, base + 1, base, base + 3, base + 2]
            else:
                idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    if not pos:
        return None
    return dict(pos=np.array(pos, np.float32), nrm=np.array(nrm, np.float32), col=np.array(col, np.float32),
                uv=np.array(uvs, np.float32), idx=np.array(idx, np.int32))


def check_winding():
    for (n, u, v) in [((1, 0, 0), (0, 0, 1), (0, 1, 0)), ((-1, 0, 0), (0, 0, -1), (0, 1, 0)),
                      ((0, 1, 0), (1, 0, 0), (0, 0, 1)), ((0, -1, 0), (1, 0, 0), (0, 0, -1)),
                      ((0, 0, 1), (-1, 0, 0), (0, 1, 0)), ((0, 0, -1), (1, 0, 0), (0, 1, 0))]:
        assert np.allclose(np.cross(u, v), n) or np.allclose(np.cross(u, v), -np.array(n)), (n, u, v)
        print(n, np.cross(u, v))


def build_characters(writer):
    chars = {
        'hero': hero(),
        'elder': villager(11, ['#4f5b7a', '#56628a', '#48536f'], ['#d8d6d0', '#c7c4bd'], beard=['#e8e6e0', '#d4d1ca']),
        'merchant': villager(12, ['#6b3b2a', '#7a4632', '#5f3424'], ['#3f2a1a', '#4a3220'], apron=['#d8cfb8', '#cbc1a8']),
        'guard': villager(13, ['#3d5a3a', '#466843', '#36502f'], ['#6b4a2a', '#5a3d22'], hood=['#2f4a2d', '#365834']),
        'farmer': villager(14, ['#7a6a3a', '#867546', '#6d5e33'], ['#8a5a2a', '#7a4f25']),
    }
    out = {}
    for name, p in chars.items():
        parts = {}
        for pid, pname in PART_NAMES.items():
            m = mesh_part(p, pid)
            if m is None:
                continue
            pv = PIVOTS[pid]
            parts[pname] = {'mesh': {k: writer.put(v) for k, v in m.items()}, 'pivot': [pv[0] * V, pv[1] * V, pv[2] * V]}
        out[name] = parts
    return out


if __name__ == '__main__':
    check_winding()
