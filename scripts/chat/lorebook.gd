class_name ChatLorebook
extends RefCounted
## 世界书：按关键词扫描最近对话，按 insertion_order / priority / token 预算注入。
## 中文默认不做整词切分（SillyTavern 也建议对无空格语言关闭 match whole words）。

const DEFAULT_PATH := "res://data/chat/lorebook.json"

const CHAR_LORE_DIR := "res://data/chat/lore/"

var book: Dictionary = {}
var extra_books: Array = []
var force_probability := false  # 测试时为 true 则忽略 probability 随机


func load_default() -> void:
	book = _load_json(DEFAULT_PATH)
	extra_books.clear()


func add_character_book(character_book: Dictionary) -> void:
	if character_book.is_empty():
		return
	extra_books.append(character_book)


func load_character(char_id: String) -> void:
	## 额外的角色世界书文件（与角色卡内 character_book 并存）。文件不存在则跳过。
	if char_id.strip_edges() == "":
		return
	var path := CHAR_LORE_DIR + char_id + ".json"
	if not FileAccess.file_exists(path):
		return
	var extra := _load_json(path)
	if not extra.is_empty():
		add_character_book(extra)


func scan(history: Array, user_text: String = "", scan_depth_override: int = -1) -> Array:
	## 返回已激活、已按预算裁剪的条目数组（Dictionary）。
	var entries: Array = []
	_collect_entries(book, entries)
	for b in extra_books:
		_collect_entries(b, entries)
	var depth := scan_depth_override
	if depth < 0:
		depth = int(book.get("scan_depth", 8))
	var budget := int(book.get("token_budget", 800))
	for b in extra_books:
		budget += int(b.get("token_budget", 0))
	var hay := _scan_text(history, user_text, depth)
	var activated: Array = []
	var seen: Dictionary = {}
	## 只按玩家的话触发。世界书正文不再拿回去二次触发，避免条目互相叫醒。
	_activate_into(entries, hay, activated, seen, user_text)
	return _apply_budget(activated, budget)


