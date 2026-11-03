extends Node
## 全局游戏状态（Autoload: Game）——修为、境界、伙伴、羁绊、灵田、存档、离线收益

signal changed
signal toast(msg: String)
signal scene_unlocked(scene_id: String)
signal bond_gained(char_id: String, amount: float)
signal seclusion_done(info: Dictionary)

const SAVE_PATH := "user://save_v1.json"
const DAILY_LIMIT := {"chat": 1, "tea": 1, "star": 1, "gift": 3, "poke": 10}
const PLOT_UNLOCK_STEP := [0, 0, 0, 4, 8, 12]
const GROW_BASE := 240.0

var s: Dictionary = {}
var scenes: Array = []
var scene_by_id: Dictionary = {}
var pools: Dictionary = {}
var _save_timer := 0.0
var _sec_timer := 0.0
var speed := 1.0
var no_save := false
var debug_force := 0   # 演示用：1=必成功 -1=必失败

func _ready() -> void:
	randomize()
	_load_story()
	if not load_game():
		s = _new_state()
	_dedupe_daily()

func _load_story() -> void:
	var f := FileAccess.open("res://data/story.json", FileAccess.READ)
	if f:
		scenes = JSON.parse_string(f.get_as_text())
		f.close()
	for sc in scenes:
		scene_by_id[sc["id"]] = sc
	var f2 := FileAccess.open("res://data/pools.json", FileAccess.READ)
	if f2:
		pools = JSON.parse_string(f2.get_as_text())
		f2.close()

func _new_state() -> Dictionary:
	var d := {
		"ver": 1, "xiu": 0.0, "stone": 60.0, "herb": 2, "step": 0, "pity": 0.0,
		"main": "", "chars": {}, "gifts": {"tea": 1, "flower": 0, "cake": 1, "dew": 0, "scroll": 0},
		"plots": [], "last_save": Time.get_unix_time_from_system(), "daily_date": "", "streak": 0,
		"sec": {}, "letters": [], "prologue": false, "seen": [], "notified": [], "stone_frac": 0.0, "fails": 0, "total_bt": 0,
	}
	for i in 6:
		d["plots"].append({"t": 0.0, "g": false})
	return d

func _dedupe_daily() -> void:
	pass

# ---------------- 存档 ----------------
func save_game() -> void:
	if no_save:
		return
	s["last_save"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s))
		f.close()

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return false
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return false
	s = _new_state()
	for k in d.keys():
		s[k] = d[k]
	s["step"] = int(s["step"])
	s["herb"] = int(s["herb"])
	while s["plots"].size() < 6:
		s["plots"].append({"t": 0.0, "g": false})
	return true

func reset_all() -> void:
	s = _new_state()
	save_game()
	changed.emit()

# ---------------- 伙伴 ----------------
func is_recruited(id: String) -> bool:
	return s["chars"].has(id)

func recruited_ids() -> Array:
	var a: Array = []
	for c in Data.CHARS:
		if s["chars"].has(c["id"]):
			a.append(c["id"])
	return a

func cdata(id: String) -> Dictionary:
	return s["chars"].get(id, {})

func lv(id: String) -> int:
	return int(cdata(id).get("lv", 1))

func bond_xp(id: String) -> float:
	return float(cdata(id).get("bond", 0.0))

func bond_lv(id: String) -> int:
	return Data.bond_level(bond_xp(id))

func recruit_cost() -> int:
	var n: int = recruited_ids().size()
	if n >= Data.RECRUIT_COST.size():
		return 99999
	return Data.RECRUIT_COST[n]

func recruit(id: String, free: bool = false) -> bool:
	if is_recruited(id):
		return false
	var cost := 0 if free else recruit_cost()
	if s["stone"] < cost:
		toast.emit("灵石不足，需要 %d 灵石" % cost)
		return false
	s["stone"] -= cost
	s["chars"][id] = {"lv": 1, "bond": 0.0, "daily": {"date": "", "chat": 0, "tea": 0, "star": 0, "gift": 0, "poke": 0}}
	if s["main"] == "":
		s["main"] = id
	changed.emit()
	save_game()
	return true

