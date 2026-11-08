#!/usr/bin/env bash
# 启动独立主界面（不加载游戏本体）。
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
exec "$GODOT_BIN" --path "$PROJECT_DIR" "$@"
