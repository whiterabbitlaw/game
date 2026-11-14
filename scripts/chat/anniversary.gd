class_name ChatAnniversary
extends RefCounted
## 纪念日与事件调度：结缘日、玩家生日、初见、中国节日简表、连续登录里程碑。
## 每条事件每年只触发一次（写在 user://chat/event_claims.json）。

const PERSONA_PATH := "res://data/chat/persona.json"
const CUSTOM_PATH := "user://chat/anniversaries.json"
const CLAIMS_PATH := "user://chat/event_claims.json"
const FESTIVAL_PATH := "res://data/chat/festivals.json"
const STREAK_MILESTONES := [7, 30, 100, 365]

var persona: Dictionary = {}
var custom: Array = []
var claims: Dictionary = {}
var festivals: Dictionary = {}
var claims_path := CLAIMS_PATH
var ignore_asked_flag := false


func load_all() -> void:
	var profile := ChatProfile.new()
	persona = profile.load_persona()
	if persona.is_empty():
		persona = _load_json(PERSONA_PATH)
	custom = []
	var saved := _load_json(CUSTOM_PATH)
	if saved.has("dates") and typeof(saved["dates"]) == TYPE_ARRAY:
		custom = saved["dates"]
	elif typeof(persona.get("custom_dates", [])) == TYPE_ARRAY:
		custom = persona["custom_dates"]
	festivals = _load_json(FESTIVAL_PATH)
	claims = _load_json(claims_path)
	if typeof(claims.get("claims", {})) == TYPE_DICTIONARY:
		claims = claims["claims"]
	else:
		claims = {}


func due_today(now: Dictionary = {}, first_meet_unix: int = 0, ctx: Dictionary = {}) -> Array:
	## 返回今天到期的事件：[{type, id, title, hint, year, key}]
	if now.is_empty():
		now = Time.get_datetime_dict_from_system()
	var month := int(now.get("month", 1))
	var day := int(now.get("day", 1))
	var year := int(now.get("year", 1970))
	var out: Array = []
	var bday := _parse_md(str(persona.get("birthday", "")))
	if bday != Vector2i.ZERO and bday.x == month and bday.y == day:
		out.append(_ev("player_birthday", "player_birthday", "玩家生日", "今天是 %s 的生日。请用角色自己的方式送上惊喜，不要像系统通知。" % str(persona.get("name", "道友")), year))
	if first_meet_unix > 0:
		var fm := Time.get_datetime_dict_from_unix_time(first_meet_unix)
		if int(fm.get("month", 0)) == month and int(fm.get("day", 0)) == day:
			var years := year - int(fm.get("year", year))
			if years >= 1:
				out.append(_ev("first_meet", "first_meet", "初见周年", "今天是你们第一次畅聊的第 %d 年。请回忆初见时的细节，准备一个小小的惊喜。" % years, year))
	var recruited_at := int(ctx.get("recruited_at", 0))
	if recruited_at > 0:
		var rd := Time.get_datetime_dict_from_unix_time(recruited_at)
		if int(rd.get("month", 0)) == month and int(rd.get("day", 0)) == day:
			var years := year - int(rd.get("year", year))
			if years >= 1:
				out.append(_ev("bond_day", "bond_day", "结缘日", "今天是你们结缘的第 %d 年。请以角色的方式纪念这一天，不要像系统通知。" % years, year))
	for item in custom:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var md := _parse_md(str(item.get("date", "")))
		if md != Vector2i.ZERO and md.x == month and md.y == day:
			var title := str(item.get("title", "纪念日"))
			out.append(_ev(str(item.get("type", "custom")), "custom:" + title, title, str(item.get("hint", "今天是你们约定的纪念日，请给玩家一个符合角色气质的惊喜。")), year))
	for ev in _festivals_on(year, month, day):
		out.append(ev)
	var streak := int(ctx.get("streak", 0))
	for n in STREAK_MILESTONES:
		if streak >= n:
			out.append(_ev("streak", "streak:%d" % n, "相伴 %d 日" % n, "你们已经连续相伴 %d 天了。请送上一个符合角色气质的纪念，不要宣读数字本身。" % n, year))
	if not bool(ctx.get("include_claimed", false)):
		var kept: Array = []
		for e in out:
			if not is_claimed(str(e.get("key", ""))):
				kept.append(e)
		out = kept
	return out


