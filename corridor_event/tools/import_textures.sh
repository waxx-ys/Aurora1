#!/usr/bin/env bash
# =============================================================================
# import_textures.sh · 贴图入库脚本（可重复执行）
# -----------------------------------------------------------------------------
# 作用：
#   1. 从原始素材压缩包中只提取本项目真正用到的贴图；
#   2. 地板贴图保持 1024（原始尺寸，无缝石砖）；
#      墙壁原木贴图从 4096 降到 2048，避免 4K 贴图导致的显存与导入耗时；
#   3. 把结果按“用途”放进 assets/floor 与 assets/wall。
#
# 为什么不用 4K 原木贴图：
#   4K albedo + normal + roughness + AO 在 GL Compatibility 渲染器下会占用
#   约 200 MB 显存，而长廊实际观看距离只有 3~5 米，2048 已看不出差别。
#   原包里的 Displace（置换/高度图）目前未使用，脚本不提取，减少体积。
#
# 原始素材位置（如移动过，改下面两个变量即可）：
#   FLOOR_ZIP  墙砖/石砖无缝贴图（本项目当“地板”用）
#   WALL_ZIP   原木墙无缝贴图（本项目当“墙壁”用）
#
# 用法：
#   cd corridor_event
#   bash tools/import_textures.sh
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOOR_ZIP="/Users/chenzhengxin/subway-runner/wall-tile-seamless.zip"
WALL_ZIP="/Users/chenzhengxin/subway-runner/wooden-log-wall-seamless-texture.zip"

FLOOR_DIR="$PROJECT_DIR/assets/floor"
WALL_DIR="$PROJECT_DIR/assets/wall"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "== 项目目录: $PROJECT_DIR"
mkdir -p "$FLOOR_DIR" "$WALL_DIR"

if [[ ! -f "$FLOOR_ZIP" ]]; then
  echo "!! 找不到地板素材包: $FLOOR_ZIP" >&2
  exit 1
fi
if [[ ! -f "$WALL_ZIP" ]]; then
  echo "!! 找不到墙壁素材包: $WALL_ZIP" >&2
  exit 1
fi

echo "== 解压地板素材（只取 textures/*.png）"
unzip -o -q "$FLOOR_ZIP" "textures/*.png" -d "$TMP_DIR/floor"

echo "== 解压墙壁素材（只取 textures/*.png）"
unzip -o -q "$WALL_ZIP" "textures/*.png" -d "$TMP_DIR/wall"

# ---- 地板：石砖 Wall / 法线 Normal / 湿滑变体 RainWall（1024，原样入库）----
cp "$TMP_DIR/floor/textures/Wall.png"     "$FLOOR_DIR/wall_tile_albedo.png"
cp "$TMP_DIR/floor/textures/Normal.png"   "$FLOOR_DIR/wall_tile_normal.png"
cp "$TMP_DIR/floor/textures/RainWall.png" "$FLOOR_DIR/wall_tile_rain.png"

# ---- 墙壁：原木 4K → 2048 优化 ----
sips -Z 2048 "$TMP_DIR/wall/textures/log_wall_4k_Albedo.png"    --out "$WALL_DIR/log_wall_albedo.png"    >/dev/null
sips -Z 2048 "$TMP_DIR/wall/textures/log_wall_4k_Normal.png"    --out "$WALL_DIR/log_wall_normal.png"    >/dev/null
sips -Z 2048 "$TMP_DIR/wall/textures/log_wall_4k_Roughness.png" --out "$WALL_DIR/log_wall_roughness.png" >/dev/null
sips -Z 2048 "$TMP_DIR/wall/textures/log_wall_4k_AO.png"        --out "$WALL_DIR/log_wall_ao.png"        >/dev/null

echo "== 完成，文件清单:"
ls -lh "$FLOOR_DIR" "$WALL_DIR"
echo "== 提示：新增/替换贴图后，在 Godot 里执行 项目 > 重新导入，或运行："
echo '   "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path "$PROJECT_DIR" --import'
