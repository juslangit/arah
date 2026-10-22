"""Draws Arah's launcher icon: a white navigation arrow on hutan green,
Writes every Android mipmap size."""
from PIL import Image, ImageDraw
import os, sys

GREEN = (11, 110, 79)
DARK = (7, 82, 58)
S = 1024

def draw(size):
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=230, fill=GREEN)
    # A soft darker disc behind the arrow.
    d.ellipse([170, 170, 854, 854], fill=DARK)
    # Navigation arrow, pointing up and to the right like "go this way".
    arrow = [(512, 250), (730, 770), (512, 660), (294, 770)]
    shadow = [(x + 14, y + 18) for x, y in arrow]
    d.polygon(shadow, fill=(0, 0, 0, 70))
    d.polygon(arrow, fill=(255, 255, 255))
    return im.resize((size, size), Image.LANCZOS)

root = sys.argv[1]
for folder, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    draw(px).save(os.path.join(root, f'mipmap-{folder}', 'ic_launcher.png'))
draw(512).save(os.path.join(os.path.dirname(__file__), 'arah-icon-512.png'))
print('ok')
