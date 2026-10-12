"""Colour-voxel material system.

Every voxel is stored as one byte:  value = (material << 2) | variant
    material 1..62  -> see MATERIALS (ids shared with common.py block ids)
    variant  0..3   -> one of four palette colours of that material
    0 = air, 255 = HOLE (LOD hand-over, never rendered)

Geometry is plain coloured cubes; the shader adds per-voxel brightness jitter,
thin bevel lines between voxels and ambient occlusion. No textures anywhere.
"""
import numpy as np
from numba import njit
import common as C

# new material ids (continue after the old block ids)
PLANT_GREEN = 43
FLOWER_WHITE = 44
FLOWER_YELLOW = 45
FLOWER_RED = 46
FLOWER_BLUE = 47
FLOWER_PURPLE = 48
WHEAT = 49
FLOWER_CENTER = 50
REED = 51
LILY = 52
CLOUD = 53
GOLD = 54
MOSS = 55
SKIN = 56
HOLE_V = 255

# id -> (name, [4 sRGB colours], emission per variant, roughness, jitter)
MATERIALS = {
    C.GRASS: ('grass', ['#5aa83a', '#4c9632', '#67b642', '#7fc650'], 0, 0.95, 0.10),
    C.DIRT: ('dirt', ['#7a5232', '#6b4629', '#86603b', '#9a8b7a'], 0, 0.95, 0.10),
    C.PATH: ('path', ['#c4a473', '#b39265', '#d0b386', '#a39684'], 0, 0.95, 0.08),
    C.STONE: ('stone', ['#8c8a85', '#7d7b76', '#9b9993', '#6e6c68'], 0, 0.9, 0.08),
    C.CLIFF: ('cliff', ['#7c7a76', '#6c6a67', '#8b8984', '#5d5b58'], 0, 0.9, 0.08),
    C.BRICKS: ('bricks', ['#a19d94', '#8e8b83', '#b2aea4', '#7b786f'], 0, 0.9, 0.05),
    C.BRICKS_DARK: ('bricks_dark', ['#7a7872', '#6c6a65', '#87857e', '#5c5a56'], 0, 0.9, 0.05),
    C.COBBLE: ('cobble', ['#928f89', '#7f7c77', '#a5a29b', '#5c5a56'], 0, 0.9, 0.06),
    C.COBBLE_MOSSY: ('cobble_mossy', ['#8d8b83', '#7a7970', '#a09e95', '#5b8a37'], 0, 0.9, 0.06),
    C.PLASTER: ('plaster', ['#eee4cf', '#e5dac3', '#f5eedd', '#d8cbb0'], 0, 0.92, 0.03),
    C.TIMBER: ('timber', ['#5c3b22', '#4f321d', '#68442a', '#3f2817'], 0, 0.85, 0.05),
    C.PLANKS: ('planks', ['#9d6c3f', '#8b5e36', '#ab7a4a', '#6e4a2a'], 0, 0.85, 0.05),
    C.PLANKS_DARK: ('planks_dark', ['#614329', '#543923', '#6e4c2f', '#3e2a19'], 0, 0.85, 0.05),
    C.SLATE: ('slate', ['#4c5867', '#424c5a', '#586473', '#363e4a'], 0, 0.7, 0.05),
    C.LOG: ('log', ['#5b3e26', '#4d341f', '#6a492d', '#b08a5a'], 0, 0.9, 0.06),
    C.PINE_LEAVES: ('pine', ['#2c5c2f', '#244e28', '#367036', '#1c3f21'], 0, 0.9, 0.10),
    C.OAK_LEAVES: ('oak', ['#4f9134', '#42812d', '#5ea33d', '#79b84a'], 0, 0.9, 0.10),
    C.SNOW: ('snow', ['#f2f5f8', '#e5ebf1', '#fbfcfd', '#d3dce6'], 0, 0.6, 0.03),
    C.SNOW_FULL: ('snow2', ['#f2f5f8', '#e5ebf1', '#fbfcfd', '#d3dce6'], 0, 0.6, 0.03),
    C.GRAVEL: ('gravel', ['#8d877e', '#7b766e', '#9d978d', '#6a655e'], 0, 0.95, 0.10),
    C.SAND: ('sand', ['#d6c48f', '#cbb782', '#e0cf9f', '#bba872'], 0, 0.95, 0.06),
    C.RIVERBED: ('riverbed', ['#77705f', '#685f50', '#857d6b', '#9b9481'], 0, 0.95, 0.08),
    C.CLOTH_WHITE: ('cloth_w', ['#ece9e0', '#dedbd1', '#f6f4ee', '#cfcbc0'], 0, 0.95, 0.03),
    C.CLOTH_BLUE: ('cloth_b', ['#2f62ad', '#28559a', '#3a70bf', '#22477f'], 0, 0.95, 0.03),
    C.CLOTH_GREEN: ('cloth_g', ['#2f7a3a', '#286a32', '#388a44', '#215a2a'], 0, 0.95, 0.03),
    C.BANNER: ('banner', ['#2f7a3a', '#286a32', '#ece6d4', '#d4a53c'], 0, 0.95, 0.03),
    C.IRON: ('iron', ['#3a3c42', '#313338', '#474a51', '#26282c'], 0, 0.45, 0.04),
    C.LANTERN: ('lantern', ['#ffcf70', '#ffc55a', '#ffe0a0', '#ffb84a'], [1.5, 1.5, 1.5, 1.5], 0.5, 0.03),
    C.WINDOW_LIT: ('window', ['#ffc25e', '#f5b24c', '#ffd47e', '#e8a040'], [1.5, 1.4, 1.6, 1.2], 0.25, 0.04),
    C.WINDOW_DARK: ('window_d', ['#3b4b5e', '#33414f', '#465a6f', '#2b3542'], 0, 0.2, 0.04),
    C.HAY: ('hay', ['#d9b04c', '#c99d3c', '#e6c25e', '#b8862e'], 0, 0.95, 0.06),
    C.CRATE: ('crate', ['#a07040', '#8f6338', '#ad7c4a', '#5a3a1f'], 0, 0.9, 0.05),
    C.WATER: ('water', ['#2f78a8', '#2f78a8', '#2f78a8', '#2f78a8'], 0, 0.1, 0.0),
    C.CLOTH_RED: ('cloth_r', ['#b03a2c', '#9c3226', '#c24636', '#7f281e'], 0, 0.95, 0.03),
    C.PINE_LEAVES_LIGHT: ('pine_l', ['#3e7c3c', '#357036', '#488c45', '#2c5f2f'], 0, 0.9, 0.10),
    C.GRASS_CLIFF: ('grass_c', ['#5aa83a', '#4c9632', '#67b642', '#7fc650'], 0, 0.95, 0.10),
    C.WATER_FALL: ('waterfall', ['#cfe8f5', '#cfe8f5', '#cfe8f5', '#cfe8f5'], 0, 0.3, 0.0),
    C.GRASS_SLOPE: ('grass_s', ['#5aa83a', '#4c9632', '#67b642', '#7fc650'], 0, 0.95, 0.10),
    C.BOULDER: ('boulder', ['#9a978f', '#8a877f', '#aaa79e', '#78756d'], 0, 0.9, 0.07),
    C.BOULDER_MOSS: ('boulder_m', ['#9a978f', '#8a877f', '#62a03e', '#4f8a32'], 0, 0.9, 0.07),
    C.MOUNTAIN_ROCK: ('mountain', ['#7f8691', '#6f7681', '#8f959f', '#5c626b'], 0, 0.9, 0.07),
    C.PEBBLE: ('pebble', ['#b5b1a8', '#a5a198', '#c4c0b6', '#8f8b83'], 0, 0.9, 0.06),
    PLANT_GREEN: ('plant', ['#5fae3c', '#4f9a32', '#78c64b', '#3b7a27'], 0, 0.9, 0.10),
    FLOWER_WHITE: ('fl_white', ['#fbfbf6', '#ececE4', '#ffffff', '#d8d8cf'], 0, 0.9, 0.04),
    FLOWER_YELLOW: ('fl_yellow', ['#ffd23a', '#f3bf28', '#ffe066', '#dfa21e'], 0, 0.9, 0.05),
    FLOWER_RED: ('fl_red', ['#e04a2e', '#c93a22', '#f0613f', '#a82e1a'], 0, 0.9, 0.05),
    FLOWER_BLUE: ('fl_blue', ['#6f8fe0', '#5a78cf', '#8aa4ee', '#4a62b5'], 0, 0.9, 0.05),
    FLOWER_PURPLE: ('fl_purple', ['#8a63c9', '#7754b5', '#9d78da', '#6346a0'], 0, 0.9, 0.05),
    WHEAT: ('wheat', ['#e0b850', '#d1a743', '#ecc865', '#b98f33'], 0, 0.9, 0.06),
    FLOWER_CENTER: ('fl_center', ['#f2b32b', '#e09a1a', '#ffc844', '#5a3a1c'], 0, 0.9, 0.04),
    REED: ('reed', ['#6b4226', '#5c381f', '#7a4c2d', '#4d2f19'], 0, 0.9, 0.05),
    LILY: ('lily', ['#4f8f33', '#43802c', '#5ca03c', '#f1e6f0'], 0, 0.7, 0.05),
    CLOUD: ('cloud', ['#ffffff', '#f3f6fa', '#e6ecf3', '#d6dfea'], [0.35, 0.3, 0.25, 0.2], 0.95, 0.02),
    GOLD: ('gold', ['#d4a53c', '#c39530', '#e6ba50', '#a87a22'], 0, 0.35, 0.04),
    MOSS: ('moss', ['#5e9a3a', '#528a32', '#6aa843', '#46782a'], 0, 0.95, 0.08),
    SKIN: ('skin', ['#e9b996', '#e3b08c', '#f0c4a4', '#c99474'], 0, 0.8, 0.02),
}
# materials that are pure aliases for colour purposes
ALIAS = {C.GRASS_CLIFF: C.GRASS, C.GRASS_SLOPE: C.GRASS, C.SNOW_FULL: C.SNOW}

