# 栖云居 · 挂机修仙（原型 v0.1）

Godot 4.7 · 2D · 竖屏 720×1280 · 纯养成 / 陪伴向（无战斗）

受《一念逍遥》启发的挂机修仙 + 伙伴情感养成原型。九位 AI 拟人角色（Q 版二次创作）作为可结缘的伙伴。

## 玩法
- **挂机修炼**：修为 / 灵石每秒自动增长；离线收益（上限 8 小时 + 绒云加成）+ 伙伴来信。
- **境界**：练气→筑基→金丹→元婴→化神→炼虚→合体→大乘→渡劫，每境 初期/中期/后期/圆满；突破有成功率 / 保底 / 失败损耗，附全屏光效。
- **伙伴**：九位角色，各有专属被动（博闻强识、审慎之心、无畏、星运、月律共鸣、青岚润泽、灵感迸发、绒云安眠、深海细致）。
- **羁绊**：好感 Lv.1–10；每日互动（闲聊 / 赠礼 / 品茶 / 观星 / 闭关同修），点按主角戳一戳也加好感。
- **剧情**：序章 + 每位 3 章回忆（视觉小说式对白、情绪气泡、分支选项），随羁绊与境界解锁；可在「回忆」重温。
- **洞府灵田**：种灵草、炼制灵茶/灵花束，灵市买桂花糕/星辰露/诗笺；每日登录礼。
- 存档：`user://save_v1.json`。

## 目录
- `scripts/` GDScript（`game.gd` 为全局状态 Autoload）
- `data/story.json`、`data/pools.json` 剧情 / 语料（由 `tools/story/*.py` 生成，改文案请改 py 再 `python3 build.py`）
- `assets/chars/` 9 位 Q 版立绘（透明 PNG）；`assets/thumbs/` 头像；`assets/bg/` 背景；`assets/fonts/` 内置思源黑体(子集)+马善政毛笔
- `shaders/` 放射光、光柱、闪白
- `tools/` 背景/字体生成脚本；`art/raw/` 原始生成图
- `tests/logic_test.gd` 逻辑自测：`godot --headless --path . --script res://tests/logic_test.gd`

## 运行 / 导出
```
godot --path .                                   # 编辑器内运行
godot --headless --path . --export-release Web build/web/index.html
python3 -m http.server -d build/web 8765
```
演示参数（Web）：`index.html?demo=main|roster|detail|home|memory|lineup|dialogue|breakthrough|bfail|secl|offline|btready`（演示模式不写存档）。
设置里有「试玩加速」×10 / ×60，便于测试。

## 版权
角色设定来自用户提供的 AI 拟人同人设定图，Q 版为二次创作。字体：Noto Sans CJK SC（SIL OFL）、Ma Shan Zheng（SIL OFL）。
