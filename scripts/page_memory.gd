class_name PageMemory
extends Control
## 回忆页：剧情章节（随羁绊与境界解锁）+ 伙伴来信

var main: Control
var mode := "story"
var list: VBoxContainer
var scroll: ScrollContainer
var b_story: Button
var b_letter: Button

func build() -> void:
	var t := UI.brush_lbl("回忆  信笺", 54, UI.GOLD_DEEP, HORIZONTAL_ALIGNMENT_LEFT)
	t.position = Vector2(30, 6)
	t.size = Vector2(420, 70)
	t.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	t.add_theme_constant_override("outline_size", 10)
	add_child(t)
	b_story = UI.btn("往事", "gold", 24, Vector2(110, 52))
	b_story.position = Vector2(468, 16)
	b_story.pressed.connect(func(): _set_mode("story"))
	add_child(b_story)
	b_letter = UI.btn("信笺", "ghost", 24, Vector2(110, 52))
	b_letter.position = Vector2(588, 16)
	b_letter.pressed.connect(func(): _set_mode("letters"))
	add_child(b_letter)
	scroll = ScrollContainer.new()
	scroll.position = Vector2(0, 84)
	scroll.size = Vector2(720, 976)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.custom_minimum_size = Vector2(720, 0)
	scroll.add_child(list)

func _set_mode(m: String) -> void:
	mode = m
	_rebuild()

func refresh() -> void:
	_rebuild()

func on_changed() -> void:
	if visible:
		_rebuild()

func focus_char(id: String) -> void:
	mode = "story"
	_rebuild()
	await get_tree().process_frame
	await get_tree().process_frame
	var idx := 0
	for c in Data.CHARS:
		if c["id"] == id:
			break
		idx += 1
	scroll.scroll_vertical = 1 + idx * 3 * 134

var _sig := ""
func _rebuild() -> void:
	var sig := mode
	for sc in Game.scenes:
		sig += Game.scene_status(sc["id"]).substr(0, 1)
	sig += str(Game.s["letters"].size()) + str(Game.s["chars"].keys().size())
	if sig == _sig:
		return
	_sig = sig
	for c in list.get_children():
		c.queue_free()
	_style_tabs()
	if mode == "story":
		_story_list()
	else:
		_letter_list()

func _style_tabs() -> void:
	for pair in [[b_story, mode == "story"], [b_letter, mode == "letters"]]:
		var b: Button = pair[0]
		var active: bool = pair[1]
		var c := UI.GOLD if active else Color(1, 1, 1, 0.6)
		var fc := Color.WHITE if active else UI.INK
		for s in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(s, UI._btn_style(c, 26, Color("#f6d98a")))
		for s in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(s, fc)

func _story_list() -> void:
	list.add_child(_gap(4))
	list.add_child(_row(Game.scene_by_id["prologue"], "prologue"))
	for c in Data.CHARS:
		var id: String = c["id"]
		var hd := UI.lbl("  %s · %s" % [c["name"], c["title"]], 26, c["color"].darkened(0.3), true)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 36)
		m.add_child(hd)
		list.add_child(m)
		for sc in Game.char_scenes(id):
			list.add_child(_row(sc, id))
	list.add_child(_gap(24))

func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _row(sc: Dictionary, id: String) -> Control:
	var st := Game.scene_status(sc["id"])
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 30)
	wrap.add_theme_constant_override("margin_right", 30)
	var b := Button.new()
	b.custom_minimum_size = Vector2(660, 118)
	b.focus_mode = Control.FOCUS_NONE
	var col: Color = Data.char_def(id).get("color", UI.GOLD)
	var locked := (st == "locked")
	b.add_theme_stylebox_override("normal", UI.panel(Color(1, 0.985, 0.95, 0.6 if locked else 0.9), col if not locked else Color(0.7, 0.68, 0.78, 0.7), 24, 2))
	b.add_theme_stylebox_override("hover", UI.panel(Color(1, 1, 0.98, 0.97), col.lightened(0.2), 24, 3))
	b.add_theme_stylebox_override("pressed", UI.panel(Color(0.95, 0.93, 0.96, 1), col, 24, 3))
	var sid: String = sc["id"]
	b.pressed.connect(func(): _tap(sid, st))
	wrap.add_child(b)
	var left: Control
	if id == "prologue":
		left = UI.lbl("序", 54, UI.GOLD_DEEP, true, HORIZONTAL_ALIGNMENT_CENTER)
		left.size = Vector2(90, 90)
		left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		left = UI.thumb(id, Vector2(90, 90))
		if locked:
			left.modulate = Color(0.2, 0.18, 0.3, 0.6)
	left.position = Vector2(14, 14)
	b.add_child(left)
	var title: String = "？？？" if (locked and sc["n"] > 1) else sc["title"]
	var t := UI.lbl("%s%s" % [("第%s章 " % ["一", "二", "三"][int(sc["n"]) - 1]) if sc["n"] > 0 else "", title], 28, UI.INK_SOFT if locked else UI.INK, true)
	t.position = Vector2(120, 14)
	b.add_child(t)
	var sub := ""
	match st:
		"locked":
			sub = Game.scene_req_text(sid) if sc["char"] != "" and Game.is_recruited(sc["char"]) else "结缘后开启"
		"new":
			sub = "点击开启 · 首次回忆有奖励"
		"seen":
			sub = "已回味 · 点击重温"
	var s := UI.lbl(sub, 22, UI.INK_SOFT)
	s.position = Vector2(120, 62)
	b.add_child(s)
	if st == "new":
		var ch := UI.chip("新", Color("#ee4f6f"), Color.WHITE, 22)
		ch.position = Vector2(590, 14)
		b.add_child(ch)
	elif st == "seen":
		var ch2 := UI.chip("✓", UI.JADE, Color.WHITE, 22)
		ch2.position = Vector2(594, 14)
		b.add_child(ch2)
	return wrap

func _tap(sid: String, st: String) -> void:
	if st == "locked":
		var sc: Dictionary = Game.scene_by_id[sid]
		if sc["char"] != "" and not Game.is_recruited(sc["char"]):
			main.show_toast("需要先与她结缘")
		else:
			main.show_toast(Game.scene_req_text(sid))
		return
	main.play_story(sid)

func _letter_list() -> void:
	list.add_child(_gap(4))
	var letters: Array = Game.s["letters"]
	if letters.is_empty():
		var l := UI.lbl("离开一阵子再回来，伙伴们会给你留信。", 26, UI.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(720, 120)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		list.add_child(l)
		return
	for le in letters:
		var who := Data.char_def(le["who"])
		var wrap := MarginContainer.new()
		wrap.add_theme_constant_override("margin_left", 30)
		wrap.add_theme_constant_override("margin_right", 30)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.panel(Color("#fff3d9"), who["color"], 24, 2))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		pc.add_child(h)
		h.add_child(UI.thumb(le["who"], Vector2(96, 96)))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		h.add_child(v)
		v.add_child(UI.lbl("%s 的来信 · %s" % [who["name"], le["time"]], 24, who["color"].darkened(0.3), true))
		var t := UI.lbl(le["text"], 23, UI.INK)
		t.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		t.custom_minimum_size = Vector2(480, 0)
		v.add_child(t)
		wrap.add_child(pc)
		list.add_child(wrap)
	list.add_child(_gap(24))
