#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$TASK_ROOT"
./scripts/build-app.sh --universal
TASK_APP="$TASK_ROOT/dist/LyricGlass.app"
TASK_ARCHS="$(lipo -archs "$TASK_APP/Contents/MacOS/LyricGlass")"
if [[ "$TASK_ARCHS" != *arm64* || "$TASK_ARCHS" != *x86_64* ]]; then
    printf 'Expected a universal app, got: %s\n' "$TASK_ARCHS" >&2
    exit 1
fi
TASK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")"
TASK_NAME="LyricGlass-v${TASK_VERSION}-macos-universal"
ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_ROOT/dist/$TASK_NAME.zip"
TASK_STAGE="$(mktemp -d "$TASK_ROOT/.build/release-stage.XXXXXX")"
trap 'rm -rf -- "$TASK_STAGE"' EXIT
ditto "$TASK_APP" "$TASK_STAGE/LyricGlass.app"
ln -s /Applications "$TASK_STAGE/Applications"
cp docs/首次运行.txt "$TASK_STAGE/首次运行.txt"
hdiutil create -volname LyricGlass -srcfolder "$TASK_STAGE" -format UDZO -ov "$TASK_ROOT/dist/$TASK_NAME.dmg"
cd "$TASK_ROOT/dist"
shasum -a 256 "$TASK_NAME.dmg" "$TASK_NAME.zip" > SHA256SUMS.txt
printf '\nPackaged: %s\n' "$TASK_NAME"
