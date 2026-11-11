#!/bin/zsh
# Build and run the unit + UI tests on connected physical devices with development signing.
#   scripts/device_test.sh build                      # build-for-testing (generic iOS device)
#   scripts/device_test.sh run <udid> [-only-testing:…]
set -euo pipefail
cd "$(dirname "$0")/.."
KEY=fastlane/AuthKey_33P5W93GJQ.p8
COMMON=(-project SimplePenNote.xcodeproj -scheme SimplePenNote -configuration Debug -derivedDataPath build/device
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration
  -authenticationKeyPath "$PWD/$KEY" -authenticationKeyID 33P5W93GJQ -authenticationKeyIssuerID ed28e2d3-ce1d-4d24-8e58-373132e4b554
  CODE_SIGN_STYLE=Automatic "CODE_SIGN_IDENTITY=Apple Development" PROVISIONING_PROFILE_SPECIFIER= DEVELOPMENT_TEAM=KUDC7C6Z9H)
case $1 in
  build) xcodebuild build-for-testing "${COMMON[@]}" -destination 'generic/platform=iOS' ;;
  run)   UDID=$2; shift 2
         xcodebuild test-without-building "${COMMON[@]}" -destination "id=$UDID" -resultBundlePath "build/device/results-$UDID-$(date +%H%M%S).xcresult" \
           -test-timeouts-enabled YES -maximum-test-execution-time-allowance 180 "$@" ;;
esac
