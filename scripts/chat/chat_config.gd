class_name ChatConfig
extends RefCounted
## 畅聊接口配置。只存在 user://，不进仓库、不进导出包。

const PATH := "user://chat_config.json"
const DEFAULT_WORKER_URL := "https://qiyunju-chat.whiterabbitlaw.workers.dev"

const PROVIDER_WORKER := "worker"
const PROVIDER_OPENAI := "openai"
const PROVIDER_GEMINI := "gemini"

var path := PATH
var worker_url := DEFAULT_WORKER_URL
var tts_enabled := true
var provider := PROVIDER_WORKER
var openai_base_url := "https://api.openai.com/v1"
var openai_model := "gpt-4o-mini"
var openai_api_key := ""
var gemini_model := "gemini-2.5-flash"
var gemini_api_key := ""
var worker_model := ""
var news_auto := true


func load_from_disk() -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	apply_dict(parsed)


func apply_dict(cfg: Dictionary) -> void:
	if str(cfg.get("worker_url", "")).strip_edges() != "":
		worker_url = str(cfg["worker_url"]).strip_edges()
	if cfg.has("tts"):
		tts_enabled = bool(cfg["tts"])
	var had_provider := cfg.has("provider")
	var p := str(cfg.get("provider", PROVIDER_WORKER)).strip_edges().to_lower()
	if p in [PROVIDER_WORKER, PROVIDER_OPENAI, PROVIDER_GEMINI]:
		provider = p
	if str(cfg.get("openai_base_url", "")).strip_edges() != "":
		openai_base_url = str(cfg["openai_base_url"]).strip_edges()
	if cfg.has("openai_model"):
		openai_model = str(cfg["openai_model"]).strip_edges()
	if cfg.has("openai_api_key"):
		openai_api_key = str(cfg["openai_api_key"]).strip_edges()
	# 兼容旧字段
	if cfg.has("model") and worker_model == "" and provider == PROVIDER_WORKER:
		worker_model = str(cfg["model"]).strip_edges()
	if cfg.has("worker_model"):
		worker_model = str(cfg["worker_model"]).strip_edges()
	if cfg.has("news_auto"):
		news_auto = bool(cfg["news_auto"])
	if cfg.has("gemini_model") and str(cfg["gemini_model"]).strip_edges() != "":
		gemini_model = str(cfg["gemini_model"]).strip_edges()
	if cfg.has("gemini_api_key"):
		gemini_api_key = str(cfg["gemini_api_key"]).strip_edges()
	# 旧版只填了 key 而未写 provider 时，视为自定义
	if not had_provider and provider == PROVIDER_WORKER:
		if openai_api_key != "":
			provider = PROVIDER_OPENAI
		elif gemini_api_key != "":
			provider = PROVIDER_GEMINI


func save() -> Error:
	var dir := path.get_base_dir()
	if dir.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join(dir.trim_prefix("user://")))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	return OK


func to_dict() -> Dictionary:
	return {
		"worker_url": worker_url,
		"tts": tts_enabled,
		"provider": provider,
		"openai_base_url": openai_base_url,
		"openai_model": openai_model,
		"openai_api_key": openai_api_key,
		"gemini_model": gemini_model,
		"gemini_api_key": gemini_api_key,
		"worker_model": worker_model,
		"news_auto": news_auto,
	}


func uses_custom_chat() -> bool:
	if provider == PROVIDER_OPENAI:
		return openai_api_key != "" and openai_base_url != ""
	if provider == PROVIDER_GEMINI:
		return gemini_api_key != ""
	return false


func openai_chat_url() -> String:
	var u := openai_base_url.rstrip("/")
	if u.ends_with("/chat/completions"):
		return u
	if u.ends_with("/v1"):
		return u + "/chat/completions"
	return u + "/v1/chat/completions"


func gemini_url() -> String:
	var m := gemini_model if gemini_model != "" else "gemini-2.5-flash"
	return "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [m, gemini_api_key]


func worker_chat_url() -> String:
	return worker_url.rstrip("/") + "/v1/chat"


func worker_tts_url() -> String:
	return worker_url.rstrip("/") + "/v1/tts"


func worker_path(path: String) -> String:
	if not path.begins_with("/"):
		path = "/" + path
	return worker_url.rstrip("/") + path


## 组装一次聊天请求（不含密钥明文日志）。TTS 始终走 Worker。
func plan_chat(messages: Array) -> Dictionary:
	if uses_custom_chat() and provider == PROVIDER_OPENAI:
		return {
			"kind": PROVIDER_OPENAI,
			"url": openai_chat_url(),
			"headers": PackedStringArray([
				"Content-Type: application/json",
				"Accept: application/json",
				"Authorization: Bearer %s" % openai_api_key,
			]),
			"body": {
				"model": openai_model if openai_model != "" else "gpt-4o-mini",
				"messages": messages,
			},
		}
	if uses_custom_chat() and provider == PROVIDER_GEMINI:
		var system := ""
		var contents: Array = []
		for m in messages:
			var role := str(m.get("role", "user"))
			var text := str(m.get("content", ""))
			if role == "system":
				if system != "":
					system += "\n\n"
				system += text
			else:
				contents.append({
					"role": "model" if role == "assistant" else "user",
					"parts": [{"text": text}],
				})
		var body := {
			"contents": contents,
			"generationConfig": {"maxOutputTokens": 512, "temperature": 0.85},
		}
		if system != "":
			body["systemInstruction"] = {"parts": [{"text": system}]}
		return {
			"kind": PROVIDER_GEMINI,
			"url": gemini_url(),
			"headers": PackedStringArray(["Content-Type: application/json", "Accept: application/json"]),
			"body": body,
		}
	var body2 := {"messages": messages}
	if worker_model != "":
		body2["model"] = worker_model
	return {
		"kind": PROVIDER_WORKER,
		"url": worker_chat_url(),
		"headers": PackedStringArray(["Content-Type: application/json", "Accept: application/json"]),
		"body": body2,
	}


func extract_chat_text(kind: String, data: Dictionary) -> String:
	if kind == PROVIDER_OPENAI:
		var choices: Variant = data.get("choices", [])
		if typeof(choices) == TYPE_ARRAY and not choices.is_empty():
			var msg: Variant = choices[0].get("message", {}) if typeof(choices[0]) == TYPE_DICTIONARY else {}
			if typeof(msg) == TYPE_DICTIONARY:
				return str(msg.get("content", "")).strip_edges()
		return str(data.get("text", "")).strip_edges()
	if kind == PROVIDER_GEMINI:
		var cands: Variant = data.get("candidates", [])
		if typeof(cands) == TYPE_ARRAY and not cands.is_empty() and typeof(cands[0]) == TYPE_DICTIONARY:
			var parts: Variant = cands[0].get("content", {}).get("parts", []) if typeof(cands[0].get("content", {})) == TYPE_DICTIONARY else []
			if typeof(parts) == TYPE_ARRAY:
				var bits: PackedStringArray = []
				for p in parts:
					if typeof(p) == TYPE_DICTIONARY:
						bits.append(str(p.get("text", "")))
				return "".join(bits).strip_edges()
		return str(data.get("text", "")).strip_edges()
	return str(data.get("text", "")).strip_edges()
