extends Node
## 配音播放（Autoload: Voice）
## 台词原文 → 台词 ID → res://audio/voice/<角色>/<ID>.ogg；没有音频的台词静默跳过。
## 映射表 data/voice_map.json 由 tools/make_voice_map.py 生成。

const MAP_PATH := "res://data/voice_map.json"
const BUS := "Voice"

var map: Dictionary = {}
var player: AudioStreamPlayer
var cur_id := ""

func _ready() -> void:
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(d) == TYPE_DICTIONARY:
			map = d
	# Voice 总线必须在 default_bus_layout.tres 里预定义。
	# 网页版默认走采样播放（Sample）；运行时再建总线，采样路径会静音。
	# 不再强制 PLAYBACK_TYPE_STREAM（无线程 Web 导出上容易卡顿）。
	if AudioServer.get_bus_index(BUS) < 0:
		push_warning("Voice bus missing from default_bus_layout.tres; audio may be silent on web")
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
	player = AudioStreamPlayer.new()
	player.bus = BUS
	player.playback_type = AudioServer.PLAYBACK_TYPE_DEFAULT
	add_child(player)
	apply_settings()
	_maybe_fetch_pack()

# 轻量网页版（Cloudflare Pages 单文件 ≤25MiB）把配音拆成 voices.pck，启动后在后台下载并挂载；
# 完整版（音频已在主包里）会直接跳过。下载完成前，台词只是没有声音。
const PACK_URL := "voices.pck"
const PACK_LOCAL := "user://voices.pck"
var pack_loaded := false

func _maybe_fetch_pack() -> void:
	if not OS.has_feature("web"):
		return
	if ResourceLoader.exists("res://audio/voice/grok/pl_grok_bt.ogg"):
		return
	var url := str(JavaScriptBridge.eval("new URL('%s', window.location.href).href" % PACK_URL))
	var req := HTTPRequest.new()
	req.timeout = 120.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var fa := FileAccess.open(PACK_LOCAL, FileAccess.WRITE)
			if fa:
				fa.store_buffer(body)
				fa.close()
			pack_loaded = ProjectSettings.load_resource_pack(PACK_LOCAL)
			print("[Voice] voices.pck loaded: ", pack_loaded, " exists=", ResourceLoader.exists("res://audio/voice/grok/pl_grok_bt.ogg"))
		else:
			print("[Voice] voices.pck download failed: ", result, " ", code)
		req.queue_free())
	var err := req.request(url)
	if err != OK:
		print("[Voice] voices.pck request error: ", err)

func volume() -> float:
	return clampf(float(Game.s.get("voice_vol", 1.0)), 0.0, 1.0)

func muted() -> bool:
	return bool(Game.s.get("voice_mute", false))

func set_volume(v: float) -> void:
	Game.s["voice_vol"] = clampf(v, 0.0, 1.0)
	apply_settings()

func set_muted(m: bool) -> void:
	Game.s["voice_mute"] = m
	apply_settings()
	if m:
		stop()

func apply_settings() -> void:
	var i := AudioServer.get_bus_index(BUS)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, muted() or volume() <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volume(), 0.001)))

## 查台词 ID；找不到返回 ""。ctx 形如 "story:kimi_s1"，用来区分同一原文的不同句子。
func id_for(who: String, text: String, ctx: String = "") -> String:
	var t := text.strip_edges()
	if ctx != "":
		var specific = map.get(ctx + "|" + who + "|" + t, "")
		if String(specific) != "":
			return String(specific)
	return String(map.get(who + "|" + t, ""))

## 台词原文是否只有省略号 /「……！」（没有可念的字）。
func is_ellipsis_only(text: String) -> bool:
	var t := text.strip_edges()
	if t.is_empty():
		return false
	var has_ellipsis := false
	for i in t.length():
		var ch := t.substr(i, 1)
		if ch == "…" or ch == ".":
			if ch == "…":
				has_ellipsis = true
			continue
		if ch == "！" or ch == "!" or ch == "？" or ch == "?" or ch == " " or ch == "　":
			continue
		return false
	return has_ellipsis

## 纯省略号台词在还没有对应 OGG 时视为有意静音；已导入音频的会正常播放。
func is_intentional_silence(who: String, text: String, ctx: String = "") -> bool:
	if not is_ellipsis_only(text):
		return false
	var id := id_for(who, text, ctx)
	if id != "" and has_voice(id):
		return false
	return true

func has_voice(id: String) -> bool:
	if id == "":
		return false
	var p := _path(id)
	return ResourceLoader.exists(p)

func _path(id: String) -> String:
	# ID 形如 pl_<char>_... / st_<char>_...，角色名在第二段
	var who := id.split("_")[1]
	return "res://audio/voice/%s/%s.ogg" % [who, id]

## 按角色 + 游戏原文播放（会打断上一句）
func say(who: String, text: String, ctx: String = "") -> bool:
	return play_id(id_for(who, text, ctx))

func play_id(id: String) -> bool:
	if id == "" or muted() or volume() <= 0.001:
		return false
	var p := _path(id)
	if not ResourceLoader.exists(p):
		return false
	var st = load(p)
	if st == null:
		return false
	player.stop()
	player.stream = st
	player.play()
	cur_id = id
	return true

func stop() -> void:
	if player:
		player.stop()
	cur_id = ""
