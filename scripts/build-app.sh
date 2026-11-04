#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$TASK_ROOT"
if [[ ! -s Resources/AppIcon.icns ]]; then
    printf 'Missing Resources/AppIcon.icns; run scripts/build-app-icon.sh first.\n' >&2
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/module-cache"
TASK_SWIFT_OPTIONS=(--disable-sandbox -debug-info-format none --cache-path .build/cache --config-path .build/config --security-path .build/security)
if [[ "${1:-}" == "--universal" && $# == 1 ]]; then
    TASK_SWIFT_OPTIONS+=(--arch arm64 --arch x86_64)
elif (( $# > 0 )); then
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 2
fi
swift build -c release --product LyricGlass "${TASK_SWIFT_OPTIONS[@]}"
TASK_BIN_DIR="$(swift build -c release "${TASK_SWIFT_OPTIONS[@]}" --show-bin-path)"
TASK_APP="$TASK_ROOT/dist/LyricGlass.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_BIN_DIR/LyricGlass" "$TASK_APP/Contents/MacOS/LyricGlass"
cp Resources/Info.plist "$TASK_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$TASK_APP/Contents/Resources/AppIcon.icns"
ditto Resources/Fonts "$TASK_APP/Contents/Resources/Fonts"
ditto Resources/Avatar "$TASK_APP/Contents/Resources/Avatar"
codesign --force --sign - --identifier ai.yufan.lyricglass.prototype --entitlements Resources/entitlements.plist "$TASK_APP"
codesign --verify --strict "$TASK_APP"
printf 'Architectures: %s\n' "$(lipo -archs "$TASK_APP/Contents/MacOS/LyricGlass")"
printf '\nBuilt: %s\n' "$TASK_APP"