func set_main(id: String) -> void:
	if is_recruited(id):
		s["main"] = id
		changed.emit()

func f_of(id: String) -> float:
	return 0.6 + 0.2 * lv(id) + 0.1 * bond_lv(id)

func weight(id: String) -> float:
	return 1.0 if s["main"] == id else 0.4

func passive(pid: String) -> float:
	var t := 0.0
	for id in recruited_ids():
		var d := Data.char_def(id)
		if d["pid"] == pid:
			t += d["per"] * f_of(id) * weight(id)
	return t

func passive_of(id: String) -> float:
	var d := Data.char_def(id)
	return d["per"] * f_of(id) * weight(id)

func passive_text(id: String) -> String:
	var d := Data.char_def(id)
	var v: float = d["per"] * f_of(id) * (1.0 if true else 0.4)
	return "%s：%s" % [d["pname"], d["pdesc"] % ("%.1f" % v)]

func upgrade_cost(id: String) -> Array:
	var l := lv(id)
	return [int(round(40.0 * pow(1.55, l - 1))), (l - 2) if l >= 4 else 0]

func upgrade(id: String) -> bool:
	if lv(id) >= 30:
		toast.emit("已达修行上限")
		return false
	var c := upgrade_cost(id)
	if s["stone"] < c[0] or s["herb"] < c[1]:
		toast.emit("资源不足：需要 灵石 %d%s" % [c[0], (" · 灵草 %d" % c[1]) if c[1] > 0 else ""])
		return false
	s["stone"] -= c[0]
	s["herb"] -= c[1]
	s["chars"][id]["lv"] = lv(id) + 1
	changed.emit()
	return true

func add_bond(id: String, amount: float, silent: bool = false) -> float:
	if not is_recruited(id):
		return 0.0
	var a := amount * (1.0 + passive("bond") / 100.0)
	s["chars"][id]["bond"] = bond_xp(id) + a
	if not silent:
		bond_gained.emit(id, a)
	_check_unlocks()
	changed.emit()
	return a

func _check_unlocks() -> void:
	for sc in scenes:
		if sc["char"] == "" or sc["n"] == 1:
			continue
		if scene_status(sc["id"]) == "new" and not (sc["id"] in s["notified"]):
			s["notified"].append(sc["id"])
			scene_unlocked.emit(sc["id"])

func scene_status(sid: String) -> String:
	var sc: Dictionary = scene_by_id.get(sid, {})
	if sc.is_empty():
		return "locked"
	if sid in s["seen"]:
		return "seen"
	if sc["char"] == "":
		return "new"
	if not is_recruited(sc["char"]):
		return "locked"
	if sc["n"] == 1:
		return "new"
	if bond_lv(sc["char"]) >= int(sc["req_bond"]) and int(s["step"]) >= int(sc["req_step"]):
		return "new"
	return "locked"

func scene_req_text(sid: String) -> String:
	var sc: Dictionary = scene_by_id[sid]
	return "需 羁绊 Lv.%d「%s」· 境界 %s" % [sc["req_bond"], Data.BOND_NAMES[int(sc["req_bond"]) - 1], Data.step_name(int(sc["req_step"]))]

func mark_seen(sid: String) -> bool:
	if sid in s["seen"]:
		return false
	s["seen"].append(sid)
	changed.emit()
	return true

func new_scene_count() -> int:
	var n := 0
	for sc in scenes:
		if sc["char"] != "" and scene_status(sc["id"]) == "new":
			n += 1
	return n

func char_scenes(id: String) -> Array:
	var a: Array = []
	for sc in scenes:
		if sc["char"] == id:
			a.append(sc)
	return a

# ---------------- 每日互动 ----------------
func today() -> String:
	return Time.get_date_string_from_system()

