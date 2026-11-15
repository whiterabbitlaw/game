class_name ChatVoiceSession
extends Node
## 实时语音：网页走 getUserMedia + JS VAD；桌面走 AudioEffectCapture。
## 模式 push（按住说话）或 handsfree（免提，静音超时自动停）。

signal utterance_ready(wav_bytes: PackedByteArray, mime: String)
signal state_changed(state: String, detail: String)
signal error_text(message: String)
signal frames_ready(frames: Array, name: String)
signal pip_event(event: String, payload: Dictionary)

const STATE_IDLE := "idle"
const STATE_LISTENING := "listening"
const STATE_THINKING := "thinking"
const STATE_SPEAKING := "speaking"

var mode := "push"  # push | handsfree
var state := STATE_IDLE
var tts_playing := false

var _js_cb: JavaScriptObject
var _vad := ChatVAD.new()
var _desktop_on := false
var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _buf := PackedFloat32Array()
var _recording := false


func _ready() -> void:
	if OS.has_feature("web"):
		_js_cb = JavaScriptBridge.create_callback(_on_js)
		JavaScriptBridge.eval("window.qiyunjuOnMedia = window.qiyunjuOnMedia || function(){};", true)
		var win = JavaScriptBridge.get_interface("window")
		if win:
			win.qiyunjuOnMedia = _js_cb
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.init){window.qiyunjuMedia.init();}", true)


func is_active() -> bool:
	return state == STATE_LISTENING or _desktop_on or _recording


func set_state(s: String, detail: String = "") -> void:
	state = s
	if s == STATE_THINKING:
		_js_busy(true)
	elif s == STATE_LISTENING or s == STATE_IDLE:
		if not tts_playing:
			_js_busy(false)
	state_changed.emit(s, detail)


func set_tts_playing(playing: bool) -> void:
	tts_playing = playing
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.setSpeaking){window.qiyunjuMedia.setSpeaking(%s);}" % ("true" if playing else "false"), true)
		if playing:
			_js_busy(true)


func set_busy(busy: bool) -> void:
	_js_busy(busy)


func _js_busy(busy: bool) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.setBusy){window.qiyunjuMedia.setBusy(%s);}" % ("true" if busy else "false"), true)


func start_handsfree() -> void:
	mode = "handsfree"
	_start_capture()


func stop_handsfree() -> void:
	mode = "push"
	_stop_capture()
	if state != STATE_THINKING and state != STATE_SPEAKING:
		set_state(STATE_IDLE)


func ptt_down() -> void:
	mode = "push"
	_start_capture()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.pttDown){window.qiyunjuMedia.pttDown();}", true)
	else:
		_recording = true
		_buf = PackedFloat32Array()
		set_state(STATE_LISTENING, "按住说话")


func ptt_up() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.pttUp){window.qiyunjuMedia.pttUp();}", true)
	else:
		_recording = false
		_flush_desktop_utterance()
		_stop_capture()


func _start_capture() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.startMic){window.qiyunjuMedia.startMic({mode:'%s'});}" % mode, true)
		set_state(STATE_LISTENING)
		return
	_ensure_desktop_mic()
	_desktop_on = true
	_vad.reset()
	_vad.sample_rate = 16000
	if mode == "handsfree":
		set_state(STATE_LISTENING, "免提")


func _stop_capture() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.stopMic){window.qiyunjuMedia.stopMic();}", true)
		return
	_desktop_on = false
	_recording = false
	if _mic_player:
		_mic_player.stop()


func _ensure_desktop_mic() -> void:
	if _capture:
		if _mic_player and not _mic_player.playing:
			_mic_player.play()
		return
	var idx := AudioServer.get_bus_index("Mic")
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Mic")
		AudioServer.set_bus_mute(idx, true)
		AudioServer.set_bus_send(idx, "Master")
	var has_cap := false
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectCapture:
			_capture = fx
			has_cap = true
			break
	if not has_cap:
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(idx, _capture)
	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = "Mic"
		add_child(_mic_player)
	_mic_player.play()


