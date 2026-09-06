#!/usr/bin/env python3
"""Renders the LocalTube app icon.

Output: AppIcon-1024.png next to this script (the source of truth that
Scripts/package_app.sh turns into AppIcon.icns with sips + iconutil), plus
AppIcon-preview.png for a quick look at dock / list sizes.

Design: the same mark the WebUI uses (purple→blue gradient tile with a
white play glyph), laid out on Apple's macOS icon grid — an 832 pt rounded
square centred on a 1024 pt canvas with a soft baked-in shadow.

Requires Pillow:  pip3 install pillow && python3 Assets/AppIcon/render_icon.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
SIZE = 1024
SS = 4                     # supersampling factor for clean anti-aliasing
S = SIZE * SS

# Brand colours (see WebUI/src/index.css --accent / --blue)
PURPLE = (168, 111, 240)   # top-left
BLUE   = (88, 162, 248)    # bottom-right
WHITE  = (255, 255, 255)


def rounded_mask(size, box, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def diagonal_gradient(size, c0, c1):
    """c0 at top-left → c1 at bottom-right."""
    g = Image.linear_gradient("L")              # 256×256, black top → white bottom
    g = g.rotate(45, resample=Image.BICUBIC, expand=True)
    w = g.size[0]
    crop = int(w * 0.2929 / 2)                  # trim the transparent rotation corners
    g = g.crop((crop, crop, w - crop, w - crop)).resize((size, size), Image.BICUBIC)
    a = Image.new("RGB", (size, size), c0)
    b = Image.new("RGB", (size, size), c1)
    return Image.composite(b, a, g)


def render():
    px = lambda v: int(round(v * SS))
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # ── Tile geometry (Apple grid: 832 pt tile, 96 pt margin) ──────────
    margin = px(96)
    tile = (margin, margin, S - margin, S - margin)
    radius = px(186)                            # ≈ 22.4 % of the tile edge

    # ── Drop shadow ────────────────────────────────────────────────────
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(tile, radius=radius, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(px(22)))
    shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -px(12)))  # push down
    canvas.alpha_composite(shadow)

    # ── Gradient tile ──────────────────────────────────────────────────
    grad = diagonal_gradient(S, PURPLE, BLUE).convert("RGBA")
    tile_mask = rounded_mask(S, tile, radius)
    tile_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tile_layer.paste(grad, (0, 0), tile_mask)
    canvas.alpha_composite(tile_layer)

    # ── Top sheen: white fading out over the upper part of the tile ────
    sheen_alpha = Image.linear_gradient("L").rotate(180).resize((S, S), Image.BICUBIC)  # white top → black bottom
    sheen_alpha = sheen_alpha.point(lambda v: int(v * 0.16))                             # max 16 % opacity
    sheen_alpha = Image.composite(sheen_alpha, Image.new("L", (S, S), 0), tile_mask)
    sheen = Image.new("RGBA", (S, S), WHITE + (0,))
    sheen.putalpha(sheen_alpha)
    canvas.alpha_composite(sheen)

    # ── Play glyph ─────────────────────────────────────────────────────
    # Optically centred: a triangle's visual centre sits left of its
    # bounding-box centre, so nudge the whole glyph right a little.
    cx, cy = px(512 + 22), px(512)
    h, w = px(400), px(352)
    pts = [(cx - w // 2, cy - h // 2), (cx - w // 2, cy + h // 2), (cx + w // 2, cy)]
    corner = px(30)

    def draw_tri(img, color):
        # A rounded triangle = the inner triangle grown by `corner` in every
        # direction: fill + thick edges + a disc at each vertex. (PIL's
        # joint="curve" leaves a square cap where the polyline closes.)
        d = ImageDraw.Draw(img)
        d.polygon(pts, fill=color)
        for i in range(3):
            d.line([pts[i], pts[(i + 1) % 3]], fill=color, width=corner * 2)
        for (x, y) in pts:
            d.ellipse((x - corner, y - corner, x + corner, y + corner), fill=color)

    glyph_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_tri(glyph_shadow, (20, 10, 60, 90))
    glyph_shadow = glyph_shadow.filter(ImageFilter.GaussianBlur(px(14)))
    glyph_shadow = glyph_shadow.transform(glyph_shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -px(10)))
    canvas.alpha_composite(glyph_shadow)

    glyph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_tri(glyph, WHITE + (255,))
    canvas.alpha_composite(glyph)

    icon = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    icon.save(HERE / "AppIcon-1024.png", optimize=True)
    return icon


def preview(icon):
    """Dock-ish preview on dark and light backgrounds plus small sizes."""
    W, H = 1280, 720
    out = Image.new("RGBA", (W, H), (13, 13, 15, 255))
    ImageDraw.Draw(out).rectangle((W // 2, 0, W, H), fill=(242, 242, 247, 255))
    big = icon.resize((420, 420), Image.LANCZOS)
    out.alpha_composite(big, (110, 90))
    out.alpha_composite(big, (W // 2 + 110, 90))
    x = 160
    for s in (128, 64, 32, 16):
        small = icon.resize((s, s), Image.LANCZOS)
        out.alpha_composite(small, (x, 560 + (128 - s) // 2))
        out.alpha_composite(small, (W // 2 + x, 560 + (128 - s) // 2))
        x += s + 40
    out.convert("RGB").save(HERE / "AppIcon-preview.png", optimize=True)


if __name__ == "__main__":
    preview(render())
    print("wrote", HERE / "AppIcon-1024.png", "and AppIcon-preview.png")
