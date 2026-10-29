# 记忆翻牌 ⇄ 跑酷：Buff 联动接口

> 触发部分（另一个游戏如何快速打开记忆翻牌）见 [INTERGAME_TRIGGER.md](INTERGAME_TRIGGER.md)。

## 设计关系

```text
记忆翻牌一局结束
      │
      ├─ 胜利 → positive 刻印
      └─ 失败 → negative 刻印（超时 / 失误超限）
                    │
                    ▼
        RunBuffs.queue_buff()      ← 记忆翻牌唯一出口
                    │
        user://memory_run_buffs.json
                    │
                    ▼
        RunBuffs.consume_pending() ← 跑酷唯一入口
                    │
                    ▼
        跑酷端 apply_buff(buff.effects …)
```

- 记忆翻牌是跑酷前的一次“试炼”；刻印是它留给下一场跑酷的**局外变量**。
- 两边的唯一契约是 `RunBuffs` Autoload，互不引用对方的场景或玩家节点。
- 记忆翻牌只负责写入，不读取、不应用；跑酷只负责读取/应用，不反写。
- 待生效刻印会持久化到 `user://memory_run_buffs.json`，关闭游戏再打开仍然存在。

## 数据结构

`RunBuffs.queue_buff()` 会补齐 `id`、时间戳、`consumed` 等元字段，最终写入的一条大致如下：

```json
{
  "id": "buff_1761000000_123456",
  "polarity": "negative",
  "source": "memory_card_game",
  "target": "parkour",
  "template_id": "",
  "title": "",
  "description": "",
  "effects": {},
  "configured": false,
  "context": {
    "level": "3x4",
    "reason": "mistakes",
    "stats": {
      "level": "3x4",
      "time_limit": 75.0,
      "time_left": 31.2,
      "time_used": 43.8,
      "mistakes": 4,
      "max_mistakes": 4,
      "pairs": 3,
      "pairs_total": 6,
      "reason": "mistakes"
    },
    "created_by": "memory_game"
  },
  "created_at": 1761000000,
  "created_at_text": "2026-10-24T09:00:00",
  "consumed": false
}
```

| 字段 | 说明 |
| --- | --- |
| `polarity` | `positive`（胜利）或 `negative`（失败） |
| `source` / `target` | 固定为 `memory_card_game` / `parkour` |
| `configured` | 是否从内容池抽到了实际定义；当前为 `false` |
| `title` / `description` | 展示文案；未配置时为空 |
| `effects` | **自由结构**。跑酷端自行解释，例如 `{"speed_mult":0.85,"fog":0.4}` |
| `context` | 生成时的局内数据，便于跑酷端做条件判断或展示来源 |
| `consumed` | 被跑酷消费后置为 `true`，并归档进历史 |

## 接口速查

Autoload：`RunBuffs`（[`scripts/run_buffs.gd`](../scripts/run_buffs.gd)）

```gdscript
# 记忆翻牌端 —— 每局结束调用一次
var buff := MemoryBuffCatalog.create_memory_buff(polarity, level_id, reason, stats)
RunBuffs.queue_buff(buff)   # 返回带 id 的完整字典

# 跑酷端 —— 开局读取并清空
var buffs: Array = RunBuffs.consume_pending()
for buff in buffs:
    apply_buff(buff)

# 只读预览（菜单显示数量）
var pending: Array = RunBuffs.peek_pending()
var count: int = RunBuffs.pending_count()

# 信号
RunBuffs.buff_queued.connect(func(buff): ...)
RunBuffs.pending_changed.connect(func(list): ...)
```

其他：

- `clear_pending()`：调试或新开档时清空。
- `history()`：最近消费历史（最多 32 条）。
- `MAX_PENDING = 12`：待生效池上限，超出时丢弃最旧一条。
- 存储路径：`user://memory_run_buffs.json`。macOS 位于 `~/Library/Application Support/Godot/app_userdata/地铁跑酷/`。

