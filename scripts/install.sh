#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d build/Terminal2.app ] || scripts/build.sh release --no-install
destination="${1:-$HOME/Application}"
mkdir -p "$destination"
stage_dir="$(mktemp -d "$destination/.Terminal2-install.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
stage="$stage_dir/Terminal2.app"
ditto build/Terminal2.app "$stage"
codesign --verify --deep --strict "$stage"
cmp build/Terminal2.app/Contents/MacOS/Terminal2 "$stage/Contents/MacOS/Terminal2"
installed="$destination/Terminal2.app"
backup=
if [ -e "$installed" ] || [ -L "$installed" ]; then
    backup="$destination/Terminal2-previous-$(date -u +%Y%m%d%H%M%S)-$$.app"
    mv "$installed" "$backup"
fi
if ! mv "$stage" "$installed"; then
    if [ -n "$backup" ]; then
        mv "$backup" "$installed"
    fi
    exit 1
fi
echo "$installed"
