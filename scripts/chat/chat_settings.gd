class_name ChatSettingsForm
extends RefCounted
## 畅聊「自定义 API」表单。密钥只写入 user://chat_config.json。

var cfg := ChatConfig.new()
var _provider: OptionButton
var _worker_url: LineEdit
var _openai_url: LineEdit
var _openai_model: LineEdit
var _openai_key: LineEdit
var _gemini_model: LineEdit
var _gemini_key: LineEdit
var _openai_box: VBoxContainer
var _gemini_box: VBoxContainer
var _persona_name: LineEdit
var _persona_birthday: LineEdit
var profile := ChatProfile.new()


func build() -> Control:
	cfg.load_from_disk()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	var hint := UI.lbl("接口与密钥只保存在这台设备上（user://），不会进存档仓库，也不会打进网页导出包。网页版直连自定义接口时，对方必须允许本游戏域名的 CORS；若浏览器拦截，请用桌面版，或改回默认 Worker。", 20, UI.INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	hint.custom_minimum_size = Vector2(560, 0)
	root.add_child(hint)
	root.add_child(UI.lbl("服务来源", 24, UI.INK, true))
	_provider = OptionButton.new()
	_provider.custom_minimum_size = Vector2(560, 48)
	_provider.add_theme_font_size_override("font_size", 22)
	_provider.add_item("默认 Worker（Workers AI Qwen）", 0)
	_provider.add_item("OpenAI 兼容（填写地址、模型、密钥）", 1)
	_provider.add_item("Gemini（AI Studio 密钥）", 2)
	var sel := 0
	if cfg.provider == ChatConfig.PROVIDER_OPENAI:
		sel = 1
	elif cfg.provider == ChatConfig.PROVIDER_GEMINI:
		sel = 2
	_provider.select(sel)
	_provider.item_selected.connect(func(_i): _sync_vis())
	root.add_child(_provider)
	root.add_child(UI.lbl("默认 Worker 地址（TTS 也走这里）", 22, UI.INK, true))
	_worker_url = _edit(cfg.worker_url, "https://qiyunju-chat.whiterabbitlaw.workers.dev")
	root.add_child(_worker_url)
	_openai_box = VBoxContainer.new()
	_openai_box.add_theme_constant_override("separation", 8)
	_openai_box.add_child(UI.lbl("Base URL", 22, UI.INK, true))
	_openai_url = _edit(cfg.openai_base_url, "https://api.openai.com/v1")
	_openai_box.add_child(_openai_url)
	_openai_box.add_child(UI.lbl("模型名", 22, UI.INK, true))
	_openai_model = _edit(cfg.openai_model, "gpt-4o-mini")
	_openai_box.add_child(_openai_model)
	_openai_box.add_child(UI.lbl("API 密钥", 22, UI.INK, true))
	_openai_key = _edit(cfg.openai_api_key, "sk-…", true)
	_openai_box.add_child(_openai_key)
	root.add_child(_openai_box)
	_gemini_box = VBoxContainer.new()
	_gemini_box.add_theme_constant_override("separation", 8)
	_gemini_box.add_child(UI.lbl("模型名", 22, UI.INK, true))
	_gemini_model = _edit(cfg.gemini_model, "gemini-2.5-flash")
	_gemini_box.add_child(_gemini_model)
	_gemini_box.add_child(UI.lbl("API 密钥", 22, UI.INK, true))
	_gemini_key = _edit(cfg.gemini_api_key, "AIza…", true)
	_gemini_box.add_child(_gemini_key)
	root.add_child(_gemini_box)
	_sync_vis()
	root.add_child(UI.lbl("玩家人设（只存在本机）", 24, UI.INK, true))
	var ph := UI.lbl("生日可填 YYYY-MM-DD 或每年 MM-DD。也可以在畅聊里自然告诉她，抽取后会写进档案。", 18, UI.INK_SOFT)
	ph.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	ph.custom_minimum_size = Vector2(560, 0)
	root.add_child(ph)
	var persona := profile.load_persona()
	root.add_child(UI.lbl("怎么称呼你", 22, UI.INK, true))
	_persona_name = _edit(str(persona.get("name", "道友")), "道友")
	root.add_child(_persona_name)
	root.add_child(UI.lbl("生日", 22, UI.INK, true))
	_persona_birthday = _edit(str(persona.get("birthday", "")), "YYYY-MM-DD 或 MM-DD")
	root.add_child(_persona_birthday)
	return root


func save() -> void:
	var i := _provider.selected
	if i == 1:
		cfg.provider = ChatConfig.PROVIDER_OPENAI
	elif i == 2:
		cfg.provider = ChatConfig.PROVIDER_GEMINI
	else:
		cfg.provider = ChatConfig.PROVIDER_WORKER
	cfg.worker_url = _worker_url.text.strip_edges()
	if cfg.worker_url == "":
		cfg.worker_url = ChatConfig.DEFAULT_WORKER_URL
	cfg.openai_base_url = _openai_url.text.strip_edges()
	cfg.openai_model = _openai_model.text.strip_edges()
	cfg.openai_api_key = _openai_key.text.strip_edges()
	cfg.gemini_model = _gemini_model.text.strip_edges()
	cfg.gemini_api_key = _gemini_key.text.strip_edges()
	cfg.save()
	if _persona_name or _persona_birthday:
		profile.save_persona({
			"name": _persona_name.text.strip_edges() if _persona_name else "",
			"birthday": _persona_birthday.text.strip_edges() if _persona_birthday else "",
		})


func _sync_vis() -> void:
	var i := _provider.selected
	if _openai_box:
		_openai_box.visible = i == 1
	if _gemini_box:
		_gemini_box.visible = i == 2


func _edit(text: String, placeholder: String, secret: bool = false) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size = Vector2(560, 48)
	e.add_theme_font_size_override("font_size", 22)
	return e
