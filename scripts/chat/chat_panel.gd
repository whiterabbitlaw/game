class_name ChatPanel
extends Control
## 畅聊面板：打字发送，实时语音（按住说 / 免提），逐句 TTS，网页抽帧看视频，PWA / 画中画小窗。

var main: Control
var char_id := ""
var assembler := ChatPromptAssembler.new()
var memory := ChatMemory.new()
var anniversary := ChatAnniversary.new()
var client: ChatClient
var player: AudioStreamPlayer
var voice: ChatVoiceSession

var log_box: VBoxContainer
var scroll: ScrollContainer
var input: LineEdit
var send_btn: Button
var status_lbl: Label
var tts_btn: Button
var title_lbl: Label
var ptt_btn: Button
var hands_btn: Button
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
var _play_q: Array = []
var _voice_stt := false
var _vision_expect := 0
var _vision_parts: PackedStringArray = PackedStringArray()
var _hint: Label
var _dim: ColorRect
var _ptt_held := false
var _drag_ready := false
var _wait_gen := 0


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
	_maybe_phone_compact()


func _build() -> void:
	var d := Data.char_def(char_id)
	var dim := ColorRect.new()
	_dim = dim
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.07, 0.14, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
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
	head.gui_input.connect(_on_head_gui)
	_hint = UI.lbl("每句话都会记在本机。可按住说话或开免提；她会逐句读出来，你开口就能打断。网页可发图、抽视频帧，也可安装到主屏。", 18, UI.INK_SOFT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_hint.custom_minimum_size = Vector2(620, 0)
	root.add_child(_hint)
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
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 8)
	root.add_child(vrow)
	ptt_btn = UI.btn("按住说", "ghost", 22, Vector2(150, 56))
	ptt_btn.button_down.connect(_on_ptt_down)
	ptt_btn.button_up.connect(_on_ptt_up)
	vrow.add_child(ptt_btn)
	hands_btn = UI.btn("免提", "ghost", 22, Vector2(110, 56))
	hands_btn.pressed.connect(_toggle_handsfree)
	vrow.add_child(hands_btn)
	if OS.has_feature("web"):
		var pipb := UI.btn("画中画", "ghost", 22, Vector2(110, 56))
		pipb.pressed.connect(func():
			if voice:
				voice.open_pip())
		vrow.add_child(pipb)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	root.add_child(mrow)
	var imgb := UI.btn("图片", "ghost", 22, Vector2(90, 56))
	imgb.pressed.connect(func(): attach.pick_image())
	mrow.add_child(imgb)
	var sttb := UI.btn("听写", "ghost", 22, Vector2(90, 56))
	sttb.pressed.connect(func(): attach.pick_audio())
	mrow.add_child(sttb)
	var vidb := UI.btn("视频", "ghost", 22, Vector2(90, 56))
	vidb.pressed.connect(_pick_video)
	mrow.add_child(vidb)
	client = ChatClient.new()
	add_child(client)
	client.chat_finished.connect(_on_chat)
	client.tts_chunk_ready.connect(_on_tts_chunk)
	client.summarize_finished.connect(_on_summarize)
	client.extract_finished.connect(_on_extract)
	client.vision_finished.connect(_on_vision)
	client.stt_finished.connect(_on_stt)
	attach = ChatAttach.new()
	add_child(attach)
	attach.file_picked.connect(_on_file)
	attach.cancelled.connect(func():
		if not OS.has_feature("web") and status_lbl and status_lbl.text.begins_with("正在"):
			return
		_set_status("没有选择文件。"))
	voice = ChatVoiceSession.new()
	add_child(voice)
	voice.utterance_ready.connect(_on_utterance)
	voice.state_changed.connect(_on_voice_state)
	voice.error_text.connect(func(msg: String): _set_status(msg))
	voice.frames_ready.connect(_on_video_frames)
	voice.pip_event.connect(_on_pip_event)
	set_process_input(true)
	set_process_unhandled_input(true)
	_sync_tts_btn()
	_maybe_background_memory()
	player = AudioStreamPlayer.new()
	if AudioServer.get_bus_index("Voice") >= 0:
		player.bus = "Voice"
	player.playback_type = AudioServer.PLAYBACK_TYPE_DEFAULT
	player.finished.connect(_on_player_finished)
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
	_interrupt_speech()
	memory.append("user", text)
	_bubble("user", text)
	_waiting = true
	if send_btn:
		send_btn.disabled = true
	if voice:
		voice.set_state(ChatVoiceSession.STATE_THINKING)
	_set_status("正在想…")
	_arm_wait_timeout(30.0, "想太久了，请再试一次。")
	var packed := assembler.assemble(char_id, memory.recent(30), text, memory, _note, ChatPromptAssembler.DEFAULT_BUDGET, _attachments)
	_attachments = []
	client.chat(packed["messages"])


