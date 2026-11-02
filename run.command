#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
"$TASK_ROOT/scripts/build-app.sh"
open "$TASK_ROOT/dist/LyricGlass.app" --args "$@"
