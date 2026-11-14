class_name ChatPanel
extends Control
## 畅聊面板：打字发送，可选把回复交给 Worker 的 MeloTTS 出声。P1 本地骨架。

var main: Control
var char_id := ""
var assembler := ChatPromptAssembler.new()
var memory := ChatMemory.new()
var anniversary := ChatAnniversary.new()
var client: ChatClient
var player: AudioStreamPlayer

var log_box: VBoxContainer
var scroll: ScrollContainer
var input: LineEdit
var send_btn: Button
var status_lbl: Label
var tts_btn: Button
var title_lbl: Label
var _note := ""
var _waiting := false


func open_chat(id: String) -> void:
	char_id = id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	memory.open(id)
	anniversary.load_all()
	_note = anniversary.format_system_note(anniversary.due_today({}, memory.first_meet_unix()))
	memory.maybe_roll_summary()
	_build()
	_hydrate()


func _build() -> void:
	var d := Data.char_def(char_id)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.07, 0.14, 0.55)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 80)
	panel.size = Vector2(680, 1120)
	panel.add_theme_stylebox_override("panel", UI.panel(Color(1, 0.985, 0.95, 0.97), d.get("color", UI.GOLD), 28, 3))
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	var back := UI.btn("返回", "dark", 24, Vector2(110, 52))
	back.pressed.connect(func():
		if main:
			main.close_free_chat())
	head.add_child(back)
	title_lbl = UI.brush_lbl("%s·畅聊" % str(d.get("title", "")), 44, d.get("color", UI.INK).darkened(0.2), HORIZONTAL_ALIGNMENT_LEFT)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_lbl)
	tts_btn = UI.btn("语音开", "ghost", 22, Vector2(110, 52))
	tts_btn.pressed.connect(_toggle_tts)
	head.add_child(tts_btn)
	var setb := UI.btn("接口", "ghost", 22, Vector2(90, 52))
	setb.pressed.connect(func():
		if main:
			main.open_chat_settings())
	head.add_child(setb)
	var hint := UI.lbl("草稿人设 · 每句话都会记在本机。连上 Worker 后才能得到新回复。", 18, UI.INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	hint.custom_minimum_size = Vector2(620, 0)
	root.add_child(hint)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(620, 760)
	root.add_child(scroll)
	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_theme_constant_override("separation", 10)
	scroll.add_child(log_box)
	status_lbl = UI.lbl("", 20, UI.INK_SOFT)
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	status_lbl.custom_minimum_size = Vector2(620, 0)
	root.add_child(status_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	input = LineEdit.new()
	input.placeholder_text = "对她说点什么……"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 56)
	input.add_theme_font_size_override("font_size", 24)
	input.text_submitted.connect(func(_t): _send())
	row.add_child(input)
	send_btn = UI.btn("发送", "jade", 26, Vector2(130, 56))
	send_btn.pressed.connect(_send)
	row.add_child(send_btn)
	client = ChatClient.new()
	add_child(client)
	client.chat_finished.connect(_on_chat)
	client.tts_finished.connect(_on_tts)
	_sync_tts_btn()
	player = AudioStreamPlayer.new()
	if AudioServer.get_bus_index("Voice") >= 0:
		player.bus = "Voice"
	player.playback_type = AudioServer.PLAYBACK_TYPE_DEFAULT
	add_child(player)


func _hydrate() -> void:
	var hist: Array = memory.data.get("messages", [])
	if hist.is_empty():
		var packed := assembler.assemble(char_id, [], "", memory, _note)
		var first := str(packed.get("first_mes", "")).strip_edges()
		if first != "":
			_bubble("assistant", first)
			memory.append("assistant", first, {"kind": "first_mes"})
	else:
		for m in hist:
			_bubble(str(m.get("role", "assistant")), str(m.get("content", "")))
	if _note != "":
		_set_status("今天有纪念日，她会记得的。")
	_scroll_to_end()


func _send() -> void:
	var text := input.text.strip_edges()
	if text == "" or _waiting:
		return
	input.text = ""
	memory.append("user", text)
	_bubble("user", text)
	_waiting = true
	send_btn.disabled = true
	_set_status("正在请她想一想……")
	var packed := assembler.assemble(char_id, memory.recent(30), text, memory, _note)
	client.chat(packed["messages"])


func _on_chat(ok: bool, text: String, _raw: Dictionary) -> void:
	_waiting = false
	send_btn.disabled = false
	if not ok:
		_set_status(text)
		return
	memory.append("assistant", text)
	_bubble("assistant", text)
	_set_status("")
	memory.maybe_roll_summary()
	if client.cfg.tts_enabled:
		client.tts(text, "ZH")
	_scroll_to_end()


func _on_tts(ok: bool, bytes: PackedByteArray) -> void:
	if not ok or bytes.is_empty():
		return
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	player.stream = stream
	player.play()


func _toggle_tts() -> void:
	client.cfg.tts_enabled = not client.cfg.tts_enabled
	client.cfg.save()
	_sync_tts_btn()


func _sync_tts_btn() -> void:
	if tts_btn and client:
		tts_btn.text = "语音开" if client.cfg.tts_enabled else "语音关"


func _bubble(role: String, text: String) -> void:
	var who := "你" if role == "user" else str(Data.char_def(char_id).get("title", "她"))
	var color := UI.JADE_DEEP if role == "user" else UI.INK
	var wrap := PanelContainer.new()
	var bg := UI.PAPER_DIM if role != "user" else Color(0.88, 0.95, 0.93, 0.95)
	wrap.add_theme_stylebox_override("panel", UI.panel(bg, Color(0.85, 0.7, 0.4, 0.45), 18, 1, false))
	var vb := VBoxContainer.new()
	wrap.add_child(vb)
	vb.add_child(UI.lbl(who, 18, UI.INK_SOFT, true))
	var body := UI.lbl(text, 24, color)
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.custom_minimum_size = Vector2(580, 0)
	vb.add_child(body)
	log_box.add_child(wrap)
	_scroll_to_end()


func _set_status(t: String) -> void:
	if status_lbl:
		status_lbl.text = t


func _scroll_to_end() -> void:
	await get_tree().process_frame
	if scroll:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
