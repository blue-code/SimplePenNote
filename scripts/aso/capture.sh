#!/bin/zsh
# Capture raw App Store screenshots in every store language.
#   scripts/aso/capture.sh iphone|ipad
# Output: fastlane/screenshots_source/<locale>/<device>_<NN>_<cut>.png
set -euo pipefail
cd "$(dirname "$0")/../.."
DEVICE=$1
APP=build/dd/Build/Products/Debug-iphonesimulator/SimplePenNote.app
BUNDLE=com.blueCode.SimplePenNote
SHOT_TMP=$(mktemp -d /private/tmp/aso-shot.XXXX)  # internal disk
if [[ $DEVICE == iphone ]]; then
  NAME="SimplePenNote-ASO-iPhone69"; TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max
  CUTS=(01:canvas 02:selectionPreset 03:exportSelection 04:snippets 05:templates 06:paywall)
else
  NAME="SimplePenNote-ASO-iPad13"; TYPE=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB
  CUTS=(01:sidebar 02:selectionPreset 03:exportSelection 04:snippets 05:templates 06:paywall)
fi
UDID=$(xcrun simctl list devices available | grep "$NAME (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)
if [[ -z $UDID ]]; then UDID=$(xcrun simctl create "$NAME" "$TYPE" com.apple.CoreSimulator.SimRuntime.iOS-27-0); fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$UDID" "$APP"
typeset -A LANGMAP=(ko "ko ko_KR" en-US "en en_US" ja "ja ja_JP" zh-Hans "zh-Hans zh_CN")
for LOC in ko en-US ja zh-Hans; do
  set -- ${=LANGMAP[$LOC]}
  mkdir -p fastlane/screenshots_source/$LOC
  if [[ $DEVICE == ipad ]]; then
    # The iPad status bar prints the date in the system language; switch it per locale.
    xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array $1
    xcrun simctl spawn "$UDID" defaults write -g AppleLocale $2
    xcrun simctl shutdown "$UDID"; xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b >/dev/null
    xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
  fi
  for CUT in $CUTS; do
    N=${CUT%%:*}; SCREEN=${CUT#*:}
    xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
    PRO=(-DemoPro); [[ $SCREEN == paywall ]] && PRO=()
    xcrun simctl launch "$UDID" $BUNDLE -DemoMode 1 $PRO -OpenScreen $SCREEN -AppleLanguages "($1)" -AppleLocale $2 >/dev/null
    [[ $SCREEN == paywall ]] && sleep 6 || sleep 4
    OUTFILE="$PWD/fastlane/screenshots_source/$LOC/${DEVICE}_${N}_${SCREEN}.png"
    for TRY in 1 2 3; do
      # CoreSimulator can't write to the external volume (times out); shoot to TMPDIR, then copy.
      timeout 45 xcrun simctl io "$UDID" screenshot --type=png "$SHOT_TMP/shot.png" >/dev/null 2>&1 && cp "$SHOT_TMP/shot.png" "$OUTFILE" && break
      echo "  retry $TRY ($LOC $SCREEN)"
      if ! xcrun simctl list devices booted | grep -q "$UDID"; then
        xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b >/dev/null
        xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
      fi
      xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
      xcrun simctl launch "$UDID" $BUNDLE -DemoMode 1 $PRO -OpenScreen $SCREEN -AppleLanguages "($1)" -AppleLocale $2 >/dev/null
      sleep 6
    done
    [[ -f $OUTFILE ]] || { echo "FAILED $OUTFILE"; exit 1; }
    echo "$LOC $N $SCREEN"
  done
done
xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
echo "UDID=$UDID"
