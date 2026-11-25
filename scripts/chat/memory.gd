class_name ChatMemory
extends RefCounted
## 本地记忆：每条玩家消息都写入 user://chat/<id>.json。
## 短期=最近对话；超过预算时先本地压缩，再交给 Worker /v1/summarize 做滚动摘要。
## 长期事实为结构化条目（称呼、喜好、日期、承诺），支持关键词检索。

const DIR := "user://chat"
const BACKUP_DIR := "user://chat/backup"
const SCHEMA := 2
const SUMMARIZE_AFTER := 24
const KEEP_RECENT := 12
const FACT_BUDGET := 400
const RECALL_CAP := 6

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


func suppress_text(text: String) -> void:
	## 从回答、摘要和再次抽取里拿掉这句话。聊天原文不删。
	var t := text.strip_edges()
	if t == "":
		return
	_remember_forgotten(t)
	var arr: Array = facts()
	for i in arr.size():
		var e: Dictionary = arr[i]
		if str(e.get("text", "")).strip_edges() != t:
			continue
		if str(e.get("status", "")) == "active":
			_remember_forgotten(str(e.get("evidence", "")))
			e["status"] = "superseded"
			arr[i] = e
	data["facts"] = arr
	data["evidence_summary"] = _build_evidence_summary(data.get("messages", []))
	_save()


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
		var old_text := str(e.get("text", "")).strip_edges()
		var old_ev := str(e.get("evidence", "")).strip_edges()
		e["text"] = t
		e["status"] = "active"
		e["source"] = "manual" if str(e.get("source", "")) != "user" else "user"
		if old_text != t:
			_remember_forgotten(old_text)
			if old_ev != "" and old_ev.find(t) < 0:
				_remember_forgotten(old_ev)
				e["evidence"] = ""
		_stop_forgetting(t)
		if typeof(e.get("keys", [])) != TYPE_ARRAY or (e["keys"] as Array).is_empty() or old_text != t:
			e["keys"] = _auto_keys(t)
		arr[i] = e
		updated = e
	if updated.is_empty():
		return {}
	data["facts"] = arr
	data["evidence_summary"] = _build_evidence_summary(data.get("messages", []))
	_save()
	return updated


func set_pinned(fact_id: String, pinned: bool, profile: ChatProfile = null) -> Dictionary:
	## 钉选只表示「这条已确认，相关问题优先带上」。不会因此告诉其他角色。
	var updated := _mutate_fact(fact_id, {"pinned": pinned})
	if updated.is_empty():
		return {}
	if profile != null and str(updated.get("scope", "")) == "shared":
		profile.mirror_fact(updated)
	return updated


func set_shared(fact_id: String, shared: bool, profile: ChatProfile) -> Dictionary:
	## 共享要另一次明确选择。取消共享时从公共档案拿掉，原话和钉选都留着。
	var updated := _mutate_fact(fact_id, {"scope": "shared" if shared else "char"})
	if updated.is_empty():
		return {}
	if shared:
		profile.mirror_fact(updated)
	else:
		profile.drop_fact(str(updated.get("text", "")), str(updated.get("kind", "")))
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
	var q := query.strip_edges()
	var ql := q.to_lower()
	var scored: Array = []
	for f in all:
		var score := 0
		var kind := str(f.get("kind", ""))
		if ql != "":
			var blob := (str(f.get("text", "")) + " " + " ".join(f.get("keys", []))).to_lower()
			if blob.find(ql) >= 0:
				score += 5
			for k in f.get("keys", []):
				var ks := str(k).strip_edges()
				if ks != "" and ql.find(ks.to_lower()) >= 0:
					score += 3
			for part in _split_query(ql):
				if part.length() >= 2 and blob.find(part) >= 0:
					score += 1
		if _asks_name(q) and kind == "name":
			score += 4
		if _asks_like(q) and kind == "like":
			score += 4
		if _asks_promise(q) and kind == "promise":
			score += 4
		if _asks_date(q) and kind == "date":
			score += 4
		if bool(f.get("pinned", false)) and score > 0:
			score += 3
		if score <= 0:
			continue
		scored.append({"f": f, "score": score, "pinned": 1 if bool(f.get("pinned", false)) else 0})
	scored.sort_custom(func(a, b):
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return int(a["pinned"]) > int(b["pinned"]))
	var kept: Array = []
	var used := 0
	for item in scored:
		if kept.size() >= RECALL_CAP:
			break
		var f: Dictionary = item["f"] as Dictionary
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
		var pin := "已钉选" if bool(f.get("pinned", false)) else "未钉选"
		var evidence := _citable_evidence(f)
		var line := "- [%s/%s/%s] %s" % [label, scope, pin, str(f.get("text", ""))]
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
		"withheld": bool(raw.get("withheld", false)),
		"pinned": bool(raw.get("pinned", false)),
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


