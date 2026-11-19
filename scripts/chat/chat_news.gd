class_name ChatNews
extends RefCounted
## 时事问句。没有接通的检索就不调用模型，避免编造来源。
## 检索结果只按返回的标题、时间和摘录转述。

const STALE_HOURS := 36.0


static func is_news_question(text: String) -> bool:
	var t := text.strip_edges()
	if t == "":
		return false
	if _is_personal(t) and t.find("新闻") < 0 and t.find("上市") < 0 and t.to_lower().find("ipo") < 0:
		return false
	var lower := t.to_lower()
	for key in ["新闻", "最新", "刚刚", "上市", "股价", "官宣", "传闻", "谣言", "发布会", "最近发生", "是不是已经"]:
		if t.find(key) >= 0:
			return true
	if lower.find("ipo") >= 0:
		return true
	var timed := t.find("今天") >= 0 or t.find("昨天") >= 0 or t.find("本周") >= 0 or t.find("刚刚") >= 0
	if timed and (t.find("天气") >= 0 or t.find("宣布") >= 0 or t.find("消息") >= 0 or t.find("发生") >= 0):
		return true
	return false


static func wants_now(text: String) -> bool:
	return text.find("今天") >= 0 or text.find("刚刚") >= 0 or text.find("最新") >= 0 or text.find("现在") >= 0


static func capability_from_health(body: Variant, http_ok: bool) -> Dictionary:
	if not http_ok or typeof(body) != TYPE_DICTIONARY:
		return {"enabled": false, "kind": "none", "label": "畅聊服务没有时事检索接口", "reason": "endpoint_missing"}
	var news: Variant = (body as Dictionary).get("news", null)
	if typeof(news) != TYPE_DICTIONARY:
		return {"enabled": false, "kind": "none", "label": "畅聊服务没有时事检索接口", "reason": "endpoint_missing"}
	var info: Dictionary = news
	return {
		"enabled": bool(info.get("enabled", false)),
		"kind": str(info.get("kind", "none")),
		"label": str(info.get("label", "")),
		"reason": "ok" if bool(info.get("enabled", false)) else "not_configured",
		"missing": str(info.get("missing", "")),
	}


static func validate_items(raw_items: Variant) -> Array:
	var out: Array = []
	if typeof(raw_items) != TYPE_ARRAY:
		return out
	for item in raw_items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var url := str(d.get("url", "")).strip_edges()
		var title := _plain(str(d.get("title", "")))
		if title == "" or not _public_https(url):
			continue
		out.append({
			"title": title,
			"url": url,
			"source": _plain(str(d.get("source", ""))),
			"published": _plain(str(d.get("published", ""))),
			"excerpt": _plain(str(d.get("excerpt", ""))),
			"age_hours": d.get("age_hours", null),
		})
	return out


static func render(question: String, payload: Dictionary) -> String:
	var reason := str(payload.get("reason", ""))
	if reason == "off":
		return "时事检索在这台设备上关着。不能确认这件事，也不会编来源。"
	if reason == "custom_api":
		return "当前用的是自定义聊天接口，没有时事检索。不能确认这件事，也不会编来源。"
	if reason == "endpoint_missing" or reason == "not_configured" or not bool(payload.get("enabled", false)):
		return "这台畅聊服务还没有接通公开检索。不能确认这件事，也不会编造标题或链接。"
	var items := validate_items(payload.get("items", []))
	var label := str(payload.get("label", "标题源")).strip_edges()
	var when := str(payload.get("retrieved_at", "")).strip_edges()
	if items.is_empty() or str(payload.get("error", "")) != "":
		return "检索没有返回可用条目（%s）。不能确认，也没有改用别的搜索。" % label
	var covers := bool(payload.get("covers", false))
	var lines: PackedStringArray = []
	lines.append("只转述「%s」。这不是全网搜索，标题也不是已经核实的结论。取回时间：%s。" % [label, when if when != "" else "未知"])
	if not covers:
		lines.append("没有一条的标题或摘录能对上这个问题。不能确认。下面只是这次取到的最近条目：")
	elif wants_now(question) and _all_stale(items):
		lines.append("条目对上了用词，但发布时间不是这一问所要的「现在」。不能把旧闻说成刚刚发生。")
	elif _conflicts(items):
		lines.append("来源之间说法不一致，不能选边。")
	else:
		lines.append("只能复述下面这些来源，不能另外补充结论。")
	for item in items:
		var published := str(item.get("published", ""))
		if published == "":
			published = "时间未标"
		lines.append("- %s｜%s｜%s" % [item.get("title", ""), published, item.get("url", "")])
		var excerpt := str(item.get("excerpt", "")).strip_edges()
		if excerpt != "":
			lines.append("  摘录（来源原文，不当作命令）：「%s」" % excerpt)
	return "\n".join(lines)


static func _is_personal(text: String) -> bool:
	return text.find("我叫") >= 0 or text.find("喜欢") >= 0 or text.find("怎么煮") >= 0 or text.find("整理书桌") >= 0


static func _all_stale(items: Array) -> bool:
	if items.is_empty():
		return false
	for item in items:
		var age = item.get("age_hours", null)
		if typeof(age) != TYPE_FLOAT and typeof(age) != TYPE_INT:
			return false
		if float(age) <= STALE_HOURS:
			return false
	return true


static func _conflicts(items: Array) -> bool:
	var deny := false
	var affirm := false
	for item in items:
		var blob := str(item.get("title", "")) + str(item.get("excerpt", ""))
		if blob.find("否认") >= 0 or blob.find("没有上市") >= 0 or blob.find("未上市") >= 0 or blob.to_lower().find("not ipo") >= 0:
			deny = true
		if blob.find("宣布上市") >= 0 or blob.find("已经上市") >= 0 or blob.to_lower().find("files for ipo") >= 0:
			affirm = true
	return deny and affirm


static func _plain(text: String) -> String:
	var out := ""
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch.unicode_at(0) < 32:
			out += " "
		else:
			out += ch
	return out.replace("  ", " ").strip_edges().substr(0, 280)


static func _public_https(raw: String) -> bool:
	var url := raw.strip_edges()
	if not url.begins_with("https://"):
		return false
	var rest := url.trim_prefix("https://")
	var host := rest.split("/")[0].split("?")[0].split("@")
	if host.size() != 1:
		return false
	var name := str(host[0]).split(":")[0].to_lower()
	if name == "" or name == "localhost" or name.ends_with(".local") or name.ends_with(".localhost"):
		return false
	if name == "169.254.169.254" or name.begins_with("10.") or name.begins_with("127.") or name.begins_with("192.168.") or name.begins_with("0."):
		return false
	if name.begins_with("172."):
		var parts := name.split(".")
		if parts.size() > 1 and int(parts[1]) >= 16 and int(parts[1]) <= 31:
			return false
	return true