## 填充 Buff 内容

打开 [`scripts/buff_catalog.gd`](../scripts/buff_catalog.gd)，目前两个池子都是空的：

```gdscript
const NEGATIVE_POOL: Array[Dictionary] = []
const POSITIVE_POOL: Array[Dictionary] = []
```

按如下结构添加即可，无需改记忆翻牌逻辑：

```gdscript
const POSITIVE_POOL: Array[Dictionary] = [
    {
        "id": "positive_swift_step",
        "title": "疾行刻印",
        "description": "下一场跑酷的起步速度提升，持续 15 秒。",
        "effects": {
            "speed_mult": 1.18,
            "duration": 15.0,
            "vfx": "green_trail"
        }
    }
]
```

- 池子非空后，`create_memory_buff()` 会随机抽一条，把 `title/description/effects` 带入刻印，`configured` 自动变成 `true`，结算界面的“待配置”印章会隐藏。
- `effects` 的结构由你和跑酷端约定，记忆翻牌不解释它。请保持 JSON 可序列化（数字、字符串、数组、字典），不要放 Node / Resource 引用。
- 如果希望成功/失败固定给某种效果，可改为按 `context.level`、`context.reason` 选择模板。

## 跑酷端接入方式

### 方式 A：直接加接收器节点（推荐起步）

把 [`integration/parkour_buff_receiver.gd`](parkour_buff_receiver.gd) 挂到跑酷场景根节点下，在开始跑酷时调用：

```gdscript
%ParkourBuffReceiver.collect_and_apply()
```

它会调用 `RunBuffs.consume_pending()`，逐条发出 `buff_applied` 信号，并把 `effects` 留在 `apply_buff()` 的 TODO 里供你接入。也可以在 Inspector 勾选 `auto_collect_on_ready`。

### 方式 B：直接调用 Autoload

```gdscript
func begin_run() -> void:
    var buffs: Array = RunBuffs.consume_pending()
    for buff in buffs:
        var effects: Dictionary = buff.get("effects", {})
        if effects.has("speed_mult"):
            player.speed_multiplier *= float(effects["speed_mult"])
        if effects.has("screen_fog"):
            camera.fog_strength = float(effects["screen_fog"])
        # context 里可以看到它来自哪一档记忆翻牌、为什么失败
```

**建议时机**：跑酷倒计时/开局展示之后、玩家真正开始移动之前消费。不要每帧调用。

## 通过 GameLink 获取一局结果

如果记忆翻牌是由另一个游戏通过 `GameLink` 打开的，可以在宿主场景里直接监听结果，而不用轮询存档：

```gdscript
GameLink.memory_run_finished.connect(func(result: Dictionary) -> void:
    var success: bool = result.get("success", false)
    var buff: Dictionary = result.get("buff", {})
    # buff 已经由记忆翻牌写入 RunBuffs；这里只是即时通知
    # 跑酷真正开始一局时仍建议调用 RunBuffs.consume_pending() 取走它
    print("trial finished: ", success, " / ", buff.get("polarity", ""))
)
```

- `result.stats` 包含本局用时、失误、配对数量等；
- `result.buff` 是已经带 `id` 的完整刻印字典；
- 不要在这里再次调用 `queue_buff()`，否则会重复入池。

## 当前刻意留空的部分

- `NEGATIVE_POOL` / `POSITIVE_POOL` 为空；
- 因此 `effects == {}`、`configured == false`；
- 结算页显示“未命名的刻印”和“待配置”印章；
- 但 Buff 的生成、入池、持久化、消费、历史归档链路已经全部可用，冒烟测试已验证。

## 冒烟测试

```bash
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --path "$HOME/地铁跑酷" \
  --audio-driver Dummy --rendering-method gl_compatibility \
  res://memory_game/tests/smoke_test.tscn
```

测试结束会清空待生效池，不会污染正式数据。
