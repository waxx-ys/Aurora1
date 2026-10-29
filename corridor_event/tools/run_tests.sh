#!/usr/bin/env bash
# 运行长廊 + 嵌入式《记忆翻牌》无头验收（单进程、单窗口方案）。
set -uo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"

echo "=============================================="
echo " 长廊 + 嵌入式《记忆翻牌》无头验收"
echo "=============================================="
"$GODOT_BIN" --headless --path "$PROJECT_DIR" res://tests/test_corridor.tscn 2>&1 \
  | grep -E "PASS|FAIL|TEST_RESULT|=== result|SCRIPT ERROR|ERROR"
code=${PIPESTATUS[0]}

if [[ $code -eq 0 ]]; then
  echo "全部测试通过 ✓"
else
  echo "存在失败测试 ✗（详见上方输出 / docs/02_维护手册.md）" >&2
fi
exit $code
