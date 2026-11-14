class_name ChatPromptAssembler
extends RefCounted
## 提示词组装器。模块由 ChatRegistry 按 data/chat/module_order.json 注册。
## 默认顺序仍对齐 SillyTavern Prompt Manager，并受 token 预算约束。

const PERSONA_PATH := "res://data/chat/persona.json"
const CARD_DIR := "res://data/chat/cards/"
const DEFAULT_BUDGET := 3500

var persona: Dictionary = {}
var last_meta: Dictionary = {}
var registry := ChatRegistry.new()
var profile := ChatProfile.new()


func _init() -> void:
	persona = profile.load_persona()
	if persona.is_empty():
		persona = _load_json(PERSONA_PATH)
	registry.load_default()


func load_card(char_id: String) -> Dictionary:
	return _load_json(CARD_DIR + char_id + ".json")


func user_name() -> String:
	var n := str(persona.get("name", "道友")).strip_edges()
	return n if n != "" else "道友"


func assemble(char_id: String, history: Array, user_text: String, memory: ChatMemory = null, extra_note: String = "", token_budget: int = DEFAULT_BUDGET, attachments: Array = []) -> Dictionary:
	persona = profile.load_persona()
	if persona.is_empty():
		persona = _load_json(PERSONA_PATH)
	var card := load_card(char_id)
	var data: Dictionary = card.get("data", {})
	var char_name := str(data.get("name", char_id))
	var lore := ChatLorebook.new()
	lore.load_default()
	lore.load_character(char_id)
	var book: Dictionary = data.get("character_book", {})
	if typeof(book) == TYPE_DICTIONARY:
		lore.add_character_book(book)
	var activated := lore.scan(history, user_text)
	var shared: Array = profile.shared_facts()
	var ctx := {
		"char_id": char_id,
		"char_name": char_name,
		"user_name": user_name(),
		"user_text": user_text,
		"history": history,
		"memory": memory,
		"extra_note": extra_note,
		"token_budget": token_budget,
		"card": card,
		"persona": persona,
		"lore": lore,
		"lore_activated": activated,
		"shared_facts": shared,
		"attachments": attachments,
	}
	var sections := registry.collect(ctx)
	var system_text := registry.system_text(sections, char_name, user_name())
	var post := str(data.get("post_history_instructions", "")).strip_edges()
	# 若模块也提供了 post_history，拼在角色卡指令之后
	var post_mod := registry.post_history(sections, char_name, user_name())
	if post_mod != "":
		post = (post + "\n\n" + post_mod).strip_edges() if post != "" else post_mod
	post = _macro(post, char_name)
	var sys_tokens := ChatLorebook.estimate_tokens(system_text + "\n" + post + "\n" + user_text)
	var remain := maxi(400, token_budget - sys_tokens)
	var kept := _trim_history(history, remain)
	var messages: Array = []
	messages.append({"role": "system", "content": system_text})
	var depth_secs := registry.at_depth_sections(sections)
	# 按 depth 插入：depth=1 表示紧贴当前句之前（历史末尾之后）；depth=n 插在倒数 n 条之前。
	var inserts: Dictionary = {}
	for s in depth_secs:
		var d := maxi(1, int(s.get("depth", 1)))
		var idx := kept.size() - d
		if idx < 0:
			idx = 0
		if not inserts.has(idx):
			inserts[idx] = PackedStringArray()
		inserts[idx].append(_macro(str(s.get("content", "")), char_name))
	for i in kept.size():
		if inserts.has(i):
			messages.append({"role": "system", "content": "\n".join(inserts[i])})
		var m: Dictionary = kept[i]
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
		"modules": registry.order,
		"sections": sections.size(),
	}
	return {
		"messages": messages,
		"meta": last_meta,
		"first_mes": _macro(str(data.get("first_mes", "")), char_name),
		"alternate_greetings": data.get("alternate_greetings", []),
	}


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
