extends Control
## 主界面：背景、顶栏、四个页签、弹窗、剧情流程

var bg_a: TextureRect
var bg_b: TextureRect
var cloud_layer: Control
var clouds: Array = []
var page_root: Control
var pages: Dictionary = {}
var tab_btns: Dictionary = {}
var tab_dot: Label
var cur_tab := "cultivate"
var overlay: Control      # 对话/详情/突破 等全屏层
var top_realm: Label
var top_stone: Label
var top_herb: Label
var toast_lbl: Label
var detail: DetailView = null
var _busy_story := false
var _toast_tw: Tween
var _bg_name := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	_build_pages()
	_build_top()
	_build_tabs()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	toast_lbl = UI.lbl("", 26, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	toast_lbl.position = Vector2(60, 118)
	toast_lbl.size = Vector2(600, 60)
	toast_lbl.add_theme_stylebox_override("normal", UI.panel(Color(0.2, 0.17, 0.35, 0.88), Color(1, 1, 1, 0.2), 22, 1))
	toast_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_lbl.modulate.a = 0.0
	add_child(toast_lbl)
	Game.toast.connect(show_toast)
	Game.changed.connect(_on_changed)
	Game.scene_unlocked.connect(_on_scene_unlocked)
	Game.seclusion_done.connect(_on_seclusion_done)
	_on_changed()
	switch_tab("cultivate")
	get_tree().root.close_requested.connect(func(): Game.save_game())
	await get_tree().process_frame
	_startup()

# ---------------- 构建 ----------------
func _build_bg() -> void:
	bg_a = TextureRect.new()
	bg_a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_a.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_a)
	bg_b = bg_a.duplicate()
	bg_b.modulate.a = 0.0
	add_child(bg_b)
	cloud_layer = Control.new()
	cloud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cloud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cloud_layer)
	var tex: Texture2D = load("res://assets/fx/cloud.png")
	for i in 5:
		var s := Sprite2D.new()
		s.texture = tex
		s.position = Vector2(randf() * 900.0 - 100.0, 160.0 + float(i) * 210.0)
		s.scale = Vector2.ONE * randf_range(0.8, 1.6)
		s.modulate = Color(1, 1, 1, randf_range(0.28, 0.5))
		cloud_layer.add_child(s)
		clouds.append({"n": s, "v": randf_range(6.0, 16.0)})
	set_bg("dawn", true)

func set_bg(name: String, instant: bool = false) -> void:
	if name == _bg_name:
		return
	_bg_name = name
	var tex: Texture2D = load("res://assets/bg/%s.jpg" % name)
	if instant:
		bg_a.texture = tex
		return
	bg_b.texture = tex
	bg_b.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(bg_b, "modulate:a", 1.0, 0.8)
	tw.tween_callback(func():
		bg_a.texture = tex
		bg_b.modulate.a = 0.0)

func _process(delta: float) -> void:
	for c in clouds:
		var n: Sprite2D = c["n"]
		n.position.x += c["v"] * delta
		if n.position.x > 900.0:
			n.position.x = -300.0
	# 根据真实时间切换背景色调（仅在主界面）
	if overlay and overlay.get_child_count() == 0:
		var h: int = Time.get_datetime_dict_from_system()["hour"]
		var tone := "dawn"
		if h >= 17 or h < 5:
			tone = "dusk"
		set_bg(tone)

func _build_pages() -> void:
	page_root = Control.new()
	page_root.position = Vector2(0, 100)
	page_root.size = Vector2(720, 1060)
	page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_root)
	pages["cultivate"] = PageCultivate.new()
	pages["roster"] = PageRoster.new()
	pages["home"] = PageHome.new()
	pages["memory"] = PageMemory.new()
	for k in pages.keys():
		var p: Control = pages[k]
		p.size = Vector2(720, 1060)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page_root.add_child(p)
		p.set("main", self)
		p.call("build")
		p.visible = false

