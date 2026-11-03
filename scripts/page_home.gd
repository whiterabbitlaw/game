class_name PageHome
extends Control
## 洞府：灵田（种植/收获）、炼制礼物、灵市、礼物库存

var main: Control
var plot_views: Array = []
var plot_btns: Array = []
var plot_lbls: Array = []
var inv_lbl: Label
var craft_btns: Dictionary = {}
var buy_btns: Dictionary = {}
var tip_lbl: Label
var all_btn: Button

class PlotView:
	extends Control
	var idx := 0
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var unlocked := Game.plot_unlocked(idx)
		var st := Game.plot_state(idx) if unlocked else "locked"
		var c := Vector2(size.x * 0.5, size.y * 0.74)
		var soil := Color("#8a6a54") if unlocked else Color("#9a97a8")
		draw_set_transform(c, 0.0, Vector2(1.0, 0.38))
		draw_circle(Vector2.ZERO, 64.0, soil.darkened(0.25))
		draw_circle(Vector2(0, -4), 58.0, soil)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if st == "growing" or st == "ripe":
			var p := Game.plot_progress(idx)
			var h := 18.0 + 66.0 * p
			var sway := sin(_t * 2.0 + float(idx)) * 3.0 * p
			var base := c + Vector2(0, -6)
			for k in 3:
				var a := -0.55 + 0.55 * float(k)
				var tip := base + Vector2(sin(a) * h * 0.7 + sway, -cos(a) * h)
				draw_line(base, tip, Color("#5aa86d"), 5.0, true)
				draw_circle(tip, 8.0 + 8.0 * p, Color("#7fd18f"))
			if st == "ripe":
				var glow := 0.5 + 0.5 * sin(_t * 3.0)
				draw_circle(base + Vector2(0, -h - 6), 14.0 + 4.0 * glow, Color(1.0, 0.92, 0.5, 0.55))
				draw_circle(base + Vector2(0, -h - 6), 8.0, Color("#ffe27a"))
		elif st == "locked":
			draw_string(UI.bold(), c + Vector2(-30, -20), "未开垦", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 24, Color("#6a667f"))

func build() -> void:
	var t := UI.brush_lbl("洞府  灵田", 54, UI.GOLD_DEEP, HORIZONTAL_ALIGNMENT_LEFT)
	t.position = Vector2(30, 6)
	t.size = Vector2(420, 70)
	t.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	t.add_theme_constant_override("outline_size", 10)
	add_child(t)
	all_btn = UI.btn("一键耕作", "gold", 24, Vector2(170, 56))
	all_btn.position = Vector2(520, 14)
	all_btn.size = Vector2(170, 56)
	all_btn.pressed.connect(_all)
	add_child(all_btn)
	tip_lbl = UI.lbl("", 22, UI.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER)
	tip_lbl.position = Vector2(0, 76)
	tip_lbl.size = Vector2(720, 32)
	add_child(tip_lbl)
	for i in 6:
		var col := i % 3
		var row := i / 3
		var x := 30.0 + float(col) * 224.0
		var y := 116.0 + float(row) * 262.0
		var card := Panel.new()
		card.position = Vector2(x, y)
		card.size = Vector2(212, 250)
		card.add_theme_stylebox_override("panel", UI.panel(Color(1, 0.985, 0.95, 0.82), Color(0.85, 0.7, 0.4, 0.8), 26, 2))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(card)
		var pv := PlotView.new()
		pv.idx = i
		pv.position = Vector2(x, y + 6)
		pv.size = Vector2(212, 170)
		pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pv)
		plot_views.append(pv)
		var l := UI.lbl("", 22, UI.INK, true, HORIZONTAL_ALIGNMENT_CENTER)
		l.position = Vector2(x, y + 168)
		l.size = Vector2(212, 30)
		add_child(l)
		plot_lbls.append(l)
		var b := UI.btn("", "jade", 24, Vector2(176, 46))
		b.position = Vector2(x + 18, y + 198)
		b.size = Vector2(176, 46)
		var idx := i
		b.pressed.connect(func(): _tap(idx))
		add_child(b)
		plot_btns.append(b)
	# 炼制
	var cp := PanelContainer.new()
	cp.position = Vector2(30, 650)
	cp.size = Vector2(660, 190)
	cp.add_theme_stylebox_override("panel", UI.panel(Color(1, 0.985, 0.95, 0.88), Color(0.85, 0.7, 0.4, 0.8), 26, 2))
	add_child(cp)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cp.add_child(cv)
	cv.add_child(UI.lbl("炼制 · 用灵草制作礼物", 26, UI.JADE_DEEP, true))
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 12)
	cv.add_child(ch)
	for g in ["tea", "flower"]:
		var b := UI.btn("", "jade", 24, Vector2(300, 80))
		var gid: String = g
		b.pressed.connect(func():
			if Game.craft(gid):
				main.show_toast("炼制成功：%s" % Data.GIFTS[gid]["name"]))
		ch.add_child(b)
		craft_btns[g] = b
	# 灵市
	var mp := PanelContainer.new()
	mp.position = Vector2(30, 856)
	mp.size = Vector2(660, 190)
	mp.add_theme_stylebox_override("panel", UI.panel(Color(1, 0.985, 0.95, 0.88), Color(0.85, 0.7, 0.4, 0.8), 26, 2))
	add_child(mp)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mp.add_child(mv)
	mv.add_child(UI.lbl("灵市 · 用灵石购买礼物", 26, UI.GOLD_DEEP, true))
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 10)
	mv.add_child(mh)
	for g in ["cake", "dew", "scroll"]:
		var b := UI.btn("", "gold", 22, Vector2(200, 80))
		var gid: String = g
		b.pressed.connect(func():
			if Game.buy(gid):
				main.show_toast("购入：%s" % Data.GIFTS[gid]["name"]))
		mh.add_child(b)
		buy_btns[g] = b
	inv_lbl = UI.lbl("", 22, UI.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER)