NATURAL = {C.GRASS, C.DIRT, C.PATH, C.STONE, C.CLIFF, C.SNOW, C.SNOW_FULL, C.GRAVEL, C.SAND, C.RIVERBED,
           C.WATER, C.WATER_FALL, C.GRASS_CLIFF, C.GRASS_SLOPE, C.MOUNTAIN_ROCK}


def srgb_to_linear(c):
    c = np.asarray(c, np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def hexc(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float64) / 255.0


def shader_tables():
    """Arrays for the voxel shader: palette[256] (linear rgb), emission[256], roughness[64], jitter[64]."""
    pal = np.zeros((256, 3), np.float32)
    em = np.zeros(256, np.float32)
    rough = np.full(64, 0.9, np.float32)
    jit = np.full(64, 0.06, np.float32)
    for m, (name, cols, e, r, j) in MATERIALS.items():
        for v in range(4):
            pal[(m << 2) | v] = srgb_to_linear(hexc(cols[v]))
            em[(m << 2) | v] = e[v] if isinstance(e, list) else e
        rough[m] = r
        jit[m] = j
    return pal, em, rough, jit


def mesher_tables():
    """solid/occluder/collide by encoded value (for the greedy mesher)."""
    solid = np.zeros(256, np.bool_)
    occ = np.zeros(256, np.bool_)
    water = np.zeros(256, np.bool_)
    for v in range(4, 255):
        m = v >> 2
        if m not in MATERIALS:
            continue
        if m in (C.WATER, C.WATER_FALL):
            water[v] = True
            continue
        solid[v] = True
        occ[v] = True
    return dict(solid=solid, occluder=occ, collide=solid.copy(), water=water,
                top=np.zeros(256, np.int64), side=np.zeros(256, np.int64), bottom=np.zeros(256, np.int64),
                emis=np.zeros(256, np.float32))


# ------------------------------------------------------------------ numba helpers
@njit(cache=True, inline='always')
def ihash(x, y, z, s):
    h = (x * 374761393 + y * 668265263 + z * 1440662683 + s * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = (h ^ (h >> 16)) & 0xFFFFFFFF
    return h


@njit(cache=True, inline='always')
def hfrac(x, y, z, s):
    return (ihash(x, y, z, s) & 0xFFFF) / 65536.0


@njit(cache=True)
def vnoise3(x, y, z, cell, s):
    """Smooth value noise on integer voxel coords with lattice spacing `cell` (in voxels)."""
    fx = x / cell
    fy = y / cell
    fz = z / cell
    ix = int(np.floor(fx))
    iy = int(np.floor(fy))
    iz = int(np.floor(fz))
    tx = fx - ix
    ty = fy - iy
    tz = fz - iz
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    tz = tz * tz * (3 - 2 * tz)
    c000 = hfrac(ix, iy, iz, s)
    c100 = hfrac(ix + 1, iy, iz, s)
    c010 = hfrac(ix, iy + 1, iz, s)
    c110 = hfrac(ix + 1, iy + 1, iz, s)
    c001 = hfrac(ix, iy, iz + 1, s)
    c101 = hfrac(ix + 1, iy, iz + 1, s)
    c011 = hfrac(ix, iy + 1, iz + 1, s)
    c111 = hfrac(ix + 1, iy + 1, iz + 1, s)
    a = c000 + (c100 - c000) * tx
    b = c010 + (c110 - c010) * tx
    c = c001 + (c101 - c001) * tx
    d = c011 + (c111 - c011) * tx
    e = a + (b - a) * ty
    f = c + (d - c) * ty
    return e + (f - e) * tz


@njit(cache=True, inline='always')
def cells(m, vs):
    """number of voxels that make up `m` metres (at least 1)."""
    n = int(m / vs + 0.5)
    return n if n > 0 else 1


@njit(cache=True)
def brick_block(x, y, z, vs):
    """(row, block) index of a running-bond ashlar course at voxel coords."""
    rh = cells(0.25, vs)
    bl = cells(0.375, vs)
    row = y // rh if y >= 0 else -((-y - 1) // rh) - 1
    along = x + z + (row & 1) * (bl // 2 + 1)
    blk = along // bl if along >= 0 else -((-along - 1) // bl) - 1
    return row, blk


@njit(cache=True)
def cobble_cell(x, y, z, vs):
    c = cells(0.25, vs)
    row = (y // c) if y >= 0 else -((-y - 1) // c) - 1
    along = x + z + (row & 1) * (c // 2)
    a = along // c if along >= 0 else -((-along - 1) // c) - 1
    return row, a, along - a * c, y - row * c


@njit(cache=True)
def paint_value(m, x, y, z, vs, top_exposed, detail):
    """Variant choice for material m at global voxel coords (x, y, z). Returns encoded byte.
    vs sets the pattern scale; detail=False drops single-voxel speckles (coarse LODs merge better)."""
    if m == 255:
        return 255
    if m == C.GRASS_CLIFF or m == C.GRASS_SLOPE:
        m = C.GRASS
    if m == C.SNOW_FULL:
        m = C.SNOW
    var = 0
    cell2 = cells(0.25, vs)
    if m == C.GRASS:
        n = vnoise3(x, 0, z, cells(5.0, vs), 11) * 0.7 + vnoise3(x, 0, z, cells(1.2, vs), 12) * 0.3
        if n < 0.42:
            var = 1
        elif n < 0.62:
            var = 0
        else:
            var = 2
        if detail and top_exposed and hfrac(x, y, z, 13) < 0.008:
            var = 3
    elif m == C.SAND or m == C.RIVERBED or m == C.PATH:
        n = vnoise3(x, y, z, cells(1.5, vs), 23) * 0.6 + vnoise3(x, y, z, cells(0.5, vs), 24) * 0.4
        var = 0 if n < 0.42 else (1 if n < 0.6 else 2)
        if detail and hfrac(x, y, z, 22) < 0.015:
            var = 3
    elif m == C.DIRT or m == C.GRAVEL:
        if detail:
            h = ihash(x // cell2, y // cell2, z // cell2, 21)
            var = h % 3
            if hfrac(x, y, z, 22) < 0.015:
                var = 3
        else:
            n = vnoise3(x, y, z, cells(1.5, vs), 25)
            var = 0 if n < 0.42 else (1 if n < 0.6 else 2)
    elif m == C.STONE or m == C.CLIFF or m == C.MOUNTAIN_ROCK:
        sh = cells(0.75, vs)
        band = ihash(0, y // sh, 0, 31) % 3
        n = vnoise3(x, y, z, cells(2.0, vs), 32)
        var = (band + (1 if n > 0.6 else 0)) % 3
        if detail and hfrac(x // cell2, y, z // cell2, 33) < 0.06:
            var = 3
    elif m == C.SNOW:
        n = vnoise3(x, y, z, cells(3.0, vs), 41)
        var = 0 if n < 0.45 else (1 if n < 0.75 else 2)
        if detail and hfrac(x, y, z, 42) < 0.02:
            var = 3
    elif m == C.BRICKS or m == C.BRICKS_DARK:
        row, blk = brick_block(x, y, z, vs)
        var = ihash(row, blk, 0, 51) % 3
        if hfrac(row, blk, 1, 52) < 0.06:
            var = 3
    elif m == C.COBBLE or m == C.COBBLE_MOSSY:
        row, a, la, ly = cobble_cell(x, y, z, vs)
        var = ihash(row, a, 0, 61) % 3
        if la == 0 and ly == 0 and hfrac(row, a, 2, 62) < 0.45:
            var = 3 if m == C.COBBLE else 1
        if m == C.COBBLE_MOSSY and top_exposed and vnoise3(x, y, z, cells(1.0, vs), 63) > 0.45:
            var = 3
    elif m == C.PLANKS or m == C.PLANKS_DARK or m == C.CRATE:
        bh = cells(0.25, vs)
        board = y // bh if y >= 0 else -((-y - 1) // bh) - 1
        seg = (x + z) // cells(1.5, vs)
        var = ihash(board, seg, 0, 71) % 3
        if detail and hfrac(x, y, z, 72) < 0.015:
            var = 3
    elif m == C.TIMBER:
        n = vnoise3(x, y * 3, z, cells(0.75, vs), 81)
        var = 0 if n < 0.4 else (1 if n < 0.7 else 2)
        if detail and hfrac(x, y, z, 82) < 0.02:
            var = 3
    elif m == C.PLASTER:
        n = vnoise3(x, y, z, cells(1.5, vs), 91)
        var = 0 if n < 0.55 else (1 if n < 0.8 else 2)
        if hfrac(x // cell2, y // cell2, z // cell2, 92) < 0.02:
            var = 3
    elif m == C.SLATE:
        sw = cells(0.25, vs)
        row = y
        along = x + z + (row & 1) * (sw // 2)
        var = ihash(row, along // sw, 0, 101) % 3
    elif m == C.LOG:
        var = ihash(x, 0, z, 111) % 3
        if top_exposed:
            var = 3
    elif m == C.PINE_LEAVES or m == C.PINE_LEAVES_LIGHT or m == C.OAK_LEAVES:
        n = vnoise3(x, y, z, cells(0.6, vs), 123)
        var = 0 if n < 0.4 else (1 if n < 0.62 else 2)
        if m == C.OAK_LEAVES:
            if top_exposed and vnoise3(x, y, z, cells(0.4, vs), 124) > 0.5:
                var = 3
        elif detail and hfrac(x, y, z, 122) < 0.04:
            var = 3
    elif m == C.HAY:
        var = ihash(x, y // cells(0.25, vs), z // 2, 131) % 3
        if (y // cells(0.25, vs)) % 3 == 1 and hfrac(x, y, z, 132) < 0.5:
            var = 3
    elif m == C.BOULDER or m == C.BOULDER_MOSS or m == C.PEBBLE:
        c = cells(0.25, vs)
        var = ihash(x // c, y // c, z // c, 141) % 2
        if m == C.BOULDER_MOSS and top_exposed and vnoise3(x, y, z, cells(0.75, vs), 142) > 0.42:
            var = 2 + (ihash(x, y, z, 143) & 1)
        elif detail and m != C.BOULDER_MOSS and hfrac(x, y, z, 144) < 0.06:
            var = 2 + (ihash(x, y, z, 145) & 1) * (1 if m != C.BOULDER else 1)
            if m == C.BOULDER and var == 3:
                var = 2
    elif m == C.WATER or m == C.WATER_FALL:
        var = 0
    elif m == CLOUD:
        var = 3 if y <= 1 else (2 if y <= 2 else (1 if y <= 4 else 0))
        if top_exposed:
            var = 0
    elif m == C.WINDOW_LIT:
        var = ihash(x // 2, y // 2, z // 2, 151) % 3
    else:
        var = ihash(x // cell2, y // cell2, z // cell2, 161) % 3
    return (m << 2) | var


@njit(cache=True)
def paint_grid(ids, ox, oy, oz, vs, detail):
    """Convert a grid of material ids into encoded colour voxels. (ox, oy, oz): global voxel offset."""
    X, Y, Z = ids.shape
    out = np.zeros(ids.shape, np.uint8)
    for i in range(X):
        for k in range(Z):
            for j in range(Y):
                m = ids[i, j, k]
                if m == 0:
                    continue
                top = (j + 1 >= Y) or ids[i, j + 1, k] == 0 or ids[i, j + 1, k] == C.WATER
                out[i, j, k] = paint_value(m, ox + i, oy + j, oz + k, vs, top, detail)
    return out


VS_INDEX = {1 / 32: 0, 1 / 16: 1, 1 / 8: 2, 1 / 4: 3, 1 / 2: 4, 1.0: 5, 2.0: 6, 4.0: 7}


def vs_index(vs):
    return int(round(np.log2(vs) + 5))