func _process(_dt: float) -> void:
	if not _desktop_on or _capture == null:
		return
	var avail := _capture.get_frames_available()
	if avail <= 0:
		return
	var frames: PackedVector2Array = _capture.get_buffer(avail)
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	for i in frames.size():
		mono[i] = (frames[i].x + frames[i].y) * 0.5
	# 简单降到 16k：若混音率是 44.1/48k，隔点取样
	var rate := int(AudioServer.get_mix_rate())
	var use := mono
	if rate > 20000:
		var step := float(rate) / 16000.0
		var down := PackedFloat32Array()
		var x := 0.0
		while int(x) < mono.size():
			down.append(mono[int(x)])
			x += step
		use = down
	if mode == "push":
		if _recording:
			_buf.append_array(use)
		return
	var ev := _vad.feed(use, tts_playing)
	if ev == "barge":
		_buf = PackedFloat32Array()
		_buf.append_array(use)
		_recording = true
		set_state(STATE_LISTENING, "打断")
		return
	if ev == "start":
		_buf = PackedFloat32Array()
		_buf.append_array(use)
		_recording = true
		set_state(STATE_LISTENING)
		return
	if _recording:
		_buf.append_array(use)
	if ev == "end":
		_recording = false
		_flush_desktop_utterance()


func _flush_desktop_utterance() -> void:
	if _buf.size() < 1600:
		_buf = PackedFloat32Array()
		if mode == "handsfree":
			set_state(STATE_LISTENING)
		else:
			set_state(STATE_IDLE)
		return
	# 最长 15 秒
	var max_n := 16000 * 15
	if _buf.size() > max_n:
		_buf = _buf.slice(_buf.size() - max_n, _buf.size())
	var pcm := ChatVAD.floats_to_pcm16(_buf)
	var wav := ChatVAD.write_wav(pcm, 16000)
	_buf = PackedFloat32Array()
	set_state(STATE_THINKING)
	utterance_ready.emit(wav, "audio/wav")


func _on_js(args: Array) -> void:
	if args.is_empty():
		return
	var parsed: Variant = JSON.parse_string(str(args[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var typ := str(d.get("type", ""))
	match typ:
		"state":
			set_state(str(d.get("state", state)), str(d.get("detail", "")))
		"audio":
			var b64 := str(d.get("data", ""))
			var bytes := Marshalls.base64_to_raw(b64) if b64 != "" else PackedByteArray()
			if bytes.is_empty():
				error_text.emit("没有录到声音")
				if mode == "handsfree":
					set_state(STATE_LISTENING)
				else:
					set_state(STATE_IDLE)
				return
			set_state(STATE_THINKING)
			utterance_ready.emit(bytes, str(d.get("mime", "audio/wav")))
		"error":
			error_text.emit(str(d.get("message", "麦克风出错")))
			if mode == "handsfree":
				set_state(STATE_LISTENING)
			else:
				set_state(STATE_IDLE)
		"barge":
			set_state(STATE_LISTENING, "打断")
		"frames":
			var frames: Array = d.get("frames", []) if typeof(d.get("frames", [])) == TYPE_ARRAY else []
			frames_ready.emit(frames, str(d.get("name", "video")))
		"pip":
			pip_event.emit(str(d.get("event", "")), d)


func pick_video() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.pickVideo){window.qiyunjuMedia.pickVideo();}", true)
	else:
		error_text.emit("视频抽帧目前在网页版可用，请用浏览器打开游戏后点「视频」。")


func open_pip() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.openPip){window.qiyunjuMedia.openPip();}", true)
	else:
		error_text.emit("画中画小窗仅在桌面 Chrome 网页版可用。桌面应用请用「小窗」。")


func update_pip(payload: Dictionary) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.updatePip){window.qiyunjuMedia.updatePip(%s);}" % JSON.stringify(payload), true)


func close_pip() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.closePip){window.qiyunjuMedia.closePip();}", true)


func _exit_tree() -> void:
	close_pip()
	_stop_capture()
