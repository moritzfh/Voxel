"""Greedy voxel mesher with per-vertex ambient occlusion (numba).

Grid layout: vox[x, y, z] uint8 block ids, 0 = air.
Faces are emitted for solid blocks next to non-solid neighbours.
Faces with uniform AO are greedily merged; others are emitted per block.
"""
import numpy as np
from numba import njit

# directions: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z
DIRS = np.array([[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]], np.int64)


@njit(cache=True)
def _solid(vox, solid, x, y, z):
    X, Y, Z = vox.shape
    if x < 0 or y < 0 or z < 0 or x >= X or z >= Z:
        return False
    if y >= Y:
        return False
    return solid[vox[x, y, z]]


@njit(cache=True)
def _occ(vox, solid, x, y, z):
    X, Y, Z = vox.shape
    if x < 0 or y < 0 or z < 0 or x >= X or y >= Y or z >= Z:
        return 0
    return 1 if (solid[vox[x, y, z]] and solid[vox[x, y, z]]) else 0


@njit(cache=True)
def _vao(s1, s2, c):
    if s1 and s2:
        return 0
    return 3 - (s1 + s2 + c)


@njit(cache=True)
def _face_axes(d):
    # returns (normal axis, u axis, v axis)
    if d < 2:
        return 0, 2, 1
    elif d < 4:
        return 1, 0, 2
    else:
        return 2, 0, 1


@njit(cache=True)
def _xyz(na, s, u, v):
    if na == 0:
        return s, v, u
    elif na == 1:
        return u, s, v
    else:
        return u, v, s