func sync_shared(profile: ChatProfile) -> void:
	for f in facts():
		if str(f.get("scope", "")) == "shared" and str(f.get("status", "")) == "active" and not bool(f.get("withheld", false)):
			profile.mirror_fact(f)
	for gone in data.get("forgotten", []):
		for sf in profile.shared_facts():
			if str(sf.get("text", "")) == str(gone) or str(sf.get("evidence", "")) == str(gone):
				profile.delete_shared_fact(str(sf.get("id", "")))


func answer_memory_question(text: String, shared: Array = []) -> String:
	## 纯回忆问句直接引用仍生效的事实。夹着别的实务问题时返回空，仍走角色对话。
	var t := text.strip_edges()
	if t == "" or not _is_memory_question(t) or _has_unrelated_clause(t):
		return ""
	var parts: PackedStringArray = []
	if _asks_name(t):
		parts.append(_name_answer(shared))
	if _asks_like(t):
		parts.append(_like_answer())
	if _asks_promise(t):
		parts.append(_kind_answer("promise", "约定"))
	if _asks_date(t):
		parts.append(_kind_answer("date", "日期"))
	var keyed := _keyed_recall(t)
	if keyed != "":
		parts.append(keyed)
	return "\n".join(parts)


func model_user_line(content: String) -> String:
	## 给模型看的副本。存档里的原句不动，已删除或已更正的说法不原样送回去。
	var t := content.strip_edges()
	if t == "" or not _line_forgotten(t):
		return content
	return "〔这句原话还在本机记录里，可以打开记忆查看。其中的说法已经删除或更正，不要当成现在仍成立。〕"


func observe_user_line(text: String) -> void:
	var t := text.strip_edges()
	if t == "" or _is_sensitive(t) or _is_memory_question(t):
		return
	var scope := "shared" if _explicit_share(t) else "char"
	if _is_name_refusal(t):
		_supersede_active("name", "")
		_add_withheld(t, scope)
		return
	var dislike := _clause_after(t, "我不喜欢")
	if dislike == "":
		dislike = _clause_after(t, "我讨厌")
	if dislike != "":
		_supersede_active("like", dislike)
		_add_observed("like", "不喜欢" + dislike, t, scope)
		return
	if _quoted_hearsay(t):
		return
	var name := _clause_after(t, "改口叫我")
	if name == "":
		name = _clause_after(t, "改叫我")
	if name == "":
		name = _clause_after(t, "以后叫我")
	if name == "":
		name = _clause_after(t, "我的名字是")
	if name == "":
		name = _clause_after(t, "请叫我")
	if name == "":
		name = _clause_after(t, "我叫")
	if _is_question_word(name):
		name = ""
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
	var proposed := str(f.get("text", "")).strip_edges()
	if not _matches_forgotten(proposed):
		for said in user_texts:
			var line := said.strip_edges()
			if _line_forgotten(line):
				continue
			if line.find(proposed) >= 0 or _keys_in_text(f, line):
				evidence = line
				break
	f["source"] = "extract"
	f["scope"] = "char"
	f["pinned"] = false
	if evidence == "" or _matches_forgotten(proposed):
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
	_stop_forgetting(clean)
	_stop_forgetting(evidence)
	merge_fact({
		"kind": kind,
		"text": clean,
		"keys": _auto_keys(clean),
		"source": "user",
		"status": "active",
		"evidence": evidence.strip_edges(),
		"scope": scope,
		"withheld": false,
	})


