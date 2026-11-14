class_name ChatPanel
extends Control
## 畅聊面板：打字发送，可选 TTS。含记忆编辑、图片/听写脚手架、小窗模式。

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
var attach: ChatAttach
var _note := ""
var _waiting := false
var _attachments: Array = []
var _mini := false
var _web_bubble := false
var _dragging := false
var _drag_off := Vector2.ZERO
var _panel: PanelContainer
var _saved_win_size := Vector2i.ZERO
var _saved_win_pos := Vector2i.ZERO
var _saved_borderless := false
var _saved_on_top := false


func open_chat(id: String) -> void:
	char_id = id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	memory.open(id)
	anniversary.load_all()
	var evs: Array = anniversary.unclaimed_today({}, memory.first_meet_unix(), {
		"recruited_at": Game.recruited_at(id) if Game.is_recruited(id) else 0,
		"streak": int(Game.s.get("streak", 0)),
	})
	var ask := anniversary.birthday_prompt_needed()
	_note = anniversary.format_system_note(evs, ask)
	if ask:
		ChatProfile.new().mark_asked_birthday()
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
	_panel = panel
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
	var memb := UI.btn("记忆", "ghost", 22, Vector2(90, 52))
	memb.pressed.connect(_open_memory)
	head.add_child(memb)
	var minib := UI.btn("小窗", "ghost", 22, Vector2(90, 52))
	minib.pressed.connect(toggle_mini)
	head.add_child(minib)
	# 让标题栏可拖（网页气泡 / 桌面无边框）
	head.gui_input.connect(_on_head_gui)
	var hint := UI.lbl("每句话都会记在本机。可点「记忆」查看或删除。网页发图走文件选择；视频抽帧稍后接入。", 18, UI.INK_SOFT)
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
	var imgb := UI.btn("图片", "ghost", 22, Vector2(90, 56))
	imgb.pressed.connect(func(): attach.pick_image())
	row.add_child(imgb)
	var sttb := UI.btn("听写", "ghost", 22, Vector2(90, 56))
	sttb.pressed.connect(func(): attach.pick_audio())
	row.add_child(sttb)
	var vidb := UI.btn("视频", "ghost", 22, Vector2(90, 56))
	vidb.pressed.connect(func():
		_set_status("视频将在本地抽帧后再看，这一步稍后接入。"))
	row.add_child(vidb)
	client = ChatClient.new()
	add_child(client)
	client.chat_finished.connect(_on_chat)
	client.tts_finished.connect(_on_tts)
	client.summarize_finished.connect(_on_summarize)
	client.extract_finished.connect(_on_extract)
	client.vision_finished.connect(_on_vision)
	client.stt_finished.connect(_on_stt)
	attach = ChatAttach.new()
	add_child(attach)
	attach.file_picked.connect(_on_file)
	attach.cancelled.connect(func(): _set_status("没有选择文件。"))
	_sync_tts_btn()
	_maybe_background_memory()
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
	var packed := assembler.assemble(char_id, memory.recent(30), text, memory, _note, ChatPromptAssembler.DEFAULT_BUDGET, _attachments)
	_attachments = []
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
	_maybe_background_memory()
	if client.cfg.tts_enabled:
		client.tts(text, "ZH")
	_scroll_to_end()


func _on_tts(ok: bool, bytes: PackedByteArray) -> void:
	if not ok or bytes.is_empty():
		return
	var stream := _stream_from_audio_bytes(bytes)
	if stream == null:
		return
	player.stream = stream
	player.play()


func _stream_from_audio_bytes(bytes: PackedByteArray) -> AudioStream:
	if bytes.size() >= 12 and _bytes_ascii(bytes, 0, 4) == "RIFF" and _bytes_ascii(bytes, 8, 4) == "WAVE":
		return _wav_from_bytes(bytes)
	var mp3 := AudioStreamMP3.new()
	mp3.data = bytes
	return mp3


func _bytes_ascii(bytes: PackedByteArray, start: int, length: int) -> String:
	return bytes.slice(start, start + length).get_string_from_ascii()


func _wav_from_bytes(bytes: PackedByteArray) -> AudioStreamWAV:
	var offset := 12
	var channels := 1
	var rate := 44100
	var bits := 16
	var data := PackedByteArray()
	while offset + 8 <= bytes.size():
		var cid := _bytes_ascii(bytes, offset, 4)
		var csize := int(bytes.decode_u32(offset + 4))
		var cstart := offset + 8
		if cid == "fmt " and csize >= 16 and cstart + 16 <= bytes.size():
			channels = maxi(int(bytes.decode_u16(cstart + 2)), 1)
			rate = maxi(int(bytes.decode_u32(cstart + 4)), 1)
			bits = int(bytes.decode_u16(cstart + 14))
		elif cid == "data":
			data = bytes.slice(cstart, mini(cstart + csize, bytes.size()))
			break
		offset = cstart + csize
		if csize % 2 == 1:
			offset += 1
	if data.is_empty():
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS if bits == 8 else AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = channels > 1
	stream.data = data
	return stream


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


