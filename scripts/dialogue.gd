class_name Dialogue
extends Control
## 视觉小说式对话：立绘、打字机文字、情绪气泡、分支选项、好感提示

signal finished(info: Dictionary)

const EMOTES := {"!": "！", "?": "？", "♥": "♥", "…": "…", "♪": "♪", "★": "★", "汗": "汗"}
const EMOTE_COL := {"！": Color("#f26b6b"), "？": Color("#6b8ff2"), "♥": Color("#ee6f8f"), "…": Color("#8a86a8"), "♪": Color("#5fb5a5"), "★": Color("#e8b43a"), "汗": Color("#6bb4e0")}

var scene: Dictionary = {}
var entries: Array = []
var idx := 0
var replay := false
var char_id := ""
var result: Dictionary = {}
var _busy := false          # 选项/选择中
var _typing := false
var _skip := false
var _full_text := ""
var _speaker := ""
var _type_id := 0

var bg: TextureRect
var dim: ColorRect
var stage: Control
var portrait: Chibi = null
var box: PanelContainer
var name_chip: PanelContainer
var name_lbl: Label
var text_lbl: Label
var arrow: Label
var choice_box: VBoxContainer
var cap_title: Label
var cap_place: Label
var emote_lbl: Label
var skip_btn: Button
var pick_layer: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	bg = TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	dim = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.1, 0.08, 0.2, 0.28)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	# 场景标题（淡入淡出）
	cap_title = UI.brush_lbl("", 70, Color.WHITE)
	cap_title.position = Vector2(0, 150)
	cap_title.size = Vector2(720, 90)
	cap_title.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.3, 0.7))
	cap_title.add_theme_constant_override("shadow_offset_x", 2)
	cap_title.add_theme_constant_override("shadow_offset_y", 3)
	cap_title.modulate.a = 0.0
	add_child(cap_title)
	cap_place = UI.lbl("", 28, Color(1, 1, 1, 0.95), false, HORIZONTAL_ALIGNMENT_CENTER)
	cap_place.position = Vector2(0, 245)
	cap_place.size = Vector2(720, 40)
	cap_place.modulate.a = 0.0
	add_child(cap_place)

	emote_lbl = UI.lbl("", 60, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	emote_lbl.size = Vector2(110, 90)
	emote_lbl.pivot_offset = Vector2(55, 45)
	emote_lbl.modulate.a = 0.0
	emote_lbl.add_theme_color_override("font_outline_color", Color.WHITE)
	emote_lbl.add_theme_constant_override("outline_size", 10)
	add_child(emote_lbl)

	# 对话框
	box = PanelContainer.new()
	box.position = Vector2(26, 900)
	box.size = Vector2(668, 300)
	box.add_theme_stylebox_override("panel", UI.panel(Color(1.0, 0.985, 0.95, 0.94), Color(0.85, 0.7, 0.4, 0.95), 30, 3))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	text_lbl = UI.lbl("", 32, UI.INK)
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text_lbl.custom_minimum_size = Vector2(620, 180)
	text_lbl.add_theme_constant_override("line_spacing", 8)
	box.add_child(text_lbl)
	name_chip = PanelContainer.new()
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = UI.GOLD
	nsb.set_corner_radius_all(18)
	nsb.content_margin_left = 24
	nsb.content_margin_right = 24
	nsb.content_margin_top = 6
	nsb.content_margin_bottom = 6
	name_chip.add_theme_stylebox_override("panel", nsb)
	name_chip.position = Vector2(60, 862)
	name_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl = UI.lbl("", 30, Color.WHITE, true)
	name_chip.add_child(name_lbl)
	add_child(name_chip)
	arrow = UI.lbl("▼", 26, UI.GOLD_DEEP, true)
	arrow.position = Vector2(640, 1150)
	add_child(arrow)

	choice_box = VBoxContainer.new()
	choice_box.position = Vector2(60, 440)
	choice_box.size = Vector2(600, 400)
	choice_box.alignment = BoxContainer.ALIGNMENT_END
	choice_box.add_theme_constant_override("separation", 16)
	add_child(choice_box)

	skip_btn = UI.btn("快进", "dark", 22, Vector2(130, 52))
	skip_btn.position = Vector2(560, 28)
	skip_btn.pressed.connect(func(): _skip = true; _advance_if_possible())
	add_child(skip_btn)

	pick_layer = Control.new()
	pick_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pick_layer.visible = false
	add_child(pick_layer)

	Game.bond_gained.connect(_on_bond)

func play(sc: Dictionary, is_replay: bool = false) -> void:
	scene = sc
	entries = sc["lines"]
	replay = is_replay
	char_id = sc.get("char", "")
	idx = 0
	var tone: String = sc.get("tone", "dawn")
	bg.texture = load("res://assets/bg/%s.jpg" % Data.TONE_BG.get(tone, "dawn"))
	if not sc.get("dyn", false):
		cap_title.text = sc.get("title", "")
		cap_place.text = sc.get("place", "")
		var tw := create_tween()
		tw.tween_property(cap_title, "modulate:a", 1.0, 0.7)
		tw.parallel().tween_property(cap_place, "modulate:a", 1.0, 0.7)
		tw.tween_interval(1.8)
		tw.tween_property(cap_title, "modulate:a", 0.0, 0.9)
		tw.parallel().tween_property(cap_place, "modulate:a", 0.0, 0.9)
	if char_id != "":
		_show_portrait(char_id, false)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)
	_next()

