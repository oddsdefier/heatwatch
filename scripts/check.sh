#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/test.sh
sh build.sh
# Diagnostics contain app/process names. Keep them private and remove them on exit.
diagnostics=$(mktemp "${TMPDIR:-/tmp}/heatwatch-check.XXXXXX")
trap 'rm -f "$diagnostics"' EXIT HUP INT TERM
.build/HeatWatch.app/Contents/MacOS/HeatWatch --diagnose --samples 2 > "$diagnostics"
python3 scripts/check-diagnostics.py "$diagnostics" --samples 2
git diff --check