func _clear_wait() -> void:
	_wait_gen += 1
	_waiting = false
	if send_btn:
		send_btn.disabled = false


func _arm_wait_timeout(sec: float, msg: String) -> void:
	_wait_gen += 1
	var g := _wait_gen
	get_tree().create_timer(sec).timeout.connect(func():
		if g != _wait_gen:
			return
		if not _waiting:
			return
		_clear_wait()
		_set_status(msg)
		if voice:
			voice.set_busy(false)
			if voice.mode == "handsfree":
				voice.set_state(ChatVoiceSession.STATE_LISTENING, "免提")
			else:
				voice.set_state(ChatVoiceSession.STATE_IDLE)
	)


func _on_chat(ok: bool, text: String, _raw: Dictionary) -> void:
	_clear_wait()
	if not ok:
		_set_status(text)
		if voice:
			if voice.mode == "handsfree":
				voice.set_state(ChatVoiceSession.STATE_LISTENING, "免提")
			else:
				voice.set_state(ChatVoiceSession.STATE_IDLE)
		return
	memory.append("assistant", text)
	_bubble("assistant", text)
	_set_status("")
	memory.maybe_roll_summary()
	_maybe_background_memory()
	if client.cfg.tts_enabled:
		_speak_reply(text)
	elif voice:
		if voice.mode == "handsfree":
			voice.set_state(ChatVoiceSession.STATE_LISTENING, "免提")
		else:
			voice.set_state(ChatVoiceSession.STATE_IDLE)
	_scroll_to_end()


func _speak_reply(text: String) -> void:
	_interrupt_speech()
	var parts: PackedStringArray = ChatTextUtil.split_sentences(text)
	if parts.is_empty():
		if voice and voice.mode == "handsfree":
			voice.set_state(ChatVoiceSession.STATE_LISTENING, "免提")
		return
	if voice:
		voice.set_state(ChatVoiceSession.STATE_SPEAKING)
		voice.set_tts_playing(true)
	_set_status("正在说…")
	for s in parts:
		client.tts_push(s, "ZH")


func _on_tts_chunk(ok: bool, bytes: PackedByteArray, _text: String) -> void:
	if not ok or bytes.is_empty():
		_kick_play()
		return
	var stream := _stream_from_audio_bytes(bytes)
	if stream:
		_play_q.append(stream)
	_kick_play()


func _kick_play() -> void:
	if player and player.playing:
		return
	if _play_q.is_empty():
		if client == null or not client.tts_pending():
			if voice:
				voice.set_tts_playing(false)
				if voice.mode == "handsfree":
					voice.set_state(ChatVoiceSession.STATE_LISTENING, "免提")
				else:
					voice.set_state(ChatVoiceSession.STATE_IDLE)
			if status_lbl and status_lbl.text.begins_with("正在说"):
				_set_status("")
		return
	if player == null:
		return
	player.stream = _play_q.pop_front()
	player.play()
	if voice:
		voice.set_tts_playing(true)
		voice.set_state(ChatVoiceSession.STATE_SPEAKING)
	_set_status("正在说…")


func _on_player_finished() -> void:
	_kick_play()


func _interrupt_speech() -> void:
	if client:
		client.tts_clear()
	_play_q.clear()
	if player and player.playing:
		player.stop()
	if voice:
		voice.set_tts_playing(false)


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
	set_process_input(true)
	set_process_unhandled_input(true)
	_sync_tts_btn()
	if not client.cfg.tts_enabled:
		_interrupt_speech()


func _sync_tts_btn() -> void:
	if tts_btn and client:
		tts_btn.text = "语音开" if client.cfg.tts_enabled else "语音关"


func _on_ptt_down() -> void:
	_ptt_held = true
	_interrupt_speech()
	if voice:
		voice.ptt_down()


func _on_ptt_up() -> void:
	if not _ptt_held:
		return
	_ptt_held = false
	if voice:
		voice.ptt_up()


func _unhandled_input(event: InputEvent) -> void:
	_maybe_release_ptt(event)


func _input(event: InputEvent) -> void:
	_maybe_release_ptt(event)


func _maybe_release_ptt(event: InputEvent) -> void:
	if not _ptt_held:
		return
	var released := false
	if event is InputEventScreenTouch and not event.pressed:
		released = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		released = true
	if released:
		_on_ptt_up()


func _toggle_handsfree() -> void:
	if voice == null:
		return
	if voice.mode == "handsfree" and voice.state != ChatVoiceSession.STATE_IDLE:
		voice.stop_handsfree()
		if hands_btn:
			hands_btn.text = "免提"
		return
	_interrupt_speech()
	voice.start_handsfree()
	if hands_btn:
		hands_btn.text = "免提中"


