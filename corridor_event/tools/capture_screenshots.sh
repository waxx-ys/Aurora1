#!/usr/bin/env bash
# 重新生成 docs/images 下的文档截图（需要图形界面，不能用 --headless）。
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
exec "$GODOT_BIN" --path "$PROJECT_DIR" res://tools/capture_screenshots.tscn
