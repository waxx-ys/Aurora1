#!/usr/bin/env bash
# 启动长廊游戏（开发预览）。可传入额外 Godot 参数，例如 --headless。
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$GODOT_BIN" ]]; then
  echo "!! 找不到 Godot: $GODOT_BIN" >&2
  echo "   可用 GODOT_BIN=/path/to/Godot bash tools/run_corridor.sh 指定" >&2
  exit 1
fi
exec "$GODOT_BIN" --path "$PROJECT_DIR" "$@"
