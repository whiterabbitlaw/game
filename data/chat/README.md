# 栖云居聊天数据（草稿）

本目录是畅聊功能的模块化数据，结构借鉴 SillyTavern：

- `persona.json`：玩家人设（Persona）草稿；本机覆盖在 `user://chat/persona_local.json`
- `cards/*.json`：角色卡，兼容 Character Card V2（`spec: chara_card_v2`）
- `lorebook.json`：共用世界书（World Info）
- `lore/<id>.json`：可选的角色专属世界书（与卡内 character_book 合并）
- `module_order.json`：提示词模块注册顺序
- `festivals.json`：中国节日简表（含 2025–2028 农历对照）

九张角色卡均标记为 **草稿**（`creator_notes` 与 `extensions.qiyunju.draft`），由现有游戏文案整理，待审阅后再定稿。

请勿把密钥、玩家真实隐私写进本目录后提交到公开仓库。聊天记录与滚动摘要保存在游戏的 `user://chat/` 下，不进仓库。

记忆与共享档案、纪念日领取记录也只写在 `user://chat/`，不要拷进本目录。