func refresh() -> void:
	on_changed()

func on_changed() -> void:
	_update()

func _tap(i: int) -> void:
	if not Game.plot_unlocked(i):
		main.show_toast("需要境界达到「%s」才能开垦" % Data.step_name(Game.PLOT_UNLOCK_STEP[i]))
		return
	match Game.plot_state(i):
		"empty":
			Game.plant(i)
			main.show_toast("种下了一株灵草")
		"ripe":
			var n := Game.harvest(i)
			main.float_text("灵草 +%d" % n, plot_views[i].global_position + Vector2(106, 60), UI.JADE_DEEP)
		_:
			main.show_toast("灵草还在生长，约需 %s" % Data.fmt_time(Game.grow_time() * (1.0 - Game.plot_progress(i))))

func _all() -> void:
	var got := 0
	var planted := 0
	for i in 6:
		if Game.plot_unlocked(i):
			if Game.plot_state(i) == "ripe":
				got += Game.harvest(i)
			if Game.plot_state(i) == "empty":
				Game.plant(i)
				planted += 1
	if got > 0:
		main.show_toast("收获灵草 +%d，重新播种 %d 块" % [got, planted])
	elif planted > 0:
		main.show_toast("播种了 %d 块灵田" % planted)
	else:
		main.show_toast("灵草还在生长")

func _update() -> void:
	tip_lbl.text = "生长约 %s · 产量 3~5 株（含青岚润泽 +%d%%）" % [Data.fmt_time(Game.grow_time()), int(Game.passive("herb"))]
	for i in 6:
		var st := Game.plot_state(i) if Game.plot_unlocked(i) else "locked"
		var b: Button = plot_btns[i]
		var l: Label = plot_lbls[i]
		match st:
			"locked":
				b.text = "境界不足"
				b.disabled = false
				l.text = Data.step_name(Game.PLOT_UNLOCK_STEP[i]) + "开启"
			"empty":
				b.text = "播种"
				l.text = "空闲"
			"growing":
				b.text = "生长中"
				l.text = "%d%%" % int(Game.plot_progress(i) * 100.0)
			"ripe":
				b.text = "收获"
				l.text = "已成熟"
	for g in craft_btns.keys():
		var cost: int = 3 if g == "tea" else 4
		var b: Button = craft_btns[g]
		b.text = "%s ×%d\n灵草 %d" % [Data.GIFTS[g]["name"], Game.gift_count(g), cost]
		b.disabled = Game.s["herb"] < cost
	for g in buy_btns.keys():
		var price: int = {"cake": 60, "dew": 140, "scroll": 100}[g]
		var b: Button = buy_btns[g]
		b.text = "%s ×%d\n灵石 %d" % [Data.GIFTS[g]["name"], Game.gift_count(g), price]
		b.disabled = Game.s["stone"] < price

func _process(_d: float) -> void:
	if visible:
		for i in 6:
			if Game.plot_unlocked(i):
				var st := Game.plot_state(i)
				if st == "growing":
					plot_lbls[i].text = "%d%% · %s" % [int(Game.plot_progress(i) * 100.0), Data.fmt_time(Game.grow_time() * (1.0 - Game.plot_progress(i)))]
					plot_btns[i].text = "生长中"
				elif st == "ripe" and plot_btns[i].text != "收获":
					_update()
