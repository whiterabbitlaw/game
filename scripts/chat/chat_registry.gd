class_name ChatRegistry
extends RefCounted
## 模块注册表：读取 data/chat/module_order.json，按顺序收集各 ChatModule 的提示词片段。

const ORDER_PATH := "res://data/chat/module_order.json"

var order: PackedStringArray = PackedStringArray()
var modules: Array = []  # Array[ChatModule]
var last_sections: Array = []


func load_default() -> void:
	order = PackedStringArray()
	var cfg := _load_json(ORDER_PATH)
	if typeof(cfg.get("order", [])) == TYPE_ARRAY:
		for id in cfg["order"]:
			order.append(str(id))
	if order.is_empty():
		order = PackedStringArray(["card_system", "persona", "lorebook_before", "card", "lorebook_after", "examples", "memory", "events", "multimodal"])
	modules.clear()
	register(_CardSystemModule.new())
	register(_PersonaModule.new())
	register(_LorebookModule.new())
	register(_CardModule.new())
	register(_ExamplesModule.new())
	register(_MemoryModule.new())
	register(_EventsModule.new())
	register(_MultimodalModule.new())


func register(mod: ChatModule) -> void:
	modules.append(mod)


func collect(ctx: Dictionary) -> Array:
	var by_id: Dictionary = {}
	for m in modules:
		var mod := m as ChatModule
		var mid := mod.module_id()
		var secs: Array = mod.prompt_sections(ctx)
		if mid in ["lorebook"]:
			# 世界书一次产出 before/after/examples/at_depth 多段，按段 id 归档
			for s in secs:
				var sid := str(s.get("id", mid))
				if not by_id.has(sid):
					by_id[sid] = []
				(by_id[sid] as Array).append(s)
		else:
			if not by_id.has(mid):
				by_id[mid] = []
			for s in secs:
				(by_id[mid] as Array).append(s)
	var out: Array = []
	for id in order:
		if by_id.has(id):
			out.append_array(by_id[id])
	# 未出现在 order 里的模块（例如 lorebook_at_depth）跟在后面
	for k in by_id.keys():
		if not (str(k) in order):
			out.append_array(by_id[k])
	last_sections = out
	return out


func system_text(sections: Array, char_name: String, user_name: String) -> String:
	var parts: PackedStringArray = []
	for s in sections:
		if str(s.get("placement", "system")) != "system":
			continue
		var c := str(s.get("content", "")).strip_edges()
		if c != "":
			parts.append(_macro(c, char_name, user_name))
	return "\n\n".join(parts)


func post_history(sections: Array, char_name: String, user_name: String) -> String:
	var parts: PackedStringArray = []
	for s in sections:
		if str(s.get("placement", "")) != "post_history":
			continue
		var c := str(s.get("content", "")).strip_edges()
		if c != "":
			parts.append(_macro(c, char_name, user_name))
	return "\n\n".join(parts)


func at_depth_sections(sections: Array) -> Array:
	var out: Array = []
	for s in sections:
		if str(s.get("placement", "")) == "at_depth":
			out.append(s)
	return out


static func _macro(text: String, char_name: String, user_name: String) -> String:
	return text.replace("{{char}}", char_name).replace("{{user}}", user_name)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


class _CardSystemModule extends ChatModule:
	func module_id() -> String:
		return "card_system"

	func prompt_sections(ctx: Dictionary) -> Array:
		var data: Dictionary = ctx.get("card", {}).get("data", {})
		var sys := str(data.get("system_prompt", "")).strip_edges()
		if sys == "":
			sys = "你正在栖云居与玩家自由畅聊。保持角色，使用简体中文，回复简短自然。"
		return [{"id": "card_system", "placement": "system", "content": sys}]


class _PersonaModule extends ChatModule:
	func module_id() -> String:
		return "persona"

	func prompt_sections(ctx: Dictionary) -> Array:
		var persona: Dictionary = ctx.get("persona", {})
		var name := str(ctx.get("user_name", persona.get("name", "道友")))
		var desc := str(persona.get("description", "")).strip_edges()
		var pers := str(persona.get("personality", "")).strip_edges()
		var body := "玩家（{{user}}）人设：%s\n%s" % [name, desc]
		if pers != "":
			body += "\n玩家性格补充：%s" % pers
		return [{"id": "persona", "placement": "system", "content": body}]


