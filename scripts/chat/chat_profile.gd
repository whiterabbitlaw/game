class_name ChatProfile
extends RefCounted
## 玩家共享档案与本机人设覆盖。只写 user://，覆盖 res:// 的草稿 persona。
## 长期事实里 scope=shared 的条目也存在这里，供所有角色检索。

const LOCAL_PATH := "user://chat/persona_local.json"
const PROFILE_PATH := "user://chat/profile.json"
const PERSONA_RES := "res://data/chat/persona.json"

var local_path := LOCAL_PATH
var profile_path := PROFILE_PATH


func load_persona() -> Dictionary:
	var base := _load_json(PERSONA_RES)
	var loc := _load_json(local_path)
	for k in loc.keys():
		if k == "facts":
			continue
		base[k] = loc[k]
	return base


func save_persona(fields: Dictionary) -> void:
	var loc := _load_json(local_path)
	for k in ["name", "description", "personality", "birthday", "notes"]:
		if fields.has(k):
			loc[k] = fields[k]
	_save_json(local_path, loc)


func load_profile() -> Dictionary:
	var p := _load_json(profile_path)
	if not p.has("facts"):
		p["facts"] = []
	if not p.has("asked_birthday"):
		p["asked_birthday"] = false
	return p


func save_profile(profile: Dictionary) -> void:
	_save_json(profile_path, profile)


func shared_facts() -> Array:
	return _normalize_facts(load_profile().get("facts", []))


func add_shared_fact(fact: Dictionary) -> Dictionary:
	return mirror_fact(fact)


func mirror_fact(fact: Dictionary) -> Dictionary:
	## 把一条已经存在的事实抄进公共档案。不改它的钉选含义，只标明范围是共享。
	var f := ChatMemory.normalize_fact(fact)
	if f.is_empty():
		return {}
	f["scope"] = "shared"
	var p := load_profile()
	var arr: Array = _normalize_facts(p.get("facts", []))
	for i in arr.size():
		var e: Dictionary = arr[i]
		if str(e.get("id", "")) == str(f.get("id", "")) or (str(e.get("text", "")) == str(f.get("text", "")) and str(e.get("kind", "")) == str(f.get("kind", ""))):
			f["id"] = str(e.get("id", f.get("id", "")))
			arr[i] = f
			p["facts"] = arr
			save_profile(p)
			return f
	arr.append(f)
	p["facts"] = arr
	save_profile(p)
	return f


func drop_fact(text: String, kind: String) -> void:
	var p := load_profile()
	var arr: Array = _normalize_facts(p.get("facts", []))
	var kept: Array = []
	for e in arr:
		if str(e.get("text", "")) == text and str(e.get("kind", "")) == kind:
			continue
		kept.append(e)
	p["facts"] = kept
	save_profile(p)
	_make_private_in_saves(text, kind)


func _make_private_in_saves(text: String, kind: String) -> void:
	## 取消共享时只改范围。不删除任何角色的聊天原文，也不改文件名。
	var dir := DirAccess.open(OS.get_user_data_dir().path_join("chat"))
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json") and name != "profile.json" and name != "persona_local.json":
			var path := "user://chat/%s" % name
			var data := _load_json(path)
			var facts: Array = data.get("facts", [])
			var changed := false
			for i in facts.size():
				if typeof(facts[i]) != TYPE_DICTIONARY:
					continue
				var e: Dictionary = facts[i]
				if str(e.get("text", "")) == text and str(e.get("kind", "")) == kind and str(e.get("scope", "")) == "shared":
					e["scope"] = "char"
					facts[i] = e
					changed = true
			if changed:
				data["facts"] = facts
				_save_json(path, data)
		name = dir.get_next()
	dir.list_dir_end()


func delete_shared_fact(fact_id: String) -> bool:
	var p := load_profile()
	var arr: Array = _normalize_facts(p.get("facts", []))
	var kept: Array = []
	var removed := false
	for e in arr:
		if str(e.get("id", "")) == fact_id:
			removed = true
		else:
			kept.append(e)
	if removed:
		p["facts"] = kept
		save_profile(p)
	return removed


func apply_birthday(text: String, raw_date: String = "") -> void:
	var loc := _load_json(local_path)
	if str(loc.get("birthday", "")).strip_edges() != "":
		return
	var d := raw_date.strip_edges()
	if d == "":
		d = _guess_date(text)
	if d == "":
		return
	loc["birthday"] = d
	_save_json(local_path, loc)


func mark_asked_birthday() -> void:
	var p := load_profile()
	p["asked_birthday"] = true
	save_profile(p)


func asked_birthday() -> bool:
	return bool(load_profile().get("asked_birthday", false))


func _guess_date(text: String) -> String:
	var t := text.strip_edges()
	var r := RegEx.new()
	r.compile("((?:19|20)\\d{2})[-./年](\\d{1,2})[-./月](\\d{1,2})")
	var m := r.search(t)
	if m:
		return "%s-%02d-%02d" % [m.get_string(1), int(m.get_string(2)), int(m.get_string(3))]
	r.compile("(\\d{1,2})[-./月](\\d{1,2})")
	m = r.search(t)
	if m:
		return "%02d-%02d" % [int(m.get_string(1)), int(m.get_string(2))]
	return ""


func _normalize_facts(arr: Array) -> Array:
	var out: Array = []
	for f in arr:
		var n := ChatMemory.normalize_fact(f)
		if not n.is_empty():
			out.append(n)
	return out


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


func _save_json(path: String, data: Dictionary) -> void:
	var rel := path.trim_prefix("user://")
	if path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join(rel.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
