#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
TASK_ICONSET="$TASK_ROOT/.build/AppIcon.iconset"
mkdir -p "$TASK_ICONSET"
# Preserve the selected D/Mist artwork; supply the standard macOS icon sizes.
for TASK_SIZE in 16 32 128 256 512; do
    sips -z "$TASK_SIZE" "$TASK_SIZE" "$TASK_ROOT/Resources/AppIcon.png" \
        --out "$TASK_ICONSET/icon_${TASK_SIZE}x${TASK_SIZE}.png" >/dev/null
    TASK_RETINA_SIZE=$(( TASK_SIZE * 2 ))
    sips -z "$TASK_RETINA_SIZE" "$TASK_RETINA_SIZE" "$TASK_ROOT/Resources/AppIcon.png" \
        --out "$TASK_ICONSET/icon_${TASK_SIZE}x${TASK_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$TASK_ICONSET" -o "$TASK_ROOT/Resources/AppIcon.icns"
printf 'Built app icon: %s\n' "$TASK_ROOT/Resources/AppIcon.icns"
