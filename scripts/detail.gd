class_name DetailView
extends Control
## 伙伴详情：立绘、羁绊、被动、互动按钮（闲聊/赠礼/品茶/观星/闭关/升级/同行/回忆）

var main: Control
var cid := ""
var char_node: Chibi
var info_box: Control
var btn_grid: GridContainer
var bond_bar: ProgressBar
var bond_lbl: Label
var lv_lbl: Label
var pass_lbl: Label
var btns: Dictionary = {}
var _built := false

func show_char(id: String) -> void:
	cid = id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var d := Data.char_def(id)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/bg/dawn.jpg")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var tint := ColorRect.new()
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(d["color"].r, d["color"].g, d["color"].b, 0.18)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	char_node = Chibi.new().setup(id, 480, true)
	char_node.position = Vector2(360, 640)
	add_child(char_node)
	if not Game.is_recruited(id):
		char_node.set_dark(true)
	else:
		char_node.set_mode("meditate")
	char_node.enter(0.0)
	# 标题
	var t := UI.brush_lbl(d["title"], 84, d["color"].darkened(0.25))
	t.position = Vector2(0, 20)
	t.size = Vector2(720, 110)
	t.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
	t.add_theme_constant_override("outline_size", 14)
	add_child(t)
	var n := UI.lbl("%s  ·  %s" % [d["name"], d["traits"]], 26, UI.INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	n.position = Vector2(0, 118)
	n.size = Vector2(720, 36)
	add_child(n)
	var back := UI.btn("返回", "dark", 26, Vector2(130, 56))
	back.position = Vector2(20, 24)
	back.pressed.connect(func(): main.close_detail())
	add_child(back)
	# 信息面板
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 660)
	panel.size = Vector2(680, 590)
	panel.add_theme_stylebox_override("panel", UI.panel(Color(1, 0.985, 0.95, 0.94), d["color"], 32, 3))
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var bio := UI.lbl(d["bio"], 22, UI.INK_SOFT)
	bio.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	bio.custom_minimum_size = Vector2(630, 0)
	vb.add_child(bio)
	pass_lbl = UI.lbl("", 23, UI.JADE_DEEP, true)
	pass_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	pass_lbl.custom_minimum_size = Vector2(630, 0)
	vb.add_child(pass_lbl)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 12)
	bond_lbl = UI.lbl("", 24, UI.ROSE, true)
	bond_lbl.custom_minimum_size = Vector2(240, 0)
	br.add_child(bond_lbl)
	bond_bar = UI.bar(18, UI.ROSE)
	bond_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bond_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(bond_bar)
	vb.add_child(br)
	lv_lbl = UI.lbl("", 22, UI.INK)
	vb.add_child(lv_lbl)
	btn_grid = GridContainer.new()
	btn_grid.columns = 2
	btn_grid.add_theme_constant_override("h_separation", 12)
	btn_grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(btn_grid)
	_built = true
	Game.changed.connect(_refresh)
	_refresh()

func _mk(key: String, text: String, kind: String, cb: Callable) -> void:
	var b := UI.btn(text, kind, 25, Vector2(306, 66))
	b.pressed.connect(cb)
	btn_grid.add_child(b)
	btns[key] = b

func _refresh() -> void:
	if not _built or not is_inside_tree():
		return
	var id := cid
	var d := Data.char_def(id)
	var rec := Game.is_recruited(id)
	for c in btn_grid.get_children():
		c.queue_free()
	btns.clear()
	if not rec:
		pass_lbl.text = "被动（结缘后生效）：%s —— %s" % [d["pname"], d["pdesc"] % ("%.1f" % (d["per"] * 0.9))]
		bond_lbl.text = "尚未结缘"
		bond_bar.value = 0
		lv_lbl.text = "结缘后将在栖云居留下，并解锁她的回忆与互动。"
		var cost := Game.recruit_cost()
		_mk("recruit", "结缘 · 灵石 %d" % cost, "gold", func(): _recruit())
		_mk("mem", "查看回忆", "ghost", func():
			main.close_detail()
			main.switch_tab("memory"))
		return
	var bl := Game.bond_lv(id)
	var pr := Data.bond_progress(Game.bond_xp(id))
	var w := "同行 100%" if Game.s["main"] == id else "伙伴 40%"
	pass_lbl.text = "被动：%s（%s）\n%s" % [d["pname"], w, d["pdesc"] % ("%.1f" % Game.passive_of(id))]
	bond_lbl.text = "♥ 羁绊 Lv.%d「%s」" % [bl, Data.BOND_NAMES[bl - 1]]
	bond_bar.max_value = pr[1]
	bond_bar.value = pr[0]
	var uc := Game.upgrade_cost(id)
	lv_lbl.text = "修行 Lv.%d    好感 %d%s" % [Game.lv(id), int(Game.bond_xp(id)), ("  /  下一级 %d" % int(Data.BOND_XP[bl])) if bl < 10 else "（满）"]
	_mk("chat", "闲聊  %d/1" % Game.daily_used(id, "chat"), "jade", func(): main.interact(id, "chat"))
	_mk("gift", "赠礼  %d/3" % Game.daily_used(id, "gift"), "rose", func(): main.interact(id, "gift"))
	_mk("tea", "品茶  %d/1（灵茶×%d）" % [Game.daily_used(id, "tea"), Game.gift_count("tea")], "jade", func(): main.interact(id, "tea"))
	_mk("star", "观星  %d/1" % Game.daily_used(id, "star"), "jade", func(): main.interact(id, "star"))
	_mk("med", "闭关同修", "gold", func(): main.interact(id, "meditate"))
	_mk("up", "提升修行 · 灵石%d%s" % [uc[0], (" 灵草%d" % uc[1]) if uc[1] > 0 else ""], "gold", func():
		if Game.upgrade(id):
			char_node.bounce()
			main.show_toast("%s 修行提升至 Lv.%d" % [d["name"], Game.lv(id)]))
	if Game.s["main"] == id:
		_mk("main", "当前同行", "ghost", func(): pass)
		btns["main"].disabled = true
	else:
		_mk("main", "设为同行", "ghost", func():
			Game.set_main(id)
			main.show_toast("%s 成为同行伙伴，被动效果全额生效" % d["name"]))
	var newn := 0
	for sc in Game.char_scenes(id):
		if Game.scene_status(sc["id"]) == "new":
			newn += 1
	_mk("mem", "回忆%s" % ("（新 %d）" % newn if newn > 0 else ""), "ghost", func():
		main.close_detail()
		main.switch_tab("memory")
		main.pages["memory"].call("focus_char", id))

func _recruit() -> void:
	var id := cid
	if Game.recruit(id):
		char_node.set_dark(false)
		char_node.set_mode("meditate")
		char_node.flash(0.6)
		main.close_detail()
		main.switch_tab("roster")
		await main.play_story(id + "_s1")
