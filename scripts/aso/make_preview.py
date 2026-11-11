#!/usr/bin/env python3
"""Record and build App Store preview videos (iPhone 6.9", 886x1920) in every store language.

The app's DEBUG `-OpenScreen autoplay` mode drives the real UI through the main features;
this script records the simulator, trims, scales, adds a localized caption per scene and a
silent stereo AAC track (App Store previews require audio).

    python3 scripts/aso/make_preview.py <simulator-udid> [locale ...]
Output: fastlane/previews/<locale>/iphone69_preview.mp4
"""
import json, os, signal, subprocess, sys, tempfile, time
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
COPY = json.loads((ROOT / "scripts/aso/copy.json").read_text())
OUT = ROOT / "fastlane/previews"
TMP = Path(tempfile.mkdtemp(prefix="aso-preview.", dir="/private/tmp"))  # internal disk: simctl can't write the SSD
BUNDLE = "com.blueCode.SimplePenNote"
LANG = {"ko": ("ko", "ko_KR"), "en-US": ("en", "en_US"), "ja": ("ja", "ja_JP"), "zh-Hans": ("zh-Hans", "zh_CN")}
W, H, FPS = 886, 1920, 30

sys.path.insert(0, str(Path(__file__).parent))
from compose import FONTS, font  # noqa: E402


def sh(*args, **kw):
    return subprocess.run(args, check=True, **kw)


def caption_png(locale, idx, path):
    _, head, _ = COPY[locale][idx]
    text = head.replace("\n", " ")
    hspec, _ = FONTS[locale]
    img = Image.new("RGBA", (W, 260), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    size = 54
    while True:
        f = font(hspec, size, 760)
        if d.textlength(text, font=f) <= W - 140 or size <= 30:
            break
        size -= 2
    tw = d.textlength(text, font=f)
    pad_x, box_h = 40, int(size * 1.9)
    x0 = (W - tw) / 2 - pad_x
    y0 = 40
    d.rounded_rectangle([x0, y0, x0 + tw + pad_x * 2, y0 + box_h], radius=box_h // 2, fill=(52, 58, 196, 238))
    d.text((W / 2, y0 + box_h / 2), text, font=f, fill="white", anchor="mm")
    img.save(path)


def record(udid, locale):
    """Record the autoplay run; return the raw file and scene times relative to recording start."""
    lang, region = LANG[locale]
    raw = TMP / f"{locale}.mov"
    subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
    rec = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", str(raw)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)
    t_rec = time.time() - 1.5
    app = subprocess.Popen(["xcrun", "simctl", "launch", "--console-pty", udid, BUNDLE, "-DemoMode", "1", "-DemoPro",
                            "-OpenScreen", "autoplay", "-AppleLanguages", f"({lang})", "-AppleLocale", region],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    scenes, first = {}, None
    deadline = time.time() + 45
    while time.time() < deadline:
        line = app.stdout.readline()
        if not line:
            break
        if line.startswith("AUTOPLAY "):
            _, n, rel = line.split()
            if first is None:
                first = time.time() - t_rec      # absolute only for scene 0
            scenes[int(n)] = first + float(rel)
            if 6 in scenes:
                break
    time.sleep(0.4)
    rec.send_signal(signal.SIGINT)
    rec.wait(timeout=60)
    app.kill()
    if 6 not in scenes:
        raise SystemExit(f"{locale}: autoplay did not finish: {scenes}")
    return raw, scenes


def build(raw, scenes, locale):
    caps = []
    for i in range(6):
        p = TMP / f"{locale}_cap{i}.png"
        caption_png(locale, i, p)
        caps.append(p)
    start = scenes[0] - 0.8
    duration = min(29.5, scenes[6] + 0.3 - start)
    times = [scenes[i] - start for i in range(7)]
    inputs = ["-ss", f"{start:.2f}", "-t", f"{duration:.2f}", "-i", str(raw)]
    for p in caps:
        inputs += ["-i", str(p)]
    inputs += ["-f", "lavfi", "-t", f"{duration:.2f}", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"]
    chain = [f"[0:v]tpad=stop_mode=clone:stop_duration=6,fps={FPS},scale={W}:{H}:flags=lanczos,setsar=1,format=yuv420p[v0]"]
    last = "v0"
    for i in range(6):
        t0, t1 = (0.0 if i == 0 else times[i] + 0.1), (times[i + 1] if i < 5 else duration)
        chain.append(f"[{last}][{i + 1}:v]overlay=0:150:enable='between(t,{t0:.2f},{t1 - 0.05:.2f})'[v{i + 1}]")
        last = f"v{i + 1}"
    out = OUT / locale / "iphone69_preview.mp4"
    out.parent.mkdir(parents=True, exist_ok=True)
    audio_idx = len(caps) + 1
    sh("ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(chain),
       "-map", f"[{last}]", "-map", f"{audio_idx}:a", "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
       "-preset", "slow", "-b:v", "10M", "-maxrate", "12M", "-bufsize", "20M", "-r", str(FPS),
       "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", "-shortest", "-movflags", "+faststart", str(out))
    return out, duration, times


def main():
    udid = sys.argv[1]
    locales = sys.argv[2:] or list(LANG)
    for locale in locales:
        raw, scenes = record(udid, locale)
        out, duration, times = build(raw, scenes, locale)
        print(locale, out, f"{duration:.1f}s", [round(t, 1) for t in times])


if __name__ == "__main__":
    main()
