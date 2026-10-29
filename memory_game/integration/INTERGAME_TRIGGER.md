# 游戏间快速触发接口（GameLink）

## 为什么不是“双击启动脚本”

每次新起一个 Godot 进程会经历引擎启动和资源导入，响应通常在 1–3 秒，无法满足“另一个游戏发指令后快速打开”。

现在的实现是 **常驻触发桥 + 预热记忆翻牌场景**：

```text
另一个游戏 / 跑酷场景
        │
        ├─ 同进程：GameLink.send_command("open_memory_game", …)   ← 最快
        │
        └─ 跨进程：UDP 127.0.0.1:45910（JSON）                    ← 预热进程同样很快
                                  │
                                  ▼
                     GameLink（Autoload，常驻）
                     ├─ 预加载 memory_game.tscn
                     ├─ 预实例化隐藏 overlay（默认开启）
                     ├─ 收到指令 → 显示 + 暂停宿主 → 发 opened 信号
                     └─ 收到关闭 → 隐藏 + 恢复宿主
```

不需要、也不会再通过双击 `.command` 来打开。开发时用 Godot 编辑器按 F5 即可；正式运行时由跑酷游戏（或任意调度器）发指令。

## 同进程触发（推荐）

适用于另一个游戏和记忆翻牌在**同一个 Godot 项目/同一个进程**中，例如未来的跑酷主场景。

```gdscript
# 打开到大厅
var result: Dictionary = GameLink.send_command("open_memory_game", {
    "view": "menu"
})

# 直接进入指定难度
GameLink.send_command("open_memory_game", {
    "view": "level",
    "level": "3x4"          # 2x3 / 3x4 / 4x5
})

# 关闭，回到调用方
GameLink.send_command("close_memory_game", {"reason": "parkour_resume"})
```

也可以直接调用具名方法：

```gdscript
GameLink.open_memory_game({"view": "level", "level": "4x5"})
GameLink.close_memory_game("parkour")
```

### 参数

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `view` | `"menu"` | `menu` 大厅；`level` 直接开局；`current` 保留当前画面 |
| `level` | 无 | `view=level` 时使用，`2x3` / `3x4` / `4x5` |
| `pause_host` | `true` | overlay 打开时暂停底层场景树；关闭时恢复 |
| `keep` | `false` | `view=current` 时保留当前牌局状态 |

### 回调

```gdscript
# 记忆翻牌被打开，latency_ms 为从指令到场景可见的耗时
GameLink.memory_game_opened.connect(func(options, latency_ms):
    print("memory opened in ", latency_ms, " ms")
)

# 一局结束（成功/失败），buff 已经写入 RunBuffs
GameLink.memory_run_finished.connect(func(result):
    print("success=", result["success"], " buff=", result["buff"])
)

# 玩家按 Esc / 点右上角 × / 被动关闭
GameLink.memory_game_closed.connect(func(reason):
    print("memory closed: ", reason)
)
```

`result` 结构：

```json
{
  "success": true,
  "reason": "cleared",
  "stats": { "level": "3x4", "time_used": 41.2, "mistakes": 0, "pairs": 6 },
  "buff": { "id": "buff_…", "polarity": "positive", "effects": {}, "configured": false }
}
```

### 跨进程结果回传（memory_run_finished，新增）

通过 UDP 收到指令时，`GameLink` 会记住最近一次发送方地址；一局结束（`run_finished`）时，
会向该地址额外回发一条事件包，把胜负与刻印带给调用方。它是**附加能力**：
旧调用方可以完全忽略它，`open/close/ping` 的行为不变。

```json
{
  "event": "memory_run_finished",
  "ok": true,
  "source": "memory_game",
  "success": true,
  "reason": "cleared",
  "stats": {"level": "3x4", "time_used": 38.2, "mistakes": 1, "pairs": 6, "pairs_total": 6},
  "buff": {
    "id": "buff_…",
    "polarity": "positive",
    "title": "",
    "effects": {},
    "configured": false
  }
}
```

- 只对 **UDP 调用方**回传；同进程调用继续用 `GameLink.memory_run_finished` 信号。
- 事件包发到调用方当时的源地址/源端口（调用方必须保持 socket 打开并在关闭前持续收包）。
- 如果 UDP 丢包或调用方已关闭，只影响这一次通知；对方仍可通过 `ping(open=false)` 得知已关闭。
- 长廊项目已按此协议接收，并据此结算“赐福（正面刻印）/ 诅咒（负面刻印）”。
- 回归测试：`res://memory_game/tests/result_echo_test.tscn`（见 README）。

