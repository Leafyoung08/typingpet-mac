#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_EXEC="$PROJECT_DIR/dist/Typing Pet.app/Contents/MacOS/TypingPet"
TEST_BUILD="$PROJECT_DIR/.build/tests"
mkdir -p "$TEST_BUILD"
if [[ ! -x "$APP_EXEC" ]]; then "$PROJECT_DIR/build.sh"; fi
"$APP_EXEC" --self-test
xcrun swiftc -swift-version 5 -O -parse-as-library \
  -vfsoverlay "$PROJECT_DIR/.build/package/swift-vfs-overlay.json" \
  -module-cache-path "$PROJECT_DIR/.build/package/module-cache-arm64" \
  -framework AppKit -framework ImageIO \
  "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/PetImages.swift" \
  "$PROJECT_DIR/Tests/ImageTests.swift" -o "$TEST_BUILD/ImageTests"
"$TEST_BUILD/ImageTests"