func _daily(id: String) -> Dictionary:
	var c: Dictionary = s["chars"][id]
	var d: Dictionary = c.get("daily", {})
	if d.get("date", "") != today():
		d = {"date": today(), "chat": 0, "tea": 0, "star": 0, "gift": 0, "poke": 0}
		c["daily"] = d
	return d

func daily_used(id: String, kind: String) -> int:
	return int(_daily(id).get(kind, 0))

func daily_left(id: String, kind: String) -> int:
	return int(DAILY_LIMIT[kind]) - daily_used(id, kind)

func use_daily(id: String, kind: String) -> void:
	var d := _daily(id)
	d[kind] = int(d.get(kind, 0)) + 1

func reset_today() -> void:
	for id in recruited_ids():
		s["chars"][id]["daily"] = {"date": today(), "chat": 0, "tea": 0, "star": 0, "gift": 0, "poke": 0}
	changed.emit()

func daily_claim() -> Dictionary:
	## 返回每日登录礼物；若今日已领返回空
	if s["daily_date"] == today():
		return {}
	var y := Time.get_unix_time_from_system() - 86400.0
	var yd := Time.get_date_string_from_unix_time(int(y) + int(Time.get_time_zone_from_system()["bias"]) * 60)
	if s["daily_date"] == yd:
		s["streak"] = int(s["streak"]) + 1
	else:
		s["streak"] = 1
	s["daily_date"] = today()
	var st: int = int(s["streak"])
	var stone: int = int(120 + 40 * mini(st, 7) + 20 * int(s["step"]))
	var herb: int = 2 + mini(st, 7) / 2
	s["stone"] += stone
	s["herb"] += herb
	var extra := ""
	if st % 7 == 0:
		s["gifts"]["dew"] = int(s["gifts"]["dew"]) + 1
		extra = "星辰露 ×1"
	reset_today()
	changed.emit()
	return {"streak": st, "stone": stone, "herb": herb, "extra": extra}

# ---------------- 修炼 ----------------
func realm_k() -> int:
	return int(s["step"])

func xiu_rate_base() -> float:
	return Data.base_rate(realm_k()) * (1.0 + passive("xiu") / 100.0)

func sec_active() -> bool:
	return not s["sec"].is_empty()

func sec_mult() -> float:
	return 1.5 + passive("seclu") / 100.0

func xiu_rate() -> float:
	var r := xiu_rate_base()
	if sec_active():
		r *= sec_mult()
	return r * speed

func stone_ratio() -> float:
	return 0.35 * (1.0 + passive("stone") / 100.0)

func stone_rate() -> float:
	return xiu_rate() * stone_ratio()

func req_now() -> float:
	return Data.req(realm_k())

func can_breakthrough() -> bool:
	return realm_k() < Data.MAX_STEP and s["xiu"] >= req_now()

func success_chance() -> float:
	var c := Data.base_success(realm_k()) + passive("bt") / 100.0 + float(s["pity"])
	return clampf(c, 0.05, 0.99)

func loss_fraction() -> float:
	return 0.2 * (1.0 - clampf(passive("fear") / 100.0, 0.0, 0.9))

func attempt_breakthrough() -> Dictionary:
	if not can_breakthrough():
		return {}
	var k := realm_k()
	var chance := success_chance()
	var res := {"from": k, "chance": chance}
	var win := randf() < chance
	if debug_force != 0:
		win = debug_force > 0
	if win:
		s["xiu"] -= req_now()
		s["step"] = k + 1
		s["pity"] = 0.0
		s["total_bt"] = int(s["total_bt"]) + 1
		res["ok"] = true
		res["major"] = Data.is_major(k)
	else:
		var loss: float = s["xiu"] * loss_fraction()
		s["xiu"] -= loss
		s["pity"] = float(s["pity"]) + 0.06
		s["fails"] = int(s["fails"]) + 1
		res["ok"] = false
		res["loss"] = loss
	_check_unlocks()
	changed.emit()
	save_game()
	return res

