"""HUD icons drawn with PIL (supersampled), saved as PNG."""
import math
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 512  # draw size
OUT = 128


def canvas():
    return Image.new('RGBA', (S, S), (0, 0, 0, 0))


def save(im, path, size=OUT):
    im = im.resize((size, size), Image.LANCZOS)
    im.save(path)


def poly(d, pts, fill, outline=None, width=0):
    d.polygon([(x * S, y * S) for x, y in pts], fill=fill, outline=outline, width=width)


def outline_shape(im, color=(20, 14, 10, 255), grow=10):
    """add a dark outline around the alpha shape"""
    a = im.split()[3]
    big = a.filter(ImageFilter.MaxFilter(grow * 2 + 1))
    base = Image.new('RGBA', im.size, color)
    base.putalpha(big)
    base.alpha_composite(im)
    return base


def rot(pts, ang, cx=0.5, cy=0.5):
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def sword():
    im = canvas()
    d = ImageDraw.Draw(im)
    a = math.radians(-45)
    blade = rot([(0.47, 0.10), (0.53, 0.10), (0.535, 0.62), (0.465, 0.62)], a)
    edge = rot([(0.5, 0.06), (0.535, 0.12), (0.535, 0.62), (0.5, 0.62)], a)
    tip = rot([(0.465, 0.12), (0.5, 0.05), (0.535, 0.12)], a)
    poly(d, blade, (205, 210, 218, 255))
    poly(d, edge, (238, 241, 245, 255))
    poly(d, tip, (225, 229, 235, 255))
    fuller = rot([(0.495, 0.16), (0.505, 0.16), (0.505, 0.58), (0.495, 0.58)], a)
    poly(d, fuller, (150, 158, 170, 255))
    guard = rot([(0.36, 0.62), (0.64, 0.62), (0.64, 0.665), (0.36, 0.665)], a)
    poly(d, guard, (176, 128, 52, 255))
    grip = rot([(0.475, 0.665), (0.525, 0.665), (0.525, 0.83), (0.475, 0.83)], a)
    poly(d, grip, (98, 60, 32, 255))
    for k in range(4):
        y = 0.68 + k * 0.04
        poly(d, rot([(0.475, y), (0.525, y + 0.012), (0.525, y + 0.022), (0.475, y + 0.01)], a), (70, 42, 22, 255))
    pom = rot([(0.46, 0.83), (0.54, 0.83), (0.54, 0.88), (0.46, 0.88)], a)
    poly(d, pom, (190, 145, 65, 255))
    return outline_shape(im)


def potion():
    im = canvas()
    d = ImageDraw.Draw(im)
    d.ellipse([0.22 * S, 0.34 * S, 0.78 * S, 0.9 * S], fill=(210, 230, 245, 120))
    d.rectangle([0.42 * S, 0.18 * S, 0.58 * S, 0.40 * S], fill=(210, 230, 245, 140))
    d.ellipse([0.26 * S, 0.46 * S, 0.74 * S, 0.88 * S], fill=(36, 92, 220, 255))
    d.chord([0.26 * S, 0.46 * S, 0.74 * S, 0.88 * S], 180, 360, fill=(70, 140, 250, 255))
    d.ellipse([0.30 * S, 0.50 * S, 0.70 * S, 0.62 * S], fill=(110, 175, 255, 255))
    d.rectangle([0.40 * S, 0.10 * S, 0.60 * S, 0.20 * S], fill=(150, 104, 62, 255))
    d.rectangle([0.40 * S, 0.10 * S, 0.60 * S, 0.13 * S], fill=(178, 130, 80, 255))
    d.ellipse([0.33 * S, 0.40 * S, 0.43 * S, 0.62 * S], fill=(255, 255, 255, 170))
    d.ellipse([0.62 * S, 0.66 * S, 0.68 * S, 0.74 * S], fill=(255, 255, 255, 120))
    return outline_shape(im)


