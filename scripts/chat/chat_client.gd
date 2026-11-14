class_name ChatClient
extends Node
## 默认走已部署的 Workers AI Worker；若在本机配置了自定义 API，则聊天直连该接口。
## TTS 始终走 Worker（MeloTTS）。密钥只读 user:// 配置，不进仓库。

signal chat_finished(ok: bool, text: String, raw: Dictionary)
signal tts_finished(ok: bool, bytes: PackedByteArray)

var cfg := ChatConfig.new()
var _http: HTTPRequest
var _busy := false
var _mode := ""
var _kind := ""


func _ready() -> void:
	reload_config()
	_http = HTTPRequest.new()
	_http.timeout = 90.0
	add_child(_http)
	_http.request_completed.connect(_on_done)


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
	reload_config()
	if _busy or not cfg.tts_enabled or text.strip_edges() == "":
		tts_finished.emit(false, PackedByteArray())
		return
	_mode = "tts"
	_kind = ChatConfig.PROVIDER_WORKER
	_busy = true
	_request(cfg.worker_tts_url(), PackedStringArray(["Content-Type: application/json", "Accept: application/json"]), {"text": text, "lang": lang})


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
		if result != HTTPRequest.RESULT_SUCCESS:
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