@njit(cache=True)
def mesh_region(vox, solid, occluder, tex_top, tex_side, tex_bottom, emis, x0, x1, z0, z1,
                out_quads, collision, use_ao):
    """Fill out_quads rows: [d, nslice, u0, v0, du, dv, block, ao0, ao1, ao2, ao3].
    Coordinates are grid indices. Returns quad count.
    occluder[b]: block hides neighbour faces. solid[b]: block emits faces.
    """
    X, Y, Z = vox.shape
    n = 0
    for d in range(6):
        na, ua, va = _face_axes(d)
        dx = 1 if d == 0 else (-1 if d == 1 else 0)
        dy = 1 if d == 2 else (-1 if d == 3 else 0)
        dz = 1 if d == 4 else (-1 if d == 5 else 0)
        # bounds per axis
        if na == 0:
            nlo, nhi = x0, x1
        elif na == 1:
            nlo, nhi = 0, Y
        else:
            nlo, nhi = z0, z1
        if ua == 0:
            ulo, uhi = x0, x1
        else:
            ulo, uhi = z0, z1
        if va == 1:
            vlo, vhi = 0, Y
        else:
            vlo, vhi = z0, z1
        # tangent unit vectors
        tux = 1 if ua == 0 else 0
        tuz = 1 if ua == 2 else 0
        tvy = 1 if va == 1 else 0
        tvz = 1 if va == 2 else 0
        W = uhi - ulo
        H = vhi - vlo
        mask = np.full((W, H), -1, np.int64)
        for s in range(nlo, nhi):
            any_face = False
            for iu in range(W):
                for iv in range(H):
                    x, y, z = _xyz(na, s, ulo + iu, vlo + iv)
                    b = vox[x, y, z]
                    key = -1
                    if solid[b]:
                        nx, ny, nz = x + dx, y + dy, z + dz
                        exposed = True
                        if 0 <= nx < X and 0 <= nz < Z and 0 <= ny < Y:
                            if occluder[vox[nx, ny, nz]]:
                                exposed = False
                        elif ny < 0:
                            exposed = False
                        elif nx < 0 or nx >= X or nz < 0 or nz >= Z:
                            exposed = False
                        if exposed:
                            if collision:
                                key = 1
                            elif not use_ao:
                                key = b | (3 << 8) | (3 << 10) | (3 << 12) | (3 << 14)
                            else:
                                a0 = 0
                                a1 = 0
                                a2 = 0
                                a3 = 0
                                for k in range(4):
                                    su = -1 if (k == 0 or k == 3) else 1
                                    sv = -1 if (k == 0 or k == 1) else 1
                                    s1 = _occ(vox, occluder, nx + su * tux, ny, nz + su * tuz)
                                    s2 = _occ(vox, occluder, nx, ny + sv * tvy, nz + sv * tvz)
                                    cc = _occ(vox, occluder, nx + su * tux, ny + sv * tvy, nz + su * tuz + sv * tvz)
                                    a = _vao(s1, s2, cc)
                                    if k == 0:
                                        a0 = a
                                    elif k == 1:
                                        a1 = a
                                    elif k == 2:
                                        a2 = a
                                    else:
                                        a3 = a
                                key = b | (a0 << 8) | (a1 << 10) | (a2 << 12) | (a3 << 14)
                                if not (a0 == a1 and a1 == a2 and a2 == a3):
                                    key |= (1 << 20)
                                    # AO that only varies across one axis can still merge along the other
                                    if a0 == a1 and a3 == a2:
                                        key |= (1 << 21)
                                    if a0 == a3 and a1 == a2:
                                        key |= (1 << 22)
                            any_face = True
                    mask[iu, iv] = key
            if not any_face:
                continue
            for iv in range(H):
                iu = 0
                while iu < W:
                    key = mask[iu, iv]
                    if key < 0:
                        iu += 1
                        continue
                    w = 1
                    h = 1
                    uni = (key >> 20) & 1 == 0
                    if uni or (key >> 21) & 1:
                        while iu + w < W and mask[iu + w, iv] == key:
                            w += 1
                    if uni or (key >> 22) & 1:
                        done = False
                        while iv + h < H and not done:
                            for k in range(w):
                                if mask[iu + k, iv + h] != key:
                                    done = True
                                    break
                            if not done:
                                h += 1
                    for a in range(w):
                        for bb in range(h):
                            mask[iu + a, iv + bb] = -1
                    if n < out_quads.shape[0]:
                        out_quads[n, 0] = d
                        out_quads[n, 1] = s
                        out_quads[n, 2] = ulo + iu
                        out_quads[n, 3] = vlo + iv
                        out_quads[n, 4] = w
                        out_quads[n, 5] = h
                        out_quads[n, 6] = key & 255
                        out_quads[n, 7] = (key >> 8) & 3
                        out_quads[n, 8] = (key >> 10) & 3
                        out_quads[n, 9] = (key >> 12) & 3
                        out_quads[n, 10] = (key >> 14) & 3
                    n += 1
                    iu += w
    return n