func _add_withheld(evidence: String, scope: String) -> void:
	merge_fact({
		"kind": "name",
		"text": "不愿透露",
		"keys": ["名字"],
		"source": "user",
		"status": "active",
		"evidence": evidence.strip_edges(),
		"scope": scope,
		"withheld": true,
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
	if bool(f.get("withheld", false)):
		return false
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


func _stop_forgetting(text: String) -> void:
	var s := text.strip_edges()
	if s == "":
		return
	var kept: Array = []
	for item in data.get("forgotten", []):
		if str(item).strip_edges() != s:
			kept.append(item)
	data["forgotten"] = kept


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
	if int(data.get("schema", 0)) < SCHEMA:
		_backup_once()
		data["schema"] = SCHEMA
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


func _is_memory_question(text: String) -> bool:
	return _clause_is_recall(text)


func _clause_is_recall(text: String) -> bool:
	if _asks_name(text) or _asks_like(text) or _asks_promise(text) or _asks_date(text):
		return true
	return _keyed_recall(text) != ""


func _asks_name(text: String) -> bool:
	for key in ["我叫什么", "我叫啥", "我的名字是什么", "我的名字叫什么", "我的名字呢", "怎么称呼我", "如何称呼我", "记得我的名字", "记得我叫什么", "喊我什么", "叫我什么"]:
		if text.find(key) >= 0:
			return true
	return false


func _asks_like(text: String) -> bool:
	return text.find("喜欢什么") >= 0 or text.find("喜欢做什么") >= 0 or text.find("喜欢啥") >= 0


func _asks_promise(text: String) -> bool:
	return text.find("什么约定") >= 0 or text.find("约好了什么") >= 0 or text.find("约好什么") >= 0 or text.find("答应过什么") >= 0 or text.find("说好了什么") >= 0 or text.find("我们的约定") >= 0


func _asks_date(text: String) -> bool:
	return text.find("生日") >= 0 or text.find("什么日子") >= 0 or text.find("哪一天") >= 0


func _has_unrelated_clause(text: String) -> bool:
	var parts := text.replace("？", "，").replace("?", "，").replace("。", "，").replace("！", "，").replace("!", "，").split("，")
	for part in parts:
		var clause := str(part).strip_edges()
		if clause == "" or clause == "吗":
			continue
		if _clause_is_recall(clause):
			continue
		if clause in ["你还记得", "还记得", "请问", "那"]:
			continue
		return true
	return false


func _is_name_refusal(text: String) -> bool:
	var bare := text.replace("。", "").replace("！", "").replace("？", "").replace("!", "").replace("?", "").strip_edges()
	if bare in ["不想告诉你", "先不告诉你", "不告诉你", "不想说"]:
		return true
	return text.find("名字") >= 0 and (text.find("不想") >= 0 or text.find("别问") >= 0 or text.find("保密") >= 0 or text.find("不告诉") >= 0)


func _is_question_word(name: String) -> bool:
	return name in ["什么", "啥", "谁", "哪个", "哪位", "吗"]


func _name_answer(shared: Array) -> String:
	if _has_withheld(facts()):
		return "你跟我说过，先不想告诉我名字。"
	var fact := _latest_named(facts())
	if fact.is_empty():
		fact = _latest_named(shared)
	if fact.is_empty():
		return "你还没有告诉我怎么称呼你。"
	return _cite_name(fact)


func _like_answer() -> String:
	var likes: Array = []
	var dislikes: Array = []
	for f in facts():
		if not _cited_fact(f) or str(f.get("kind", "")) != "like":
			continue
		if str(f.get("text", "")).begins_with("不喜欢"):
			dislikes.append(f)
		else:
			likes.append(f)
	if likes.is_empty() and dislikes.is_empty():
		return "你还没有告诉我你喜欢什么。"
	var lines: PackedStringArray = []
	for f in likes:
		lines.append(_cite_like(f))
	for f in dislikes:
		lines.append(_cite_like(f))
	return "\n".join(lines)


func _cite_name(fact: Dictionary) -> String:
	var name := str(fact.get("text", "")).strip_edges()
	var evidence := _citable_evidence(fact)
	if evidence != "":
		return "你告诉过我，叫「%s」。原话是：「%s」。" % [name, evidence]
	return "你后来记下的称呼是「%s」。" % name


func _cite_like(fact: Dictionary) -> String:
	return _cite_fact(fact)


func _cite_fact(fact: Dictionary) -> String:
	var text := str(fact.get("text", "")).strip_edges()
	var evidence := _citable_evidence(fact)
	if evidence != "":
		return "现在仍算数的是「%s」。原话是：「%s」。" % [text, evidence]
	return "现在仍算数的是「%s」。" % text


func _citable_evidence(fact: Dictionary) -> String:
	var evidence := str(fact.get("evidence", "")).strip_edges()
	var text := str(fact.get("text", "")).strip_edges()
	if evidence == "" or _matches_forgotten(evidence):
		return ""
	if text != "" and evidence.find(text) < 0:
		return ""
	return evidence


func _kind_answer(kind: String, label: String) -> String:
	var lines: PackedStringArray = []
	for f in facts():
		if not _cited_fact(f) or str(f.get("kind", "")) != kind:
			continue
		lines.append(_cite_fact(f))
	if lines.is_empty():
		return "你还没有告诉我现在仍算数的%s。" % label
	return "\n".join(lines)


func _keyed_recall(text: String) -> String:
	if text.find("怎么") >= 0 or text.find("如何") >= 0 or text.find("为什么") >= 0:
		return ""
	if text.find("记得") < 0 and text.find("之前说") < 0 and text.find("说过") < 0:
		return ""
	var lines: PackedStringArray = []
	for f in facts():
		if not _cited_fact(f) or not _fact_mentioned(f, text):
			continue
		if _asks_name(text) and str(f.get("kind", "")) == "name":
			continue
		if _asks_like(text) and str(f.get("kind", "")) == "like":
			continue
		if _asks_promise(text) and str(f.get("kind", "")) == "promise":
			continue
		if _asks_date(text) and str(f.get("kind", "")) == "date":
			continue
		var line := _cite_fact(f)
		if line not in lines:
			lines.append(line)
	return "\n".join(lines)


func _fact_mentioned(fact: Dictionary, text: String) -> bool:
	var body := str(fact.get("text", "")).strip_edges()
	if body.length() >= 2 and text.find(body) >= 0:
		return true
	for k in fact.get("keys", []):
		var ks := str(k).strip_edges()
		if ks.length() >= 2 and text.find(ks) >= 0:
			return true
	return false


func _mutate_fact(fact_id: String, fields: Dictionary) -> Dictionary:
	var arr: Array = facts()
	var updated := {}
	for i in arr.size():
		var e: Dictionary = arr[i]
		if str(e.get("id", "")) != fact_id:
			continue
		for k in fields.keys():
			e[k] = fields[k]
		arr[i] = e
		updated = e
	if updated.is_empty():
		return {}
	data["facts"] = arr
	_save()
	return updated


func _backup_once() -> void:
	var msgs: Array = data.get("messages", [])
	var fact_arr: Array = data.get("facts", [])
	if msgs.is_empty() and fact_arr.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("chat/backup"))
	var dest := BACKUP_DIR + "/%s.json" % char_id
	if FileAccess.file_exists(dest):
		return
	var src := _path()
	if not FileAccess.file_exists(src):
		return
	var raw := FileAccess.get_file_as_string(src)
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f:
		f.store_string(raw)


func _has_withheld(arr: Array) -> bool:
	for f in arr:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = f
		if bool(item.get("withheld", false)) and str(item.get("status", "")) == "active" and str(item.get("kind", "")) == "name":
			return true
	return false


func _latest_named(arr: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_ts := -1
	for f in arr:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = f
		if not _cited_fact(item) or str(item.get("kind", "")) != "name" or bool(item.get("withheld", false)):
			continue
		var ts := int(item.get("ts", 0))
		if ts >= best_ts:
			best = item
			best_ts = ts
	return best


func _cited_fact(f: Dictionary) -> bool:
	if str(f.get("status", "")) != "active":
		return false
	if bool(f.get("withheld", false)):
		return false
	var source := str(f.get("source", ""))
	if source == "extract" and str(f.get("evidence", "")).strip_edges() == "":
		return false
	if source == "legacy":
		return false
	return not _matches_forgotten(str(f.get("text", ""))) and not _matches_forgotten(str(f.get("evidence", "")))


func _matches_forgotten(text: String) -> bool:
	var t := text.strip_edges()
	if t == "":
		return false
	for item in data.get("forgotten", []):
		if str(item).strip_edges() == t:
			return true
	return false


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
