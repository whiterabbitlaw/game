class_name ChatEventLetter
extends Control
## 纪念日礼物/书信界面。正文可由模型生成，失败时用本地草稿。

signal accepted(events: Array)

var events: Array = []
var char_title := "她"
var body_text := ""


func setup(p_events: Array, title: String, text: String) -> void:
	events = p_events
	char_title = title
	body_text = text
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.07, 0.06, 0.12, 0.62)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(50, 180)
	panel.size = Vector2(620, 880)
	panel.add_theme_stylebox_override("panel", UI.panel(Color(0.99, 0.96, 0.9, 0.98), Color(0.75, 0.55, 0.28, 0.95), 32, 3))
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)
	var heads: PackedStringArray = []
	for e in events:
		heads.append(str(e.get("title", "纪念日")))
	root.add_child(UI.brush_lbl("一封信 · " + "、".join(heads), 40, UI.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var from := UI.lbl("来自%s" % char_title, 22, UI.INK_SOFT)
	root.add_child(from)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(560, 560)
	root.add_child(scroll)
	var body := UI.lbl(body_text, 28, UI.INK)
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.custom_minimum_size = Vector2(540, 0)
	scroll.add_child(body)
	var gift := UI.lbl("附上一份心意。点「收下」后，今年就不会再提同一件事。", 18, UI.INK_SOFT)
	gift.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	gift.custom_minimum_size = Vector2(560, 0)
	root.add_child(gift)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)
	var ok := UI.btn("收下", "jade", 28, Vector2(240, 64))
	ok.pressed.connect(func():
		accepted.emit(events)
		queue_free())
	row.add_child(ok)