def sprint():
    im = canvas()
    d = ImageDraw.Draw(im)
    W = (240, 240, 236, 255)
    d.ellipse([0.56 * S, 0.12 * S, 0.70 * S, 0.26 * S], fill=W)
    lw = int(0.075 * S)
    def ln(p, q):
        d.line([(p[0] * S, p[1] * S), (q[0] * S, q[1] * S)], fill=W, width=lw)
        r = lw / 2
        for pt in (p, q):
            d.ellipse([pt[0] * S - r, pt[1] * S - r, pt[0] * S + r, pt[1] * S + r], fill=W)
    ln((0.60, 0.30), (0.50, 0.55))      # torso
    ln((0.60, 0.32), (0.74, 0.44)); ln((0.74, 0.44), (0.82, 0.38))   # front arm
    ln((0.57, 0.34), (0.44, 0.40)); ln((0.44, 0.40), (0.38, 0.50))   # back arm
    ln((0.50, 0.55), (0.66, 0.66)); ln((0.66, 0.66), (0.64, 0.84))   # front leg
    ln((0.50, 0.55), (0.40, 0.70)); ln((0.40, 0.70), (0.24, 0.72))   # back leg
    for (y, x0, x1) in ((0.36, 0.10, 0.32), (0.50, 0.06, 0.30), (0.64, 0.12, 0.30)):
        d.line([(x0 * S, y * S), (x1 * S, y * S)], fill=(240, 240, 236, 200), width=int(0.035 * S))
    return outline_shape(im, grow=8)


def glider():
    im = canvas()
    d = ImageDraw.Draw(im)
    # bat-wing glider canopy
    pts = [(0.06, 0.52), (0.18, 0.36), (0.34, 0.26), (0.5, 0.22), (0.66, 0.26), (0.82, 0.36), (0.94, 0.52),
           (0.82, 0.47), (0.74, 0.53), (0.62, 0.46), (0.5, 0.52), (0.38, 0.46), (0.26, 0.53), (0.18, 0.47)]
    poly(d, pts, (176, 106, 62, 255))
    for i, (x, y) in enumerate(pts[:7]):
        d.line([(0.5 * S, 0.22 * S), (x * S, y * S)], fill=(110, 62, 34, 255), width=int(0.018 * S))
    poly(d, [(0.34, 0.26), (0.5, 0.22), (0.66, 0.26), (0.5, 0.30)], (205, 140, 90, 255))
    d.line([(0.5 * S, 0.22 * S), (0.5 * S, 0.78 * S)], fill=(90, 56, 30, 255), width=int(0.03 * S))
    d.line([(0.38 * S, 0.46 * S), (0.5 * S, 0.78 * S)], fill=(150, 120, 90, 200), width=int(0.01 * S))
    d.line([(0.62 * S, 0.46 * S), (0.5 * S, 0.78 * S)], fill=(150, 120, 90, 200), width=int(0.01 * S))
    d.rectangle([0.44 * S, 0.76 * S, 0.56 * S, 0.80 * S], fill=(90, 56, 30, 255))
    return outline_shape(im)


def meat():
    im = canvas()
    d = ImageDraw.Draw(im)
    d.ellipse([0.14 * S, 0.24 * S, 0.86 * S, 0.80 * S], fill=(232, 220, 200, 255))
    d.ellipse([0.18 * S, 0.27 * S, 0.82 * S, 0.76 * S], fill=(160, 46, 40, 255))
    d.ellipse([0.24 * S, 0.31 * S, 0.70 * S, 0.66 * S], fill=(186, 62, 52, 255))
    for (x, y, r) in ((0.40, 0.45, 0.05), (0.56, 0.56, 0.04), (0.33, 0.58, 0.03), (0.62, 0.40, 0.035)):
        d.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=(225, 160, 150, 255))
    d.ellipse([0.62 * S, 0.54 * S, 0.80 * S, 0.70 * S], fill=(245, 240, 230, 255))
    d.ellipse([0.67 * S, 0.58 * S, 0.75 * S, 0.66 * S], fill=(205, 190, 170, 255))
    return outline_shape(im)


def heart():
    im = canvas()
    d = ImageDraw.Draw(im)
    pts = []
    for i in range(200):
        t = i / 200 * 2 * math.pi
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((0.5 + x / 40, 0.5 + y / 40))
    poly(d, pts, (222, 38, 46, 255))
    d.ellipse([0.28 * S, 0.30 * S, 0.40 * S, 0.42 * S], fill=(255, 150, 150, 220))
    return outline_shape(im, grow=6)


def mana():
    im = canvas()
    d = ImageDraw.Draw(im)
    poly(d, [(0.5, 0.08), (0.80, 0.42), (0.5, 0.92), (0.20, 0.42)], (40, 110, 230, 255))
    poly(d, [(0.5, 0.08), (0.80, 0.42), (0.5, 0.42)], (110, 180, 255, 255))
    poly(d, [(0.20, 0.42), (0.5, 0.42), (0.5, 0.92)], (30, 80, 190, 255))
    poly(d, [(0.36, 0.30), (0.46, 0.18), (0.46, 0.34)], (220, 240, 255, 230))
    return outline_shape(im, grow=6)