func _build_top() -> void:
	var bar := Panel.new()
	bar.position = Vector2.ZERO
	bar.size = Vector2(720, 96)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.98, 0.94, 0.72)
	sb.border_color = Color(0.85, 0.7, 0.4, 0.6)
	sb.border_width_bottom = 2
	sb.corner_radius_bottom_left = 28
	sb.corner_radius_bottom_right = 28
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	top_realm = UI.brush_lbl("", 48, UI.GOLD_DEEP, HORIZONTAL_ALIGNMENT_LEFT)
	top_realm.position = Vector2(26, 20)
	top_realm.size = Vector2(260, 60)
	add_child(top_realm)
	var c1 := UI.chip("", Color(0.45, 0.42, 0.7, 0.9))
	c1.position = Vector2(290, 28)
	top_stone = c1.get_child(0)
	top_stone.add_theme_font_size_override("font_size", 24)
	add_child(c1)
	var c2 := UI.chip("", Color(0.4, 0.68, 0.55, 0.95))
	c2.position = Vector2(470, 28)
	top_herb = c2.get_child(0)
	top_herb.add_theme_font_size_override("font_size", 24)
	add_child(c2)
	var gear := UI.btn("设置", "ghost", 22, Vector2(86, 52))
	gear.position = Vector2(612, 22)
	gear.pressed.connect(open_settings)
	add_child(gear)

func _build_tabs() -> void:
	var bar := Panel.new()
	bar.position = Vector2(0, 1164)
	bar.size = Vector2(720, 116)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.98, 0.94, 0.9)
	sb.border_color = Color(0.85, 0.7, 0.4, 0.7)
	sb.border_width_top = 2
	sb.corner_radius_top_left = 30
	sb.corner_radius_top_right = 30
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	var defs := [["cultivate", "修炼"], ["roster", "伙伴"], ["home", "洞府"], ["memory", "回忆"]]
	for i in defs.size():
		var b := UI.btn(defs[i][1], "ghost", 32, Vector2(160, 84))
		b.position = Vector2(20 + i * 175, 1180)
		b.size = Vector2(160, 84)
		var key: String = defs[i][0]
		b.pressed.connect(func(): switch_tab(key))
		add_child(b)
		tab_btns[key] = b
	tab_dot = UI.lbl("●", 26, Color("#ee4f6f"), true)
	tab_dot.position = Vector2(20 + 3 * 175 + 118, 1170)
	tab_dot.visible = false
	add_child(tab_dot)

func switch_tab(t: String) -> void:
	cur_tab = t
	for k in pages.keys():
		var p: Control = pages[k]
		p.visible = (k == t)
		if k == t:
			p.call("refresh")
			p.modulate.a = 0.0
			create_tween().tween_property(p, "modulate:a", 1.0, 0.2)
	for k in tab_btns.keys():
		var b: Button = tab_btns[k]
		var active: bool = (k == t)
		var c := UI.GOLD if active else Color(1, 1, 1, 0.55)
		var sb := UI._btn_style(c, 26, Color("#f6d98a") if active else Color(0.85, 0.7, 0.4, 0.8))
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		var fc := Color.WHITE if active else UI.INK
		b.add_theme_color_override("font_color", fc)
		b.add_theme_color_override("font_hover_color", fc)
		b.add_theme_color_override("font_pressed_color", fc)

func _on_changed() -> void:
	top_realm.text = "栖云居"
	top_stone.text = "灵石 %s" % Data.fmt(Game.s["stone"])
	top_herb.text = "灵草 %d" % Game.s["herb"]
	tab_dot.visible = Game.new_scene_count() > 0
	var p: Control = pages.get(cur_tab)
	if p:
		p.call("on_changed")

func show_toast(msg: String) -> void:
	toast_lbl.text = msg
	toast_lbl.modulate.a = 1.0
	if _toast_tw and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_interval(1.8)
	_toast_tw.tween_property(toast_lbl, "modulate:a", 0.0, 0.5)

func float_text(msg: String, pos: Vector2, color: Color = Color("#ee6f8f")) -> void:
	var l := UI.lbl(msg, 30, color, true, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", 10)
	l.position = pos - Vector2(150, 0)
	l.size = Vector2(300, 44)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - 90.0, 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)

