class_name ChatLorebook
extends RefCounted
## 世界书：按关键词扫描最近对话，按 insertion_order / priority / token 预算注入。
## 中文默认不做整词切分（SillyTavern 也建议对无空格语言关闭 match whole words）。

const DEFAULT_PATH := "res://data/chat/lorebook.json"

var book: Dictionary = {}
var extra_books: Array = []


func load_default() -> void:
	book = _load_json(DEFAULT_PATH)
	extra_books.clear()


func add_character_book(character_book: Dictionary) -> void:
	if character_book.is_empty():
		return
	extra_books.append(character_book)


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
	var recurse := bool(book.get("recursive_scanning", true))
	var hay := _scan_text(history, user_text, depth)
	var activated: Array = []
	var seen: Dictionary = {}
	_activate_into(entries, hay, activated, seen)
	if recurse:
		var guard := 0
		while guard < 3:
			guard += 1
			var before := activated.size()
			var extra_hay := hay
			for e in activated:
				extra_hay += "\n" + str(e.get("content", ""))
			_activate_into(entries, extra_hay, activated, seen)
			if activated.size() == before:
				break
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
	var parts: PackedStringArray = []
	if user_text.strip_edges() != "":
		parts.append(user_text)
	var start := maxi(0, history.size() - depth)
	for i in range(history.size() - 1, start - 1, -1):
		var m: Dictionary = history[i]
		parts.append(str(m.get("content", "")))
	return "\n".join(parts)


func _activate_into(entries: Array, hay: String, activated: Array, seen: Dictionary) -> void:
	var hay_l := hay.to_lower()
	for e in entries:
		var key := _entry_id(e)
		if seen.has(key):
			continue
		if bool(e.get("constant", false)) or _keys_match(e, hay, hay_l):
			seen[key] = true
			activated.append(e)


func _keys_match(e: Dictionary, hay: String, hay_l: String) -> bool:
	var case_sens := bool(e.get("case_sensitive", false))
	if not _any_key(e.get("keys", []), hay, hay_l, case_sens):
		return false
	if bool(e.get("selective", false)):
		return _any_key(e.get("secondary_keys", []), hay, hay_l, case_sens)
	return true


func _any_key(keys: Variant, hay: String, hay_l: String, case_sens: bool) -> bool:
	if typeof(keys) != TYPE_ARRAY:
		return false
	for k in keys:
		var needle := str(k)
		if needle.is_empty():
			continue
		if case_sens:
			if hay.find(needle) >= 0:
				return true
		else:
			if hay_l.find(needle.to_lower()) >= 0:
				return true
	return false


func _apply_budget(activated: Array, budget: int) -> Array:
	if budget <= 0:
		return activated
	var ranked: Array = activated.duplicate()
	ranked.sort_custom(func(a, b):
		var pw := int(a.get("priority", 100)) - int(b.get("priority", 100))
		if pw != 0:
			return int(a.get("priority", 100)) > int(b.get("priority", 100))
		return int(a.get("insertion_order", 100)) < int(b.get("insertion_order", 100))
	)
	var kept: Array = []
	var used := 0
	for e in ranked:
		var cost := estimate_tokens(str(e.get("content", "")))
		if kept.is_empty() or used + cost <= budget:
			kept.append(e)
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
