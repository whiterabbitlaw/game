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
	_migrate_loaded()
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
	if role == "user":
		observe_user_line(content)
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
	## 回答时只用由玩家原话整理的摘要。旧的模型摘要留在 legacy_summary，不注入。
	return str(data.get("evidence_summary", ""))


func legacy_summary() -> String:
	return str(data.get("legacy_summary", ""))


func summary_model() -> String:
	return str(data.get("summary_model", ""))


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
			var ev := str(e.get("evidence", "")).strip_edges()
			var gone := str(e.get("text", "")).strip_edges()
			if ev != "":
				_remember_forgotten(ev)
			if gone != "":
				_remember_forgotten(gone)
		else:
			kept.append(e)
	if removed:
		data["facts"] = kept
		data["evidence_summary"] = _build_evidence_summary(data.get("messages", []))
		_save()
	return removed


func update_fact(fact_id: String, text: String) -> Dictionary:
	var t := text.strip_edges()
	if t == "":
		return {}
	var arr: Array = facts()
	var updated := {}
	for i in arr.size():
		var e: Dictionary = arr[i]
		if str(e.get("id", "")) != fact_id:
			continue
		e["text"] = t
		e["status"] = "active"
		e["source"] = "manual" if str(e.get("source", "")) != "user" else "user"
		if typeof(e.get("keys", [])) != TYPE_ARRAY or (e["keys"] as Array).is_empty():
			e["keys"] = _auto_keys(t)
		arr[i] = e
		updated = e
	if updated.is_empty():
		return {}
	data["facts"] = arr
	data["evidence_summary"] = _build_evidence_summary(data.get("messages", []))
	_save()
	return updated


func clear_messages() -> void:
	## 只有玩家明确要删对话时才清原话。事实另行删除。
	data["messages"] = []
	data["evidence_summary"] = ""
	data["extract_upto"] = 0
	_save()


func active_facts() -> Array:
	var out: Array = []
	for f in facts():
		if not _fact_answers(f):
			continue
		out.append(f)
	return out


func retrieve(query: String, extra_facts: Array = [], token_budget: int = FACT_BUDGET) -> Array:
	## 关键词检索：只取仍生效的事实。未核对和已更正的不参与回答。
	var all: Array = active_facts()
	for f in extra_facts:
		var n := normalize_fact(f)
		if not n.is_empty() and _fact_answers(n):
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
		var evidence := str(f.get("evidence", "")).strip_edges()
		var line := "- [%s/%s] %s" % [label, scope, str(f.get("text", ""))]
		if evidence != "":
			line += "（玩家原话：「%s」）" % evidence
		fl.append(line)
	return "【长期记得的事。只包括玩家明确说过、且没有更正或删除的。她编的话不算。】\n" + "\n".join(fl)


func maybe_roll_summary() -> bool:
	## 对话变长时整理「回答用摘要」。原话留在 messages 里，不截断、不删。
	var msgs: Array = data.get("messages", [])
	if msgs.size() < SUMMARIZE_AFTER:
		return false
	data["evidence_summary"] = _build_evidence_summary(msgs)
	data["summary_kind"] = "evidence"
	data["pending_llm_summary"] = false
	data["pending_summary_messages"] = []
	_save()
	return str(data["evidence_summary"]).strip_edges() != ""


