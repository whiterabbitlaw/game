class_name ChatClient
extends Node
## 调用本地 / 已部署的畅聊 Worker。地址存在 user://chat_config.json，默认本地 wrangler dev。

const CONFIG_PATH := "user://chat_config.json"
const DEFAULT_URL := "http://127.0.0.1:8787"

signal chat_finished(ok: bool, text: String, raw: Dictionary)
signal tts_finished(ok: bool, bytes: PackedByteArray)

var base_url := DEFAULT_URL
var tts_enabled := true
var model := ""
var _http: HTTPRequest
var _busy := false
var _mode := ""


func _ready() -> void:
	_load_config()
	_http = HTTPRequest.new()
	_http.timeout = 90.0
	add_child(_http)
	_http.request_completed.connect(_on_done)


func is_busy() -> bool:
	return _busy


func chat(messages: Array) -> void:
	if _busy:
		return
	_mode = "chat"
	_busy = true
	var body := {"messages": messages}
	if model != "":
		body["model"] = model
	_post("/v1/chat", body)


func tts(text: String, lang: String = "ZH") -> void:
	if _busy or not tts_enabled or text.strip_edges() == "":
		tts_finished.emit(false, PackedByteArray())
		return
	_mode = "tts"
	_busy = true
	_post("/v1/tts", {"text": text, "lang": lang})


func _post(path: String, body: Dictionary) -> void:
	var url := base_url.rstrip("/") + path
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_busy = false
		if _mode == "chat":
			chat_finished.emit(false, "无法发起请求（%s）" % err, {})
		else:
			tts_finished.emit(false, PackedByteArray())


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var mode := _mode
	_busy = false
	_mode = ""
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var hint := "Worker 未响应"
		if result != HTTPRequest.RESULT_SUCCESS:
			hint = "连不上 Worker（请先在本机运行 wrangler dev，默认 http://127.0.0.1:8787）"
		else:
			hint = "Worker 返回 HTTP %d" % code
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
		var text := str(data.get("text", "")).strip_edges()
		if text == "":
			chat_finished.emit(false, "模型没有返回文本", data)
		else:
			chat_finished.emit(true, text, data)
	else:
		var b64 := str(data.get("audio", ""))
		var bytes := Marshalls.base64_to_raw(b64) if b64 != "" else PackedByteArray()
		tts_finished.emit(bytes.size() > 0, bytes)


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var cfg: Dictionary = parsed
	if str(cfg.get("worker_url", "")) != "":
		base_url = str(cfg["worker_url"])
	if cfg.has("tts"):
		tts_enabled = bool(cfg["tts"])
	model = str(cfg.get("model", ""))
