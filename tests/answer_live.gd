extends SceneTree
## 真实链路：压缩 → 线上 /v1/vision → 组装 Claude 提示 → /v1/chat。
## 运行：godot --headless --path . --script res://tests/answer_live.gd
## 图片由调用方先写到 /tmp/qa-photo.png 和 /tmp/qa-screen.png。

const WORKER := "https://qiyunju-chat.whiterabbitlaw.workers.dev"
const OLD_VISION := "只根据画面本身用简体中文描述：主体、颜色、数量、场景、画面里能读到的文字。不要编故事，不要评价画质。看不清就说看不清。80到160字。"

var failed := 0
var asm := ChatPromptAssembler.new()
var history: Array = []


func _initialize() -> void:
	print("== live answer quality ==")
	var photo := _load_ready("/tmp/qa-photo.png")
	var screen := _load_ready("/tmp/qa-screen.png")
	if photo.is_empty() or screen.is_empty():
		print("answer_live: FAILED missing fixtures")
		quit(1)
		return
	var screen_q := "画面上的错误原文是什么？按钮写了什么？"
	var photo_q := "图里有几块主要颜色？红色的东西在什么位置，是什么形状？"
	var old_cap := await _vision(screen, OLD_VISION)
	var new_cap := await _vision(screen, ChatVision.prompt_for(screen_q))
	var photo_cap := await _vision(photo, ChatVision.prompt_for(photo_q))
	_report_vision("screenshot old generic caption", old_cap)
	_report_vision("screenshot question caption", new_cap)
	_report_vision("photo question caption", photo_cap)
	_ok(str(new_cap.get("model", "")).find("llama-3.2-11b-vision") >= 0, "vision route is llama 3.2 11b")
	_ok(str(new_cap.get("text", "")).find("磁盘已满") >= 0, "questioned caption reads the error text")
	_ok(str(new_cap.get("text", "")).find("重试") >= 0, "questioned caption reads the button")
	var turns := [
		"今天午饭吃什么比较好？",
		"用三步说说白粥怎么煮，要能照着做。",
		"1公里大约等于多少米？",
		"我有点失眠，有什么普通的办法？不要讲故事。",
		"讲一个不提花的短故事，关于一个修表的人。",
		"你觉得周一开会紧张，算正常吗？",
	]
	var model := ""
	for q in turns:
		var reply := await _chat_turn(q, [])
		model = str(reply.get("model", model))
		_judge_reply(q, str(reply.get("text", "")))
	_ok(model.find("qwen3-30b") >= 0, "chat route echoes qwen3 30b (%s)" % model)
	if str(new_cap.get("text", "")).strip_edges() != "":
		var stored := ChatVision.compose_stored(screen_q, [{"kind": "image", "description": str(new_cap.get("text", ""))}])
		var seen := await _chat_turn(stored, [{"kind": "image", "description": str(new_cap.get("text", ""))}])
		var answer := str(seen.get("text", ""))
		_ok(answer.find("磁盘") >= 0 or answer.find("已满") >= 0, "chat answers the screenshot from the caption")
		_ok(answer.find("向日葵") < 0, "screenshot answer does not add a sunflower")
		var follow := await _chat_turn("那我该先点哪个？", [])
		_judge_reply("screenshot followup", str(follow.get("text", "")))
	if str(photo_cap.get("text", "")).strip_edges() != "":
		var stored_p := ChatVision.compose_stored(photo_q, [{"kind": "image", "description": str(photo_cap.get("text", ""))}])
		var seen_p := await _chat_turn(stored_p, [{"kind": "image", "description": str(photo_cap.get("text", ""))}])
		var answer_p := str(seen_p.get("text", ""))
		_ok(answer_p.find("红") >= 0, "chat mentions the red object from the photo caption")
		_ok(answer_p.find("向日葵") < 0, "photo answer does not add a sunflower")
	if failed == 0:
		print("answer_live: ALL OK")
	else:
		print("answer_live: FAILED ", failed)
	quit(1 if failed else 0)


func _load_ready(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		print("  FAIL missing ", path)
		failed += 1
		return {}
	var prepared := ChatVision.prepare_image(bytes, "image/png")
	_ok(bool(prepared.get("ok", false)), "compressed %s (%s bytes)" % [path.get_file(), prepared.get("bytes", 0)])
	return prepared


func _vision(prepared: Dictionary, prompt: String) -> Dictionary:
	var raw := await _post("/v1/vision", {
		"image": str(prepared.get("b64", "")),
		"prompt": prompt,
		"mime": str(prepared.get("mime", "image/jpeg")),
	})
	return raw


func _chat_turn(user_text: String, attachments: Array) -> Dictionary:
	var packed := asm.assemble("claude", history, user_text, null, "", ChatPromptAssembler.DEFAULT_BUDGET, attachments)
	var raw := await _post("/v1/chat", {"messages": packed.get("messages", [])})
	var text := str(raw.get("text", "")).strip_edges()
	history.append({"role": "user", "content": user_text})
	history.append({"role": "assistant", "content": text})
	print("  Q ", user_text.substr(0, 40).replace("\n", " "))
	print("  A ", text.replace("\n", " / "))
	print("  model ", raw.get("model", ""))
	return raw


func _judge_reply(q: String, text: String) -> void:
	_ok(text.strip_edges() != "", "reply not empty: " + q.substr(0, 18))
	_ok(text.find("向日葵") < 0, "no unprompted sunflower: " + q.substr(0, 18))
	_ok(text.find("不知道该怎么答") < 0 and text.find("不能回答") < 0 and text.find("这个话题") < 0, "does not refuse the topic: " + q.substr(0, 18))


func _report_vision(label: String, raw: Dictionary) -> void:
	var text := str(raw.get("text", "")).strip_edges()
	print("  VISION ", label)
	print("  model ", raw.get("model", ""), " http ", raw.get("http", ""))
	print("  text ", text.replace("\n", " / "))
	if text == "":
		_ok(false, label + " returned text")


func _post(path: String, payload: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	await process_frame
	http.timeout = 90.0
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Origin: https://whiterabbitlaw.github.io",
	])
	var err := http.request(WORKER + path, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http.queue_free()
		return {"http": 0, "error": "request failed %s" % err, "text": ""}
	var result: Array = await http.request_completed
	http.queue_free()
	var code := int(result[1])
	var raw := (result[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"http": code, "error": raw.substr(0, 240), "text": ""}
	var out: Dictionary = parsed
	out["http"] = code
	return out


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		failed += 1
		print("  FAIL ", msg)