func _on_voice_state(s: String, detail: String) -> void:
	if s == ChatVoiceSession.STATE_LISTENING and detail == "打断":
		_interrupt_speech()
	match s:
		ChatVoiceSession.STATE_LISTENING:
			_set_status("正在听…" + (("（%s）" % detail) if detail != "" else ""))
		ChatVoiceSession.STATE_THINKING:
			_set_status("正在想…")
		ChatVoiceSession.STATE_SPEAKING:
			_set_status("正在说…")
		ChatVoiceSession.STATE_IDLE:
			if not _waiting and status_lbl and (status_lbl.text.begins_with("正在听") or status_lbl.text.begins_with("正在说") or status_lbl.text.begins_with("正在想")):
				_set_status("")
	if hands_btn and voice:
		hands_btn.text = "免提中" if voice.mode == "handsfree" and s != ChatVoiceSession.STATE_IDLE else "免提"
	_sync_pip_status()


func _on_utterance(wav: PackedByteArray, _mime: String) -> void:
	_interrupt_speech()
	if wav.is_empty():
		_set_status("没有录到声音。")
		return
	_voice_stt = true
	if voice:
		voice.set_state(ChatVoiceSession.STATE_THINKING)
	_set_status("正在听写…")
	_arm_wait_timeout(20.0, "听写超时，请再试一次。")
	# _waiting is also used so the watchdog can reset listening state
	_waiting = true
	client.stt(Marshalls.raw_to_base64(wav), "wav", "zh")


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
	body.custom_minimum_size = Vector2(580 if not _web_bubble and not _mini else 400, 0)
	vb.add_child(body)
	log_box.add_child(wrap)
	_scroll_to_end()
	if voice:
		voice.update_pip({"role": role, "who": who, "line": text, "status": status_lbl.text if status_lbl else ""})


func _set_status(t: String) -> void:
	if status_lbl:
		status_lbl.text = t
	_sync_pip_status()


func _sync_pip_status() -> void:
	if voice:
		voice.update_pip({"status": status_lbl.text if status_lbl else ""})


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
			var cf: Dictionary = (f as Dictionary).duplicate()
			cf["scope"] = "char"
			memory.merge_fact(cf)


func _on_vision(ok: bool, text: String, _raw: Dictionary) -> void:
	if _vision_expect > 0:
		var n := _vision_parts.size() + 1
		var piece := text.strip_edges() if ok and text.strip_edges() != "" else "看不清"
		_vision_parts.append("第%d帧：%s" % [n, piece])
		_vision_expect -= 1
		if _vision_expect == 0:
			var summary := "这段视频里依次看到：\n" + "\n".join(_vision_parts)
			_attachments.append({"kind": "video", "description": summary})
			_set_status("她已经在看这段视频了。补一句要说的话，或直接发送。")
			if input and input.text.strip_edges() == "":
				input.text = "你看这段视频。"
		else:
			_set_status("正在看视频（%d 帧完成）…" % _vision_parts.size())
		return
	if not ok or text.strip_edges() == "":
		_set_status(text if text != "" else "看图失败。")
		return
	_attachments.append({"kind": "image", "description": text.strip_edges()})
	_set_status("她已经在看这张图了。补一句要说的话，或直接发送。")
	if input and input.text.strip_edges() == "":
		input.text = "你看这张图。"


func _on_stt(ok: bool, text: String, _raw: Dictionary) -> void:
	if _voice_stt:
		_voice_stt = false
		_clear_wait()
		text = ChatTextUtil.to_simplified(text.strip_edges())
		if not ok or text == "":
			_set_status(text if text != "" else "没听清，请再试一次。")
			if voice and voice.mode == "handsfree":
				voice.set_state(ChatVoiceSession.STATE_LISTENING, "免提")
			elif voice:
				voice.set_state(ChatVoiceSession.STATE_IDLE)
			return
		if input:
			input.text = text.strip_edges()
		_send()
		return
	if not ok or text.strip_edges() == "":
		_set_status(text if text != "" else "听写失败。也可按住说话，或先选一段音频文件。")
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
		client.stt(b64, "wav" if mime.find("wav") >= 0 else mime, "zh")
	else:
		_set_status("正在看图……")
		client.vision(b64, "请用简体中文简要描述这张图片里有什么，不超过 120 字。", mime)


func _pick_video() -> void:
	if OS.has_feature("web"):
		_set_status("请选择一段视频，将在本地抽 3–4 帧…")
		if voice:
			voice.pick_video()
		elif attach:
			attach.pick_video()
		return
	_set_status("视频抽帧目前在网页版可用，请用浏览器打开后再点「视频」。")


