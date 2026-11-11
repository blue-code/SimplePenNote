#!/usr/bin/env python3
"""Fill exported .xcloc XLIFFs from scripts/l10n/translations.json and verify placeholders.

    xcodebuild -exportLocalizations ... -localizationPath DIR -exportLanguage en -exportLanguage ja -exportLanguage zh-Hans
    python3 scripts/l10n/fill_xliff.py DIR
    xcodebuild -importLocalizations -localizationPath DIR/<lang>.xcloc ...
"""
import json, re, sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "urn:oasis:names:tc:xliff:document:1.2"
ET.register_namespace("", NS)
LANGS = {"en": 0, "ja": 1, "zh-Hans": 2}
T = json.loads((Path(__file__).parent / "translations.json").read_text())
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|%)")

def specs(s):
    # Compare by type in order; positional and plain forms are equivalent.
    return sorted(re.sub(r"\d+\$", "", m) for m in SPEC.findall(s))

root = Path(sys.argv[1]); errors = []
for lang, idx in LANGS.items():
    path = root / f"{lang}.xcloc" / "Localized Contents" / f"{lang}.xliff"
    tree = ET.parse(path)
    for unit in tree.getroot().iter(f"{{{NS}}}trans-unit"):
        key, source = unit.get("id"), unit.find(f"{{{NS}}}source").text or ""
        if key not in T:
            errors.append(f"missing translation: {key!r}"); continue
        text = T[key][idx]
        if specs(text) != specs(source):
            errors.append(f"{lang} placeholder mismatch: {key!r} -> {text!r}")
        target = unit.find(f"{{{NS}}}target")
        if target is None:
            target = ET.SubElement(unit, f"{{{NS}}}target")
        target.text = text
        target.set("state", "translated")
    tree.write(path, encoding="UTF-8", xml_declaration=True)
unused = set(T) - {u.get("id") for u in ET.parse(root / "en.xcloc/Localized Contents/en.xliff").getroot().iter(f"{{{NS}}}trans-unit")}
print("unused keys:", sorted(unused))
print("\n".join(sorted(set(errors))) or "all units translated, placeholders match")
sys.exit(1 if errors else 0)
