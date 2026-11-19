class_name ChatClient
extends Node
## 默认走已部署的 Workers AI Worker；若在本机配置了自定义 API，则聊天直连该接口。
## TTS 始终走 Worker（MeloTTS）。密钥只读 user:// 配置，不进仓库。

signal chat_finished(ok: bool, text: String, raw: Dictionary)
signal tts_finished(ok: bool, bytes: PackedByteArray)
signal tts_chunk_ready(ok: bool, bytes: PackedByteArray, text: String)
signal summarize_finished(ok: bool, text: String, raw: Dictionary)
signal extract_finished(ok: bool, facts: Array, raw: Dictionary)
signal vision_finished(ok: bool, text: String, raw: Dictionary)
signal stt_finished(ok: bool, text: String, raw: Dictionary)

var cfg := ChatConfig.new()
var _http: HTTPRequest
var _bg: HTTPRequest
var _busy := false
var _bg_busy := false
var _mode := ""
var _kind := ""
var _bg_mode := ""
var _bg_queue: Array = []
var _tts_http: HTTPRequest
var _tts_busy := false
var _tts_q: Array = []
var _tts_cur := ""
var _stt_http: HTTPRequest
var _stt_busy := false


func _ready() -> void:
	reload_config()
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	_bg = HTTPRequest.new()
	_bg.timeout = 30.0
	add_child(_bg)
	_bg.request_completed.connect(_on_bg_done)
	_tts_http = HTTPRequest.new()
	_tts_http.timeout = 20.0
	add_child(_tts_http)
	_tts_http.request_completed.connect(_on_tts_http)
	_stt_http = HTTPRequest.new()
	_stt_http.timeout = 20.0
	add_child(_stt_http)
	_stt_http.request_completed.connect(_on_stt_http)


func reload_config() -> void:
	cfg.load_from_disk()


func is_busy() -> bool:
	return _busy


func chat(messages: Array) -> void:
	if _busy:
		return
	reload_config()
	var plan: Dictionary = cfg.plan_chat(messages)
	_mode = "chat"
	_kind = str(plan.get("kind", ChatConfig.PROVIDER_WORKER))
	_busy = true
	_request(str(plan["url"]), plan["headers"], plan["body"])


func tts(text: String, lang: String = "ZH") -> void:
	tts_clear()
	tts_push(text, lang)


func tts_push(text: String, lang: String = "ZH") -> void:
	reload_config()
	if not cfg.tts_enabled or text.strip_edges() == "":
		return
	_tts_q.append({"text": text.strip_edges(), "lang": lang})
	_kick_tts()


func tts_clear() -> void:
	_tts_q.clear()
	_tts_cur = ""
	if _tts_busy and _tts_http:
		_tts_http.cancel_request()
		_tts_busy = false


func tts_pending() -> bool:
	return _tts_busy or not _tts_q.is_empty()