func _on_video_frames(frames: Array, _name: String) -> void:
	if frames.is_empty():
		_set_status("没有抽到视频帧。")
		return
	_vision_parts = PackedStringArray()
	_vision_expect = 0
	var usable: Array = []
	for fr in frames:
		if typeof(fr) != TYPE_DICTIONARY:
			continue
		if str((fr as Dictionary).get("data", "")) == "":
			continue
		usable.append(fr)
	if usable.is_empty():
		_set_status("没有抽到视频帧。")
		return
	_vision_expect = usable.size()
	_set_status("正在看视频（0/%d）…" % _vision_expect)
	for fr2 in usable:
		var fd: Dictionary = fr2
		client.vision(str(fd.get("data", "")), "请用简体中文简要描述这一帧画面里有什么，不超过 80 字。不要评论拍摄质量。", str(fd.get("mime", "image/jpeg")))


func _on_pip_event(event: String, payload: Dictionary) -> void:
	match event:
		"send":
			var t := str(payload.get("text", "")).strip_edges()
			if t == "":
				return
			if input:
				input.text = t
			_send()
		"ptt_down":
			_on_ptt_down()
		"ptt_up":
			_on_ptt_up()
		"unsupported":
			_set_status("当前浏览器不支持文档画中画。桌面 Chrome 可用；手机请用「小窗」气泡或把网页安装到主屏。")
		"error":
			_set_status(str(payload.get("message", "无法打开画中画")))
		"opened":
			_set_status("画中画小窗已打开。")
			_sync_pip_status()
		"closed":
			pass


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


func _maybe_phone_compact() -> void:
	var mobile := false
	if OS.has_feature("mobile"):
		mobile = true
	elif OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval("!!(/Mobi|Android|iPhone|iPad/i.test(navigator.userAgent) || (Math.min(window.innerWidth||9999, window.innerHeight||9999) < 560))", true)
		mobile = str(raw) == "true" or raw == true or str(raw) == "1"
	if mobile:
		_web_bubble = true
		_apply_compact_panel(true)


func _apply_compact_panel(compact: bool) -> void:
	if _panel == null:
		for c in get_children():
			if c is PanelContainer:
				_panel = c
				break
	if _panel == null:
		return
	# 手机气泡不要用全屏遮罩吞掉点击；只让气泡自己接收触摸。
	if compact:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _dim:
			_dim.visible = false
			_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_panel.position = Vector2(20, 200)
		_panel.size = Vector2(460, 820)
		if scroll:
			scroll.custom_minimum_size = Vector2(420, 420)
		if _hint:
			_hint.custom_minimum_size = Vector2(420, 0)
		if status_lbl:
			status_lbl.custom_minimum_size = Vector2(420, 0)
	else:
		mouse_filter = Control.MOUSE_FILTER_STOP
		if _dim:
			_dim.visible = true
			_dim.mouse_filter = Control.MOUSE_FILTER_STOP
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_panel.position = Vector2(20, 80)
		_panel.size = Vector2(680, 1120)
		if scroll:
			scroll.custom_minimum_size = Vector2(620, 760)
		if _hint:
			_hint.custom_minimum_size = Vector2(620, 0)
		if status_lbl:
			status_lbl.custom_minimum_size = Vector2(620, 0)


func _on_head_gui(event: InputEvent) -> void:
	if not (_mini or _web_bubble):
		return
	# 点在按钮上不要开始拖，否则手机上轻轻一滑就吃掉点击。
	if _is_press_on_button(event):
		_dragging = false
		_drag_ready = false
		return
	var pressed := false
	var released := false
	var rel := Vector2.ZERO
	if event is InputEventScreenTouch:
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		rel = event.relative
	elif event is InputEventMouseMotion:
		rel = event.relative
	if pressed:
		_drag_ready = true
		_dragging = false
		_drag_off = event.position
		return
	if released:
		_drag_ready = false
		_dragging = false
		return
	if rel != Vector2.ZERO and _drag_ready:
		if not _dragging:
			if rel.length() < 12.0:
				return
			_dragging = true
		if OS.has_feature("web"):
			if _panel:
				_panel.position += rel
		else:
			var win := get_window()
			win.position = win.position + Vector2i(rel)
		accept_event()


func _is_press_on_button(event: InputEvent) -> bool:
	if not ((event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)):
		return false
	var hovered := get_viewport().gui_get_hovered_control() if get_viewport() else null
	var n: Control = hovered
	while n:
		if n is BaseButton:
			return true
		n = n.get_parent() as Control
	return false


func _exit_tree() -> void:
	_interrupt_speech()
	if voice:
		voice.close_pip()
	if _mini and not OS.has_feature("web"):
		var win := get_window()
		win.borderless = _saved_borderless
		win.always_on_top = _saved_on_top
		if _saved_win_size != Vector2i.ZERO:
			win.size = _saved_win_size
			win.position = _saved_win_pos
