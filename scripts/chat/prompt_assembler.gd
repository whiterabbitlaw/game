class_name ChatPromptAssembler
extends RefCounted
## 提示词组装器。顺序借鉴 SillyTavern Prompt Manager：
## 系统设定 → 玩家人设 → 角色卡 → 世界书(before/after) → 长期事实与滚动摘要
## → 作者注/纪念日 → 裁剪后的历史 → 历史后指令。并受 token 预算约束。

const PERSONA_PATH := "res://data/chat/persona.json"
const CARD_DIR := "res://data/chat/cards/"
const DEFAULT_BUDGET := 3500

var persona: Dictionary = {}
var last_meta: Dictionary = {}


func _init() -> void:
	persona = _load_json(PERSONA_PATH)


func load_card(char_id: String) -> Dictionary:
	return _load_json(CARD_DIR + char_id + ".json")


func user_name() -> String:
	var n := str(persona.get("name", "道友")).strip_edges()
	return n if n != "" else "道友"


func assemble(char_id: String, history: Array, user_text: String, memory: ChatMemory = null, extra_note: String = "", token_budget: int = DEFAULT_BUDGET) -> Dictionary:
	var card := load_card(char_id)
	var data: Dictionary = card.get("data", {})
	var char_name := str(data.get("name", char_id))
	var lore := ChatLorebook.new()
	lore.load_default()
	var book: Dictionary = data.get("character_book", {})
	if typeof(book) == TYPE_DICTIONARY:
		lore.add_character_book(book)
	var activated := lore.scan(history, user_text)
	var before := lore.contents_for_position(activated, "before_char")
	var after := lore.contents_for_position(activated, "after_char")

	var sys := PackedStringArray()
	var sys_p := _macro(str(data.get("system_prompt", "")), char_name)
	if sys_p != "":
		sys.append(sys_p)
	else:
		sys.append("你正在栖云居与玩家自由畅聊。保持角色，使用简体中文，回复简短自然。")
	sys.append("玩家（{{user}}）人设：%s\n%s" % [user_name(), str(persona.get("description", ""))])
	var pers := str(persona.get("personality", "")).strip_edges()
	if pers != "":
		sys.append("玩家性格补充：%s" % pers)
	for t in before:
		sys.append("【世界书】" + _macro(t, char_name))
	sys.append("【角色】%s\n%s" % [char_name, _macro(str(data.get("description", "")), char_name)])
	var personality := str(data.get("personality", "")).strip_edges()
	if personality != "":
		sys.append("【性格】" + _macro(personality, char_name))
	var scenario := str(data.get("scenario", "")).strip_edges()
	if scenario != "":
		sys.append("【情境】" + _macro(scenario, char_name))
	for t in after:
		sys.append("【世界书】" + _macro(t, char_name))
	var examples := _macro(str(data.get("mes_example", "")).strip_edges(), char_name)
	if examples != "":
		sys.append("【对话示例，只学语气，不要照抄】\n" + examples)
	if memory:
		if memory.summary() != "":
			sys.append("【较早对话的摘要】\n" + memory.summary())
		var facts: Array = memory.facts()
		if not facts.is_empty():
			var fl: PackedStringArray = []
			for f in facts:
				fl.append("- " + str(f))
			sys.append("【长期记得的事】\n" + "\n".join(fl))
	if extra_note.strip_edges() != "":
		sys.append(_macro(extra_note.strip_edges(), char_name))

	var system_text := _macro("\n\n".join(sys), char_name)
	var post := _macro(str(data.get("post_history_instructions", "")).strip_edges(), char_name)
	var sys_tokens := ChatLorebook.estimate_tokens(system_text + "\n" + post + "\n" + user_text)
	var remain := maxi(400, token_budget - sys_tokens)
	var kept := _trim_history(history, remain)

	var messages: Array = []
	messages.append({"role": "system", "content": system_text})
	for m in kept:
		var role := str(m.get("role", "user"))
		if role != "user" and role != "assistant" and role != "system":
			role = "assistant"
		messages.append({"role": role, "content": str(m.get("content", ""))})
	if post != "":
		messages.append({"role": "system", "content": post})
	messages.append({"role": "user", "content": user_text})

	last_meta = {
		"char_id": char_id,
		"char_name": char_name,
		"lore_count": activated.size(),
		"history_kept": kept.size(),
		"tokens_est": sys_tokens + ChatLorebook.estimate_tokens(JSON.stringify(kept) + user_text),
		"budget": token_budget,
	}
	return {"messages": messages, "meta": last_meta, "first_mes": _macro(str(data.get("first_mes", "")), char_name), "alternate_greetings": data.get("alternate_greetings", [])}


func _trim_history(history: Array, token_budget: int) -> Array:
	if history.is_empty():
		return []
	var acc: Array = []
	var used := 0
	for i in range(history.size() - 1, -1, -1):
		var m: Dictionary = history[i]
		var cost := ChatLorebook.estimate_tokens(str(m.get("content", ""))) + 4
		if acc.size() > 0 and used + cost > token_budget:
			break
		acc.push_front(m)
		used += cost
	return acc


func _macro(text: String, char_name: String) -> String:
	return text.replace("{{char}}", char_name).replace("{{user}}", user_name())


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