# ---------------- 弹窗 ----------------
func modal(title: String, body: Control, buttons: Array = [], width: float = 620.0) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.color = Color(0.08, 0.06, 0.18, 0.55)
	root.add_child(d)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.panel(Color(1, 0.985, 0.95, 0.98), Color(0.85, 0.7, 0.4), 34, 3))
	root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.custom_minimum_size = Vector2(width - 40.0, 0)
	pc.add_child(vb)
	if title != "":
		vb.add_child(UI.brush_lbl(title, 52, UI.GOLD_DEEP))
	if body:
		vb.add_child(body)
	if buttons.size() > 0:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(hb)
		for bd in buttons:
			var b := UI.btn(bd["t"], bd.get("kind", "jade"), 28, Vector2(bd.get("w", 200), 70))
			var cb: Callable = bd.get("cb", Callable())
			var keep: bool = bd.get("keep", false)
			b.pressed.connect(func():
				if not keep:
					root.queue_free()
				if cb.is_valid():
					cb.call())
			hb.add_child(b)
	add_child(root)
	# 居中
	await get_tree().process_frame
	if is_instance_valid(pc):
		pc.position = (Vector2(720, 1280) - pc.size) * 0.5
		pc.pivot_offset = pc.size * 0.5
		pc.scale = Vector2(0.9, 0.9)
		pc.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(pc, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(pc, "modulate:a", 1.0, 0.2)
	return root

func body_text(t: String, size: int = 28, color: Color = UI.INK, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UI.lbl(t, size, color, false, align)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = Vector2(560, 0)
	return l

# ---------------- 启动流程 ----------------
func _startup() -> void:
	var demo := _demo_param()
	if demo != "":
		Game.apply_demo(demo)
		_run_demo(demo)
		return
	if not Game.s["prologue"]:
		await play_prologue()
		return
	var off := Game.process_offline()
	if not off.is_empty():
		await show_offline(off)
	Game.check_seclusion()
	var dg := Game.daily_claim()
	if not dg.is_empty():
		await show_daily(dg)

func _demo_param() -> String:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('demo') || ''")
		return str(v)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			return a.substr(7)
	return ""

func _run_demo(mode: String) -> void:
	await get_tree().create_timer(0.4).timeout
	match mode:
		"main":
			switch_tab("cultivate")
		"roster":
			switch_tab("roster")
		"home":
			switch_tab("home")
		"memory":
			switch_tab("memory")
		"lineup":
			switch_tab("roster")
			pages["roster"].call("open_lineup")
		"dialogue":
			play_story("grok_s2", true)
		"detail":
			open_detail("grok")
		"breakthrough":
			switch_tab("cultivate")
			await get_tree().create_timer(0.8).timeout
			Game.debug_force = 1
			do_breakthrough()
		"btready":
			switch_tab("cultivate")
			Game.debug_force = 1
		"bfail":
			switch_tab("cultivate")
			await get_tree().create_timer(0.8).timeout
			Game.debug_force = -1
			do_breakthrough()
		"secl":
			Game.start_seclusion("qwen", 900.0)
			switch_tab("cultivate")
		"prologue":
			play_prologue()
		"offline":
			show_offline({"elapsed": 5400.0, "used": 5400.0, "xiu": 8120.0, "stone": 2840.0, "capped": false, "eff": 0.6, "letter": Game.pools["grok"]["letters"][0], "who": "grok"})

func play_prologue() -> void:
	Game.s["prologue"] = false
	var info: Dictionary = await play_story("prologue", false, true)
	var picked: String = info.get("picked", "")
	if picked == "":
		picked = Game.s["main"] if Game.s["main"] != "" else "chatgpt"
		if not Game.is_recruited(picked):
			Game.recruit(picked, true)
			Game.set_main(picked)
	await play_story(picked + "_s1", false, true)
	Game.s["prologue"] = true
	Game.s["daily_date"] = Game.today()
	Game.s["streak"] = 1
	Game.save_game()
	var b := body_text("修为会自动增长；灵石由修炼凝结。\n\n· 点「突破」冲击更高境界\n· 在「伙伴」页与她们互动：闲聊、赠礼、品茶、观星、闭关同修\n· 好感与境界提升后，会解锁新的回忆\n· 去「洞府」种灵草，炼制礼物\n· 离开时，伙伴们会写信给你", 27)
	modal("栖云居小记", b, [{"t": "开始修行", "kind": "gold", "w": 260}])

# ---------------- 剧情 ----------------
func play_story(sid: String, force_replay: bool = false, silent_reward: bool = false) -> Dictionary:
	var sc: Dictionary = Game.scene_by_id[sid]
	var replay: bool = force_replay or (sid in Game.s["seen"])
	return await play_scene_dict(sc, replay, silent_reward)

func play_scene_dict(sc: Dictionary, replay: bool, silent_reward: bool = false, start_bond: float = 0.0) -> Dictionary:
	if is_instance_valid(detail):
		detail.visible = false
	var dlg := Dialogue.new()
	overlay.add_child(dlg)
	dlg.play(sc, replay)
	if start_bond > 0.0 and sc.get("char", "") != "":
		Game.add_bond(sc["char"], start_bond)
	var info: Dictionary = await dlg.finished
	if is_instance_valid(detail):
		detail.visible = true
	var sid: String = sc.get("id", "")
	if sid != "" and not sc.get("dyn", false) and not replay:
		Game.mark_seen(sid)
		if sc["char"] != "" and not silent_reward:
			var n := int(sc["n"])
			var stone := 120 * (n + 1)
			Game.s["stone"] += stone
			Game.s["herb"] += 3
			var cid: String = sc["char"]
			Game.add_bond(cid, 20.0, true)
			var b := body_text("「%s」已加入你的回忆。\n\n获得  灵石 +%d   灵草 +3   好感 +20" % [sc["title"], stone], 28, UI.INK, HORIZONTAL_ALIGNMENT_CENTER)
			modal("回忆获得", b, [{"t": "收下", "kind": "gold", "w": 220}])
	Game.save_game()
	return info

func _on_scene_unlocked(sid: String) -> void:
	var sc: Dictionary = Game.scene_by_id[sid]
	show_toast("新的回忆解锁：%s · %s（回忆页）" % [Data.char_def(sc["char"])["name"], sc["title"]])

# ---------------- 互动 ----------------
func interact(id: String, kind: String) -> void:
	var d := Data.char_def(id)
	var pool: Dictionary = Game.pools[id]
	match kind:
		"chat":
			if Game.daily_left(id, "chat") <= 0:
				show_toast("今天已经聊过啦，明天再来吧")
				return
			Game.use_daily(id, "chat")
			var topic: Dictionary = pool["chat"][randi() % pool["chat"].size()]
			var opts: Array = []
			for c in topic["c"]:
				opts.append({"t": c[0], "b": 4, "r": ["%s|%s" % [id, c[1]]]})
			var sc := {"id": "_chat", "char": id, "n": 0, "title": "", "place": "", "tone": _tone_now(), "dyn": true,
				"lines": ["n|你在%s身边坐下，闲聊了起来。" % d["name"], "%s|%s" % [id, topic["l"]], {"c": opts}]}
			await play_scene_dict(sc, false, false, 15.0)
		"tea":
			if Game.daily_left(id, "tea") <= 0:
				show_toast("今天已经一起喝过茶啦")
				return
			if not Game.use_gift("tea"):
				show_toast("没有灵茶了——去洞府用灵草炼制")
				return
			Game.use_daily(id, "tea")
			var line: String = pool["tea"][randi() % pool["tea"].size()]
			Game.s["xiu"] += Game.xiu_rate_base() * 60.0
			var sc2 := {"id": "_tea", "char": id, "n": 0, "title": "", "place": "", "tone": "dusk", "dyn": true,
				"lines": ["n|你取出一盏灵茶，与%s对坐，热气袅袅升起。" % d["name"], "%s:♥|%s" % [id, line], "n|一盏茶的工夫，修为也悄悄精进了一点。（修为 +%s）" % Data.fmt(Game.xiu_rate_base() * 60.0)]}
			await play_scene_dict(sc2, false, false, 22.0)
		"star":
			if Game.daily_left(id, "star") <= 0:
				show_toast("今天已经一起看过星星了")
				return
			Game.use_daily(id, "star")
			var line2: String = pool["star"][randi() % pool["star"].size()]
			var hour: int = Time.get_datetime_dict_from_system()["hour"]
			var intro := "夜幕垂落，你与%s并肩坐在观星台上。" % d["name"]
			if hour >= 6 and hour < 18:
				intro = "白天的星星藏在光里。你与%s并肩坐在观星台上，一起想象着它们的模样。" % d["name"]
			Game.s["xiu"] += Game.xiu_rate_base() * 45.0
			var sc3 := {"id": "_star", "char": id, "n": 0, "title": "", "place": "", "tone": "starry", "dyn": true,
				"lines": ["n|" + intro, "%s:★|%s" % [id, line2]]}
			await play_scene_dict(sc3, false, false, 20.0)
		"gift":
			_open_gift_chooser(id)
		"meditate":
			_open_seclusion_chooser(id)

func _tone_now() -> String:
	var h: int = Time.get_datetime_dict_from_system()["hour"]
	if h >= 18 or h < 5:
		return "night"
	if h >= 16:
		return "dusk"
	return "dawn"

func _open_gift_chooser(id: String) -> void:
	if Game.daily_left(id, "gift") <= 0:
		show_toast("今天已经收了很多礼物，明天再送吧")
		return
	var d := Data.char_def(id)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(body_text("送什么给%s呢？（今日还可赠礼 %d 次）" % [d["name"], Game.daily_left(id, "gift")], 26))
	var holder: Array = [null]
	for g in Data.GIFT_ORDER:
		var gd: Dictionary = Data.GIFTS[g]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var liked: bool = (d["gift"] == g)
		var l := UI.lbl("%s  ×%d%s" % [gd["name"], Game.gift_count(g), "   ♥ 喜爱" if liked else ""], 28, UI.ROSE if liked else UI.INK, liked)
		l.custom_minimum_size = Vector2(360, 0)
		row.add_child(l)
		var b := UI.btn("赠送", "rose" if liked else "jade", 26, Vector2(150, 60))
		b.disabled = Game.gift_count(g) <= 0
		var gid: String = g
		b.pressed.connect(func():
			if holder[0]:
				holder[0].queue_free()
			_give_gift(id, gid))
		row.add_child(b)
		vb.add_child(row)
	var m := await modal("赠礼", vb, [{"t": "取消", "kind": "ghost", "w": 200}])
	holder[0] = m

func _give_gift(id: String, g: String) -> void:
	if not Game.use_gift(g):
		return
	Game.use_daily(id, "gift")
	var d := Data.char_def(id)
	var pool: Dictionary = Game.pools[id]
	var liked: bool = (d["gift"] == g)
	var gname: String = Data.GIFTS[g]["name"]
	var line: String = pool["gift_like"] if liked else pool["gift_ok"]
	var sc := {"id": "_gift", "char": id, "n": 0, "title": "", "place": "", "tone": _tone_now(), "dyn": true,
		"lines": ["n|你把一份「%s」递给%s。%s" % [gname, d["name"], "——正是她最喜欢的！" if liked else ""], "%s:%s|%s" % [id, "♥" if liked else "★", line]]}
	await play_scene_dict(sc, false, false, 45.0 if liked else 22.0)

func _open_seclusion_chooser(id: String) -> void:
	if Game.sec_active():
		show_toast("已经有人在闭关同修中")
		return
	var d := Data.char_def(id)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(body_text("与%s一同闭关：期间修为获取 ×%.2f（含月律加成），结束时获得好感与修为奖励。可离开游戏，离线同样计算。" % [d["name"], Game.sec_mult()], 24))
	var opts := [["1 分钟（试玩）", 60.0], ["15 分钟", 900.0], ["1 小时", 3600.0], ["4 小时", 14400.0]]
	var holder: Array = [null]
	for o in opts:
		var secs: float = o[1]
		var b := UI.btn("%s  ·  好感约 +%d" % [o[0], int(12.0 + minf(48.0, secs / 90.0))], "jade", 26, Vector2(560, 64))
		b.pressed.connect(func():
			holder[0].queue_free()
			_start_seclusion(id, secs))
		vb.add_child(b)
	var m := await modal("闭关同修", vb, [{"t": "取消", "kind": "ghost", "w": 200}])
	holder[0] = m

func _start_seclusion(id: String, secs: float) -> void:
	Game.start_seclusion(id, secs)
	close_detail()
	switch_tab("cultivate")
	var line: String = Game.pools[id]["med_start"]
	var d := Data.char_def(id)
	show_toast("%s：%s" % [d["name"], line.substr(0, 28)])

func _on_seclusion_done(info: Dictionary) -> void:
	var id: String = info["id"]
	var d := Data.char_def(id)
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 12)
	var t := UI.lbl(Game.pools[id]["med_done"], 28, UI.INK)
	t.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	t.custom_minimum_size = Vector2(560, 0)
	b.add_child(UI.lbl("%s · %s" % [d["name"], d["title"]], 26, d["color"].darkened(0.2), true))
	b.add_child(t)
	b.add_child(UI.lbl("闭关 %s · 好感 +%d · 修为 +%s" % [Data.fmt_time(info["secs"]), int(info["bond"]), Data.fmt(info["xiu"])], 26, UI.GOLD_DEEP, true))
	modal("出关", b, [{"t": "好的", "kind": "gold", "w": 220}])

# ---------------- 突破 ----------------
func do_breakthrough() -> void:
	if not Game.can_breakthrough():
		return
	var res := Game.attempt_breakthrough()
	if res.is_empty():
		return
	var fx := BreakthroughFx.new()
	overlay.add_child(fx)
	var mid: String = Game.s["main"]
	fx.start(res, mid)
	await fx.closed
	if res["ok"]:
		for id in Game.recruited_ids():
			Game.add_bond(id, 3.0, true)

# ---------------- 详情 / 设置 / 离线 / 每日 ----------------
func open_detail(id: String) -> void:
	close_detail()
	detail = DetailView.new()
	detail.main = self
	overlay.add_child(detail)
	detail.show_char(id)

func close_detail() -> void:
	if is_instance_valid(detail):
		detail.queue_free()
	detail = null

func show_offline(off: Dictionary) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	var cap := "（已达离线上限）" if off["capped"] else ""
	vb.add_child(body_text("你离开了 %s%s，伙伴们守着洞府，修炼不曾停歇。" % [Data.fmt_time(off["elapsed"]), cap], 27))
	vb.add_child(UI.lbl("修为 +%s     灵石 +%s" % [Data.fmt(off["xiu"]), Data.fmt(off["stone"])], 30, UI.GOLD_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER))
	if off.get("letter", "") != "":
		var who := Data.char_def(off["who"])
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.panel(Color("#fff3d9"), who["color"], 18, 2, false))
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", 6)
		pc.add_child(lv)
		lv.add_child(UI.lbl("信 · %s 留下的信" % who["name"], 26, who["color"].darkened(0.25), true))
		var t := UI.lbl(off["letter"], 25, UI.INK)
		t.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		t.custom_minimum_size = Vector2(520, 0)
		lv.add_child(t)
		vb.add_child(pc)
	var done: Array = [false]
	var m := await modal("离线归来", vb, [{"t": "收下", "kind": "gold", "w": 240, "cb": func(): done[0] = true}])
	while not done[0]:
		await get_tree().process_frame

