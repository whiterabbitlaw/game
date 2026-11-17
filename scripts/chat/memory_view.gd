class_name ChatMemoryView
extends Control
## 记忆查看/编辑：角色事实 + 共享玩家档案，可删除。

signal closed

var memory: ChatMemory
var profile := ChatProfile.new()
var _list: VBoxContainer
var _add: LineEdit
var _panel: PanelContainer
var pull_text: Callable
var push_text: Callable


func composer() -> LineEdit:
	return _add


func setup(mem: ChatMemory) -> void:
	memory = mem
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.07, 0.14, 0.55)
	add_child(dim)
	var panel := PanelContainer.new()
	_panel = panel
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", UI.panel(Color(1, 0.985, 0.95, 0.98), UI.GOLD, 28, 3))
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := UI.brush_lbl("记忆", 36, UI.INK, HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size = Vector2(0, 0)
	head.add_child(title)
	var closeb := UI.btn("关闭", "dark", 22, Vector2(96, 48))
	closeb.pressed.connect(func():
		closed.emit()
		queue_free())
	head.add_child(closeb)
	var hint := UI.lbl("这些只存在这台设备上。共享档案对每位伙伴可见；下面是与眼前这位有关的记忆。摘要不可逐条删除，但清掉事实不影响对话记录。", 18, UI.INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	hint.custom_minimum_size = Vector2(0, 0)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(hint)
	if memory and memory.summary().strip_edges() != "":
		root.add_child(UI.lbl("滚动摘要", 24, UI.INK, true))
		var sl := UI.lbl(memory.summary(), 20, UI.INK_SOFT)
		sl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		sl.custom_minimum_size = Vector2(0, 0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(sl)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 120)
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	_add = LineEdit.new()
	_add.placeholder_text = "手动补一条事实，例如：喜欢桂花糕"
	_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add.custom_minimum_size = Vector2(0, 52)
	_add.add_theme_font_size_override("font_size", 22)
	row.add_child(_add)
	var addb := UI.btn("记下", "jade", 24, Vector2(120, 52))
	addb.pressed.connect(_on_add)
	row.add_child(addb)
	_rebuild()
	_fit()
	if is_inside_tree() and not get_viewport().size_changed.is_connected(_fit):
		get_viewport().size_changed.connect(_fit)


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_section("共享档案", profile.shared_facts(), true)
	if memory:
		_section("与她相关", memory.facts(), false)


func _section(title: String, facts: Array, shared: bool) -> void:
	_list.add_child(UI.lbl(title, 24, UI.INK, true))
	if facts.is_empty():
		_list.add_child(UI.lbl("（还没有）", 20, UI.INK_SOFT))
		return
	for f in facts:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var kind := str(f.get("kind", "other"))
		var labels := {"name": "称呼", "like": "喜好", "date": "日期", "promise": "约定"}
		var label := str(labels.get(kind, "其它"))
		var body := UI.lbl("[%s] %s" % [label, str(f.get("text", ""))], 22, UI.INK)
		body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.custom_minimum_size = Vector2(0, 0)
		row.add_child(body)
		var del := UI.btn("删除", "ghost", 20, Vector2(90, 44))
		var fact_id := str(f.get("id", ""))
		var is_shared := shared
		del.pressed.connect(func():
			if is_shared:
				profile.delete_shared_fact(fact_id)
			elif memory:
				memory.delete_fact(fact_id)
			_rebuild())
		row.add_child(del)
		_list.add_child(row)


func _on_add() -> void:
	if _add == null or memory == null:
		return
	if pull_text.is_valid():
		_add.text = str(pull_text.call())
	var t := _add.text.strip_edges()
	if t == "":
		return
	_add.text = ""
	if push_text.is_valid():
		push_text.call("")
	memory.add_fact(t, "other", [])
	_rebuild()


func _fit() -> void:
	if _panel == null or not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	if vp.x < 8.0:
		return
	var r := ChatLayout.fit_rect(vp, 16.0, 0.0)
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = r.position.x
	_panel.offset_top = r.position.y
	_panel.offset_right = r.end.x
	_panel.offset_bottom = r.end.y
