class_name ChatMemory
extends RefCounted
## 本地记忆：每条玩家消息都写入 user://chat/<id>.json。
## 短期=最近对话；超过预算时先本地压缩，再交给 Worker /v1/summarize 做滚动摘要。
## 长期事实为结构化条目（称呼、喜好、日期、承诺），支持关键词检索。

const DIR := "user://chat"
const SUMMARIZE_AFTER := 24
const KEEP_RECENT := 12
const FACT_BUDGET := 400

var char_id := ""
var data: Dictionary = {}


func open(id: String) -> void:
	char_id = id
	data = {
		"char_id": id,
		"messages": [],
		"summary": "",
		"facts": [],
		"first_meet": 0,
		"updated": 0,
		"pending_llm_summary": false,
		"pending_summary_messages": [],
		"extract_upto": 0,
	}
	var path := _path()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				for k in parsed.keys():
					data[k] = parsed[k]
	data["facts"] = _normalized_facts(data.get("facts", []))
	if int(data.get("first_meet", 0)) <= 0 and not (data.get("messages", []) as Array).is_empty():
		var first: Dictionary = (data["messages"] as Array)[0]
		data["first_meet"] = int(first.get("ts", Time.get_unix_time_from_system()))
	elif int(data.get("first_meet", 0)) <= 0:
		data["first_meet"] = int(Time.get_unix_time_from_system())
		_save()
	else:
		_save()


func append(role: String, content: String, extra: Dictionary = {}) -> Dictionary:
	## 玩家每句话都必须走这里；助手回复同样落盘。
	if char_id == "":
		push_warning("ChatMemory.append without open()")
		return {}
	var msg := {
		"id": _new_id(),
		"role": role,
		"content": content,
		"ts": int(Time.get_unix_time_from_system()),
	}
	for k in extra.keys():
		msg[k] = extra[k]
	var msgs: Array = data.get("messages", [])
	msgs.append(msg)
	data["messages"] = msgs
	data["updated"] = msg["ts"]
	if int(data.get("first_meet", 0)) <= 0:
		data["first_meet"] = msg["ts"]
	_save()
	return msg


func recent(n: int = 24) -> Array:
	var msgs: Array = data.get("messages", [])
	if msgs.size() <= n:
		return msgs.duplicate()
	return msgs.slice(msgs.size() - n, msgs.size())


func all_player_texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for m in data.get("messages", []):
		if str(m.get("role", "")) == "user":
			out.append(str(m.get("content", "")))
	return out


func summary() -> String:
	return str(data.get("summary", ""))


func facts() -> Array:
	return _normalized_facts(data.get("facts", []))


func add_fact(text: String, kind: String = "other", keys: Array = []) -> Dictionary:
	return merge_fact({
		"kind": kind,
		"text": text,
		"keys": keys,
		"source": "manual",
		"scope": "char",
	})


func merge_fact(fact: Dictionary) -> Dictionary:
	var f := normalize_fact(fact)
	if f.is_empty():
		return {}
	f["scope"] = str(f.get("scope", "char"))
	if f.get("char_id", "") == "":
		f["char_id"] = char_id
	var arr: Array = facts()
	for e in arr:
		if str(e.get("text", "")) == str(f.get("text", "")) and str(e.get("kind", "")) == str(f.get("kind", "")):
			return e
	arr.append(f)
	data["facts"] = arr
	_save()
	return f


func merge_facts(incoming: Array) -> int:
	var n := 0
	for item in incoming:
		var f := merge_fact(item if typeof(item) == TYPE_DICTIONARY else {"text": str(item)})
		if not f.is_empty():
			n += 1
	return n


func delete_fact(fact_id: String) -> bool:
	var arr: Array = facts()
	var kept: Array = []
	var removed := false
	for e in arr:
		if str(e.get("id", "")) == fact_id:
			removed = true
		else:
			kept.append(e)
	if removed:
		data["facts"] = kept
		_save()
	return removed


func retrieve(query: String, extra_facts: Array = [], token_budget: int = FACT_BUDGET) -> Array:
	## 关键词检索：命中 query 的事实优先，未命中的低优先级补齐，受词元预算限制。
	var all: Array = facts().duplicate()
	for f in extra_facts:
		var n := normalize_fact(f)
		if not n.is_empty():
			all.append(n)
	var q := query.strip_edges().to_lower()
	var scored: Array = []
	for f in all:
		var score := 0
		if q != "":
			var blob := (str(f.get("text", "")) + " " + " ".join(f.get("keys", []))).to_lower()
			if blob.find(q) >= 0:
				score += 5
			for k in f.get("keys", []):
				var ks := str(k).strip_edges()
				if ks != "" and q.find(ks.to_lower()) >= 0:
					score += 3
			for part in _split_query(q):
				if part.length() >= 2 and blob.find(part) >= 0:
					score += 1
		scored.append({"f": f, "score": score})
	scored.sort_custom(func(a, b):
		return int(a["score"]) > int(b["score"]))
	var kept: Array = []
	var used := 0
	for item in scored:
		var f: Dictionary = item["f"] as Dictionary
		# 无命中时仍注入若干高价值事实（喜好/承诺/日期优先）
		if int(item["score"]) <= 0 and kept.size() >= 8:
			var kind := str(f.get("kind", ""))
			if kind not in ["like", "promise", "date", "name"]:
				continue
		var cost := ChatLorebook.estimate_tokens(str(f.get("text", ""))) + 2
		if kept.is_empty() or used + cost <= token_budget:
			kept.append(f)
			used += cost
	return kept


