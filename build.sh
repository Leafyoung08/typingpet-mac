#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/package"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="Typing Pet"
BUNDLE_ID="local.typingpet.mac"
APP_STAGE="$BUILD_DIR/$APP_NAME.app"
APP_PATH="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/TypingPet-macOS.zip"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

# Some Command Line Tools installations expose Dispatch twice, once through
# the SDK and once through this toolchain module map. Hide only the latter
# for these compiler invocations; no installed SDK files are changed.
OVERLAY_PATH="$BUILD_DIR/swift-vfs-overlay.json"
EMPTY_MODULEMAP="$BUILD_DIR/empty.modulemap"
printf '' > "$EMPTY_MODULEMAP"
python3 - "$OVERLAY_PATH" "$EMPTY_MODULEMAP" <<'PY'
import json
import pathlib
import sys
overlay, empty = sys.argv[1:]
duplicate = pathlib.Path('/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap')
roots = []
if duplicate.exists():
    roots.append({'type': 'file', 'name': str(duplicate), 'external-contents': empty})
pathlib.Path(overlay).write_text(json.dumps({'version': 0, 'roots': roots}))
PY

SOURCES=("$PROJECT_DIR"/Sources/*.swift)
if [[ ! -e "${SOURCES[0]}" ]]; then
    printf 'No Swift source files found in %s/Sources.\n' "$PROJECT_DIR" >&2
    exit 1
fi

ARCHS=(arm64 x86_64)
if [[ "${TYPINGPET_NATIVE_ONLY:-0}" == "1" ]]; then
    ARCHS=("$(uname -m)")
fi

BINARIES=()
for arch in "${ARCHS[@]}"; do
    binary="$BUILD_DIR/TypingPet-$arch"
    printf 'Building macOS 13+ executable for %s…\n' "$arch"
    xcrun swiftc -swift-version 5 -O \
        -sdk "$SDK_PATH" -target "$arch-apple-macosx13.0" \
        -vfsoverlay "$OVERLAY_PATH" \
        -module-cache-path "$BUILD_DIR/module-cache-$arch" \
        -framework AppKit -framework SwiftUI -framework ImageIO \
        -framework ServiceManagement -framework ApplicationServices \
        "${SOURCES[@]}" -o "$binary"
    BINARIES+=("$binary")
done

rm -rf "$APP_STAGE"
mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_STAGE/Contents/Info.plist"
ditto "$PROJECT_DIR/Resources/images" "$APP_STAGE/Contents/Resources/images"
cp "$PROJECT_DIR/README-使用说明.md" "$PROJECT_DIR/THIRD-PARTY-NOTICES.md" "$APP_STAGE/Contents/Resources/"

if [[ "${#BINARIES[@]}" == "1" ]]; then
    cp "${BINARIES[0]}" "$APP_STAGE/Contents/MacOS/TypingPet"
else
    xcrun lipo -create "${BINARIES[@]}" -output "$APP_STAGE/Contents/MacOS/TypingPet"
fi
xcrun lipo "$APP_STAGE/Contents/MacOS/TypingPet" -verify_arch "${ARCHS[@]}"

# Use the bundled default pose to make a padded macOS icon.
cat > "$BUILD_DIR/make-icon.swift" <<'SWIFT'
import AppKit

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: source), image.size.width > 0, image.size.height > 0,
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not read the original pet image or create an icon canvas")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill(using: .copy)
let scale = min(880 / image.size.width, 880 / image.size.height)
let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
image.draw(in: NSRect(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2,
                      width: size.width, height: size.height),
           from: .zero, operation: .sourceOver, fraction: 1)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the icon")
}
try png.write(to: destination)
SWIFT

xcrun swiftc -swift-version 5 -sdk "$SDK_PATH" \
    -vfsoverlay "$OVERLAY_PATH" -module-cache-path "$BUILD_DIR/module-cache-icon" \
    -framework AppKit "$BUILD_DIR/make-icon.swift" -o "$BUILD_DIR/make-icon"
"$BUILD_DIR/make-icon" "$PROJECT_DIR/Resources/images/basic.png" "$BUILD_DIR/icon-1024.png"
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double="$((size * 2))"
    sips -z "$double" "$double" "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_STAGE/Contents/Resources/AppIcon.icns"
plutil -lint "$APP_STAGE/Contents/Info.plist"
codesign --force --sign - --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    --timestamp=none "$APP_STAGE"
codesign --verify --deep --strict --verbose=2 "$APP_STAGE"

rm -rf "$APP_PATH"
ditto "$APP_STAGE" "$APP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
cp "$PROJECT_DIR/README-使用说明.md" "$PROJECT_DIR/THIRD-PARTY-NOTICES.md" "$DIST_DIR/"
printf '\nBuilt: %s\nArchive: %s\nArchitectures: ' "$APP_PATH" "$ZIP_PATH"
xcrun lipo -archs "$APP_PATH/Contents/MacOS/TypingPet"
printf 'Signing: local ad-hoc signature; no Developer ID or notarization.\n'