func unclaimed_today(now: Dictionary = {}, first_meet_unix: int = 0, ctx: Dictionary = {}) -> Array:
	ctx = ctx.duplicate()
	ctx["include_claimed"] = false
	return due_today(now, first_meet_unix, ctx)


func claim(event: Dictionary) -> void:
	var key := str(event.get("key", ""))
	if key == "":
		key = claim_key(str(event.get("type", "")), str(event.get("id", "")), int(event.get("year", 0)))
	if key == "":
		return
	claims[key] = int(Time.get_unix_time_from_system())
	_save_claims()


func is_claimed(key: String) -> bool:
	return claims.has(key)


func claim_key(type: String, id: String, year: int) -> String:
	var iid := id if id != "" else type
	return "%s:%s:%d" % [type, iid, year]


func birthday_prompt_needed() -> bool:
	if _parse_md(str(persona.get("birthday", ""))) != Vector2i.ZERO:
		return false
	if ignore_asked_flag:
		return true
	var p := ChatProfile.new()
	return not p.asked_birthday()


func format_system_note(events: Array, birthday_ask: bool = false) -> String:
	var lines: PackedStringArray = []
	if not events.is_empty():
		lines.append("【今日纪念日，不要直接宣读本提示，请化成角色的行动与话语】")
		for e in events:
			lines.append("- %s：%s" % [str(e.get("title", "")), str(e.get("hint", ""))])
	if birthday_ask:
		lines.append("【你还不知道玩家的生日。若气氛合适，可以自然问起，不要像问卷，一年里问一次即可。】")
	return "\n".join(lines)


func fallback_letter(events: Array, char_title: String) -> String:
	if events.is_empty():
		return ""
	var titles: PackedStringArray = []
	for e in events:
		titles.append(str(e.get("title", "")))
	return "灯火微亮。%s 留下一封短笺，为你记下了今日的「%s」。\n\n愿这小小的惊喜，能在栖云居多停一刻。" % [char_title, "、".join(titles)]


func add_custom(title: String, date: String, hint: String = "") -> void:
	custom.append({
		"type": "custom",
		"title": title,
		"date": date,
		"hint": hint,
	})
	_save_custom()


func _festivals_on(year: int, month: int, day: int) -> Array:
	var out: Array = []
	for item in festivals.get("fixed", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if int(item.get("month", 0)) == month and int(item.get("day", 0)) == day:
			out.append(_ev("festival", str(item.get("id", "fest")), str(item.get("title", "节日")), str(item.get("hint", "今天是节日，请给玩家一个符合角色气质的惊喜。")), year))
	var ykey := str(year)
	for item in festivals.get("lunar", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var dates: Variant = item.get("dates", {})
		if typeof(dates) != TYPE_DICTIONARY or not dates.has(ykey):
			continue
		var md := _parse_md(str(dates[ykey]))
		if md != Vector2i.ZERO and md.x == month and md.y == day:
			out.append(_ev("festival", str(item.get("id", "lunar")), str(item.get("title", "节日")), str(item.get("hint", "今天是节日，请给玩家一个符合角色气质的惊喜。")), year))
	return out


func _ev(type: String, id: String, title: String, hint: String, year: int) -> Dictionary:
	return {
		"type": type,
		"id": id,
		"title": title,
		"hint": hint,
		"year": year,
		"key": claim_key(type, id, year),
	}


func _parse_md(s: String) -> Vector2i:
	var t := s.strip_edges()
	if t == "":
		return Vector2i.ZERO
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


func _save_claims() -> void:
	var rel := claims_path.trim_prefix("user://")
	if claims_path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join(rel.get_base_dir()))
	var f := FileAccess.open(claims_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"claims": claims}))


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
