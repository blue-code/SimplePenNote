#!/usr/bin/env python3
"""Generate single-line handwriting strokes for DEBUG demo notes (App Store captures).

Each text is rendered with a handwriting font, skeletonized to a one-pixel centerline,
traced into polylines and written to SimplePenNote/DemoInk.swift (compiled only in DEBUG).
The app then rebuilds them as PencilKit pen strokes, so screenshots show real-looking ink
in every store language instead of placeholder squiggles.

    python3 scripts/generate_demo_ink.py [--preview DIR]
"""
import base64, glob, json, struct, sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
from skimage.morphology import skeletonize

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "SimplePenNote" / "DemoInk.swift"
ASSETS = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/*/AssetData/"

FONTS = {
    "ko": (glob.glob(ASSETS + "NanumScript.ttc")[0], 1),      # Nanum Pen Script
    "en": ("/System/Library/Fonts/Noteworthy.ttc", 0),        # Noteworthy Light
    "ja": (glob.glob(ASSETS + "Klee.ttc")[0], 1),             # Klee Medium
    "zh": (glob.glob(ASSETS + "Hanzipen.ttc")[0], 0),         # HanziPen SC Regular
}
RENDER_PX = 220          # glyph render size; output units are 1/1000 of this
UNITS = 1000

TEXTS = json.loads((ROOT / "scripts" / "demo_ink_texts.json").read_text())


def trace(skel):
    """Split a skeleton into polylines broken at endpoints and junctions."""
    ys, xs = np.nonzero(skel)
    pts = set(zip(ys.tolist(), xs.tolist()))
    nb = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

    def neighbors(p):
        return [(p[0] + dy, p[1] + dx) for dy, dx in nb if (p[0] + dy, p[1] + dx) in pts]

    deg = {p: len(neighbors(p)) for p in pts}
    nodes = {p for p, d in deg.items() if d != 2}
    used = set()
    paths = []

    def walk(start, nxt):
        path = [start, nxt]
        used.add(frozenset((start, nxt)))
        prev, cur = start, nxt
        while cur not in nodes:
            cand = [n for n in neighbors(cur) if n != prev and frozenset((cur, n)) not in used]
            if not cand:
                break
            prev, cur = cur, cand[0]
            used.add(frozenset((prev, cur)))
            path.append(cur)
        return path

    for n in nodes:
        for m in neighbors(n):
            if frozenset((n, m)) not in used:
                paths.append(walk(n, m))
    for p in pts:  # closed loops with no nodes
        for m in neighbors(p):
            if frozenset((p, m)) not in used:
                nodes.add(p)
                paths.append(walk(p, m))
                nodes.discard(p)
    return paths


def rdp(points, eps):
    if len(points) < 3:
        return points
    a, b = np.array(points[0]), np.array(points[-1])
    ab = b - a
    norm = np.hypot(*ab)
    if norm < 1e-6:
        # Closed loop: split at the point farthest from the start so it isn't collapsed.
        i = int(np.argmax([np.hypot(*(np.array(p) - a)) for p in points]))
        return rdp(points[: i + 1], eps)[:-1] + rdp(points[i:], eps)
    d = [abs(ab[0] * (p[1] - a[1]) - ab[1] * (p[0] - a[0])) / norm for p in points[1:-1]]
    i = int(np.argmax(d)) + 1
    if d[i - 1] > eps:
        return rdp(points[: i + 1], eps)[:-1] + rdp(points[i:], eps)
    return [points[0], points[-1]]


def smooth(path):
    arr = np.array(path, dtype=float)
    if len(arr) < 5:
        return arr
    k = np.ones(5) / 5
    out = arr.copy()
    for c in range(2):
        padded = np.pad(arr[:, c], 2, mode="edge")
        out[:, c] = np.convolve(padded, k, mode="valid")
    out[0], out[-1] = arr[0], arr[-1]
    return out


def strokes_for(text, font_path, index):
    font = ImageFont.truetype(font_path, RENDER_PX, index=index)
    l, t, r, b = font.getbbox(text)
    pad = 20
    img = Image.new("L", (r - l + pad * 2, RENDER_PX * 2), 0)
    ImageDraw.Draw(img).text((pad - l, pad), text, font=font, fill=255)
    ink = np.array(img) > 110
    ink = ndimage.binary_closing(ink, iterations=1)
    dist = ndimage.distance_transform_edt(ink)
    skel = skeletonize(ink)
    width = float(np.median(dist[skel])) * 2 if skel.any() else 4
    # Baseline reference: ascent from the font so lines of mixed text align.
    ascent, _ = font.getmetrics()
    base_y = pad + ascent
    strokes = []
    for path in trace(skel):
        pts = smooth([(x, y) for y, x in path])
        length = np.sum(np.hypot(*np.diff(pts, axis=0).T)) if len(pts) > 1 else 0
        if length < width * 0.9:
            continue
        simp = rdp([tuple(p) for p in pts], 0.7)
        strokes.append([((x - pad) * UNITS / RENDER_PX, (y - base_y) * UNITS / RENDER_PX) for x, y in simp])
    strokes.sort(key=lambda s: min(p[0] for p in s))
    adv = font.getlength(text) * UNITS / RENDER_PX
    return strokes, width * UNITS / RENDER_PX, adv


def encode(strokes):
    """[count][n, x0,y0, x1,y1 ...]... as little-endian Int16, base64."""
    buf = bytearray(struct.pack("<h", len(strokes)))
    for s in strokes:
        buf += struct.pack("<h", len(s))
        for x, y in s:
            buf += struct.pack("<hh", int(round(x)), int(round(y)))
    return base64.b64encode(bytes(buf)).decode()


def preview(locale, key, strokes, width, outdir):
    scale = 0.12
    xs = [p[0] for s in strokes for p in s]; ys = [p[1] for s in strokes for p in s]
    w, h = int((max(xs) - min(xs)) * scale) + 40, int((max(ys) - min(ys)) * scale) + 40
    img = Image.new("RGB", (w, h), "white"); d = ImageDraw.Draw(img)
    ox, oy = min(xs), min(ys)
    for s in strokes:
        d.line([((x - ox) * scale + 20, (y - oy) * scale + 20) for x, y in s], fill="black",
               width=max(1, int(width * scale)), joint="curve")
    outdir.mkdir(parents=True, exist_ok=True)
    img.save(outdir / f"{locale}_{key}.png")


def main():
    prev_dir = Path(sys.argv[sys.argv.index("--preview") + 1]) if "--preview" in sys.argv else None
    lines = ["// Generated by scripts/generate_demo_ink.py — do not edit.",
             "// Handwriting strokes for App Store demo notes. DEBUG only.",
             "#if DEBUG", "import Foundation", "", "enum DemoInk {",
             "    /// locale → text id → (pen width, advance, base64 Int16 strokes) in 1/1000 em.",
             "    static let table: [String: [String: (width: Double, advance: Double, data: String)]] = ["]
    for locale, texts in TEXTS.items():
        font_path, index = FONTS[locale]
        lines.append(f'        "{locale}": [')
        for key, text in texts.items():
            strokes, width, adv = strokes_for(text, font_path, index)
            if prev_dir:
                preview(locale, key, strokes, width, prev_dir)
            lines.append(f'            "{key}": ({width:.1f}, {adv:.1f}, "{encode(strokes)}"),')
        lines.append("        ],")
    lines += ["    ]", "}", "#endif", ""]
    OUT.write_text("\n".join(lines))
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
