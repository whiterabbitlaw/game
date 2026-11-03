class_name PageCultivate
extends Control
## 修炼主页：境界、修为条、主角打坐（灵气粒子 / 光环）、伙伴小队、突破、闭关同修

var main: Control
var title_lbl: Label
var next_lbl: Label
var bar: ProgressBar
var bar_lbl: Label
var rate_lbl: Label
var sec_panel: PanelContainer
var sec_lbl: Label
var bt_btn: Button
var bt_info: Label
var seat_btn: Button
var stage: Control
var main_node: Chibi = null
var partner_node: Chibi = null
var crowd: Array = []
var bubble: PanelContainer
var bubble_lbl: Label
var bubble_name: Label
var tap_btn: Button
var _sig := ""
var _meditate := true
var _bubble_t := 6.0
var _pulse := 0.0
var _bt_tw: Tween

func build() -> void:
	title_lbl = UI.brush_lbl("", 88, UI.GOLD_DEEP)
	title_lbl.position = Vector2(0, 0)
	title_lbl.size = Vector2(720, 110)
	title_lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	title_lbl.add_theme_constant_override("outline_size", 12)
	add_child(title_lbl)
	next_lbl = UI.lbl("", 24, UI.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER)
	next_lbl.position = Vector2(0, 98)
	next_lbl.size = Vector2(720, 34)
	add_child(next_lbl)
	bar = UI.bar(34, UI.GOLD)
	bar.position = Vector2(60, 138)
	bar.size = Vector2(600, 34)
	add_child(bar)
	bar_lbl = UI.lbl("", 22, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	bar_lbl.position = Vector2(60, 138)
	bar_lbl.size = Vector2(600, 34)
	bar_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_lbl.add_theme_color_override("font_outline_color", Color(0.45, 0.3, 0.1, 0.8))
	bar_lbl.add_theme_constant_override("outline_size", 6)
	add_child(bar_lbl)
	rate_lbl = UI.lbl("", 24, UI.INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	rate_lbl.position = Vector2(0, 178)
	rate_lbl.size = Vector2(720, 34)
	add_child(rate_lbl)

	stage = Control.new()
	stage.position = Vector2.ZERO
	stage.size = Vector2(720, 1060)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	bubble = PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UI.panel(Color(1, 0.985, 0.95, 0.94), Color(0.85, 0.7, 0.4, 0.9), 24, 2))
	bubble.position = Vector2(60, 232)
	bubble.size = Vector2(600, 100)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 2)
	bubble.add_child(bv)
	bubble_name = UI.lbl("", 22, UI.GOLD_DEEP, true)
	bv.add_child(bubble_name)
	bubble_lbl = UI.lbl("", 25, UI.INK)
	bubble_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	bubble_lbl.custom_minimum_size = Vector2(556, 0)
	bv.add_child(bubble_lbl)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.modulate.a = 0.0
	add_child(bubble)

	tap_btn = Button.new()
	tap_btn.flat = true
	tap_btn.focus_mode = Control.FOCUS_NONE
	tap_btn.position = Vector2(150, 330)
	tap_btn.size = Vector2(420, 440)
	tap_btn.pressed.connect(_on_tap)
	add_child(tap_btn)

	sec_panel = PanelContainer.new()
	sec_panel.add_theme_stylebox_override("panel", UI.panel(Color(0.5, 0.45, 0.85, 0.92), Color(1, 1, 1, 0.5), 22, 2))
	sec_panel.position = Vector2(60, 790)
	sec_panel.size = Vector2(600, 50)
	sec_lbl = UI.lbl("", 24, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	sec_panel.add_child(sec_lbl)
	sec_panel.visible = false
	add_child(sec_panel)

	bt_btn = UI.btn("", "gold", 40, Vector2(560, 100))
	bt_btn.position = Vector2(80, 842)
	bt_btn.size = Vector2(560, 100)
	bt_btn.pressed.connect(func(): main.do_breakthrough())
	add_child(bt_btn)
	bt_info = UI.lbl("", 22, UI.INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	bt_info.position = Vector2(0, 944)
	bt_info.size = Vector2(720, 30)
	add_child(bt_info)

	var row := HBoxContainer.new()
	row.position = Vector2(40, 980)
	row.size = Vector2(640, 66)
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	seat_btn = UI.btn("起身活动", "ghost", 24, Vector2(0, 66))
	seat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seat_btn.pressed.connect(func():
		_meditate = not _meditate
		_apply_mode())
	row.add_child(seat_btn)
	var b2 := UI.btn("闭关同修", "jade", 24, Vector2(0, 66))
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b2.pressed.connect(func(): _on_sec_pressed())
	row.add_child(b2)
	var b3 := UI.btn("全员合影", "rose", 24, Vector2(0, 66))
	b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b3.pressed.connect(func():
		main.switch_tab("roster")
		main.pages["roster"].call("open_lineup"))
	row.add_child(b3)

func _on_sec_pressed() -> void:
	if Game.sec_active():
		var id: String = Game.s["sec"]["id"]
		main.modal("闭关中", main.body_text("正与%s闭关同修，剩余 %s。\n提前出关将不会获得完成奖励。" % [Data.char_def(id)["name"], Data.fmt_time(Game.sec_remaining())], 27), [
			{"t": "继续闭关", "kind": "jade", "w": 220},
			{"t": "提前出关", "kind": "rose", "w": 220, "cb": func(): Game.cancel_seclusion()}])
		return
	# 选一位同修
	var ids := Game.recruited_ids()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.add_child(main.body_text("选择一位伙伴陪你闭关：", 26))
	var holder: Array = [null]
	for id in ids:
		var d := Data.char_def(id)
		var b := UI.btn("%s · %s   （羁绊 Lv.%d）" % [d["name"], d["title"], Game.bond_lv(id)], "ghost", 24, Vector2(560, 56))
		var cid: String = id
		b.pressed.connect(func():
			holder[0].queue_free()
			main._open_seclusion_chooser(cid))
		vb.add_child(b)
	var m = await main.modal("闭关同修", vb, [{"t": "取消", "kind": "ghost", "w": 200}])
	holder[0] = m

func _on_tap() -> void:
	if main_node == null:
		return
	var id: String = Game.s["main"]
	main_node.bounce()
	var pool: Array = Game.pools[id]["poke"]
	_show_bubble(id, pool[randi() % pool.size()])
	if Game.daily_left(id, "poke") > 0:
		Game.use_daily(id, "poke")
		Game.add_bond(id, 1.0, true)
		main.float_text("♥ +1", Vector2(360, 380) + position)
		if randf() < 0.4:
			main_node.shy()

func _show_bubble(id: String, text: String) -> void:
	bubble_name.text = "%s · %s" % [Data.char_def(id)["name"], Data.char_def(id)["title"]]
	bubble_lbl.text = text
	bubble.size = Vector2(600, 10)
	bubble.modulate.a = 1.0
	_bubble_t = 7.0

func _apply_mode() -> void:
	if main_node:
		main_node.set_mode("meditate" if (_meditate or Game.sec_active()) else "idle")
	if partner_node:
		partner_node.set_mode("meditate")
	seat_btn.text = "起身活动" if _meditate else "静心打坐"

func _signature() -> String:
	var a := Game.recruited_ids()
	return "%s|%s|%s|%s" % [",".join(a), Game.s["main"], Game.s["sec"].get("id", ""), str(Game.sec_active())]

func refresh() -> void:
	_rebuild_chars(true)
	on_changed()

func on_changed() -> void:
	_rebuild_chars(false)

func _rebuild_chars(force: bool) -> void:
	var sig := _signature()
	if sig == _sig and not force:
		return
	_sig = sig
	for c in stage.get_children():
		c.queue_free()
	main_node = null
	partner_node = null
	crowd.clear()
	var mid: String = Game.s["main"]
	if mid == "":
		return
	var sid: String = Game.s["sec"].get("id", "")
	var has_partner := Game.sec_active() and sid != "" and sid != mid
	if has_partner:
		main_node = Chibi.new().setup(mid, 470, true)
		main_node.position = Vector2(250, 790)
		partner_node = Chibi.new().setup(sid, 430, true)
		partner_node.position = Vector2(490, 790)
		stage.add_child(partner_node)
		stage.add_child(main_node)
	else:
		main_node = Chibi.new().setup(mid, 520, true)
		main_node.position = Vector2(360, 790)
		stage.add_child(main_node)
	_apply_mode()
	# 伙伴小队
	var others: Array = []
	for id in Game.recruited_ids():
		if id != mid and id != sid:
			others.append(id)
	var n := others.size()
	var span := minf(640.0, float(n) * 82.0)
	for i in n:
		var cn := Chibi.new().setup(others[i], 118, false)
		var x := 360.0 - span * 0.5 + 41.0 + float(i) * (span / maxf(1.0, float(n)))
		cn.position = Vector2(x, 1052 if false else 836)
		stage.add_child(cn)
		crowd.append(cn)
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.position = Vector2(x - 36.0, 836.0 - 118.0)
		btn.size = Vector2(72, 118)
		var oid: String = others[i]
		btn.pressed.connect(func():
			cn.bounce()
			main.open_detail(oid))
		stage.add_child(btn)

func _process(delta: float) -> void:
	if not visible:
		return
	var k := Game.realm_k()
	title_lbl.text = "%s  %s" % [Data.realm_name(k), Data.stage_name(k)]
	var req := Game.req_now()
	if k >= Data.MAX_STEP:
		next_lbl.text = "大道巅峰 · 敬请期待后续飞升"
		bar.value = 100.0
		bar_lbl.text = "—"
	else:
		next_lbl.text = "下一阶段：%s%s" % [Data.step_name(k + 1), "（大境界突破）" if Data.is_major(k) else ""]
		bar.max_value = req
		bar.value = minf(Game.s["xiu"], req)
		bar_lbl.text = "%s / %s" % [Data.fmt(Game.s["xiu"]), Data.fmt(req)]
	rate_lbl.text = "修为 +%s/秒    灵石 +%s/秒" % [Data.fmt(Game.xiu_rate()), Data.fmt(Game.stone_rate())]
	# 闭关
	if Game.sec_active():
		var d := Data.char_def(Game.s["sec"]["id"])
		sec_panel.visible = true
		sec_lbl.text = "闭关同修 · %s · 剩余 %s · 修为 ×%.2f" % [d["name"], Data.fmt_time(Game.sec_remaining()), Game.sec_mult()]
	else:
		sec_panel.visible = false
	# 突破按钮
	if k >= Data.MAX_STEP:
		bt_btn.text = "已至大道巅峰"
		bt_btn.disabled = true
		bt_info.text = ""
	elif Game.can_breakthrough():
		bt_btn.text = "突破！成功率 %d%%" % int(round(Game.success_chance() * 100.0))
		bt_btn.disabled = false
		_pulse += delta * 4.0
		bt_btn.pivot_offset = bt_btn.size * 0.5
		bt_btn.scale = Vector2.ONE * (1.0 + sin(_pulse) * 0.025)
		bt_info.text = "失败将损失约 %d%% 修为，下次成功率提升" % int(round(Game.loss_fraction() * 100.0))
	else:
		bt_btn.text = "修为未满 · 还差 %s" % Data.fmt(req - Game.s["xiu"])
		bt_btn.disabled = true
		bt_btn.scale = Vector2.ONE
		bt_info.text = "%s成功率 %d%%" % ["大境界突破 · " if Data.is_major(k) else "", int(round(Game.success_chance() * 100.0))]
	# 气泡自动
	_bubble_t -= delta
	if _bubble_t <= 0.0 and Game.s["main"] != "":
		var id: String = Game.s["main"]
		if bubble.modulate.a > 0.5:
			bubble.modulate.a = maxf(0.0, bubble.modulate.a - delta * 2.0)
			if bubble.modulate.a <= 0.0:
				_bubble_t = 9.0
		else:
			var pool: Array = Game.pools[id]["poke"]
			_show_bubble(id, pool[randi() % pool.size()])
	elif bubble.modulate.a > 0.0 and _bubble_t > 0.0:
		pass

func open_lineup_placeholder() -> void:
	pass
