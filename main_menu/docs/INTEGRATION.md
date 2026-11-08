# 与游戏本体嵌套的步骤

> 本工程按要求**没有**接入游戏本体。下面给出两种集成方式，任选一种。
>
> 关键接口：`scripts/menu.gd` 的 `start_requested` 信号，以及 `Menu` 根节点的 `game_scene_path` 导出路径。主界面点击任意位置时都会调用 `_start_game()`。

---

## 方式 A：把主界面放进游戏本体工程（推荐）

适合已经有一个完整游戏工程（例如 `corridor_event`），只想把主界面作为启动画面。

### 1. 复制文件到游戏工程

把以下内容复制到游戏工程根目录（保持路径）：

```text
main_menu/scenes/menu.tscn
main_menu/scenes/lantern.tscn
main_menu/scripts/menu.gd
main_menu/scripts/lantern.gd
main_menu/shaders/menu_vignette.gdshader
main_menu/assets/model/            # OBJ + MTL + textures
main_menu/audio/bad_day.wav
main_menu/materials_iron.tres
main_menu/materials_glass.tres
```

> `menu.tscn` 里引用的路径是 `res://...`，复制后不要改路径；如果游戏工程里已有同名 `assets/model/`，请合并/改名，不要覆盖原资源。

### 2. 设置启动场景

在游戏工程的 `project.godot`：

```ini
[application]
run/main_scene="res://scenes/menu.tscn"
```

或者不修改启动场景，从现有启动场景里加载菜单：

```gdscript
get_tree().change_scene_to_file("res://scenes/menu.tscn")
```

### 3. 改标题（可选）

选中 `Menu` 根节点，改 **Title Text**（默认“幽魂廊”），或调用：

```gdscript
$Menu.set_title("新的暂定名")
```

字体默认是 `assets/fonts/hakidame.TTF`（最初版字体）；也可以在 `Menu` 根节点的 `title_font_path` 里换字体。若新字体缺字，把缺失字加到 `scripts/menu.gd` 的 `TITLE_FALLBACK_CHARS` 用系统宋体补。

### 4. 告诉主界面游戏本体场景在哪

打开 `scenes/menu.tscn`，选中根节点 `Menu`，在检查器里把：

```text
Game Scene Path = res://scenes/main.tscn
```

填成你的游戏主场景路径。

然后点击主界面任意位置：

1. `start_requested` 发出；
2. 黑场淡出 0.8 秒；
3. `get_tree().change_scene_to_file("res://scenes/main.tscn")`。

主界面音乐随场景释放自动停止，不需要额外处理。

### 5. 游戏结束/返回时回主界面

在主界面的游戏本体里加一个返回入口（按钮、按键或剧情结束信号），调用：

```gdscript
get_tree().change_scene_to_file("res://scenes/menu.tscn")
```

如果游戏本体原本没有“返回主界面”的概念，建议在游戏的结算/退出流程里加一行；主界面会重新播音乐。

### 6. 注意

- 游戏工程原有的 Autoload 不要删；主界面不依赖任何 Autoload。
- 如果游戏工程已经有 `RunBuffs`/`GameLink` 等，保留即可；主界面不会调用它们。
- 主界面只有标题“幽魂廊”一个文字层（右上角、无阴影）；没有按钮/提示文字。改标题见 `Menu.title_text` / `set_title()`。
- 音频文件较大（19 MB），导出时确认 `audio/bad_day.wav` 在包内。

---

## 方式 B：让主界面工程作为启动器（独立工程 + 游戏本体作为子工程）

适合不想改游戏工程的目录结构。

1. 把这个 `main_menu/` 作为新的 Godot 工程（已经是），游戏本体放在它下面或旁边。
2. 在 `Menu` 根节点 `game_scene_path` 只能填**本工程内**的 `res://` 路径；Godot 不能直接 `change_scene_to_file("res://../other_project/...")`。
3. 因此需要把游戏本体的场景与资源复制进本工程，或把本主界面复制进游戏工程（方式 A）。
4. 如果游戏本体必须保持独立工程，则由一个外部启动器/平台负责：点击后启动游戏进程，主界面工程只做启动画面。这需要在 `menu.gd` 的 `_start_game()` 里替换 `change_scene_to_file` 为平台启动逻辑（本工程默认没有写）。

> 推荐方式 A：同一个 Godot 工程、单窗口、没有进程切换，体验最好。

---

## 方式 C：只接信号，不改 `game_scene_path`

如果游戏有全局场景管理器，可以保持 `game_scene_path` 为空，连接信号：

```gdscript
# 例如放在游戏工程的某个 Autoload / 启动场景里
func _ready() -> void:
	var menu := load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	menu.start_requested.connect(_on_menu_start)

func _on_menu_start() -> void:
	# 播完淡出后由你的管理器切场景
	await get_tree().create_timer(0.8).timeout
	get_tree().change_scene_to_file("res://scenes/main.tscn")
```

注意：`menu.gd` 在 `game_scene_path` 为空时会做一次黑场呼吸，然后继续停留在主界面；
如果外部要接管切换，建议在连接信号后把 `game_scene_path` 填上，或者直接调用 `set_game_scene()`。

---

## 集成检查清单

- [ ] `game_scene_path` 指向真实存在的 `.tscn`。
- [ ] 点击主界面任意位置（不只是中央）都能触发；鼠标左键/Enter/Space 均支持。
- [ ] 进入游戏后主界面音乐停止（场景释放自动停止）。
- [ ] 游戏返回主界面时重新播放音乐。
- [ ] 标题文字按需要修改（`Menu.title_text` 或 `set_title()`），没有残留的按钮/提示文字。
- [ ] 游戏工程原有 Autoload、输入映射、窗口设置不被覆盖。
- [ ] 导出包包含 `audio/bad_day.wav`、`assets/model/`、`scripts/lantern.gd`、`materials_*.tres`。

## 回退

如果集成后不想用主界面：

1. 把 `project.godot` 的 `run/main_scene` 改回游戏原主场景；
2. 或在游戏启动逻辑里不加载 `menu.tscn`；
3. 主界面资源可以保留，不影响游戏本体。
