class_name ChatMemoryView
extends Control
## 记忆查看/编辑：角色事实 + 共享玩家档案，可删除。

signal closed

var memory: ChatMemory
var profile := ChatProfile.new()
var _list: VBoxContainer
var _add: LineEdit
var _panel: PanelContainer
var _editing_id := ""
var _editing_shared := false
var _editing_text := ""
var _editing_kind := "other"
var _sheet_lines: PackedStringArray = PackedStringArray()
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
	var hint := UI.lbl("钉选只给当前这位，不会自动告诉别人。告诉大家之后，其他角色得到的是派生副本；取消共享会收回副本，不会变成她们自己的私有记忆。她亲耳听到的单独留着。全都忘掉才会让所有角色都不再引用。对话原文不删除。", 18, UI.INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	hint.custom_minimum_size = Vector2(0, 0)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(hint)
	if memory and memory.summary().strip_edges() != "":
		root.add_child(UI.lbl("较早的原话", 24, UI.INK, true))
		var sl := UI.lbl(memory.summary(), 20, UI.INK_SOFT)
		sl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		sl.custom_minimum_size = Vector2(0, 0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(sl)
	if memory and memory.legacy_summary().strip_edges() != "":
		root.add_child(UI.lbl("旧摘要（未逐句核对，不参与回答）", 22, UI.INK, true))
		var legacy := UI.lbl(memory.legacy_summary(), 18, UI.INK_SOFT)
		legacy.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		legacy.custom_minimum_size = Vector2(0, 0)
		legacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(legacy)
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
	addb.set_meta("hit", "save")
	addb.pressed.connect(_on_add)
	row.add_child(addb)
	var clearb := UI.btn("清除对话", "ghost", 20, Vector2(140, 48))
	clearb.pressed.connect(func():
		if clearb.text != "确认清除对话":
			clearb.text = "确认清除对话"
			return
		if memory:
			memory.clear_messages()
		clearb.text = "清除对话"
		_rebuild())
	root.add_child(clearb)
	_rebuild()
	_fit()
	if is_inside_tree() and not get_viewport().size_changed.is_connected(_fit):
		get_viewport().size_changed.connect(_fit)


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_sheet_lines = PackedStringArray()
	if memory:
		memory.adopt_public(profile)
	_section("告诉大家的自设", profile.shared_facts(), "public")
	if memory:
		var active: Array = []
		var derived: Array = []
		var unverified: Array = []
		for f in memory.facts():
			if str(f.get("status", "")) == "superseded":
				continue
			if str(f.get("scope", "")) == "shared":
				continue
			if str(f.get("provenance", "")) == "shared":
				derived.append(f)
			elif str(f.get("status", "")) == "unverified":
				unverified.append(f)
			else:
				active.append(f)
		_section("来自大家（取消共享后不会留下）", derived, "derived")
		_section("只给她（亲耳听到或在这里写下）", active, "private")
		_section("未核对（不参与回答）", unverified, "unverified")
	_queue_hits()


func _section(title: String, facts: Array, mode: String) -> void:
	_list.add_child(UI.lbl(title, 24, UI.INK, true))
	if facts.is_empty():
		_list.add_child(UI.lbl("（还没有）", 20, UI.INK_SOFT))
		return
	for f in facts:
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 6)
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kind := str(f.get("kind", "other"))
		var labels := {"name": "称呼", "like": "喜好", "date": "日期", "promise": "约定"}
		var label := str(labels.get(kind, "其它"))
		var sources := {"user": "原话", "manual": "手动", "extract": "提取", "legacy": "旧档"}
		var source := str(sources.get(str(f.get("source", "")), str(f.get("source", "旧档"))))
		var pin := "已钉选" if bool(f.get("pinned", false)) else "未钉选"
		var scope := "派生" if mode == "derived" else ("大家" if mode == "public" else "只给她")
		var prov := {"spoken": "亲耳听到", "manual": "这里写下", "shared": "由共享而来", "legacy": "旧档未标来源"}
		var origin := str(prov.get(str(f.get("provenance", "")), "未标来源"))
		var body := UI.lbl("[%s/%s/%s/%s/%s] %s" % [label, source, pin, scope, origin, str(f.get("text", ""))], 22, UI.INK)
		_sheet_lines.append(title + " " + body.text)
		body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.custom_minimum_size = Vector2(0, 0)
		block.add_child(body)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var fact_id := str(f.get("id", ""))
		var fact_text := str(f.get("text", ""))
		var fact_kind := kind
		var is_public := mode == "public"
		var pinned := bool(f.get("pinned", false))
		if mode == "unverified" and memory:
			var keep := UI.btn("采用", "jade", 18, Vector2(72, 44))
			keep.pressed.connect(func():
				memory.update_fact(fact_id, fact_text)
				_rebuild())
			row.add_child(keep)
		if mode == "private" or mode == "public":
			var pin_b := UI.btn("取消钉选" if pinned else "钉选", "ghost", 18, Vector2(110, 44))
			pin_b.set_meta("hit", "pin")
			pin_b.pressed.connect(func():
				_toggle_pin(fact_id, fact_text, fact_kind, is_public, not pinned)
				_rebuild())
			row.add_child(pin_b)
			var share_b := UI.btn("仅她" if is_public else "告诉大家", "ghost", 18, Vector2(120, 44))
			share_b.set_meta("hit", "share")
			share_b.pressed.connect(func():
				_toggle_share(fact_id, fact_text, fact_kind, not is_public)
				_rebuild())
			row.add_child(share_b)
		if mode != "derived":
			var edit := UI.btn("改", "ghost", 18, Vector2(56, 44))
			edit.set_meta("hit", "edit")
			edit.pressed.connect(func():
				_editing_id = fact_id
				_editing_shared = is_public or mode == "derived"
				_editing_text = fact_text
				_editing_kind = fact_kind
				if _add:
					_add.text = fact_text
					_add.placeholder_text = "改完后点记下"
				if push_text.is_valid():
					push_text.call(fact_text))
			row.add_child(edit)
			var del := UI.btn("删除", "ghost", 18, Vector2(72, 44))
			del.set_meta("hit", "delete")
			del.pressed.connect(func():
				if del.text != "确认":
					del.text = "确认"
					return
				if is_public and memory:
					memory.retract_public(fact_text, fact_kind, profile)
				elif memory:
					memory.delete_fact(fact_id)
				_rebuild())
			row.add_child(del)
		if mode == "public" or mode == "derived":
			var forget := UI.btn("全都忘掉", "ghost", 18, Vector2(120, 44))
			forget.set_meta("hit", "forget")
			forget.pressed.connect(func():
				if forget.text != "确认全忘":
					forget.text = "确认全忘"
					return
				if memory:
					memory.forget_everywhere(fact_text, fact_kind, profile)
				_rebuild())
			row.add_child(forget)
		block.add_child(row)
		_list.add_child(block)


func _on_add() -> void:
	if _add == null or memory == null:
		return
	if pull_text.is_valid():
		_add.text = str(pull_text.call())
	var t := _add.text.strip_edges()
	if t == "":
		return
	_add.text = ""
	_add.placeholder_text = "手动补一条事实，例如：喜欢桂花糕"
	if push_text.is_valid():
		push_text.call("")
	if _editing_id != "":
		var local_id := _local_id(_editing_id, _editing_text, _editing_kind)
		if local_id == "":
			var created := memory.add_fact(t, _editing_kind, [])
			local_id = str(created.get("id", ""))
		if _editing_shared and local_id != "":
			memory.publish_edit(local_id, t, profile)
		elif local_id != "":
			memory.update_fact(local_id, t)
		_editing_id = ""
		_editing_shared = false
		_editing_text = ""
	else:
		memory.add_fact(t, "other", [])
	_rebuild()


func _toggle_pin(fact_id: String, fact_text: String, fact_kind: String, shared: bool, pinned: bool) -> void:
	if memory == null:
		return
	var local_id := _local_id(fact_id, fact_text, fact_kind)
	if local_id != "":
		memory.set_pinned(local_id, pinned, profile)
		return
	if shared:
		for f in profile.shared_facts():
			if str(f.get("text", "")) == fact_text and str(f.get("kind", "")) == fact_kind:
				f["pinned"] = pinned
				profile.mirror_fact(f)
				return


func _toggle_share(fact_id: String, fact_text: String, fact_kind: String, shared: bool) -> void:
	if memory == null:
		return
	var local_id := _local_id(fact_id, fact_text, fact_kind)
	if local_id == "":
		var created := memory.add_fact(fact_text, fact_kind, [])
		local_id = str(created.get("id", ""))
	if local_id == "":
		return
	memory.set_shared(local_id, shared, profile)


func _local_id(fact_id: String, fact_text: String, fact_kind: String) -> String:
	if memory == null:
		return ""
	for f in memory.facts():
		if str(f.get("status", "")) == "superseded":
			continue
		if str(f.get("id", "")) == fact_id:
			return fact_id
		if str(f.get("text", "")) == fact_text and str(f.get("kind", "")) == fact_kind:
			return str(f.get("id", ""))
	return ""


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
	_queue_hits()


var _hit_queued := false


func _queue_hits() -> void:
	if _hit_queued:
		return
	_hit_queued = true
	_publish_later()


func _publish_later() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_hit_queued = false
	_publish_web_hits()


func _publish_web_hits() -> void:
	if not OS.has_feature("web") or not is_inside_tree():
		return
	var hits := {}
	_collect_hits(self, hits)
	JavaScriptBridge.eval("window.qiyunjuViewport = {w:720,h:1280}; window.qiyunjuHits = Object.assign(window.qiyunjuHits || {}, %s); window.qiyunjuMemoryText = %s;" % [JSON.stringify(hits), JSON.stringify("\n".join(_sheet_lines))], true)


func _collect_hits(node: Node, hits: Dictionary) -> void:
	if node is Control and str(node.get_meta("hit", "")) != "":
		var c := node as Control
		var xf := c.get_global_transform_with_canvas()
		var origin := xf.origin
		var scale := xf.get_scale()
		var w := c.size.x * scale.x
		var h := c.size.y * scale.y
		if w > 2.0 and h > 2.0 and origin.y >= 0.0:
			hits[str(node.get_meta("hit"))] = {"x": origin.x, "y": origin.y, "w": w, "h": h}
	for child in node.get_children():
		_collect_hits(child, hits)