func _show_portrait(id: String, animate: bool = true) -> void:
	if portrait and portrait.cid == id:
		return
	if portrait:
		var old := portrait
		var tw := create_tween()
		tw.tween_property(old, "modulate:a", 0.0, 0.15)
		tw.tween_callback(old.queue_free)
	portrait = Chibi.new().setup(id, 880, false)
	portrait.position = Vector2(360, 1080)
	stage.add_child(portrait)
	portrait.enter(40.0 if animate else 0.0)

func _dim_portrait(on: bool) -> void:
	if portrait:
		var c := Color(0.62, 0.62, 0.7, 1.0) if on else Color.WHITE
		create_tween().tween_property(portrait.spr, "modulate", c, 0.15)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_advance_if_possible()
	elif ev is InputEventScreenTouch and ev.pressed:
		_advance_if_possible()

func _advance_if_possible() -> void:
	if _busy or pick_layer.visible:
		return
	if _typing:
		_finish_typing()
		return
	_next()

func _next() -> void:
	if idx >= entries.size():
		_end()
		return
	var e = entries[idx]
	idx += 1
	if typeof(e) == TYPE_DICTIONARY:
		if e.has("c"):
			_show_choices(e["c"])
		elif e.has("pick"):
			_show_pick()
		return
	_say(String(e))

func _say(line: String) -> void:
	var parts := line.split("|", true, 1)
	var head := parts[0]
	var txt := parts[1] if parts.size() > 1 else ""
	var emote := ""
	var who := head
	if head.contains(":"):
		var hp := head.split(":", true, 1)
		who = hp[0]
		emote = hp[1]
	_speaker = who
	arrow.visible = false
	if who == "n":
		name_chip.visible = false
		text_lbl.add_theme_color_override("font_color", Color("#5b5778"))
		_dim_portrait(true)
	elif who == "p":
		name_chip.visible = true
		name_lbl.text = "你"
		name_chip.get_theme_stylebox("panel").bg_color = UI.JADE
		text_lbl.add_theme_color_override("font_color", UI.INK)
		_dim_portrait(true)
	else:
		var d := Data.char_def(who)
		name_chip.visible = true
		name_lbl.text = "%s · %s" % [d["name"], d["title"]]
		name_chip.get_theme_stylebox("panel").bg_color = d["color"].darkened(0.1)
		text_lbl.add_theme_color_override("font_color", UI.INK)
		_show_portrait(who)
		_dim_portrait(false)
		if emote != "":
			_emote(emote)
		if emote == "!" or emote == "★" or emote == "♪":
			portrait.bounce()
		elif emote == "♥" or emote == "汗":
			portrait.shy()
	_full_text = txt
	text_lbl.text = txt
	text_lbl.visible_characters = 0
	_typing = true
	_type_loop()

func _type_loop() -> void:
	var n := _full_text.length()
	var cps := 60.0 if _skip else 38.0
	var shown := 0
	_type_id += 1
	var my := _type_id
	while shown < n and _typing and my == _type_id:
		shown += 1
		text_lbl.visible_characters = shown
		await get_tree().create_timer(1.0 / cps).timeout
		if not is_inside_tree():
			return
	if my == _type_id:
		_finish_typing()

func _finish_typing() -> void:
	if not _typing:
		return
	_typing = false
	text_lbl.visible_characters = -1
	arrow.visible = true
	var tw := create_tween().set_loops(3)
	tw.tween_property(arrow, "position:y", 1160.0, 0.3)
	tw.tween_property(arrow, "position:y", 1150.0, 0.3)
	if _skip:
		await get_tree().create_timer(0.12).timeout
		if is_inside_tree() and not _busy and not pick_layer.visible:
			_next()

