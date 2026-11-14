class_name ChatMemory
extends RefCounted
## 本地记忆：每条玩家消息都写入 user://chat/<id>.json。
## 短期=最近对话；滚动摘要钩子（P1 可先本地压缩，P2 再调用 Worker 总结）；长期事实列表。

const DIR := "user://chat"
const SUMMARIZE_AFTER := 24
const KEEP_RECENT := 12

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
	}
	var path := _path()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				for k in parsed.keys():
					data[k] = parsed[k]
	if int(data.get("first_meet", 0)) <= 0 and not (data.get("messages", []) as Array).is_empty():
		var first: Dictionary = (data["messages"] as Array)[0]
		data["first_meet"] = int(first.get("ts", Time.get_unix_time_from_system()))
	elif int(data.get("first_meet", 0)) <= 0:
		data["first_meet"] = int(Time.get_unix_time_from_system())
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
	return data.get("facts", [])


func add_fact(text: String) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	var arr: Array = data.get("facts", [])
	for f in arr:
		if str(f) == t:
			return
	arr.append(t)
	data["facts"] = arr
	_save()


func maybe_roll_summary() -> bool:
	## P1 钩子：超过阈值时把更早的对话压成一段摘要。未接 Worker 时做本地截断式摘要。
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
	_save()
	return true


func first_meet_unix() -> int:
	return int(data.get("first_meet", 0))


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
