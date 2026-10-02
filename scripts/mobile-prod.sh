#!/usr/bin/env bash
# Builds the iOS app in Release (production API: api.strava.echimine.fr) and installs it
# on a physical iPhone connected by cable or on the same Wi-Fi network.
#
#   pnpm mobile:prod                 # first connected iPhone
#   pnpm mobile:prod "iPhone de X"   # a device by name or UDID
#
# Signing uses DEVELOPMENT_TEAM from apps/mobile/Config/Secrets.xcconfig (automatic signing,
# profiles created by Xcode with -allowProvisioningUpdates).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOBILE="$ROOT/apps/mobile"
# Outside the repo: Tailwind's source scan (apps/admin) loops on SwiftPM checkout symlinks.
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/StravaClone-prod"
BUNDLE_ID="fr.echimine.stravaclone"
WANTED="${1:-}"

devices_json="$(mktemp)"
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null

DEVICE="$(node -e '
  const [file, wanted] = process.argv.slice(1);
  const devices = JSON.parse(require("fs").readFileSync(file, "utf8")).result.devices
    .filter((d) => d.hardwareProperties?.platform === "iOS" && d.hardwareProperties?.reality === "physical")
    .filter((d) => d.connectionProperties?.tunnelState !== "unavailable");
  const match = wanted
    ? devices.find((d) => d.deviceProperties?.name === wanted || d.hardwareProperties?.udid === wanted || d.identifier === wanted)
    : devices[0];
  if (match) console.log(`${match.identifier}\t${match.deviceProperties?.name ?? ""}`);
' "$devices_json" "$WANTED")"

if [[ -z "$DEVICE" ]]; then
  echo "No connected iPhone found${WANTED:+ matching \"$WANTED\"}. Plug it in, unlock it and trust this Mac." >&2
  exit 1
fi
DEVICE_ID="${DEVICE%%$'\t'*}"
echo "▶ Target: ${DEVICE#*$'\t'} ($DEVICE_ID)"

echo "▶ Generating the Xcode project"
(cd "$MOBILE" && xcodegen generate --quiet)

echo "▶ Building Release"
xcodebuild build \
  -project "$MOBILE/StravaClone.xcodeproj" \
  -scheme StravaClone \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  -skipPackagePluginValidation \
  -allowProvisioningUpdates \
  -quiet

APP="$DERIVED/Build/Products/Release-iphoneos/StravaClone.app"

echo "▶ Installing"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "▶ Launching"
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID" \
  || echo "Installed. Unlock the iPhone and open the app (first launch may require trusting the developer in Settings > General > VPN & Device Management)."
