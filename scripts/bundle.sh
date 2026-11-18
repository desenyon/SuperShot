#!/bin/zsh
set -euo pipefail
export EDITOR=vim VISUAL=vim GIT_EDITOR=vim
cd "${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
output="${BUNDLE_OUTPUT_DIR:-$PWD/dist}"
swift build -c "$configuration"
bin_path=$(swift build -c "$configuration" --show-bin-path)
mkdir -p "$output"
stage=$(mktemp -d "$output/.bundle.XXXXXX")
app="$stage/SuperShot.app"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/AppIcon.iconset
cp "$bin_path/SuperShot" "$app/Contents/MacOS/SuperShot"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SuperShotBuildConfiguration string $configuration" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SuperShotBuildDate string $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$app/Contents/Info.plist"
"$bin_path/SuperShot" --render-app-icon "$PWD/.build/AppIcon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" .build/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" .build/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$app"
else
    keychain="$PWD/.local-signing/SuperShot.keychain-db"
    if [[ ! -f "$keychain" ]]; then
        print -u2 'No stable signing identity. Run scripts/setup-signing.sh or set SIGNING_IDENTITY.'
        exit 1
    fi
    security unlock-keychain -p "$(cat .local-signing/password)" "$keychain"
    codesign --force --sign 'SuperShot Local Development' --keychain "$keychain" --timestamp=none "$app"
fi
codesign --verify --deep --strict --verbose=2 "$app"
destination="$output/SuperShot.app"
if pgrep -f -x "$destination/Contents/MacOS/SuperShot" >/dev/null; then
    print -u2 "SuperShot is running from $destination. Quit it first, or set BUNDLE_OUTPUT_DIR to stage an update."
    exit 1
fi
previous="$stage/Previous.app"
if [[ -d "$destination" ]]; then
    mv "$destination" "$previous"
fi
if ! mv "$app" "$destination"; then
    [[ ! -d "$previous" ]] || mv "$previous" "$destination"
    exit 1
fi
print "Built and signed $destination"
