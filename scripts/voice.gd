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
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
	player = AudioStreamPlayer.new()
	player.bus = BUS
	add_child(player)
	apply_settings()

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

## 查台词 ID；找不到返回 ""
func id_for(who: String, text: String) -> String:
	return String(map.get(who + "|" + text.strip_edges(), ""))

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
func say(who: String, text: String) -> bool:
	return play_id(id_for(who, text))

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