func format_facts_block(retrieved: Array) -> String:
	if retrieved.is_empty():
		return ""
	var fl: PackedStringArray = []
	for f in retrieved:
		var kind := str(f.get("kind", "other"))
		var labels := {"name": "称呼", "like": "喜好", "date": "日期", "promise": "约定"}
		var label := str(labels.get(kind, "其它"))
		var scope := "共同" if str(f.get("scope", "")) == "shared" else "此伴"
		fl.append("- [%s/%s] %s" % [label, scope, str(f.get("text", ""))])
	return "【长期记得的事】\n" + "\n".join(fl)


func maybe_roll_summary() -> bool:
	## 超过阈值时把更早的对话压成一段摘要，并标记待 Worker 精炼。
	var msgs: Array = data.get("messages", [])
	if msgs.size() < SUMMARIZE_AFTER:
		return false
	var old: Array = msgs.slice(0, msgs.size() - KEEP_RECENT)
	var lines: PackedStringArray = []
	for m in old:
		var role := "玩家" if str(m.get("role", "")) == "user" else "她"
		lines.append("%s：%s" % [role, str(m.get("content", "")).strip_edges()])
	var blob := "\n".join(lines)
	if blob.length() > 800:
		blob = blob.substr(0, 800) + "……"
	var prev := summary()
	if prev != "":
		data["summary"] = prev + "\n" + blob
	else:
		data["summary"] = blob
	if str(data["summary"]).length() > 1600:
		data["summary"] = str(data["summary"]).substr(str(data["summary"]).length() - 1600, 1600)
	data["messages"] = msgs.slice(msgs.size() - KEEP_RECENT, msgs.size())
	data["pending_llm_summary"] = true
	data["pending_summary_messages"] = old
	_save()
	return true


func apply_llm_summary(text: String) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	var prev := summary()
	# 用模型摘要替换刚刚拼上的本地截断稿（若有），并保留更早的摘要头。
	if bool(data.get("pending_llm_summary", false)):
		data["summary"] = t
	elif prev != "":
		data["summary"] = prev + "\n" + t
	else:
		data["summary"] = t
	if str(data["summary"]).length() > 2000:
		data["summary"] = str(data["summary"]).substr(str(data["summary"]).length() - 2000, 2000)
	data["pending_llm_summary"] = false
	data["pending_summary_messages"] = []
	_save()


func needs_llm_summary() -> bool:
	return bool(data.get("pending_llm_summary", false))


func pending_summary_messages() -> Array:
	return data.get("pending_summary_messages", [])


func unextracted_messages() -> Array:
	var msgs: Array = data.get("messages", [])
	var upto := int(data.get("extract_upto", 0))
	if upto <= 0:
		return msgs.duplicate()
	if upto >= msgs.size():
		return []
	return msgs.slice(upto, msgs.size())


func mark_extracted() -> void:
	data["extract_upto"] = (data.get("messages", []) as Array).size()
	_save()


func first_meet_unix() -> int:
	return int(data.get("first_meet", 0))


static func normalize_fact(raw: Variant) -> Dictionary:
	if typeof(raw) == TYPE_STRING:
		var t := str(raw).strip_edges()
		if t == "":
			return {}
		return {
			"id": _fact_id_static(t),
			"kind": "other",
			"text": t,
			"keys": _auto_keys(t),
			"source": "legacy",
			"scope": "char",
			"ts": int(Time.get_unix_time_from_system()),
		}
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var text := str(raw.get("text", "")).strip_edges()
	if text == "":
		return {}
	var kind := str(raw.get("kind", "other")).strip_edges().to_lower()
	if kind not in ["name", "like", "date", "promise", "other"]:
		kind = "other"
	var keys: Array = []
	if typeof(raw.get("keys", [])) == TYPE_ARRAY:
		for k in raw["keys"]:
			var ks := str(k).strip_edges()
			if ks != "" and ks not in keys:
				keys.append(ks)
	if keys.is_empty():
		keys = _auto_keys(text)
	var id := str(raw.get("id", "")).strip_edges()
	if id == "":
		id = _fact_id_static(text + kind)
	return {
		"id": id,
		"kind": kind,
		"text": text,
		"keys": keys,
		"source": str(raw.get("source", "extract")),
		"scope": str(raw.get("scope", "char")),
		"char_id": str(raw.get("char_id", "")),
		"ts": int(raw.get("ts", Time.get_unix_time_from_system())),
	}


static func _auto_keys(text: String) -> Array:
	var keys: Array = []
	for part in text.split("，"):
		for p2 in str(part).split("、"):
			var s := p2.strip_edges()
			s = s.replace("玩家", "").replace("喜欢", "").replace("答应", "")
			s = s.strip_edges()
			if s.length() >= 2 and s.length() <= 12 and s not in keys:
				keys.append(s)
	if keys.is_empty() and text.length() >= 2:
		keys.append(text.substr(0, mini(8, text.length())))
	return keys


static func _fact_id_static(seed: String) -> String:
	return "f-%d-%d" % [abs(seed.hash()), int(Time.get_unix_time_from_system()) % 100000]


func _normalized_facts(arr: Array) -> Array:
	var out: Array = []
	for f in arr:
		var n := normalize_fact(f)
		if not n.is_empty():
			out.append(n)
	return out


func _split_query(q: String) -> PackedStringArray:
	var parts: PackedStringArray = []
	var i := 0
	while i < q.length():
		if i + 1 < q.length():
			parts.append(q.substr(i, 2))
		i += 1
	return parts


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(_abs_dir())
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		push_warning("ChatMemory save failed: " + _path())
		return
	f.store_string(JSON.stringify(data))


func _path() -> String:
	return DIR + "/%s.json" % char_id


func _abs_dir() -> String:
	return OS.get_user_data_dir().path_join("chat")


func _new_id() -> String:
	return "%d-%d" % [Time.get_unix_time_from_system(), randi()]
