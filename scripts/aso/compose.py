#!/usr/bin/env python3
"""Compose connected-panorama App Store screenshots.

One wide "paper" canvas (ruled lines + a flowing ink stroke + doodles) is drawn across all
cuts and sliced, so the carousel reads as one continuous sheet. Each slice gets a chip,
headline and subtitle, then the framed device capture.

    python3 scripts/aso/compose.py            # all locales, iphone + ipad
Input : fastlane/screenshots_source/<locale>/<device>_<NN>_<cut>.png
Output: fastlane/screenshots/<locale>/<device>_<NN>_<cut>.png
"""
import glob, json, math, os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "fastlane/screenshots_source"
OUT = ROOT / "fastlane/screenshots"
COPY = json.loads((ROOT / "scripts/aso/copy.json").read_text())

PAPER = (248, 244, 235)
RULE = (226, 219, 204)
INK = (52, 58, 196)          # indigo, the app's accent
INK_SOFT = (52, 58, 196, 46)
TEXT = (28, 28, 34)
SUB = (92, 92, 104)
RED = (226, 64, 70)
GREEN = (36, 150, 96)

PINGFANG = glob.glob("/System/Library/AssetsV2/com_apple_MobileAsset_Font8/*/AssetData/PingFang.ttc")[0]
FONTS = {  # (path, index) for headline / body
    "ko": (("/System/Library/Fonts/AppleSDGothicNeo.ttc", 6), ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 2)),
    "en-US": (("/System/Library/Fonts/SFNS.ttf", 0), ("/System/Library/Fonts/SFNS.ttf", 0)),
    "ja": (("/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc", 0), ("/System/Library/Fonts/ヒラギノ角ゴシック W5.ttc", 0)),
    "zh-Hans": ((PINGFANG, 11), (PINGFANG, 7)),
}
DEVICES = {
    "iphone": dict(W=1320, H=2868, card_w=0.80, card_top=0.255, radius=0.11, head=118, sub=50, chip=40),
    "ipad": dict(W=2064, H=2752, card_w=0.76, card_top=0.275, radius=0.035, head=128, sub=54, chip=44),
}


def font(spec, size, bold_variation=None):
    path, index = spec
    f = ImageFont.truetype(path, size, index=index)
    if path.endswith("SFNS.ttf"):
        # Axes are Width, Optical Size, GRAD, Weight — set them all so width stays 100.
        f.set_variation_by_axes([100, min(96, max(17, size / 3)), 400, bold_variation or 700])
    return f


def wave_points(x0, x1, base, amp, period, phase=0.0, step=6):
    return [(x, base + amp * math.sin((x / period) * 2 * math.pi + phase)
             + amp * 0.35 * math.sin((x / (period * 0.37)) * 2 * math.pi)) for x in range(int(x0), int(x1), step)]


def draw_panorama(n, W, H):
    """The continuous background shared by every slice."""
    master = Image.new("RGBA", (W * n, H), PAPER + (255,))
    d = ImageDraw.Draw(master, "RGBA")
    gap = int(H * 0.034)
    for y in range(int(H * 0.06), H, gap):
        d.line([(0, y), (W * n, y)], fill=RULE + (255,), width=3)
    # Margin line like a notebook, running the whole sheet.
    d.line([(0, int(H * 0.045)), (W * n, int(H * 0.045))], fill=(232, 160, 160, 255), width=4)
    # One flowing ink ribbon behind all cards — the "connected" thread.
    pts = wave_points(-40, W * n + 40, H * 0.62, H * 0.07, W * 1.45, 0.6)
    d.line(pts, fill=INK_SOFT, width=int(W * 0.09), joint="curve")
    # Doodles straddling slice borders (same master, so they line up across shots).
    for i in range(1, n):
        x = W * i
        if i % 2:
            star(d, (x, int(H * 0.145)), int(W * 0.035), RED)
        else:
            check(d, (x - 40, int(H * 0.13)), int(W * 0.06), GREEN)
    return master


def star(d, c, r, color):
    pts = []
    for k in range(6):
        t = (k * 2 % 5) / 5 * 2 * math.pi - math.pi / 2
        pts.append((c[0] + r * math.cos(t), c[1] + r * math.sin(t)))
    d.line(pts, fill=color + (255,), width=9, joint="curve")


def check(d, o, s, color):
    d.line([(o[0], o[1] + s * 0.5), (o[0] + s * 0.35, o[1] + s * 0.85), (o[0] + s, o[1])],
           fill=color + (255,), width=11, joint="curve")


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def wrap_check(draw, text, f, max_w):
    for line in text.split("\n"):
        if draw.textlength(line, font=f) > max_w:
            return False
    return True


def compose_slice(bg, shot, locale, idx, spec):
    W, H = spec["W"], spec["H"]
    chip, head, sub = COPY[locale][idx]
    hfont_spec, bfont_spec = FONTS[locale]
    canvas = bg.copy()
    d = ImageDraw.Draw(canvas, "RGBA")
    margin = int(W * 0.085)

    # Chip
    cf = font(bfont_spec, spec["chip"], 600)
    tw = d.textlength(chip, font=cf)
    cx, cy = margin, int(H * 0.05)
    ch = int(spec["chip"] * 1.9)
    d.rounded_rectangle([cx, cy, cx + tw + ch, cy + ch], radius=ch // 2, fill=INK + (255,))
    d.text((cx + ch / 2, cy + ch / 2), chip, font=cf, fill=(255, 255, 255), anchor="lm")

    # Headline (shrink to fit)
    size = spec["head"]
    while True:
        hf = font(hfont_spec, size, 800)
        if wrap_check(d, head, hf, W - margin * 2) or size < 60:
            break
        size -= 4
    y = cy + ch + int(H * 0.022)
    lh = int(size * 1.18)
    for line in head.split("\n"):
        d.text((margin, y), line, font=hf, fill=TEXT)
        y += lh
    bf = font(bfont_spec, spec["sub"], 500)
    d.text((margin, y + int(H * 0.008)), sub, font=bf, fill=SUB)

    # Device card
    card_w = int(W * spec["card_w"])
    scale = card_w / shot.width
    card = shot.resize((card_w, int(shot.height * scale)), Image.LANCZOS)
    radius = int(card_w * spec["radius"])
    card = rounded(card, radius)
    bezel = int(card_w * 0.018)
    frame = Image.new("RGBA", (card.width + bezel * 2, card.height + bezel * 2), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle([0, 0, frame.width - 1, frame.height - 1],
                                             radius=radius + bezel, fill=(24, 24, 28, 255))
    frame.alpha_composite(card, (bezel, bezel))
    top = int(H * spec["card_top"])
    left = (W - frame.width) // 2
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([left + 10, top + 34, left + frame.width - 10, top + frame.height + 30],
                                              radius=radius + bezel, fill=(40, 34, 20, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(frame, (left, top))
    return canvas.convert("RGB")


def main():
    for device, spec in DEVICES.items():
        for locale in COPY:
            shots = sorted((SRC / locale).glob(f"{device}_*.png"))
            if not shots:
                continue
            n = len(shots)
            master = draw_panorama(n, spec["W"], spec["H"])
            (OUT / locale).mkdir(parents=True, exist_ok=True)
            for i, path in enumerate(shots):
                bg = master.crop((i * spec["W"], 0, (i + 1) * spec["W"], spec["H"]))
                out = compose_slice(bg, Image.open(path).convert("RGB"), locale, i, spec)
                out.save(OUT / locale / path.name, optimize=True)
            print(device, locale, n)


if __name__ == "__main__":
    main()