func show_daily(dg: Dictionary) -> void:
	var main_id: String = Game.s["main"]
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	if main_id != "":
		var d := Data.char_def(main_id)
		vb.add_child(body_text("%s：「早安！今天也一起好好修行吧。」" % d["name"], 27))
	vb.add_child(UI.lbl("连续登录第 %d 天" % dg["streak"], 26, UI.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER))
	var rw := "灵石 +%d    灵草 +%d" % [dg["stone"], dg["herb"]]
	if dg["extra"] != "":
		rw += "    " + dg["extra"]
	vb.add_child(UI.lbl(rw, 30, UI.GOLD_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER))
	var done: Array = [false]
	await modal("每日赠礼", vb, [{"t": "领取", "kind": "gold", "w": 240, "cb": func(): done[0] = true}])
	while not done[0]:
		await get_tree().process_frame

func open_settings() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.add_child(body_text("栖云居 · 挂机修仙（原型 v0.1）\n角色为 AI 拟人同人设定的 Q 版二次创作。", 24, UI.INK_SOFT))
	var holder: Array = [null]
	var sp := UI.btn("试玩加速：×%d（点击切换）" % int(Game.speed), "ghost", 26, Vector2(560, 64))
	sp.pressed.connect(func():
		Game.speed = {1.0: 10.0, 10.0: 60.0, 60.0: 1.0}.get(Game.speed, 1.0)
		sp.text = "试玩加速：×%d（点击切换）" % int(Game.speed))
	vb.add_child(sp)
	var rd := UI.btn("重置今日互动次数（测试）", "ghost", 26, Vector2(560, 64))
	rd.pressed.connect(func():
		Game.reset_today()
		show_toast("今日互动已重置"))
	vb.add_child(rd)
	var sv := UI.btn("立即保存", "jade", 26, Vector2(560, 64))
	sv.pressed.connect(func():
		Game.save_game()
		show_toast("已保存"))
	vb.add_child(sv)
	var rs := UI.btn("清除存档，重新开始", "rose", 26, Vector2(560, 64))
	rs.pressed.connect(func():
		holder[0].queue_free()
		_confirm_reset())
	vb.add_child(rs)
	var m := await modal("设置", vb, [{"t": "关闭", "kind": "gold", "w": 220}])
	holder[0] = m

func _confirm_reset() -> void:
	modal("确认清除？", body_text("所有进度、好感与回忆都会被清除，无法恢复。", 28), [
		{"t": "取消", "kind": "ghost", "w": 200},
		{"t": "清除", "kind": "rose", "w": 200, "cb": func():
			Game.reset_all()
			get_tree().reload_current_scene()}])
