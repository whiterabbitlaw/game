class_name PageRoster
extends Control
## 伙伴页：九位伙伴卡片 + 全员合影

var main: Control
var head_lbl: Label
var scroll: ScrollContainer
var list: VBoxContainer
var lineup: Control = null

func build() -> void:
	head_lbl = UI.brush_lbl("", 54, UI.GOLD_DEEP, HORIZONTAL_ALIGNMENT_LEFT)
	head_lbl.position = Vector2(30, 6)
	head_lbl.size = Vector2(420, 70)
	head_lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	head_lbl.add_theme_constant_override("outline_size", 10)
	add_child(head_lbl)
	var b := UI.btn("全员合影", "rose", 24, Vector2(170, 56))
	b.position = Vector2(520, 14)
	b.size = Vector2(170, 56)
	b.pressed.connect(open_lineup)
	add_child(b)
	scroll = ScrollContainer.new()
	scroll.position = Vector2(0, 84)
	scroll.size = Vector2(720, 976)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.custom_minimum_size = Vector2(720, 0)
	scroll.add_child(list)

func refresh() -> void:
	_rebuild()

func on_changed() -> void:
	if visible and not _is_dragging():
		_rebuild()

func _is_dragging() -> bool:
	return false

var _sig := ""
func _rebuild() -> void:
	var sig := "%s|%s|%d|%d" % [str(Game.s["chars"].keys()), Game.s["main"], int(Game.s["stone"] / 10.0 if Game.recruited_ids().size() < 9 else 0), Game.new_scene_count()]
	var det := ""
	for id in Game.recruited_ids():
		det += "%d:%d:%d;" % [Game.lv(id), Game.bond_lv(id), int(Game.bond_xp(id) / 5.0)]
	sig += det
	if sig == _sig:
		return
	_sig = sig
	var keep_scroll := scroll.scroll_vertical
	for c in list.get_children():
		c.queue_free()
	head_lbl.text = "伙伴  %d / 9" % Game.recruited_ids().size()
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 2)
	list.add_child(pad)
	for c in Data.CHARS:
		list.add_child(_card(c))
	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0, 20)
	list.add_child(bottom)
	await get_tree().process_frame
	scroll.scroll_vertical = keep_scroll

