#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-dependencies.py
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) echo "Usage: scripts/build.sh [debug|release]" >&2; exit 2 ;; esac
swift build -c "$configuration" --disable-automatic-resolution
binary_dir="$(swift build -c "$configuration" --show-bin-path --disable-automatic-resolution)"
build_stamp="$(date -u +%Y%m%d%H%M%S)-$$"
app="build/.Terminal2-$build_stamp.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Terminal2" "$app/Contents/MacOS/Terminal2"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift Resources/AppIcon.svg build/Terminal2.iconset
iconutil -c icns build/Terminal2.iconset -o "$app/Contents/Resources/AppIcon.icns"
cp Resources/Mark.svg "$app/Contents/Resources/Mark.svg"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp .build/checkouts/SwiftTerm/LICENSE "$app/Contents/Resources/SwiftTerm-LICENSE"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date -u +%Y%m%d%H%M%S)" "$app/Contents/Info.plist"
for bundle in "$binary_dir/"*.bundle; do
    [ -d "$bundle" ] || continue
    ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
# Preserve the old executable inode so a rebuild does not invalidate running sessions.
if [ -d build/Terminal2.app ]; then
    mkdir -p build/history
    mv build/Terminal2.app "build/history/Terminal2-$build_stamp.app"
fi
mv "$app" build/Terminal2.app
echo "$PWD/build/Terminal2.app"