func _emote(e: String) -> void:
	var sym: String = EMOTES.get(e, "")
	if sym == "":
		return
	emote_lbl.text = sym
	emote_lbl.add_theme_color_override("font_color", EMOTE_COL.get(sym, Color.WHITE))
	emote_lbl.position = Vector2(470, 190)
	emote_lbl.scale = Vector2(0.2, 0.2)
	emote_lbl.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(emote_lbl, "scale", Vector2(1.2, 1.2), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(emote_lbl, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(1.0)
	tw.tween_property(emote_lbl, "modulate:a", 0.0, 0.4)

func _show_choices(opts: Array) -> void:
	_busy = true
	_skip = false
	arrow.visible = false
	for o in opts:
		var b := UI.btn(String(o["t"]), "paper", 28, Vector2(600, 84))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		choice_box.add_child(b)
		b.pressed.connect(func(): _choose(o))
		b.modulate.a = 0.0
		create_tween().tween_property(b, "modulate:a", 1.0, 0.25)

func _choose(o: Dictionary) -> void:
	for c in choice_box.get_children():
		c.queue_free()
	_busy = false
	var b := int(o.get("b", 0))
	if b > 0 and not replay and char_id != "":
		Game.add_bond(char_id, float(b))
	# 插入回复
	var rep: Array = o.get("r", [])
	var tail := entries.slice(idx)
	var head := entries.slice(0, idx)
	entries = head + rep + tail
	_next()

func _on_bond(id: String, amount: float) -> void:
	var l := UI.lbl("♥ %s 好感 +%d" % [Data.char_def(id)["name"], int(round(amount))], 30, Color("#ee6f8f"), true, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", 10)
	l.position = Vector2(110, 790)
	l.size = Vector2(500, 50)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 720.0, 1.4)
	tw.tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)

func _show_pick() -> void:
	pick_layer.visible = true
	for c in pick_layer.get_children():
		c.queue_free()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.08, 0.06, 0.18, 0.55)
	pick_layer.add_child(shade)
	var t := UI.brush_lbl("第一盏灯，亮了——是谁？", 52, Color.WHITE)
	t.position = Vector2(0, 90)
	t.size = Vector2(720, 70)
	pick_layer.add_child(t)
	var sub := UI.lbl("选择与你结缘的第一位伙伴（其余八位之后可逐一结缘）", 24, Color(1, 1, 1, 0.9), false, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 165)
	sub.size = Vector2(720, 36)
	pick_layer.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(30, 230)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	pick_layer.add_child(grid)
	for c in Data.CHARS:
		var id: String = c["id"]
		var b := Button.new()
		b.custom_minimum_size = Vector2(204, 300)
		b.focus_mode = Control.FOCUS_NONE
		var sb := UI.panel(Color(1, 0.985, 0.95, 0.93), c["color"], 24, 3)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", UI.panel(Color(1, 1, 1, 1), c["color"].lightened(0.2), 24, 4))
		b.add_theme_stylebox_override("pressed", UI.panel(Color(0.93, 0.9, 0.95, 1), c["color"], 24, 4))
		var th := UI.thumb(id, Vector2(180, 180))
		th.position = Vector2(12, 12)
		b.add_child(th)
		var n := UI.lbl(c["title"], 28, UI.INK, true, HORIZONTAL_ALIGNMENT_CENTER)
		n.position = Vector2(0, 200)
		n.size = Vector2(204, 40)
		b.add_child(n)
		var tr := UI.lbl(c["name"], 22, UI.INK_SOFT, false, HORIZONTAL_ALIGNMENT_CENTER)
		tr.position = Vector2(0, 238)
		tr.size = Vector2(204, 32)
		b.add_child(tr)
		b.pressed.connect(func(): _picked(id))
		grid.add_child(b)

func _picked(id: String) -> void:
	pick_layer.visible = false
	Game.recruit(id, true)
	Game.set_main(id)
	result["picked"] = id
	char_id = id
	_show_portrait(id)
	_dim_portrait(false)
	var lines: Array = [
		"n|灯芯亮起，一道熟悉又陌生的影子，缓缓在光里站稳了。",
	]
	entries = entries.slice(0, idx) + lines + entries.slice(idx)
	_next()

func _end() -> void:
	_busy = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		finished.emit(result)
		queue_free())
