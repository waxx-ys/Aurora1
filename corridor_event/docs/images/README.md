# 截图说明与素材来源（v3.0）

| 文件 | 内容 |
| --- | --- |
| `01_corridor_start.png` | 长廊起点：重雾、旧灯、2520 米纵深 |
| `02_floor_walls.png` | 长走廊：石砖地面/原木墙/横梁/UV 循环 |
| `03_wall_closeup.png` | 第一人称贴近原木墙，检查材质与法线 |
| `04_approach_fog.png` | 接近中段牌阵，雾明显变浓 |
| `05_pact_image.png` | 触发区弹出的女巫契约图（无任何对白/倒计时） |
| `06_memory_menu.png` | 同一窗口嵌入的《记忆翻牌》大厅，3 档难度由玩家自选 |
| `07_memory_game.png` | 翻牌游戏 3×4 牌局（SubViewport 嵌入） |
| `08_return_corridor.png` | 关闭翻牌后回到长廊，雾恢复，HUD 显示正面刻印 |
| `09_deep_corridor.png` | 长廊深处（2400 m 附近） |
| `10_ending_text.png` | 尽头 z≈2512 的结局文本触发区 |
| `11_first_person.png` | 第一人称走长廊 |
| `12_debug_overlay.png` | F3 调试：状态/坐标/雾密度/试炼结果 |

## 素材来源

- 地板：`wall-tile-seamless.zip` 的 `textures/Wall.png`、`Normal.png`
- 墙壁：`wooden-log-wall-seamless-texture.zip` 的 `textures/log_wall_4k_*.png`（2048 降采样）
- 女巫契约图：用户提供的 `61C77D33-...PNG`，保存为 `assets/ui/witch_pact.png`
- 氛围贴图：`tools/generate_fx_textures.py` 生成（雾、卡背、符纸、破布）
- 翻牌卡面/medallion：从 `/Users/chenzhengxin/subway-runner/memory_game/art/` 复制
- 翻牌大厅背景：从 `/Users/chenzhengxin/subway-runner/output/witch-ui/` 复制
- 字体：`hakidame.TTF` 来自原翻牌工程；长廊 HUD 使用系统衬线字体
- 原始 zip 不随工程提交，处理脚本在 `tools/import_textures.sh`

## 重新截图

```bash
cd "$HOME/地铁跑酷/corridor_event"
bash tools/capture_screenshots.sh
```

截图脚本会：

1. 强制窗口模式并置前；
2. 冻结玩家输入，避免杂散输入让角色漂移；
3. 按 z=5 / 120 / 200 / 1248 / 1260 等位置拍长廊；
4. 在 z=1260 等契约图出现后截图；
5. 点击契约图，等嵌入翻牌大厅出现；
6. 选择 3×4 拍牌局；
7. 模拟胜利并关闭，拍回到长廊；
8. 走到 z=2512 拍结局面板。
