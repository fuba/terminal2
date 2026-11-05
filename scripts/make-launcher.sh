#!/bin/bash
set -euo pipefail

destination="$HOME/Applications"
launcher="$destination/Terminal2 Launcher.app"
icon="$destination/Terminal2.app/Contents/Resources/AppIcon.icns"
if [ ! -f "$icon" ]; then
    echo 'Build and install Terminal2 with scripts/build.sh first.' >&2
    exit 1
fi
if [ -e "$launcher" ] || [ -L "$launcher" ]; then
    echo "Launcher already exists: $launcher" >&2
    exit 1
fi

stage_dir="$(mktemp -d "$destination/.Terminal2-launcher.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
bundle="$stage_dir/Terminal2 Launcher.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$icon" "$bundle/Contents/Resources/AppIcon.icns"

cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>dev.fuba.Terminal2.Launcher</string>
    <key>CFBundleName</key><string>Terminal2 Launcher</string>
    <key>CFBundleExecutable</key><string>launch</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
</dict></plist>
PLIST

cat > "$bundle/Contents/MacOS/launch" <<'LAUNCH'
#!/bin/sh
exec /usr/bin/open -a "$HOME/Applications/Terminal2.app"
LAUNCH
chmod +x "$bundle/Contents/MacOS/launch"
codesign --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
mv "$bundle" "$launcher"
echo "$launcher"
