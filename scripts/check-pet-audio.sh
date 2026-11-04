#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$TASK_ROOT"
mkdir -p .build
xcrun clang -std=c11 -Wall -Wextra -Wno-unused-parameter -ISources/PetAudio/include \
  Sources/PetAudio/PetAudio.c Tests/PetAudioChecks/main.c -framework CoreAudio -o .build/pet-audio-checks
.build/pet-audio-checks