def quads_to_arrays(quads, vs, origin, tex_top, tex_side, tex_bottom, emis, uv_unit, collision=False):
    """Convert quads to vertex arrays.
    vs: voxel size (m); origin: world position of grid index (0,0,0) corner.
    uv_unit: metres per texture tile.
    Returns dict of numpy arrays.
    """
    q = quads
    nq = len(q)
    if nq == 0:
        return None
    d = q[:, 0]
    s = q[:, 1]
    u0 = q[:, 2]
    v0 = q[:, 3]
    w = q[:, 4]
    h = q[:, 5]
    b = q[:, 6]
    ao = q[:, 7:11].astype(np.float32)
    na = np.where(d < 2, 0, np.where(d < 4, 1, 2))
    ua = np.where(d < 2, 2, 0)
    va = np.where(d < 2, 1, np.where(d < 4, 2, 1))
    plane = s + np.where(d % 2 == 0, 1, 0)  # positive faces sit on the far side
    # 4 corners in (u,v): (-,-), (+,-), (+,+), (-,+)
    cu = np.stack([u0, u0 + w, u0 + w, u0], 1)
    cv = np.stack([v0, v0, v0 + h, v0 + h], 1)
    pos = np.zeros((nq, 4, 3), np.float64)
    for k in range(4):
        pos[np.arange(nq), k, na] = plane
        pos[np.arange(nq), k, ua] = cu[:, k]
        pos[np.arange(nq), k, va] = cv[:, k]
    pos = pos * vs + np.asarray(origin)[None, None, :]
    normals = np.zeros((nq, 3), np.float32)
    dirs = np.array([[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]], np.float32)
    normals = dirs[d]
    # winding: we want counter-clockwise when seen from the normal side (Godot: clockwise front faces!)
    # Godot uses clockwise winding for front faces. Determine via cross product.
    e1 = pos[:, 1] - pos[:, 0]
    e2 = pos[:, 2] - pos[:, 0]
    cr = np.cross(e1, e2)
    facing = np.einsum('ij,ij->i', cr, normals)
    # triangle indices per quad; choose diagonal by AO (anisotropy fix)
    flip_diag = (ao[:, 0] + ao[:, 2]) < (ao[:, 1] + ao[:, 3])
    base = (np.arange(nq) * 4)[:, None]
    tri_a = np.array([0, 1, 2, 0, 2, 3])
    tri_b = np.array([0, 1, 3, 1, 2, 3])
    idx = np.where(flip_diag[:, None], tri_b[None, :], tri_a[None, :])
    # if cross product points along normal, the order is CCW from the front -> reverse for Godot
    rev = facing > 0
    idx = np.where(rev[:, None], idx[:, [0, 2, 1, 3, 5, 4]], idx)
    indices = (idx + base).astype(np.int32).reshape(-1)
    out = {'pos': pos.reshape(-1, 3).astype(np.float32), 'idx': indices}
    if collision:
        return out
    # UVs: world-aligned, in texture tiles
    wp = pos.reshape(nq, 4, 3)
    uvs = np.zeros((nq, 4, 2), np.float32)
    ux = wp[:, :, 0] / uv_unit
    uy = wp[:, :, 1] / uv_unit
    uz = wp[:, :, 2] / uv_unit
    is_x = (d < 2)[:, None]
    is_y = ((d >= 2) & (d < 4))[:, None]
    # side faces: u along horizontal axis, v = -y (texture top at block top)
    sgn_x = np.where(d == 0, -1.0, 1.0)[:, None]  # mirror so texture reads correctly
    sgn_z = np.where(d == 4, 1.0, -1.0)[:, None]
    uvs[:, :, 0] = np.where(is_x, uz * sgn_x, np.where(is_y, ux, ux * sgn_z))
    uvs[:, :, 1] = np.where(is_y, uz, -uy)
    layer = np.where(d == 2, tex_top[b], np.where(d == 3, tex_bottom[b], tex_side[b])).astype(np.float32)
    uv2 = np.zeros((nq, 4, 2), np.float32)
    uv2[:, :, 0] = layer[:, None] + 0.25
    uv2[:, :, 1] = ao / 3.0
    out['nrm'] = np.repeat(normals, 4, axis=0).astype(np.float32)
    out['uv'] = uvs.reshape(-1, 2)
    out['uv2'] = uv2.reshape(-1, 2)
    return out


def mesh_grid(vox, blocks, vs, origin, x0, x1, z0, z1, uv_unit, collision=False, max_quads=3_000_000, use_ao=True):
    out = np.zeros((max_quads, 11), np.int64)
    solid = blocks['solid'] if not collision else blocks['collide']
    occluder = blocks['occluder']
    n = mesh_region(vox, solid, occluder, blocks['top'], blocks['side'], blocks['bottom'], blocks['emis'],
                    x0, x1, z0, z1, out, collision, use_ao)
    if n > max_quads:
        raise RuntimeError('too many quads')
    return quads_to_arrays(out[:n], vs, origin, blocks['top'], blocks['side'], blocks['bottom'], blocks['emis'],
                           uv_unit, collision)


# ---------------------------------------------------------------- colour-voxel output
_BUF = {}