func _process(delta: float) -> void:
	if s.is_empty():
		return
	var gain := xiu_rate() * delta
	s["xiu"] += gain
	var sf: float = float(s["stone_frac"]) + gain * stone_ratio()
	var whole := floorf(sf)
	s["stone"] += whole
	s["stone_frac"] = sf - whole
	_save_timer += delta
	if _save_timer >= 10.0:
		_save_timer = 0.0
		save_game()
	_sec_timer += delta
	if _sec_timer >= 0.5:
		_sec_timer = 0.0
		check_seclusion()

# ---------------- 闭关同修 ----------------
func start_seclusion(id: String, secs: float) -> void:
	var now := Time.get_unix_time_from_system()
	s["sec"] = {"id": id, "start": now, "end": now + secs, "secs": secs}
	changed.emit()
	save_game()

func sec_remaining() -> float:
	if not sec_active():
		return 0.0
	return maxf(0.0, float(s["sec"]["end"]) - Time.get_unix_time_from_system())

func cancel_seclusion() -> void:
	s["sec"] = {}
	changed.emit()

func check_seclusion() -> void:
	if not sec_active():
		return
	if Time.get_unix_time_from_system() >= float(s["sec"]["end"]):
		var info: Dictionary = s["sec"].duplicate()
		s["sec"] = {}
		var secs := float(info["secs"])
		var b := 12.0 + minf(48.0, secs / 90.0)
		b *= (1.0 + passive("seclu") / 100.0 * 0.0)
		var got := add_bond(info["id"], b, true)
		info["bond"] = got
		var xiu_bonus := xiu_rate_base() * minf(secs, 3600.0) * 0.25
		s["xiu"] += xiu_bonus
		info["xiu"] = xiu_bonus
		changed.emit()
		save_game()
		seclusion_done.emit(info)

# ---------------- 离线 ----------------
func off_cap_hours() -> float:
	var h := 8.0
	for id in recruited_ids():
		var d := Data.char_def(id)
		if d["pid"] == "off":
			h += 0.3 * f_of(id) * weight(id)
	return h

func process_offline() -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var last: float = float(s["last_save"])
	var el := now - last
	if last <= 0.0 or el < 60.0:
		return {}
	var cap := off_cap_hours() * 3600.0
	var used := minf(el, cap)
	var ov := 0.0
	if sec_active():
		var a := maxf(last, float(s["sec"]["start"]))
		var b := minf(last + used, float(s["sec"]["end"]))
		ov = maxf(0.0, b - a)
	var eff := minf(1.0, 0.6 * (1.0 + passive("off") / 100.0))
	var rate := xiu_rate_base()
	var xiu := rate * eff * ((used - ov) + ov * sec_mult())
	var stones := floorf(xiu * stone_ratio())
	s["xiu"] += xiu
	s["stone"] += stones
	var res := {"elapsed": el, "used": used, "xiu": xiu, "stone": stones, "capped": el > cap, "eff": eff}
	# 离线期间灵田自然成熟（按时间戳）无需处理
	var letter := ""
	var who := ""
	if el >= 180.0 and recruited_ids().size() > 0:
		var ids := recruited_ids()
		who = s["main"] if (randf() < 0.5 and s["main"] != "") else ids[randi() % ids.size()]
		var arr: Array = pools.get(who, {}).get("letters", [])
		if arr.size() > 0:
			letter = arr[randi() % arr.size()]
			add_letter(who, letter)
	res["letter"] = letter
	res["who"] = who
	changed.emit()
	return res

func add_letter(who: String, text: String) -> void:
	var t := Time.get_datetime_dict_from_system()
	s["letters"].push_front({"who": who, "text": text, "time": "%02d月%02d日 %02d:%02d" % [t["month"], t["day"], t["hour"], t["minute"]]})
	while s["letters"].size() > 30:
		s["letters"].pop_back()

# ---------------- 灵田 ----------------
func plot_unlocked(i: int) -> bool:
	return realm_k() >= PLOT_UNLOCK_STEP[i]

