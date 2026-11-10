#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
validation_dir="$(mktemp -d "${TMPDIR:-/tmp}/SimplePenNoteModel.XXXXXX")"
trap 'rm -rf "$validation_dir"' EXIT
app_dir="$validation_dir/ModelRegression.app"
mkdir -p "$app_dir/Contents/MacOS"
# PencilKit requires a bundle identifier, even for a command-line regression harness.
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.blueCode.SimplePenNote.ModelRegression</string>
<key>CFBundleExecutable</key><string>ModelRegression</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Compile the exact production model with same-file checks for its private merge logic.
cat "$repo_dir/SimplePenNote/NoteModel.swift" "$repo_dir/scripts/NoteModelRegression.swift" > "$validation_dir/Combined.swift"
xcrun swiftc -parse-as-library -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  "$validation_dir/Combined.swift" -o "$app_dir/Contents/MacOS/ModelRegression"
"$app_dir/Contents/MacOS/ModelRegression"