func _kick_tts() -> void:
	if _tts_busy or _tts_q.is_empty() or _tts_http == null:
		return
	var job: Dictionary = _tts_q.pop_front()
	_tts_cur = str(job.get("text", ""))
	_tts_busy = true
	var err := _tts_http.request(
		cfg.worker_tts_url(),
		PackedStringArray(["Content-Type: application/json", "Accept: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"text": _tts_cur, "lang": str(job.get("lang", "ZH"))})
	)
	if err != OK:
		_tts_busy = false
		tts_chunk_ready.emit(false, PackedByteArray(), _tts_cur)
		tts_finished.emit(false, PackedByteArray())
		_kick_tts()


func _on_tts_http(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_tts_busy = false
	var text := _tts_cur
	_tts_cur = ""
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	var bytes := PackedByteArray()
	if ok:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			var b64 := str(parsed.get("audio", ""))
			if b64 != "":
				bytes = Marshalls.base64_to_raw(b64)
	ok = ok and bytes.size() > 0
	tts_chunk_ready.emit(ok, bytes, text)
	tts_finished.emit(ok, bytes)
	_kick_tts()


func summarize(messages: Array) -> void:
	_enqueue_bg("summarize", cfg.worker_path("/v1/summarize"), {"messages": messages})


func extract_facts(messages: Array) -> void:
	_enqueue_bg("extract", cfg.worker_path("/v1/memory/extract"), {"messages": messages})


func vision(image_b64: String, prompt: String = "", mime: String = "image/jpeg") -> void:
	var body := {"image": image_b64, "mime": mime}
	if prompt.strip_edges() != "":
		body["prompt"] = prompt
	_enqueue_bg("vision", cfg.worker_path("/v1/vision"), body)


func stt(audio_b64: String, format: String = "wav", language: String = "zh") -> void:
	reload_config()
	if _stt_http == null:
		stt_finished.emit(false, "听写组件未就绪", {})
		return
	if _stt_busy:
		_stt_http.cancel_request()
		_stt_busy = false
	_stt_busy = true
	var err := _stt_http.request(
		cfg.worker_path("/v1/stt"),
		PackedStringArray(["Content-Type: application/json", "Accept: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"audio": audio_b64, "format": format, "language": language})
	)
	if err != OK:
		_stt_busy = false
		stt_finished.emit(false, "无法发起听写（%s）" % err, {})


func _on_stt_http(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_stt_busy = false
	var raw: Dictionary = {}
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) == TYPE_DICTIONARY:
		raw = parsed
	if result == HTTPRequest.RESULT_TIMEOUT:
		stt_finished.emit(false, "听写超时，请再试一次。", raw)
		return
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	var text := str(raw.get("text", "")).strip_edges()
	if not ok:
		var err := str(raw.get("error", "听写失败" if code else "听写请求失败"))
		if code:
			err = "听写失败（HTTP %d）" % code if err == "" else err
		stt_finished.emit(false, err, raw)
		return
	stt_finished.emit(true, ChatTextUtil.to_simplified(text), raw)


func _enqueue_bg(mode: String, url: String, body: Dictionary) -> void:
	reload_config()
	_bg_queue.append({"mode": mode, "url": url, "body": body})
	_kick_bg()


func _kick_bg() -> void:
	if _bg_busy or _bg_queue.is_empty() or _bg == null:
		return
	var job: Dictionary = _bg_queue.pop_front()
	_bg_mode = str(job.get("mode", ""))
	_bg_busy = true
	var err := _bg.request(str(job["url"]), PackedStringArray(["Content-Type: application/json", "Accept: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(job["body"]))
	if err != OK:
		_bg_busy = false
		_emit_bg(false, _bg_mode, {}, "无法发起请求（%s）" % err)
		_kick_bg()


func _on_bg_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var mode := _bg_mode
	_bg_busy = false
	_bg_mode = ""
	var raw: Dictionary = {}
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) == TYPE_DICTIONARY:
		raw = parsed
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	var err := ""
	if not ok:
		err = str(raw.get("error", "HTTP %d" % code if code else "请求失败"))
	_emit_bg(ok, mode, raw, err)
	_kick_bg()


func _emit_bg(ok: bool, mode: String, raw: Dictionary, err: String) -> void:
	match mode:
		"summarize":
			summarize_finished.emit(ok, str(raw.get("text", err)).strip_edges(), raw)
		"extract":
			var facts: Array = raw.get("facts", []) if typeof(raw.get("facts", [])) == TYPE_ARRAY else []
			extract_finished.emit(ok, facts, raw)
		"vision":
			vision_finished.emit(ok, str(raw.get("text", err)).strip_edges(), raw)
		"stt":
			stt_finished.emit(ok, str(raw.get("text", err)).strip_edges(), raw)


func _request(url: String, headers: PackedStringArray, body: Dictionary) -> void:
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_busy = false
		if _mode == "chat":
			chat_finished.emit(false, "无法发起请求（%s）" % err, {})
		else:
			tts_finished.emit(false, PackedByteArray())


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var mode := _mode
	var kind := _kind
	_busy = false
	_mode = ""
	_kind = ""
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var hint := "请求失败"
		if result == HTTPRequest.RESULT_TIMEOUT:
			hint = "想太久了，请再试一次。"
		elif result != HTTPRequest.RESULT_SUCCESS:
			if kind == ChatConfig.PROVIDER_WORKER:
				hint = "连不上畅聊服务（%s）" % cfg.worker_url
			else:
				hint = "连不上自定义接口。网页版可能被对方 CORS 拦截，可换桌面版或改回默认 Worker。"
		else:
			hint = "接口返回 HTTP %d" % code
			var parsed_err: Variant = JSON.parse_string(body.get_string_from_utf8())
			if typeof(parsed_err) == TYPE_DICTIONARY:
				var msg := str(parsed_err.get("error", ""))
				if typeof(parsed_err.get("error", null)) == TYPE_DICTIONARY:
					msg = str(parsed_err["error"].get("message", msg))
				if msg != "":
					hint += "：%s" % msg
		if mode == "chat":
			chat_finished.emit(false, hint, {"status": code})
		else:
			tts_finished.emit(false, PackedByteArray())
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		if mode == "chat":
			chat_finished.emit(false, "回复不是有效 JSON", {})
		else:
			tts_finished.emit(false, PackedByteArray())
		return
	var data: Dictionary = parsed
	if mode == "chat":
		var text := cfg.extract_chat_text(kind, data)
		if text == "":
			chat_finished.emit(false, "模型没有返回文本", data)
		else:
			chat_finished.emit(true, text, data)
	else:
		var b64 := str(data.get("audio", ""))
		var bytes := Marshalls.base64_to_raw(b64) if b64 != "" else PackedByteArray()
		tts_finished.emit(bytes.size() > 0, bytes)


func probe_news() -> Dictionary:
	reload_config()
	if cfg.uses_custom_chat():
		return {"enabled": false, "kind": "none", "reason": "custom_api", "label": "自定义接口"}
	var result := await _request_json(cfg.worker_path("/health"), HTTPClient.METHOD_GET, "")
	return ChatNews.capability_from_health(result.get("body", {}), bool(result.get("ok", false)))


func query_news(question: String) -> Dictionary:
	reload_config()
	var result := await _request_json(cfg.worker_path("/v1/news"), HTTPClient.METHOD_POST, JSON.stringify({"query": question.strip_edges().substr(0, 160)}))
	if not bool(result.get("ok", false)):
		return {"enabled": false, "kind": "none", "reason": "endpoint_missing", "items": []}
	var body: Dictionary = result.get("body", {})
	body["reason"] = "ok" if bool(body.get("enabled", false)) else "not_configured"
	return body


func _request_json(url: String, method: int, payload: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	await get_tree().process_frame
	var headers := PackedStringArray(["Accept: application/json"])
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: application/json")
	var err := http.request(url, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "body": {}}
	var done: Array = await http.request_completed
	http.queue_free()
	var parsed: Variant = JSON.parse_string((done[3] as PackedByteArray).get_string_from_utf8())
	var body: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var code := int(done[1])
	return {"ok": int(done[0]) == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, "body": body, "code": code}