func _maybe_background_memory() -> void:
	if client == null:
		return
	if memory.needs_llm_summary():
		var hist: Array = memory.pending_summary_messages()
		if hist.is_empty():
			hist = memory.recent(24)
		client.summarize(hist)
	var fresh := memory.unextracted_messages()
	var users := 0
	for m in fresh:
		if str(m.get("role", "")) == "user":
			users += 1
	if users >= 1 and fresh.size() >= 2:
		client.extract_facts(fresh)


func _on_summarize(ok: bool, text: String, _raw: Dictionary) -> void:
	if ok and text != "":
		memory.apply_llm_summary(text)


func _on_extract(ok: bool, facts: Array, _raw: Dictionary) -> void:
	if not ok:
		return
	memory.mark_extracted()
	var profile := ChatProfile.new()
	for f in facts:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var kind := str(f.get("kind", "other"))
		var shared := kind in ["name", "like", "date"]
		if f.has("shared"):
			shared = bool(f.get("shared"))
		if shared:
			profile.add_shared_fact(f)
			if kind == "date" and (str(f.get("text", "")).find("生日") >= 0 or str(f.get("kind_hint", "")) == "birthday"):
				profile.apply_birthday(str(f.get("text", "")), str(f.get("date", "")))
		if not shared or kind == "promise":
			memory.merge_fact(f)
		elif kind == "like":
			# 喜好同时记一份在当前角色下，方便检索
			var cf: Dictionary = (f as Dictionary).duplicate()
			cf["scope"] = "char"
			memory.merge_fact(cf)


func _on_vision(ok: bool, text: String, _raw: Dictionary) -> void:
	if not ok or text.strip_edges() == "":
		_set_status(text if text != "" else "看图失败。")
		return
	_attachments.append({"kind": "image", "description": text.strip_edges()})
	_set_status("她已经在看这张图了。补一句要说的话，或直接发送。")
	if input and input.text.strip_edges() == "":
		input.text = "你看这张图。"


func _on_stt(ok: bool, text: String, _raw: Dictionary) -> void:
	if not ok or text.strip_edges() == "":
		_set_status(text if text != "" else "听写失败。麦克风实时采集稍后接入，现在可先选一段音频文件。")
		return
	if input:
		if input.text.strip_edges() != "":
			input.text = input.text + text
		else:
			input.text = text
	_set_status("听写完成，可以改一改再发送。")


func _on_file(kind: String, bytes: PackedByteArray, mime: String, _name: String) -> void:
	if bytes.is_empty():
		return
	var b64 := Marshalls.raw_to_base64(bytes)
	if kind == "audio":
		_set_status("正在听写……")
		client.stt(b64, mime)
	else:
		_set_status("正在看图……")
		client.vision(b64, "请用简体中文简要描述这张图片里有什么，不超过 120 字。", mime)


func _open_memory() -> void:
	var view := ChatMemoryView.new()
	add_child(view)
	view.setup(memory)


func toggle_mini() -> void:
	if OS.has_feature("web"):
		_web_bubble = not _web_bubble
		_apply_web_bubble()
		return
	_mini = not _mini
	var win := get_window()
	if _mini:
		_saved_win_size = win.size
		_saved_win_pos = win.position
		_saved_borderless = win.borderless
		_saved_on_top = win.always_on_top
		win.borderless = true
		win.always_on_top = true
		win.size = Vector2i(420, 680)
		_apply_compact_panel(true)
	else:
		win.borderless = _saved_borderless
		win.always_on_top = _saved_on_top
		if _saved_win_size != Vector2i.ZERO:
			win.size = _saved_win_size
			win.position = _saved_win_pos
		_apply_compact_panel(false)


func _apply_web_bubble() -> void:
	_apply_compact_panel(_web_bubble)


func _apply_compact_panel(compact: bool) -> void:
	if _panel == null:
		for c in get_children():
			if c is PanelContainer:
				_panel = c
				break
	if _panel == null:
		return
	if compact:
		_panel.position = Vector2(20, 200)
		_panel.size = Vector2(460, 820)
		if scroll:
			scroll.custom_minimum_size = Vector2(420, 480)
	else:
		_panel.position = Vector2(20, 80)
		_panel.size = Vector2(680, 1120)
		if scroll:
			scroll.custom_minimum_size = Vector2(620, 760)


func _on_head_gui(event: InputEvent) -> void:
	if not (_mini or _web_bubble):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _panel:
			_drag_off = event.position
		if OS.has_feature("web") == false and event.pressed:
			pass
	elif event is InputEventMouseMotion and _dragging:
		if OS.has_feature("web"):
			if _panel:
				_panel.position += event.relative
		else:
			var win := get_window()
			win.position = win.position + Vector2i(event.relative)


func _exit_tree() -> void:
	if _mini and not OS.has_feature("web"):
		var win := get_window()
		win.borderless = _saved_borderless
		win.always_on_top = _saved_on_top
		if _saved_win_size != Vector2i.ZERO:
			win.size = _saved_win_size
			win.position = _saved_win_pos