class _LorebookModule extends ChatModule:
	func module_id() -> String:
		return "lorebook"

	func prompt_sections(ctx: Dictionary) -> Array:
		var lore: ChatLorebook = ctx.get("lore", null)
		var activated: Array = ctx.get("lore_activated", [])
		if lore == null:
			return []
		var out: Array = []
		var pos_ids := {
			"before_char": "lorebook_before",
			"after_char": "lorebook_after",
			"before_example": "lorebook_before_example",
			"after_example": "lorebook_after_example",
		}
		for pos in pos_ids.keys():
			var texts: PackedStringArray = lore.contents_for_position(activated, pos)
			if texts.is_empty():
				continue
			var packed: PackedStringArray = []
			for t in texts:
				packed.append("【世界书】" + t)
			out.append({"id": str(pos_ids[pos]), "placement": "system", "content": "\n\n".join(packed)})
		# at_depth 条目
		for e in activated:
			if str(e.get("position", "")) != "at_depth":
				continue
			var c := str(e.get("content", "")).strip_edges()
			if c == "":
				continue
			out.append({
				"id": "lorebook_at_depth",
				"placement": "at_depth",
				"content": "【世界书】" + c,
				"depth": int(e.get("depth", 1)),
			})
		return out


class _CardModule extends ChatModule:
	func module_id() -> String:
		return "card"

	func prompt_sections(ctx: Dictionary) -> Array:
		var data: Dictionary = ctx.get("card", {}).get("data", {})
		var char_name := str(ctx.get("char_name", data.get("name", "")))
		var parts: PackedStringArray = []
		parts.append("【角色】%s\n%s" % [char_name, str(data.get("description", ""))])
		var personality := str(data.get("personality", "")).strip_edges()
		if personality != "":
			parts.append("【性格】" + personality)
		var scenario := str(data.get("scenario", "")).strip_edges()
		if scenario != "":
			parts.append("【情境】" + scenario)
		return [{"id": "card", "placement": "system", "content": "\n\n".join(parts)}]


class _ExamplesModule extends ChatModule:
	func module_id() -> String:
		return "examples"

	func prompt_sections(ctx: Dictionary) -> Array:
		var data: Dictionary = ctx.get("card", {}).get("data", {})
		var examples := str(data.get("mes_example", "")).strip_edges()
		if examples == "":
			return []
		return [{"id": "examples", "placement": "system", "content": "【对话示例，只学语气，不要照抄】\n" + examples}]


class _MemoryModule extends ChatModule:
	func module_id() -> String:
		return "memory"

	func prompt_sections(ctx: Dictionary) -> Array:
		var memory: ChatMemory = ctx.get("memory", null)
		if memory == null:
			return []
		var parts: PackedStringArray = []
		if memory.summary() != "":
			parts.append("【较早对话的摘要】\n" + memory.summary())
		var query := str(ctx.get("user_text", ""))
		for m in ctx.get("history", []):
			query += "\n" + str(m.get("content", ""))
		var shared: Array = ctx.get("shared_facts", [])
		var retrieved := memory.retrieve(query, shared)
		var block := memory.format_facts_block(retrieved)
		if block != "":
			parts.append(block)
		if parts.is_empty():
			return []
		return [{"id": "memory", "placement": "system", "content": "\n\n".join(parts)}]


class _EventsModule extends ChatModule:
	func module_id() -> String:
		return "events"

	func prompt_sections(ctx: Dictionary) -> Array:
		var note := str(ctx.get("extra_note", "")).strip_edges()
		if note == "":
			return []
		return [{"id": "events", "placement": "system", "content": note}]


class _MultimodalModule extends ChatModule:
	func module_id() -> String:
		return "multimodal"

	func prompt_sections(ctx: Dictionary) -> Array:
		var att: Array = ctx.get("attachments", [])
		if att.is_empty():
			return []
		var lines: PackedStringArray = ["【玩家本轮附上了媒体。下面是模型真正看到的描述，请只根据这些画面细节回答，不要说自己看不到，也不要改成向日葵、笔记等角色习惯话题。描述里没有的东西不要编。】"]
		for a in att:
			var kind := str(a.get("kind", "image"))
			var desc := str(a.get("description", "")).strip_edges()
			if kind == "video":
				lines.append("视频逐帧所见：" + (desc if desc != "" else "（尚无描述）"))
			else:
				lines.append("图片：" + (desc if desc != "" else "（尚无描述）"))
		return [{"id": "multimodal", "placement": "system", "content": "\n".join(lines)}]
