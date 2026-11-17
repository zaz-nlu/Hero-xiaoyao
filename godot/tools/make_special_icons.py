"""Paints the three special-action icons (jianyi / probe / foresight) in the same
round gold-ringed style as the AI martial icon pack.

The gold ring is copied from icon_martial_taiji.png; the inside is drawn here
with PIL at 4x supersampling. Run from the godot/ directory:
    python3 tools/make_special_icons.py
"""
import math
from PIL import Image, ImageDraw, ImageFilter

GAME = "assets/ai/game/"
SIZE = 96
SS = 4
CENTER = SIZE * SS / 2.0
INNER_R = 34.5 * SS  # inside of the gold ring


def radial_disc(inner, outer):
    """A filled disc with a radial gradient, as an RGBA image at supersampled size."""
    big = SIZE * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    px = img.load()
    for y in range(big):
        for x in range(big):
            d = math.hypot(x - CENTER, y - CENTER) / INNER_R
            if d <= 1.0:
                t = min(1.0, d)
                px[x, y] = tuple(
                    int(inner[i] + (outer[i] - inner[i]) * t) for i in range(3)
                ) + (255,)
    return img


def glow(layer, color, radius):
    blurred = layer.filter(ImageFilter.GaussianBlur(radius * SS))
    tinted = Image.new("RGBA", layer.size, color + (0,))
    tinted.putalpha(blurred.getchannel("A"))
    return tinted


def paint_jianyi():
    # a lone sword standing in violet light, with sword-qi arcs
    img = radial_disc((92, 52, 150), (26, 14, 52))
    d = ImageDraw.Draw(img)
    c = CENTER
    for k, a in enumerate((70, 50, 34)):
        r = (16 + k * 6) * SS
        d.arc([c - r, c - r, c + r, c + r], 200 + k * 20, 340 - k * 10,
              fill=(190, 150, 255, a * 3), width=2 * SS)
    shape = Image.new("RGBA", img.size, (0, 0, 0, 0))
    s = ImageDraw.Draw(shape)
    blade = [(c, c - 30 * SS), (c + 4.5 * SS, c - 22 * SS), (c + 4.5 * SS, c + 8 * SS),
             (c - 4.5 * SS, c + 8 * SS), (c - 4.5 * SS, c - 22 * SS)]
    s.polygon(blade, fill=(236, 226, 255, 255))
    s.line([(c, c - 28 * SS), (c, c + 7 * SS)], fill=(160, 130, 230, 255), width=SS)
    s.rectangle([c - 12 * SS, c + 8 * SS, c + 12 * SS, c + 11.5 * SS], fill=(214, 170, 80, 255))
    s.rectangle([c - 2.2 * SS, c + 11.5 * SS, c + 2.2 * SS, c + 24 * SS], fill=(120, 76, 150, 255))
    s.ellipse([c - 4 * SS, c + 23 * SS, c + 4 * SS, c + 28 * SS], fill=(214, 170, 80, 255))
    img = Image.alpha_composite(img, glow(shape, (200, 160, 255), 5))
    img = Image.alpha_composite(img, shape)
    return img


