#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$TASK_ROOT"
TASK_APP="$TASK_ROOT/.build/AppearanceChecks.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources" "$TASK_ROOT/.build/module-cache"
xcrun swiftc -O -gnone -swift-version 5 -module-cache-path "$TASK_ROOT/.build/module-cache" \
  Sources/LyricGlass/RaindropScene.swift Sources/LyricGlass/Appearance.swift Sources/LyricGlass/LyricsTypography.swift Sources/LyricGlass/PlaybackControls.swift Sources/LyricGlass/LyricsPanel.swift Sources/LyricGlass/IslandPanel.swift \
  Sources/LyricGlass/AppearancePreview.swift Sources/LyricGlass/SettingsControls.swift Sources/LyricGlass/QuickMenu.swift Sources/LyricGlass/SettingsState.swift Sources/LyricGlass/AppearanceSettings.swift \
  Tests/AppearanceChecks/main.swift -framework AppKit -framework CoreText -framework SceneKit \
  -o "$TASK_APP/Contents/MacOS/AppearanceChecks"
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>ai.yufan.lyricglass.appearance-checks</string>
<key>CFBundleExecutable</key><string>AppearanceChecks</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
ditto Resources/Fonts "$TASK_APP/Contents/Resources/Fonts"
ditto Resources/Avatar "$TASK_APP/Contents/Resources/Avatar"
codesign --force --sign - "$TASK_APP"
"$TASK_APP/Contents/MacOS/AppearanceChecks"
