#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh debug
open "$HOME/Applications/Terminal2.app"
echo "Log: $HOME/Library/Logs/Terminal2/app.log"
