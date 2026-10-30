#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d build/Terminal2.app ] || scripts/build.sh release
destination="${1:-$HOME/Applications}"
mkdir -p "$destination"
stage="$destination/.Terminal2-install-$$.app"
ditto build/Terminal2.app "$stage"
codesign --verify --deep --strict "$stage"
if [ -e "$destination/Terminal2.app" ]; then
    mv "$destination/Terminal2.app" "$destination/Terminal2-previous-$(date -u +%Y%m%d%H%M%S)-$$.app"
fi
mv "$stage" "$destination/Terminal2.app"
cmp build/Terminal2.app/Contents/MacOS/Terminal2 "$destination/Terminal2.app/Contents/MacOS/Terminal2"
echo "$destination/Terminal2.app"