def paint_probe():
    # a sword tip pricking a target ring: "feel out the weak point"
    img = radial_disc((120, 90, 40), (38, 26, 12))
    d = ImageDraw.Draw(img)
    c = CENTER
    cx, cy = c + 4 * SS, c + 6 * SS
    for r, a in ((22, 160), (14, 220)):
        d.ellipse([cx - r * SS, cy - r * SS, cx + r * SS, cy + r * SS],
                  outline=(255, 214, 120, a), width=2 * SS)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        d.line([(cx + dx * 18 * SS, cy + dy * 18 * SS), (cx + dx * 27 * SS, cy + dy * 27 * SS)],
               fill=(255, 214, 120, 230), width=2 * SS)
    d.ellipse([cx - 3 * SS, cy - 3 * SS, cx + 3 * SS, cy + 3 * SS], fill=(255, 120, 90, 255))
    shape = Image.new("RGBA", img.size, (0, 0, 0, 0))
    s = ImageDraw.Draw(shape)
    # blade coming in from the upper left, point at the target centre
    ang = math.radians(-40)
    ux, uy = math.cos(ang), math.sin(ang)
    px_, py_ = -uy, ux
    tip = (cx, cy)
    def pt(along, side):
        return (cx - ux * along * SS + px_ * side * SS, cy - uy * along * SS + py_ * side * SS)
    s.polygon([tip, pt(26, 4), pt(26, -4)], fill=(240, 240, 248, 255))
    s.line([pt(2, 0), pt(26, 0)], fill=(170, 176, 196, 255), width=SS)
    s.polygon([pt(26, 11), pt(29, 11), pt(29, -11), pt(26, -11)], fill=(220, 172, 70, 255))
    s.line([pt(29, 0), pt(40, 0)], fill=(130, 84, 40, 255), width=int(3.4 * SS))
    img = Image.alpha_composite(img, glow(shape, (255, 220, 140), 3))
    img = Image.alpha_composite(img, shape)
    return img


def paint_foresight():
    # an open eye with a bright iris: "read the enemy ahead of time"
    img = radial_disc((40, 120, 130), (10, 34, 44))
    d = ImageDraw.Draw(img)
    c = CENTER
    w, h = 27 * SS, 15 * SS
    top = [(c - w + (2 * w) * i / 40, c - h * math.sin(math.pi * i / 40) ** 0.9) for i in range(41)]
    bottom = [(c + w - (2 * w) * i / 40, c + h * math.sin(math.pi * i / 40) ** 0.9) for i in range(41)]
    d.polygon(top + bottom, fill=(236, 252, 250, 255))
    r = 11 * SS
    d.ellipse([c - r, c - r, c + r, c + r], fill=(48, 168, 178, 255))
    d.ellipse([c - 7 * SS, c - 7 * SS, c + 7 * SS, c + 7 * SS], fill=(14, 50, 64, 255))
    d.ellipse([c - 4.5 * SS, c - 6.5 * SS, c - 0.5 * SS, c - 2.5 * SS], fill=(255, 255, 255, 255))
    d.line(top, fill=(20, 70, 84, 255), width=int(1.6 * SS))
    d.line(bottom, fill=(20, 70, 84, 255), width=int(1.6 * SS))
    # sparkles above: a glimpse of what is coming
    for sx, sy, sr in ((c + 20 * SS, c - 24 * SS, 3.2), (c - 22 * SS, c - 22 * SS, 2.2)):
        pts = []
        for i in range(8):
            rad = sr * SS * (1.0 if i % 2 == 0 else 0.35)
            a = math.pi / 4 * i - math.pi / 2
            pts.append((sx + rad * math.cos(a), sy + rad * math.sin(a)))
        d.polygon(pts, fill=(190, 255, 250, 255))
    return img


def finish(inner_big, name):
    inner = inner_big.resize((SIZE, SIZE), Image.LANCZOS)
    ring_src = Image.open(GAME + "icon_martial_taiji.png").convert("RGBA")
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ip, rp, op = inner.load(), ring_src.load(), out.load()
    cen = (SIZE - 1) / 2.0
    r_in = INNER_R / SS
    for y in range(SIZE):
        for x in range(SIZE):
            dist = math.hypot(x - cen, y - cen)
            if dist >= r_in - 1.0:
                # ring and everything outside it come from the pack, but the 1px seam
                # is a mix so the painted art does not end in a hard edge
                if dist < r_in:
                    t = dist - (r_in - 1.0)
                    a, b = ip[x, y], rp[x, y]
                    op[x, y] = tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(4))
                else:
                    op[x, y] = rp[x, y]
            else:
                op[x, y] = ip[x, y]
    out.save(GAME + name)
    print("wrote", GAME + name)


if __name__ == "__main__":
    finish(paint_jianyi(), "icon_special_jianyi.png")
    finish(paint_probe(), "icon_special_probe.png")
    finish(paint_foresight(), "icon_special_foresight.png")
