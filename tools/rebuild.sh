#!/bin/bash
# Full regeneration: python generator -> Godot import -> bake
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/tools/gen"
python3 world.py ../out
cd "$ROOT"
godot --headless --path . --import > /tmp/claude-0/import.log 2>&1 || true
grep -iE "SCRIPT ERROR|Parse" /tmp/claude-0/import.log | head -5 || true
godot --headless --path . --script res://bake/bake.gd 2>&1 | grep -E "bake:|SCRIPT ERROR"