## 跨进程触发（本地 UDP）

适用于另一个游戏是**独立进程/独立引擎**的情况。端口只绑定 `127.0.0.1`，不暴露外网。

协议：一个 UDP 数据包，内容是 JSON（也兼容纯文本 `open_memory_game`）。

```json
{"command":"open_memory_game","view":"menu"}
{"command":"open_memory_game","view":"level","level":"3x4"}
{"command":"close_memory_game","reason":"parkour"}
{"command":"ping"}
```

响应会回发到发送方端口：

```json
{
  "ok": true,
  "latency_ms": 1.327,
  "open": true,
  "overlay": true,
  "prewarmed": true,
  "paused_host": true,
  "source": "udp"
}
```

### 外部游戏端最小示例

Python（用于测试或非 Godot 的外部程序）：

```python
import json, socket

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(1.0)
sock.sendto(
    json.dumps({"command": "open_memory_game", "view": "menu"}).encode("utf-8"),
    ("127.0.0.1", 45910),
)
print(sock.recvfrom(8192)[0].decode("utf-8"))
```

Godot 外部客户端：

```gdscript
var udp := PacketPeerUDP.new()
udp.bind(0, "127.0.0.1")
udp.set_dest_address("127.0.0.1", 45910)
udp.put_packet(JSON.stringify({
    "command": "open_memory_game",
    "view": "level",
    "level": "3x4"
}).to_utf8_buffer())
```

### 预热模式（跨进程推荐）

如果记忆翻牌是独立进程，不要在每次指令时才 `create_process`。应在另一个游戏启动时把它拉起来并保持最小化：

```bash
GODOT_BIN --path "/Users/chenzhengxin/地铁跑酷" -- --warm
```

- `--warm`：启动后最小化窗口，等待 UDP 指令；
- 收到 `open_memory_game` 后恢复窗口并显示，关闭时再次最小化，保持热启动；
- 默认启动时会**预加载 + 预实例化**隐藏场景；加 `--no-prewarm` 可关闭预实例化（响应会变慢一些）；
- 自定义端口：`MEMORY_TRIGGER_PORT=45911 Godot ...`，客户端也同步改端口。

记忆翻牌进程需要处于运行状态。**冷启动**一个 Godot 进程仍然需要 1 秒以上，因此对“响应要快”的场景，请使用同进程 overlay 或 `--warm` 常驻进程。

## 实测数据

本机 Godot 4.7.2、无头测试环境：

| 场景 | 耗时 |
| --- | --- |
| 同进程打开大厅（预热后） | 约 **4 ms** |
| 同进程首次直接进入 3×4（构建 12 张牌） | 约 **65–85 ms** |
| UDP 收到指令 → 处理完成 | 约 **0.3–2 ms**（另有 1 帧轮询与渲染） |
| 关闭并恢复宿主 | 亚毫秒级 |

这些测试包含宿主暂停、视口切换和嵌入返回按钮；实际画面在下一帧绘制完成。

## 关闭与返回

- overlay 模式下右上角会出现 **×**，右下角提示 **ESC 返回游戏**；
- 关闭时自动恢复 `get_tree().paused` 到打开前的状态；
- 程序侧也可以调用 `GameLink.close_memory_game()`；
- 如果记忆翻牌是独立进程，被关闭时窗口最小化但不退出，方便下一次快速打开。

## 可视化测试台

在 Godot 里单独运行 [`trigger_demo.tscn`](trigger_demo.tscn)（F6）。它是一个模拟的“另一个游戏”，按钮会直接调用 GameLink：

- 打开大厅 / 直接进入 3×4 / 直接进入 4×5；
- 关闭记忆翻牌；
- 显示最近一次指令耗时和 `memory_game_opened` / `memory_game_closed` 信号。

## 测试

```bash
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless \
  --path "$HOME/地铁跑酷" --audio-driver Dummy \
  res://memory_game/tests/intergame_trigger_test.tscn
```

覆盖：预热、ping、同进程打开、宿主暂停、暂停状态下记忆翻牌仍在计时、关闭恢复、UDP 打开与 JSON 响应。

## 注意

- `GameLink` 是 `project.godot` 中的 Autoload；另一个游戏直接用它，不要再手工实例化记忆翻牌场景。
- 同进程触发时，记忆翻牌被加在 `CanvasLayer(layer=100)` 的 overlay 里，不会销毁宿主场景，关闭后宿主从原状态继续。
- UDP 只监听回环地址；不要把它当作公网服务。
- 端口冲突时查看启动日志，或设置 `MEMORY_TRIGGER_PORT`。