func grow_time() -> float:
	return GROW_BASE / (1.0 + clampf(passive("grow") / 100.0, 0.0, 0.7))

func plot_state(i: int) -> String:
	var p: Dictionary = s["plots"][i]
	if not p["g"]:
		return "empty"
	if Time.get_unix_time_from_system() - float(p["t"]) >= grow_time():
		return "ripe"
	return "growing"

func plot_progress(i: int) -> float:
	var p: Dictionary = s["plots"][i]
	if not p["g"]:
		return 0.0
	return clampf((Time.get_unix_time_from_system() - float(p["t"])) / grow_time(), 0.0, 1.0)

func plant(i: int) -> bool:
	if plot_state(i) != "empty" or not plot_unlocked(i):
		return false
	s["plots"][i] = {"t": Time.get_unix_time_from_system(), "g": true}
	changed.emit()
	return true

func harvest(i: int) -> int:
	if plot_state(i) != "ripe":
		return 0
	var n := int(round(float(randi_range(3, 5)) * (1.0 + passive("herb") / 100.0)))
	s["herb"] += n
	s["plots"][i] = {"t": 0.0, "g": false}
	changed.emit()
	return n

func craft(gift: String) -> bool:
	var cost: int = 3 if gift == "tea" else 4
	if s["herb"] < cost:
		toast.emit("灵草不足，需要 %d 灵草" % cost)
		return false
	s["herb"] -= cost
	s["gifts"][gift] = int(s["gifts"][gift]) + 1
	changed.emit()
	return true

func buy(gift: String) -> bool:
	var price: int = {"cake": 60, "dew": 140, "scroll": 100}[gift]
	if s["stone"] < price:
		toast.emit("灵石不足，需要 %d 灵石" % price)
		return false
	s["stone"] -= price
	s["gifts"][gift] = int(s["gifts"][gift]) + 1
	changed.emit()
	return true

func gift_count(g: String) -> int:
	return int(s["gifts"].get(g, 0))

func use_gift(g: String) -> bool:
	if gift_count(g) <= 0:
		return false
	s["gifts"][g] = gift_count(g) - 1
	changed.emit()
	return true

# ---------------- 演示/调试 ----------------
func apply_demo(mode: String) -> void:
	no_save = true
	s = _new_state()
	s["prologue"] = true
	s["daily_date"] = today()
	s["streak"] = 3
	var ids := Data.char_ids()
	var n := 9 if mode in ["roster", "lineup", "dialogue", "detail", "memory"] else 4
	var bonds := [980.0, 360.0, 1450.0, 120.0, 640.0, 40.0, 220.0, 520.0, 90.0]
	for i in n:
		s["chars"][ids[i]] = {"lv": 3 + (i * 2) % 7, "bond": bonds[i], "daily": {"date": today(), "chat": 0, "tea": 0, "star": 0, "gift": 0, "poke": 0}}
	s["main"] = "grok"
	if mode in ["lineup", "roster"]:
		for i in 9:
			s["chars"][ids[i]]["lv"] = 5 + i
	s["step"] = 7
	s["xiu"] = Data.req(7) * (1.0 if mode in ["breakthrough", "bfail", "btready"] else 0.62)
	s["stone"] = 2480.0
	s["herb"] = 18
	s["gifts"] = {"tea": 2, "flower": 1, "cake": 3, "dew": 1, "scroll": 2}
	s["seen"] = ["grok_s1", "chatgpt_s1", "claude_s1", "gemini_s1", "prologue"]
	for i in 6:
		s["plots"][i] = {"t": Time.get_unix_time_from_system() - (300.0 if i % 2 == 0 else 90.0), "g": i < 5}
	s["letters"] = [{"who": "grok", "text": pools["grok"]["letters"][0], "time": "11月03日 22:10"}, {"who": "qwen", "text": pools["qwen"]["letters"][1], "time": "11月02日 18:45"}]
	changed.emit()
