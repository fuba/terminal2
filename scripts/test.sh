#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-dependencies.py
swift test --disable-automatic-resolution "$@"