func contents_for_position(activated: Array, position: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var filtered: Array = []
	for e in activated:
		var pos := str(e.get("position", "after_char"))
		if pos == position or (position == "after_char" and pos == ""):
			filtered.append(e)
	filtered.sort_custom(func(a, b):
		return int(a.get("insertion_order", 100)) < int(b.get("insertion_order", 100))
	)
	for e in filtered:
		var c := str(e.get("content", "")).strip_edges()
		if c != "":
			out.append(c)
	return out


static func estimate_tokens(text: String) -> int:
	## 中文约 1.5 字/词元，英文约 4 字符/词元；取偏保守的估计。
	if text.is_empty():
		return 0
	var cjk := 0
	var other := 0
	for i in text.length():
		var cp := text.unicode_at(i)
		if cp >= 0x2E80 and cp <= 0x9FFF:
			cjk += 1
		elif cp > 32:
			other += 1
	return maxi(1, int(ceil(cjk / 1.5 + other / 4.0)))


func _collect_entries(src: Dictionary, into: Array) -> void:
	if src.is_empty():
		return
	var arr: Array = src.get("entries", [])
	for e in arr:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if not bool(e.get("enabled", true)):
			continue
		into.append(e)


func _scan_text(history: Array, user_text: String, depth: int) -> String:
	## 深度仍按最近若干条消息计，但只采用玩家说的内容。
	## 她自己反复讲的景物不能再把同一条世界书触发回来。
	var parts: PackedStringArray = []
	if user_text.strip_edges() != "":
		parts.append(user_text)
	var start := maxi(0, history.size() - depth)
	for i in range(start, history.size()):
		var m: Dictionary = history[i]
		if str(m.get("role", "")) != "user":
			continue
		parts.append(str(m.get("content", "")))
	return "\n".join(parts)


func _activate_into(entries: Array, hay: String, activated: Array, seen: Dictionary, current: String) -> void:
	var hay_l := hay.to_lower()
	var now := current.strip_edges()
	var now_l := now.to_lower()
	for e in entries:
		var key := _entry_id(e)
		if seen.has(key):
			continue
		var hit := bool(e.get("constant", false)) or _keys_match(e, hay, hay_l)
		if not hit or not _passes_probability(e):
			continue
		var copy: Dictionary = e.duplicate(true)
		copy["_match_now"] = now != "" and (bool(e.get("constant", false)) == false) and _keys_match(e, now, now_l)
		seen[key] = true
		activated.append(copy)


func _passes_probability(e: Dictionary) -> bool:
	var p := int(e.get("probability", 100))
	if p >= 100:
		return true
	if p <= 0:
		return false
	if force_probability:
		return true
	return randi() % 100 < p


func _wants_whole_words(e: Dictionary) -> bool:
	if e.has("match_whole_words"):
		return bool(e.get("match_whole_words"))
	var ext: Variant = book.get("extensions", {})
	if typeof(ext) == TYPE_DICTIONARY:
		var q: Variant = ext.get("qiyunju", {})
		if typeof(q) == TYPE_DICTIONARY:
			return bool(q.get("match_whole_words", false))
	return false


func _keys_match(e: Dictionary, hay: String, hay_l: String) -> bool:
	var case_sens := bool(e.get("case_sensitive", false))
	var whole := _wants_whole_words(e)
	var primary := _any_key(e.get("keys", []), hay, hay_l, case_sens, whole)
	var logic := str(e.get("selective_logic", "")).strip_edges().to_lower()
	var selective := bool(e.get("selective", false)) or logic != ""
	if not selective:
		return primary
	if logic == "":
		logic = "and_any"
	match logic:
		"or":
			return primary or _any_key(e.get("secondary_keys", []), hay, hay_l, case_sens, whole)
		"not", "not_any", "and_not":
			return primary and not _any_key(e.get("secondary_keys", []), hay, hay_l, case_sens, whole)
		"and_all", "and":
			return primary and _all_keys(e.get("secondary_keys", []), hay, hay_l, case_sens, whole)
		"not_all":
			return primary and not _all_keys(e.get("secondary_keys", []), hay, hay_l, case_sens, whole)
		_:
			# and_any：主键任一命中，且副键任一命中（SillyTavern 默认）
			return primary and _any_key(e.get("secondary_keys", []), hay, hay_l, case_sens, whole)


func _contains(hay: String, hay_l: String, needle: String, case_sens: bool, whole: bool) -> bool:
	if needle.is_empty():
		return false
	if whole:
		return _whole_word(hay if case_sens else hay_l, needle if case_sens else needle.to_lower())
	if case_sens:
		return hay.find(needle) >= 0
	return hay_l.find(needle.to_lower()) >= 0


func _is_word_char(cp: int) -> bool:
	return (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) or cp == 95


func _whole_word(hay: String, needle: String) -> bool:
	var i := 0
	while true:
		var at := hay.find(needle, i)
		if at < 0:
			return false
		var left_ok := at == 0 or not _is_word_char(hay.unicode_at(at - 1))
		var right := at + needle.length()
		var right_ok := right >= hay.length() or not _is_word_char(hay.unicode_at(right))
		if left_ok and right_ok:
			return true
		i = at + 1
	return false


func _any_key(keys: Variant, hay: String, hay_l: String, case_sens: bool, whole: bool = false) -> bool:
	if typeof(keys) != TYPE_ARRAY:
		return false
	for k in keys:
		if _contains(hay, hay_l, str(k), case_sens, whole):
			return true
	return false


func _all_keys(keys: Variant, hay: String, hay_l: String, case_sens: bool, whole: bool = false) -> bool:
	if typeof(keys) != TYPE_ARRAY or (keys as Array).is_empty():
		return false
	for k in keys:
		if not _contains(hay, hay_l, str(k), case_sens, whole):
			return false
	return true


func _apply_budget(activated: Array, budget: int) -> Array:
	if budget <= 0:
		return activated
	var ranked: Array = activated.duplicate()
	ranked.sort_custom(func(a, b):
		var am := 1 if bool(a.get("_match_now", false)) else 0
		var bm := 1 if bool(b.get("_match_now", false)) else 0
		if am != bm:
			return am > bm
		var pw := int(a.get("priority", 100)) - int(b.get("priority", 100))
		if pw != 0:
			return int(a.get("priority", 100)) > int(b.get("priority", 100))
		return int(a.get("insertion_order", 100)) < int(b.get("insertion_order", 100))
	)
	var kept: Array = []
	var used := 0
	var seen_body := {}
	for e in ranked:
		var body := str(e.get("content", "")).strip_edges()
		if body != "" and seen_body.has(body):
			continue
		var cost := estimate_tokens(body)
		if kept.is_empty() or used + cost <= budget:
			kept.append(e)
			if body != "":
				seen_body[body] = true
			used += cost
	return kept


func _entry_id(e: Dictionary) -> String:
	if e.has("id"):
		return "id:%s" % str(e.get("id"))
	return "k:%s|%s" % [str(e.get("name", "")), str(e.get("keys", []))]


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ChatLorebook missing: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