def quads_to_vox_arrays(q, vs, origin, vsi):
    """Quads -> pos/nrm/cus(RGBA8: value, ao, vs-index, 255)/idx."""
    nq = len(q)
    if nq == 0:
        return None
    d = q[:, 0]
    s = q[:, 1]
    u0 = q[:, 2]
    v0 = q[:, 3]
    w = q[:, 4]
    h = q[:, 5]
    b = q[:, 6]
    ao = q[:, 7:11]
    na = np.where(d < 2, 0, np.where(d < 4, 1, 2))
    ua = np.where(d < 2, 2, 0)
    va = np.where(d < 2, 1, np.where(d < 4, 2, 1))
    plane = s + np.where(d % 2 == 0, 1, 0)
    cu = np.stack([u0, u0 + w, u0 + w, u0], 1)
    cv = np.stack([v0, v0, v0 + h, v0 + h], 1)
    pos = np.zeros((nq, 4, 3), np.float64)
    ar = np.arange(nq)
    for k in range(4):
        pos[ar, k, na] = plane
        pos[ar, k, ua] = cu[:, k]
        pos[ar, k, va] = cv[:, k]
    pos = pos * vs + np.asarray(origin, np.float64)[None, None, :]
    dirs = np.array([[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]], np.float32)
    normals = dirs[d]
    e1 = pos[:, 1] - pos[:, 0]
    e2 = pos[:, 2] - pos[:, 0]
    facing = np.einsum('ij,ij->i', np.cross(e1, e2), normals)
    flip_diag = (ao[:, 0] + ao[:, 2]) < (ao[:, 1] + ao[:, 3])
    base = (ar * 4)[:, None]
    tri_a = np.array([0, 1, 2, 0, 2, 3])
    tri_b = np.array([0, 1, 3, 1, 2, 3])
    idx = np.where(flip_diag[:, None], tri_b[None, :], tri_a[None, :])
    idx = np.where((facing > 0)[:, None], idx[:, [0, 2, 1, 3, 5, 4]], idx)
    cus = np.zeros((nq, 4, 4), np.uint8)
    cus[:, :, 0] = b[:, None]
    cus[:, :, 1] = ao
    cus[:, :, 2] = vsi
    cus[:, :, 3] = 255
    return {'pos': pos.reshape(-1, 3).astype(np.float32), 'nrm': np.repeat(normals, 4, axis=0),
            'cus': cus.reshape(-1, 4), 'idx': (idx + base).astype(np.int32).reshape(-1)}


def mesh_vox(vox, tables, vs, origin, x0, x1, z0, z1, use_ao=True, max_quads=1_500_000, solid=None):
    """Greedy-mesh encoded colour voxels in columns [x0,x1) x [z0,z1)."""
    key = max_quads
    if key not in _BUF:
        _BUF[key] = np.zeros((max_quads, 11), np.int64)
    out = _BUF[key]
    s = tables['solid'] if solid is None else solid
    n = mesh_region(vox, s, tables['occluder'] if solid is None else tables['occ_water'],
                    tables['top'], tables['side'], tables['bottom'], tables['emis'],
                    x0, x1, z0, z1, out, False, use_ao)
    if n > max_quads:
        raise RuntimeError(f'too many quads: {n}')
    import vox as VX
    return quads_to_vox_arrays(out[:n].copy(), vs, origin, VX.vs_index(vs))


def mesh_collision(vox, solid, occluder, vs, origin, x0, x1, z0, z1, max_quads=1_500_000):
    key = ('col', max_quads)
    if key not in _BUF:
        _BUF[key] = np.zeros((max_quads, 11), np.int64)
    out = _BUF[key]
    z = np.zeros(256, np.int64)
    n = mesh_region(vox, solid, occluder, z, z, z, np.zeros(256, np.float32), x0, x1, z0, z1, out, True, False)
    if n == 0:
        return None
    return quads_to_arrays(out[:n].copy(), vs, origin, z, z, z, None, 1.0, collision=True)