func _card(c: Dictionary) -> Control:
	var id: String = c["id"]
	var rec := Game.is_recruited(id)
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 30)
	wrap.add_theme_constant_override("margin_right", 30)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(660, 176)
	btn.focus_mode = Control.FOCUS_NONE
	var col: Color = c["color"]
	btn.add_theme_stylebox_override("normal", UI.panel(Color(1, 0.985, 0.95, 0.9 if rec else 0.72), col if rec else Color(0.7, 0.68, 0.78, 0.8), 28, 3 if rec else 2))
	btn.add_theme_stylebox_override("hover", UI.panel(Color(1, 1, 0.98, 0.97), col.lightened(0.2), 28, 3))
	btn.add_theme_stylebox_override("pressed", UI.panel(Color(0.95, 0.93, 0.96, 1), col, 28, 3))
	btn.pressed.connect(func(): main.open_detail(id))
	wrap.add_child(btn)
	# 头像
	var frame := Panel.new()
	frame.position = Vector2(16, 16)
	frame.size = Vector2(144, 144)
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = col.lightened(0.55)
	fsb.set_corner_radius_all(24)
	fsb.set_border_width_all(3)
	fsb.border_color = col
	frame.add_theme_stylebox_override("panel", fsb)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := UI.thumb(id, Vector2(144, 144))
	if not rec:
		th.modulate = Color(0.12, 0.1, 0.22, 0.85)
	frame.add_child(th)
	btn.add_child(frame)
	var nm := UI.lbl("%s" % c["title"], 34, UI.INK, true)
	nm.position = Vector2(176, 12)
	btn.add_child(nm)
	var en := UI.lbl(c["name"], 22, col.darkened(0.2), true)
	en.position = Vector2(176, 56)
	btn.add_child(en)
	var tr := UI.lbl(c["traits"], 22, UI.INK_SOFT)
	tr.position = Vector2(176, 88)
	btn.add_child(tr)
	if rec:
		var bl := Game.bond_lv(id)
		var pr := Data.bond_progress(Game.bond_xp(id))
		var hl := UI.lbl("♥ Lv.%d %s" % [bl, Data.BOND_NAMES[bl - 1]], 22, UI.ROSE, true)
		hl.position = Vector2(176, 122)
		btn.add_child(hl)
		var pb := UI.bar(14, UI.ROSE)
		pb.position = Vector2(340, 132)
		pb.size = Vector2(190, 14)
		pb.max_value = pr[1]
		pb.value = pr[0]
		btn.add_child(pb)
		var lv := UI.lbl("修行 Lv.%d" % Game.lv(id), 22, UI.JADE_DEEP, true, HORIZONTAL_ALIGNMENT_RIGHT)
		lv.position = Vector2(500, 12)
		lv.size = Vector2(140, 30)
		btn.add_child(lv)
		if Game.s["main"] == id:
			var ch := UI.chip("同行", UI.GOLD, Color.WHITE, 22)
			ch.position = Vector2(548, 52)
			btn.add_child(ch)
		var newn := 0
		for sc in Game.char_scenes(id):
			if Game.scene_status(sc["id"]) == "new":
				newn += 1
		if newn > 0:
			var nc := UI.chip("新回忆 %d" % newn, Color("#ee4f6f"), Color.WHITE, 20)
			nc.position = Vector2(520, 100)
			btn.add_child(nc)
	else:
		var cost := Game.recruit_cost()
		var ch2 := UI.chip("未结缘 · 灵石 %d" % cost, Color(0.45, 0.42, 0.7, 0.9), Color.WHITE, 22)
		ch2.position = Vector2(176, 122)
		btn.add_child(ch2)
	return wrap

func open_lineup() -> void:
	if is_instance_valid(lineup):
		lineup.queue_free()
	lineup = Control.new()
	lineup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lineup.mouse_filter = Control.MOUSE_FILTER_STOP
	var layer: Control = main.overlay
	layer.add_child(lineup)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/bg/dawn.jpg")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lineup.add_child(bg)
	var t := UI.brush_lbl("栖云居  全员合影", 66, UI.GOLD_DEEP)
	t.position = Vector2(0, 36)
	t.size = Vector2(720, 90)
	t.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
	t.add_theme_constant_override("outline_size", 14)
	lineup.add_child(t)
	var sub := UI.lbl("%d / 9 位伙伴已归来" % Game.recruited_ids().size(), 26, UI.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 126)
	sub.size = Vector2(720, 36)
	lineup.add_child(sub)
	# 三排站位：后排 3，中排 3，前排 3
	var order := ["chatgpt", "kimi", "qwen", "claude", "gemini", "seed", "grok", "llama", "deepseek"]
	var rows := [[0, 1, 2], [3, 4, 5], [6, 7, 8]]
	var ys := [610.0, 860.0, 1120.0]
	var hs := [440.0, 500.0, 560.0]
	var delay := 0.0
	for r in 3:
		for j in 3:
			var id: String = order[rows[r][j]]
			var cn := Chibi.new().setup(id, hs[r], false)
			var x := 130.0 + float(j) * 230.0 + (40.0 if r == 1 else 0.0) - (20.0 if r == 2 else 0.0)
			cn.position = Vector2(x + (r - 1) * 0.0, ys[r])
			if not Game.is_recruited(id):
				cn.set_dark(true)
			lineup.add_child(cn)
			cn.enter(0.0)
			cn.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_interval(delay)
			tw.tween_property(cn, "modulate:a", 1.0, 0.35)
			tw.tween_callback(cn.bounce)
			delay += 0.12
	var close := UI.btn("返回", "dark", 28, Vector2(180, 64))
	close.position = Vector2(270, 1196)
	close.pressed.connect(func(): lineup.queue_free())
	lineup.add_child(close)