def bolt():
    im = canvas()
    d = ImageDraw.Draw(im)
    poly(d, [(0.58, 0.04), (0.22, 0.56), (0.48, 0.56), (0.36, 0.96), (0.80, 0.38), (0.54, 0.38), (0.70, 0.04)], (246, 196, 40, 255))
    poly(d, [(0.58, 0.04), (0.40, 0.32), (0.54, 0.32), (0.70, 0.04)], (255, 230, 120, 255))
    return outline_shape(im, grow=6)


def floppy():
    im = canvas()
    d = ImageDraw.Draw(im)
    Wc = (230, 226, 214, 255)
    d.rounded_rectangle([0.14 * S, 0.14 * S, 0.86 * S, 0.86 * S], radius=int(0.06 * S), outline=Wc, width=int(0.06 * S))
    d.rectangle([0.30 * S, 0.14 * S, 0.66 * S, 0.38 * S], outline=Wc, width=int(0.05 * S))
    d.rectangle([0.54 * S, 0.19 * S, 0.61 * S, 0.33 * S], fill=Wc)
    d.rounded_rectangle([0.28 * S, 0.54 * S, 0.72 * S, 0.86 * S], radius=int(0.03 * S), outline=Wc, width=int(0.05 * S))
    return im


def book():
    im = canvas()
    d = ImageDraw.Draw(im)
    Wc = (236, 230, 214, 255)
    poly(d, [(0.08, 0.22), (0.48, 0.30), (0.48, 0.84), (0.08, 0.76)], Wc)
    poly(d, [(0.92, 0.22), (0.52, 0.30), (0.52, 0.84), (0.92, 0.76)], Wc)
    poly(d, [(0.06, 0.74), (0.5, 0.84), (0.94, 0.74), (0.94, 0.80), (0.5, 0.90), (0.06, 0.80)], (190, 150, 90, 255))
    for k in range(4):
        y = 0.40 + k * 0.09
        d.line([(0.16 * S, (y - 0.02) * S), (0.42 * S, (y + 0.03) * S)], fill=(150, 140, 120, 255), width=int(0.02 * S))
        d.line([(0.84 * S, (y - 0.02) * S), (0.58 * S, (y + 0.03) * S)], fill=(150, 140, 120, 255), width=int(0.02 * S))
    return im


def sun():
    im = canvas()
    d = ImageDraw.Draw(im)
    for i in range(12):
        a = i * math.pi / 6
        p1 = (0.5 + math.cos(a) * 0.30, 0.5 + math.sin(a) * 0.30)
        p2 = (0.5 + math.cos(a) * 0.46, 0.5 + math.sin(a) * 0.46)
        d.line([(p1[0] * S, p1[1] * S), (p2[0] * S, p2[1] * S)], fill=(255, 196, 40, 255), width=int(0.06 * S))
    d.ellipse([0.26 * S, 0.26 * S, 0.74 * S, 0.74 * S], fill=(255, 200, 50, 255))
    d.ellipse([0.32 * S, 0.30 * S, 0.56 * S, 0.50 * S], fill=(255, 235, 150, 255))
    return im


def house_icon():
    im = canvas()
    d = ImageDraw.Draw(im)
    Wc = (240, 236, 224, 255)
    poly(d, [(0.12, 0.50), (0.5, 0.14), (0.88, 0.50), (0.78, 0.50), (0.78, 0.86), (0.22, 0.86), (0.22, 0.50)], (60, 52, 44, 255))
    poly(d, [(0.18, 0.50), (0.5, 0.20), (0.82, 0.50), (0.74, 0.50), (0.74, 0.82), (0.26, 0.82), (0.26, 0.50)], Wc)
    d.rectangle([0.43 * S, 0.60 * S, 0.57 * S, 0.82 * S], fill=(120, 80, 50, 255))
    return im


def arrow():
    im = canvas()
    d = ImageDraw.Draw(im)
    poly(d, [(0.5, 0.06), (0.86, 0.90), (0.5, 0.70), (0.14, 0.90)], (250, 248, 240, 255))
    poly(d, [(0.5, 0.06), (0.5, 0.70), (0.14, 0.90)], (215, 210, 200, 255))
    return outline_shape(im, grow=12)


def build(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for name, fn in (('sword', sword), ('potion', potion), ('sprint', sprint), ('glider', glider), ('meat', meat),
                     ('heart', heart), ('mana', mana), ('bolt', bolt), ('floppy', floppy), ('book', book), ('sun', sun),
                     ('house', house_icon), ('arrow', arrow)):
        save(fn(), os.path.join(out_dir, f'icon_{name}.png'))


if __name__ == '__main__':
    build(sys.argv[1])
