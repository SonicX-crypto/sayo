#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
RELEASE_DIR="$PROJECT_DIR/dist/releases"
STAGING_DIR="$(mktemp -d /private/tmp/sayo-release.XXXXXX)"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
if [[ -n "${SAYO_RELEASE_SIGNING_IDENTITY:-}" ]]; then
    SAYO_SIGNING_IDENTITY="$SAYO_RELEASE_SIGNING_IDENTITY" ./build-app.sh
else
    SAYO_ALLOW_ADHOC_SIGNING=1 SAYO_FORCE_ADHOC_SIGNING=1 ./build-app.sh
fi

mkdir -p "$RELEASE_DIR"
ZIP_PATH="$RELEASE_DIR/Sayo-$VERSION-macOS-arm64.zip"
DMG_PATH="$RELEASE_DIR/Sayo-$VERSION-macOS-arm64.dmg"

ditto -c -k --sequesterRsrc --keepParent "dist/Sayo.app" "$ZIP_PATH"
ditto "dist/Sayo.app" "$STAGING_DIR/Sayo.app"
cp "$PROJECT_DIR/scripts/setup-dependencies.sh" "$STAGING_DIR/Install Sayo Components.command"
cp "$PROJECT_DIR/scripts/download-model.sh" "$STAGING_DIR/download-model.sh"
cp "$PROJECT_DIR/INSTALL.md" "$STAGING_DIR/Installation Guide.md"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -quiet -volname "Sayo" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

(
    cd "$RELEASE_DIR"
    shasum -a 256 "${ZIP_PATH:t}" "${DMG_PATH:t}" > "Sayo-$VERSION-SHA256SUMS.txt"
)

echo "$ZIP_PATH"
echo "$DMG_PATH"
echo "$RELEASE_DIR/Sayo-$VERSION-SHA256SUMS.txt"