func apply_llm_summary(text: String) -> void:
	## 线上摘要只留档，不覆盖玩家原话整理出的摘要，避免旧稿把删掉的事实写回来。
	var t := text.strip_edges()
	if t == "":
		return
	data["summary_model"] = t
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
	var raw_keys: Variant = raw.get("keys", [])
	if typeof(raw_keys) == TYPE_ARRAY:
		for k in raw_keys:
			var ks := str(k).strip_edges()
			if ks != "" and ks not in keys:
				keys.append(ks)
	if keys.is_empty():
		keys = _auto_keys(text)
	var id := str(raw.get("id", "")).strip_edges()
	if id == "":
		id = _fact_id_static(text + kind)
	var source := str(raw.get("source", "")).strip_edges()
	if source == "":
		source = "manual"
	var evidence := str(raw.get("evidence", "")).strip_edges()
	var status := str(raw.get("status", "")).strip_edges()
	if status not in ["active", "superseded", "unverified"]:
		if source in ["extract", "legacy"] and evidence == "":
			status = "unverified"
		else:
			status = "active"
	return {
		"id": id,
		"kind": kind,
		"text": text,
		"keys": keys,
		"source": source,
		"status": status,
		"evidence": evidence,
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


func observe_user_line(text: String) -> void:
	var t := text.strip_edges()
	if t == "" or _is_sensitive(t):
		return
	var scope := "shared" if _explicit_share(t) else "char"
	var dislike := _clause_after(t, "我不喜欢")
	if dislike == "":
		dislike = _clause_after(t, "我讨厌")
	if dislike != "":
		_supersede_active("like", dislike)
		_add_observed("like", "不喜欢" + dislike, t, scope)
		return
	if _quoted_hearsay(t):
		return
	var name := _clause_after(t, "我叫")
	if name == "":
		name = _clause_after(t, "我的名字是")
	if name == "":
		name = _clause_after(t, "请叫我")
	if name != "":
		_supersede_active("name", "")
		_add_observed("name", name, t, scope)
		return
	var like := _clause_after(t, "我喜欢")
	if like != "":
		_supersede_active("like", like)
		_add_observed("like", "喜欢" + like, t, scope)
		return
	if t.begins_with("记住") or t.find("请记住") >= 0:
		_add_observed("other", t, t, scope)


func accept_extracted(fact: Dictionary, user_texts: PackedStringArray) -> Dictionary:
	## 提取结果必须能在玩家原话里找到，否则只标成未核对，不拿来回答。
	var f := normalize_fact(fact)
	if f.is_empty():
		return {}
	if _is_sensitive(str(f.get("text", ""))):
		return {}
	var evidence := ""
	for said in user_texts:
		if said.find(str(f.get("text", ""))) >= 0 or _keys_in_text(f, said):
			evidence = said.strip_edges()
			break
	f["source"] = "extract"
	f["scope"] = "char"
	if evidence == "":
		f["status"] = "unverified"
		f["evidence"] = ""
	else:
		f["status"] = "active"
		f["evidence"] = evidence
	return merge_fact(f)


func _add_observed(kind: String, text: String, evidence: String, scope: String) -> void:
	var clean := text.strip_edges().trim_suffix("了")
	if clean == "":
		return
	merge_fact({
		"kind": kind,
		"text": clean,
		"keys": _auto_keys(clean),
		"source": "user",
		"status": "active",
		"evidence": evidence.strip_edges(),
		"scope": scope,
	})


func _supersede_active(kind: String, needle: String) -> void:
	var arr: Array = facts()
	var changed := false
	for i in arr.size():
		var e: Dictionary = arr[i]
		if str(e.get("kind", "")) != kind or str(e.get("status", "")) != "active":
			continue
		if needle != "" and str(e.get("text", "")).find(needle) < 0 and str(e.get("evidence", "")).find(needle) < 0:
			continue
		e["status"] = "superseded"
		_remember_forgotten(str(e.get("evidence", "")))
		_remember_forgotten(str(e.get("text", "")))
		arr[i] = e
		changed = true
	if changed:
		data["facts"] = arr


func _fact_answers(f: Dictionary) -> bool:
	if str(f.get("status", "active")) != "active":
		return false
	var forgotten: Array = data.get("forgotten", [])
	var text := str(f.get("text", "")).strip_edges()
	var evidence := str(f.get("evidence", "")).strip_edges()
	for item in forgotten:
		var s := str(item).strip_edges()
		if s != "" and (s == text or s == evidence):
			return false
	return true


func _remember_forgotten(text: String) -> void:
	var s := text.strip_edges()
	if s == "":
		return
	var arr: Array = data.get("forgotten", [])
	if s not in arr:
		arr.append(s)
	data["forgotten"] = arr


func _build_evidence_summary(msgs: Array) -> String:
	var older: Array = []
	if msgs.size() > KEEP_RECENT:
		older = msgs.slice(0, msgs.size() - KEEP_RECENT)
	var lines: PackedStringArray = []
	for m in older:
		if str(m.get("role", "")) != "user":
			continue
		var content := str(m.get("content", "")).strip_edges()
		if content == "" or _line_forgotten(content):
			continue
		lines.append("「%s」" % content)
	if lines.is_empty():
		return "更早的原话仍完整留在本机。没有额外确认过的事。"
	return "更早的玩家原话，整句保留：\n" + "\n".join(lines)


func _line_forgotten(content: String) -> bool:
	var t := content.strip_edges()
	for item in data.get("forgotten", []):
		var s := str(item).strip_edges()
		if s != "" and s == t:
			return true
	return false


func _migrate_loaded() -> void:
	if str(data.get("summary_kind", "")) != "evidence":
		var old := str(data.get("summary", "")).strip_edges()
		if old != "" and str(data.get("legacy_summary", "")).strip_edges() == "":
			data["legacy_summary"] = old
		data["summary"] = ""
		data["summary_kind"] = "evidence"
		data["pending_llm_summary"] = false
		data["pending_summary_messages"] = []
	if str(data.get("evidence_summary", "")) == "" and not (data.get("messages", []) as Array).is_empty():
		data["evidence_summary"] = _build_evidence_summary(data.get("messages", []))
	var facts: Array = data.get("facts", [])
	var changed := false
	for i in facts.size():
		if typeof(facts[i]) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = facts[i]
		var source := str(f.get("source", ""))
		var evidence := str(f.get("evidence", "")).strip_edges()
		var status := str(f.get("status", ""))
		if status == "" and source in ["extract", "legacy"] and evidence == "":
			f["status"] = "unverified"
			facts[i] = f
			changed = true
	if changed:
		data["facts"] = facts


func _is_sensitive(text: String) -> bool:
	for w in ["密码", "密钥", "身份证", "银行卡", "api key", "apikey"]:
		if text.to_lower().find(w) >= 0:
			return true
	return false


func _explicit_share(text: String) -> bool:
	return text.find("告诉大家") >= 0 or text.find("每位伙伴") >= 0 or text.find("所有伙伴") >= 0


func _quoted_hearsay(text: String) -> bool:
	return text.find("她说") >= 0 or text.find("你说") >= 0 or text.find("据说") >= 0


func _clause_after(text: String, marker: String) -> String:
	var at := text.find(marker)
	if at < 0:
		return ""
	if marker == "我喜欢" and at > 0 and text.substr(at - 1, 1) == "不":
		return ""
	var rest := text.substr(at + marker.length()).strip_edges()
	for stop in ["，", "。", "！", "？", "!", "?", "\n", "；"]:
		var cut := rest.find(stop)
		if cut >= 0:
			rest = rest.substr(0, cut)
	rest = rest.strip_edges().trim_prefix("是").trim_suffix("了")
	if rest.length() < 1 or rest.length() > 24:
		return ""
	return rest


func _keys_in_text(fact: Dictionary, said: String) -> bool:
	var hits := 0
	for k in fact.get("keys", []):
		var ks := str(k).strip_edges()
		if ks.length() >= 2 and said.find(ks) >= 0:
			hits += 1
	return hits >= 1 and said.find("我") >= 0


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
