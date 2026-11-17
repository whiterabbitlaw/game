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
var _vision_busy := false
var _pending_image_name := ""
var _img_btn: Button
var _attach_lbl: Label
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
var _keyboard_inset := 0.0
var _web_input: ChatWebInput
var _ime_target: LineEdit
var _ime_submit: Callable
var _fitting := false
var _ime_poll := 0.0
var _last_ime_sig := ""


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
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UI.panel(Color(1, 0.985, 0.95, 0.97), d.get("color", UI.GOLD), 28, 3))
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	var back := _flex_btn("返回", "dark")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size = Vector2(88, 46)
	back.pressed.connect(func():
		if main:
			main.close_free_chat())
	head.add_child(back)
	title_lbl = UI.brush_lbl("%s·畅聊" % str(d.get("title", "")), 34, d.get("color", UI.INK).darkened(0.2), HORIZONTAL_ALIGNMENT_LEFT)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.clip_text = true
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.custom_minimum_size = Vector2(0, 0)
	head.add_child(title_lbl)
	head.gui_input.connect(_on_head_gui)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	tts_btn = _flex_btn("语音开", "ghost")
	tts_btn.pressed.connect(_toggle_tts)
	actions.add_child(tts_btn)
	var setb := _flex_btn("接口", "ghost")
	setb.pressed.connect(func():
		if main:
			main.open_chat_settings())
	actions.add_child(setb)
	var memb := _flex_btn("记忆", "ghost")
	memb.pressed.connect(_open_memory)
	actions.add_child(memb)
	var minib := _flex_btn("小窗", "ghost")
	minib.pressed.connect(toggle_mini)
	actions.add_child(minib)
	actions.gui_input.connect(_on_head_gui)
	_hint = UI.lbl("每句话都会记在本机。可按住说话或开免提；她会逐句读出来，你开口就能打断。网页可发图、抽视频帧，也可安装到主屏。", 18, UI.INK_SOFT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_hint.custom_minimum_size = Vector2(0, 0)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_hint)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 72)
	root.add_child(scroll)
	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_theme_constant_override("separation", 10)
	scroll.add_child(log_box)
	status_lbl = UI.lbl("", 20, UI.INK_SOFT)
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	status_lbl.custom_minimum_size = Vector2(0, 0)
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(status_lbl)
	_attach_lbl = UI.lbl("", 18, UI.INK)
	_attach_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_attach_lbl.custom_minimum_size = Vector2(0, 0)
	_attach_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attach_lbl.visible = false
	root.add_child(_attach_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	input = LineEdit.new()
	input.placeholder_text = "对她说点什么……"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 52)
	input.add_theme_font_size_override("font_size", 22)
	input.text_submitted.connect(func(_t): _send())
	row.add_child(input)
	send_btn = _flex_btn("发送", "jade")
	send_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	send_btn.custom_minimum_size = Vector2(88, 52)
	send_btn.pressed.connect(_send)
	row.add_child(send_btn)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 8)
	root.add_child(vrow)
	ptt_btn = _flex_btn("按住说", "ghost")
	ptt_btn.button_down.connect(_on_ptt_down)
	ptt_btn.button_up.connect(_on_ptt_up)
	vrow.add_child(ptt_btn)
	hands_btn = _flex_btn("免提", "ghost")
	hands_btn.pressed.connect(_toggle_handsfree)
	vrow.add_child(hands_btn)
	if OS.has_feature("web"):
		var pipb := _flex_btn("画中画", "ghost")
		pipb.pressed.connect(func():
			if voice:
				voice.open_pip())
		vrow.add_child(pipb)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	root.add_child(mrow)
	var imgb := _flex_btn("图片", "ghost")
	_img_btn = imgb
	imgb.pressed.connect(func(): attach.pick_image())
	mrow.add_child(imgb)
	var sttb := _flex_btn("听写", "ghost")
	sttb.pressed.connect(func(): attach.pick_audio())
	mrow.add_child(sttb)
	var vidb := _flex_btn("视频", "ghost")
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
	attach.pick_failed.connect(_on_pick_failed)
	attach.cancelled.connect(func():
		if _vision_busy:
			return
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
	if OS.has_feature("web"):
		_web_input = ChatWebInput.new()
		add_child(_web_input)
		_web_input.setup()
		if _web_input.available():
			input.virtual_keyboard_enabled = false
			input.focus_mode = Control.FOCUS_NONE
			input.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_web_input.text_event.connect(_on_ime_text)
			_web_input.submit_event.connect(_on_ime_submit)
			_web_input.inset_event.connect(_on_ime_inset)
			_bind_ime(input, _send)
			set_process(true)
	_fit_panel()
	if not get_viewport().size_changed.is_connected(_fit_panel):
		get_viewport().size_changed.connect(_fit_panel)


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
	_pull_ime_into(input)
	var text := input.text.strip_edges() if input else ""
	if _vision_busy:
		_set_status("图片还在看。看完，或出现失败提示之后，再发送。")
		return
	if _waiting:
		return
	if text == "" and _attachments.is_empty():
		return
	var stored := ChatVision.compose_stored(text, _attachments)
	var prior: Array = memory.recent(30)
	_set_composer("")
	_show_attach("")
	_interrupt_speech()
	memory.append("user", stored)
	_bubble("user", stored)
	_waiting = true
	if send_btn:
		send_btn.disabled = true
	if voice:
		voice.set_state(ChatVoiceSession.STATE_THINKING)
	_set_status("正在想…")
	_arm_wait_timeout(30.0, "想太久了，请再试一次。")
	var packed := assembler.assemble(char_id, prior, stored, memory, _note, ChatPromptAssembler.DEFAULT_BUDGET, _attachments)
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
	if not ok or text.strip_edges() == "":
		_set_status(text if text.strip_edges() != "" else "她没有说出话。请再试一次。")
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
	var body := UI.lbl(text, 22, color)
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.custom_minimum_size = Vector2(0, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
				_set_composer("你看这段视频。")
		else:
			_set_status("正在看视频（%d 帧完成）…" % _vision_parts.size())
		return
	_vision_busy = false
	if not ok or text.strip_edges() == "":
		_attachments = []
		var fail := ChatVision.explain_vision_error(text)
		_show_attach(fail)
		_set_status(fail)
		return
	_attachments = [{"kind": "image", "description": text.strip_edges(), "name": _pending_image_name}]
	var seen := "已看到：%s" % text.strip_edges()
	_show_attach(seen)
	_set_status("画面已记下。再问她时会按这些细节回答；描述不对就再发一次图。")


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
		_set_composer(text.strip_edges())
		_send()
		return
	if not ok or text.strip_edges() == "":
		_set_status(text if text != "" else "听写失败。也可按住说话，或先选一段音频文件。")
		return
	if input:
		var merged := text if input.text.strip_edges() == "" else input.text + text
		_set_composer(merged)
	_set_status("听写完成，可以改一改再发送。")


func _on_pick_failed(message: String) -> void:
	_vision_busy = false
	_attachments = []
	_show_attach(message)
	_set_status(message)


func _on_file(kind: String, bytes: PackedByteArray, mime: String, name: String) -> void:
	if bytes.is_empty():
		_on_pick_failed("没有读到文件。")
		return
	if kind == "audio":
		_set_status("正在听写……")
		client.stt(Marshalls.raw_to_base64(bytes), "wav" if mime.find("wav") >= 0 else mime, "zh")
		return
	var prepared := ChatVision.prepare_image(bytes, mime)
	if not bool(prepared.get("ok", false)):
		_on_pick_failed(str(prepared.get("error", "这张图打不开。")))
		return
	_pending_image_name = name
	_vision_busy = true
	_attachments = []
	var label := name if name != "" else "图片"
	_show_attach("正在看图：%s。看完之前发送不会带上画面。" % label)
	_set_status("正在看图：%s" % label)
	client.vision(str(prepared.get("b64", "")), ChatVision.PROMPT, str(prepared.get("mime", "image/jpeg")))


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
			_set_composer(t)
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
	view.pull_text = _pull_ime_value
	view.push_text = _push_ime_text
	view.closed.connect(_on_memory_closed)
	add_child(view)
	view.setup(memory)
	if view.composer():
		_bind_ime(view.composer(), view._on_add)


func toggle_mini() -> void:
	if OS.has_feature("web"):
		_web_bubble = not _web_bubble
		_fit_panel()
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
	else:
		win.borderless = _saved_borderless
		win.always_on_top = _saved_on_top
		if _saved_win_size != Vector2i.ZERO:
			win.size = _saved_win_size
			win.position = _saved_win_pos
	_fit_panel()


func _maybe_phone_compact() -> void:
	# 手机不再强制缩小成固定气泡。固定宽度小于标题栏最小宽度时，面板会被撑出视口右侧。
	_fit_panel()


func _layout_bubble() -> bool:
	return _web_bubble or _mini


func _fit_panel() -> void:
	if _fitting or _panel == null or not is_inside_tree():
		return
	_fitting = true
	var vp := get_viewport_rect().size
	if vp.x < 8.0 or vp.y < 8.0:
		vp = Vector2(720, 1280)
	var rect := ChatLayout.bubble_rect(vp, _keyboard_inset) if _layout_bubble() else ChatLayout.fit_rect(vp, 12.0, _keyboard_inset)
	if _layout_bubble() and _panel.size.x > 1.0 and _panel.position != Vector2.ZERO:
		rect.position = ChatLayout.clamp_pos(_panel.position, rect.size, vp)
	_apply_panel_rect(rect)
	var bubble := _layout_bubble()
	mouse_filter = Control.MOUSE_FILTER_IGNORE if bubble else Control.MOUSE_FILTER_STOP
	if _dim:
		_dim.visible = not bubble
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE if bubble else Control.MOUSE_FILTER_STOP
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if _hint:
		_hint.visible = not bubble and _keyboard_inset < 160.0
	if scroll:
		scroll.custom_minimum_size = Vector2(0, 0 if _keyboard_inset > 200.0 else 72)
	_fitting = false
	_last_ime_sig = ""
	_sync_ime_rect()


func _apply_panel_rect(r: Rect2) -> void:
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = r.position.x
	_panel.offset_top = r.position.y
	_panel.offset_right = r.end.x
	_panel.offset_bottom = r.end.y
	_panel.clip_contents = true


func _flex_btn(text: String, kind: String) -> Button:
	var b := UI.btn(text, kind, 20, Vector2(0, 46))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := b.get_theme_stylebox(state_name)
		if sb is StyleBoxFlat:
			var flat := (sb as StyleBoxFlat).duplicate()
			flat.content_margin_left = 6
			flat.content_margin_right = 6
			flat.content_margin_top = 4
			flat.content_margin_bottom = 4
			b.add_theme_stylebox_override(state_name, flat)
	return b


func _process(delta: float) -> void:
	if _web_input == null or not _web_input.available():
		return
	_ime_poll += delta
	if _ime_poll < 0.12:
		return
	_ime_poll = 0.0
	var vp := get_viewport_rect().size
	var inset := _web_input.poll_inset(vp)
	if absf(inset - _keyboard_inset) > 1.5:
		_keyboard_inset = inset
		_fit_panel()
	_sync_ime_rect(true)


func _bind_ime(target: LineEdit, on_submit: Callable) -> void:
	_ime_target = target
	_ime_submit = on_submit
	_last_ime_sig = ""
	if _web_input == null or not _web_input.available() or target == null:
		return
	var label := target.placeholder_text if target.placeholder_text != "" else "输入"
	_web_input.open_field(target.placeholder_text, label)
	_web_input.set_text(target.text)
	_sync_ime_rect()


func _current_ime_target() -> LineEdit:
	if _ime_target != null and is_instance_valid(_ime_target) and _ime_target.visible:
		return _ime_target
	return null


func _sync_ime_rect(force: bool = false) -> void:
	_sync_file_picker()
	if _web_input == null or not _web_input.available():
		return
	var target := _current_ime_target()
	if target == null:
		_web_input.hide()
		_last_ime_sig = ""
		return
	var r := target.get_global_rect()
	var vp := get_viewport_rect().size
	var sig := "%0.1f,%0.1f,%0.1f,%0.1f,%0.1f,%0.1f" % [r.position.x, r.position.y, r.size.x, r.size.y, vp.x, vp.y]
	if not force and sig == _last_ime_sig:
		return
	_last_ime_sig = sig
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	_web_input.place(r, vp)


func _sync_file_picker() -> void:
	if attach == null or _img_btn == null or not is_instance_valid(_img_btn) or not _img_btn.visible:
		if attach:
			attach.hide_picker()
		return
	var r := _img_btn.get_global_rect()
	if r.size.x < 2.0 or r.size.y < 2.0:
		attach.hide_picker()
		return
	attach.place_picker(r, get_viewport_rect().size)


func _show_attach(message: String) -> void:
	if _attach_lbl == null:
		return
	_attach_lbl.text = message
	_attach_lbl.visible = message.strip_edges() != ""


func _pull_ime_value() -> String:
	if _web_input != null and _web_input.available():
		return _web_input.value()
	if _ime_target != null and is_instance_valid(_ime_target):
		return _ime_target.text
	return input.text if input else ""


func _push_ime_text(t: String) -> void:
	if _web_input != null and _web_input.available():
		_web_input.set_text(t)


func _pull_ime_into(target: LineEdit) -> void:
	if target == null or _web_input == null or not _web_input.available():
		return
	if _ime_target != target:
		return
	target.text = _web_input.value()


func _set_composer(t: String) -> void:
	if input:
		input.text = t
	if _ime_target == input:
		_push_ime_text(t)


func _on_ime_text(text: String, kind: String, composing: bool) -> void:
	var target := _current_ime_target()
	if target == null:
		return
	if kind == "focus":
		return
	if composing and kind == "composition":
		return
	target.text = text


func _on_ime_submit(text: String) -> void:
	var target := _current_ime_target()
	if target:
		target.text = text
	if _ime_submit.is_valid():
		_ime_submit.call()


func _on_ime_inset(px: float) -> void:
	if absf(px - _keyboard_inset) <= 1.5:
		return
	_keyboard_inset = px
	_fit_panel()


func _on_memory_closed() -> void:
	_bind_ime(input, _send)


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
				var vp := get_viewport_rect().size
				_panel.position = ChatLayout.clamp_pos(_panel.position, _panel.size, vp)
				_last_ime_sig = ""
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
	if _web_input:
		_web_input.close()
	if attach:
		attach.hide_picker()
	if voice:
		voice.close_pip()
	if _mini and not OS.has_feature("web"):
		var win := get_window()
		win.borderless = _saved_borderless
		win.always_on_top = _saved_on_top
		if _saved_win_size != Vector2i.ZERO:
			win.size = _saved_win_size
			win.position = _saved_win_pos
