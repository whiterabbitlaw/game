#!/bin/bash
# GitHub Pages：完整 Web 导出到 docs/，并注入 PWA / 麦克风脚本。
set -e
cd "$(dirname "$0")/.."
G=${GODOT:-/workspace/tools/Godot_v4.7.2-stable_linux.x86_64}
$G --headless --path . --export-release Web docs/index.html
python3 "$(dirname "$0")/inject_pwa.py" docs
echo "output: docs"
