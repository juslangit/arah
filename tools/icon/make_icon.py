"""Draws Arah's launcher icon: Mochi (the rice-cake mascot, see lib/ui/mochi.dart)
on a soft pink tile. Writes every Android mipmap size, and with a second
argument the web app's icons (python3 make_icon.py <android res dir> <web dir>)."""
from PIL import Image, ImageDraw
import os, sys

PINK = (255, 214, 226)
S = 1024


def bez(p0, p1, p2, p3, n=40):
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t * t
        d = t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def mochi(d, ox, oy, k):
    """Mochi on a 100×100 grid, scaled by k and moved to (ox, oy) — same shapes as mochi.dart."""
    P = lambda x, y: (ox + x * k, oy + y * k)
    d.ellipse([*P(20, 89), *P(80, 99)], fill=(240, 170, 192))
    body = (bez(P(14, 66), P(14, 42), P(30, 22), P(50, 22)) + bez(P(50, 22), P(70, 22), P(86, 42), P(86, 66))
            + bez(P(86, 66), P(86, 81), P(70, 90), P(50, 90)) + bez(P(50, 90), P(30, 90), P(14, 81), P(14, 66)))
    d.polygon(body, fill=(255, 255, 255), outline=(243, 201, 216), width=max(2, int(2.5 * k)))
    d.polygon(bez(P(50, 22), P(48, 13), P(54, 7), P(63, 8)) + bez(P(63, 8), P(62, 16), P(57, 21), P(50, 22)), fill=(124, 203, 142))
    d.polygon(bez(P(50, 22), P(51, 15), P(47, 10), P(41, 10)) + bez(P(41, 10), P(41, 16), P(44, 20), P(50, 22)), fill=(154, 219, 169))
    ink = (90, 62, 75)
    for cx in (37, 63):
        d.ellipse([*P(cx - 4.2, 60 - 4.2), *P(cx + 4.2, 60 + 4.2)], fill=ink)
        d.ellipse([*P(cx + 1.5 - 1.3, 58.5 - 1.3), *P(cx + 1.5 + 1.3, 58.5 + 1.3)], fill=(255, 255, 255))
    for cx in (29, 71):
        d.ellipse([*P(cx - 6, 69 - 3.6), *P(cx + 6, 69 + 3.6)], fill=(255, 179, 201))
    d.line(bez(P(45, 67), P(48, 70.5), P(52, 70.5), P(55, 67), 20), fill=ink, width=max(2, int(2.6 * k)), joint='curve')


def draw(size, square=False):
    """square: full-bleed, for iPhone home screens and maskable icons (the OS rounds them)."""
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=0 if square else 230, fill=PINK)
    # Mochi inside the maskable safe zone (centre 80%).
    mochi(d, 152, 120, 7.2)
    return im.resize((size, size), Image.LANCZOS)


root = sys.argv[1]
for folder, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    draw(px).save(os.path.join(root, f'mipmap-{folder}', 'ic_launcher.png'))
draw(512).save(os.path.join(os.path.dirname(__file__), 'arah-icon-512.png'))
if len(sys.argv) > 2:
    web = sys.argv[2]
    draw(32).save(os.path.join(web, 'favicon.png'))
    draw(180, square=True).convert('RGB').save(os.path.join(web, 'icons', 'apple-touch-icon.png'))
    for px in (192, 512):
        draw(px).save(os.path.join(web, 'icons', f'Icon-{px}.png'))
        draw(px, square=True).save(os.path.join(web, 'icons', f'Icon-maskable-{px}.png'))
print('ok')
