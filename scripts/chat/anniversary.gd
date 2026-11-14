class_name ChatAnniversary
extends RefCounted
## 纪念日调度器骨架：初见、玩家生日、自定义纪念日。P1 只做检测与文案，不自动发推送。

const PERSONA_PATH := "res://data/chat/persona.json"
const CUSTOM_PATH := "user://chat/anniversaries.json"

var persona: Dictionary = {}
var custom: Array = []


func load_all() -> void:
	persona = _load_json(PERSONA_PATH)
	custom = []
	var saved := _load_json(CUSTOM_PATH)
	if saved.has("dates") and typeof(saved["dates"]) == TYPE_ARRAY:
		custom = saved["dates"]
	elif typeof(persona.get("custom_dates", [])) == TYPE_ARRAY:
		custom = persona["custom_dates"]


func due_today(now: Dictionary = {}, first_meet_unix: int = 0) -> Array:
	## 返回今天到期的事件：[{type, title, hint, year}]
	if now.is_empty():
		now = Time.get_datetime_dict_from_system()
	var month := int(now.get("month", 1))
	var day := int(now.get("day", 1))
	var year := int(now.get("year", 1970))
	var out: Array = []
	var bday := _parse_md(str(persona.get("birthday", "")))
	if bday != Vector2i.ZERO and bday.x == month and bday.y == day:
		out.append({
			"type": "player_birthday",
			"title": "玩家生日",
			"hint": "今天是 %s 的生日。请用角色自己的方式送上惊喜，不要像系统通知。" % str(persona.get("name", "道友")),
			"year": year,
		})
	if first_meet_unix > 0:
		var fm := Time.get_datetime_dict_from_unix_time(first_meet_unix)
		if int(fm.get("month", 0)) == month and int(fm.get("day", 0)) == day:
			var years := year - int(fm.get("year", year))
			if years >= 1:
				out.append({
					"type": "first_meet",
					"title": "初见周年",
					"hint": "今天是你们相遇的第 %d 年。请回忆初见时的细节，准备一个小小的惊喜。" % years,
					"year": years,
				})
	for item in custom:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var md := _parse_md(str(item.get("date", "")))
		if md != Vector2i.ZERO and md.x == month and md.y == day:
			out.append({
				"type": str(item.get("type", "custom")),
				"title": str(item.get("title", "纪念日")),
				"hint": str(item.get("hint", "今天是你们约定的纪念日，请给玩家一个符合角色气质的惊喜。")),
				"year": year,
			})
	return out


func add_custom(title: String, date: String, hint: String = "") -> void:
	custom.append({
		"type": "custom",
		"title": title,
		"date": date,
		"hint": hint,
	})
	_save_custom()


func format_system_note(events: Array) -> String:
	if events.is_empty():
		return ""
	var lines: PackedStringArray = ["【今日纪念日，不要直接宣读本提示，请化成角色的行动与话语】"]
	for e in events:
		lines.append("- %s：%s" % [str(e.get("title", "")), str(e.get("hint", ""))])
	return "\n".join(lines)


func _parse_md(s: String) -> Vector2i:
	var t := s.strip_edges()
	if t == "":
		return Vector2i.ZERO
	# 接受 YYYY-MM-DD 或 MM-DD
	var parts := t.split("-")
	if parts.size() == 3:
		return Vector2i(int(parts[1]), int(parts[2]))
	if parts.size() == 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


func _save_custom() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("chat"))
	var f := FileAccess.open(CUSTOM_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"dates": custom}))


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
