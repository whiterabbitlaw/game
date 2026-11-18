class_name ChatVision
extends RefCounted
## 看图：把原图压到可上传的大小，并把「真正看见的描述」写进这轮和之后的对话。
## 没有描述时不要假装已经看懂。

## 线上 Worker 会把提示截到 400 字。这里留在 380 以内，并把玩家的问题放进去。
const PROMPT_LIMIT := 380
const MAX_SIDE := 1280

static func prompt_for(question: String) -> String:
	var base := "用简体中文看图。先写和问题直接相关的细节：物体、彼此关系、可读文字、界面按钮、数量、颜色、位置。看不清就写看不清，不要编，不要写故事。"
	var q := question.strip_edges()
	if q == "":
		var plain := base + "没有具体问题时，按这些项目把画面写清楚，方便之后追问。"
		return plain.substr(0, PROMPT_LIMIT)
	var prefix := base + "问题："
	var room := PROMPT_LIMIT - prefix.length()
	if room < 8:
		return base.substr(0, PROMPT_LIMIT)
	if q.length() > room:
		q = q.substr(0, room)
	return prefix + q


static func prompt() -> String:
	return prompt_for("")


static func prepare_image(bytes: PackedByteArray, mime: String) -> Dictionary:
	if bytes.is_empty():
		return {"ok": false, "error": "没有读到图片数据。"}
	var img := Image.new()
	var err := _load_image(img, bytes, mime)
	if err != OK:
		return {"ok": false, "error": "这张图打不开。请换 jpg 或 png。"}
	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 2:
		return {"ok": false, "error": "这张图太小，看不出内容。"}
	var side := maxi(w, h)
	if side > MAX_SIDE:
		var scale := float(MAX_SIDE) / float(side)
		img.resize(maxi(1, int(round(w * scale))), maxi(1, int(round(h * scale))), Image.INTERPOLATE_BILINEAR)
	var jpg := img.save_jpg_to_buffer(0.8)
	if jpg.is_empty():
		return {"ok": false, "error": "图片压缩失败，没有送出。"}
	return {"ok": true, "b64": Marshalls.raw_to_base64(jpg), "mime": "image/jpeg", "bytes": jpg.size()}


static func _load_image(img: Image, bytes: PackedByteArray, mime: String) -> Error:
	var m := mime.to_lower()
	var order: PackedStringArray = PackedStringArray()
	if m.find("png") >= 0:
		order.append("png")
	elif m.find("webp") >= 0:
		order.append("webp")
	elif m.find("jpeg") >= 0 or m.find("jpg") >= 0:
		order.append("jpg")
	for kind in ["jpg", "png", "webp"]:
		if not (kind in order):
			order.append(kind)
	for kind in order:
		var err := ERR_FILE_CORRUPT
		if kind == "png":
			err = img.load_png_from_buffer(bytes)
		elif kind == "webp":
			err = img.load_webp_from_buffer(bytes)
		else:
			err = img.load_jpg_from_buffer(bytes)
		if err == OK:
			return OK
	return ERR_FILE_CORRUPT


static func compose_stored(typed: String, attachments: Array) -> String:
	var notes := PackedStringArray()
	for a in attachments:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var desc := str((a as Dictionary).get("description", "")).strip_edges()
		if desc == "":
			continue
		var kind := "图片" if str((a as Dictionary).get("kind", "image")) != "video" else "视频"
		notes.append("【你此刻真正看到的%s】%s" % [kind, desc])
	var text := typed.strip_edges()
	if notes.is_empty():
		return text
	if text == "":
		return "\n".join(notes)
	return text + "\n" + "\n".join(notes)


static func picker_error(code: String) -> String:
	match code:
		"file too large":
			return "原图超过 18MB，没有附上。请换一张小一些的图。"
		"unreadable":
			return "浏览器打不开这张图。请换 jpg 或 png。"
		"encode":
			return "图片压缩失败，没有附上。"
		_:
			return "没有附上图片。" if code == "" else "没有附上图片：%s" % code


static func explain_vision_error(raw: String) -> String:
	var t := raw.to_lower()
	if t.find("too large") >= 0 or t.find("413") >= 0:
		return "图片太大，服务器没有收下。这轮没有画面，请再发一次。"
	if t.find("timeout") >= 0 or t.find("超时") >= 0:
		return "看图超时。这轮没有画面，请再试一次。"
	if t.find("origin") >= 0:
		return "看图请求被拒绝。这轮没有画面。"
	if raw.strip_edges() == "":
		return "看图失败。这轮没有画面。"
	return "看图失败，这轮没有画面：%s" % raw.strip_edges()
