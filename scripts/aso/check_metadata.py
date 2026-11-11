#!/usr/bin/env python3
"""Check App Store metadata per locale: limits, keyword duplicates, and language match.

    python3 scripts/aso/check_metadata.py
"""
import json, re, sys, unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
M = ROOT / "fastlane/metadata"
COPY = json.loads((ROOT / "scripts/aso/copy.json").read_text())
LOCALES = ["ko", "en-US", "ja", "zh-Hans"]
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170,
          "description": 4000, "release_notes": 4000}
HANGUL = re.compile(r"[가-힣]")
KANA = re.compile(r"[぀-ヿ]")
HAN = re.compile(r"[一-鿿]")
LATIN_WORD = re.compile(r"[A-Za-z]{3,}")
ALLOWED_LATIN = {"SimplePenNote", "Pro", "PNG", "PDF", "iPhone", "iPad", "Duo", "iCloud", "Apple", "Face", "Touch",
                 "PencilKit", "SDK", "https", "blue", "code", "github", "legal", "simplepennote", "privacy", "html",
                 "support", "digimaru", "gmail", "com", "Gmail", "Note"}
SIMPLIFIED_ONLY_BAD = set("們這個說時對會來還後點為與發開關體緊簡記筆畫圖題頁設賬戶號數據備錄")  # Traditional forms


def read(loc, key):
    p = M / loc / f"{key}.txt"
    return p.read_text().strip() if p.exists() else ""


def script_errors(loc, text, label):
    errs = []
    if loc == "ko":
        if KANA.search(text): errs.append(f"{label}: kana in Korean")
        if not HANGUL.search(text): errs.append(f"{label}: no Hangul")
    elif loc == "en-US":
        if HANGUL.search(text) or KANA.search(text) or HAN.search(text): errs.append(f"{label}: CJK in English")
    elif loc == "ja":
        if HANGUL.search(text): errs.append(f"{label}: Hangul in Japanese")
        if len(text) > 12 and not KANA.search(text): errs.append(f"{label}: no kana (reads as Chinese?)")
    elif loc == "zh-Hans":
        if HANGUL.search(text) or KANA.search(text): errs.append(f"{label}: Hangul/kana in Chinese")
        bad = sorted(set(text) & SIMPLIFIED_ONLY_BAD)
        if bad: errs.append(f"{label}: traditional characters {bad}")
    if loc != "en-US":
        stray = sorted({w for w in LATIN_WORD.findall(text) if w not in ALLOWED_LATIN})
        if stray: errs.append(f"{label}: untranslated English words {stray}")
    return errs


def norm(word):
    w = word.lower().strip()
    return re.sub(r"(es|s)$", "", w) if re.fullmatch(r"[a-z]+", w) else w


errors = []
for loc in LOCALES:
    fields = {k: read(loc, k) for k in LIMITS}
    for k, limit in LIMITS.items():
        if not fields[k]:
            errors.append(f"[{loc}] {k} missing")
        elif len(fields[k]) > limit:
            errors.append(f"[{loc}] {k} {len(fields[k])}/{limit}")
    kws = [k for k in fields["keywords"].split(",")]
    if any(k != k.strip() or not k for k in kws):
        errors.append(f"[{loc}] keywords have spaces or empty items")
    seen = {}
    for k in kws:
        if norm(k) in seen: errors.append(f"[{loc}] duplicate keyword {k!r}")
        seen[norm(k)] = k
    title = fields["name"] + " " + fields["subtitle"]
    title_words = {norm(w) for w in re.findall(r"[A-Za-z]+", title)} | {norm(w) for w in re.split(r"[\s&·,]+", fields["subtitle"]) if w}
    for k in kws:
        if norm(k) in title_words or (not re.fullmatch(r"[A-Za-z]+", k) and k in title):
            errors.append(f"[{loc}] keyword {k!r} already in name/subtitle")
    for k in ["subtitle", "keywords", "promotional_text", "description", "release_notes"]:
        errors += [f"[{loc}] {e}" for e in script_errors(loc, fields[k], k)]
    for i, (chip, head, sub) in enumerate(COPY[loc]):
        errors += [f"[{loc}] screenshot {i + 1}: {e}" for e in script_errors(loc, chip + head + sub, "copy")]
    print(f"{loc:8} name {len(fields['name'])} | subtitle {len(fields['subtitle'])} | keywords {len(fields['keywords'])} "
          f"| promo {len(fields['promotional_text'])} | desc {len(fields['description'])} | notes {len(fields['release_notes'])}")

# The same text must not appear in two locales (copy-paste mistakes).
for k in ["subtitle", "promotional_text", "description", "release_notes", "keywords"]:
    vals = {loc: read(loc, k) for loc in LOCALES}
    for a in LOCALES:
        for b in LOCALES:
            if a < b and vals[a] and vals[a] == vals[b]:
                errors.append(f"{k} identical in {a} and {b}")

print("\n".join(errors) if errors else "OK — limits, duplicates and language match all pass")
sys.exit(1 if errors else 0)
