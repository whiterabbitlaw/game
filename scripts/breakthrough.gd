class_name BreakthroughFx
extends Control
## 突破演出：聚气 → 光柱/光环 → 闪白 → 结果。使用 shader（放射光、光柱、闪白）+ 粒子 + Tween

signal closed

const FAIL_LINES := {
	"chatgpt": "「没关系的。失败也是一页记录，我替你好好存着。下一页，会更好。」",
	"claude": "「别责怪自己。你已经很努力了，我一直在这儿。我们慢慢来，好吗？」",
	"grok": "「哼，不过是一次小失误！本公主陪你再来——不许气馁，听见没有！」",
	"gemini": "「喵……没事没事！下一次一定成功！来，我给你一颗星星糖。」",
	"kimi": "「气息乱了一点。深呼吸，慢慢调匀。……我吹一段曲子给你听吧。」",
	"qwen": "「胜败乃常事。来，先饮一盏茶，静一静，再来不迟。」",
	"seed": "「不要皱眉嘛！失败的颜色也很好看——是下一次成功的底色哦！」",
	"llama": "「……没关系。先歇一歇，睡一觉……醒来，就又有力气了。」",
	"deepseek": "「主人，请不要灰心。我已备好热茶与点心，请先休息一下。」",
}

var res: Dictionary = {}
var content: Control
var dark: ColorRect
var rays: ColorRect
var pillar: ColorRect
var flash_rect: ColorRect
var char_node: Chibi
var conv: Sparks
var burst: Sparks
var rings: Array[Sprite2D] = []
var title_lbl: Label
var sub_lbl: Label
var speech: PanelContainer
var tap_hint: Label
var _can_close := false
var _spin := 0.0

func start(r: Dictionary, main_id: String) -> void:
	res = r
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var ok: bool = r["ok"]
	var accent := Color("#ffd86b") if ok else Color("#9a8cff")
	content = Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	dark = ColorRect.new()
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.color = Color(0.04, 0.03, 0.12, 0.0)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(dark)

	var rmat := ShaderMaterial.new()
	rmat.shader = load("res://shaders/rays.gdshader")
	rmat.set_shader_parameter("color", accent)
	rmat.set_shader_parameter("intensity", 0.0)
	rays = ColorRect.new()
	rays.size = Vector2(1500, 1500)
	rays.position = Vector2(360 - 750, 590 - 750)
	rays.material = rmat
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(rays)

	var pmat := ShaderMaterial.new()
	pmat.shader = load("res://shaders/pillar.gdshader")
	pmat.set_shader_parameter("color", accent.lightened(0.4))
	pmat.set_shader_parameter("intensity", 0.0)
	pillar = ColorRect.new()
	pillar.size = Vector2(520, 1280)
	pillar.position = Vector2(100, 0)
	pillar.material = pmat
	pillar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(pillar)

	for i in 3:
		var rg := Sprite2D.new()
		rg.texture = load("res://assets/fx/ring.png")
		rg.position = Vector2(360, 700)
		rg.scale = Vector2.ZERO
		rg.modulate = Color(accent.r, accent.g, accent.b, 0.0)
		content.add_child(rg)
		rings.append(rg)

	char_node = Chibi.new().setup(main_id, 560, true)
	char_node.position = Vector2(360, 900)
	content.add_child(char_node)
	char_node.set_mode("meditate")

	conv = Sparks.new()
	conv.kind = "converge"
	conv.radius = 430.0
	conv.rate = 60.0
	conv.life_range = Vector2(1.1, 1.6)
	conv.size_range = Vector2(22.0, 48.0)
	conv.tint = accent.lightened(0.3)
	conv.position = Vector2(360, 640)
	content.add_child(conv)

	burst = Sparks.new()
	burst.kind = "burst"
	burst.life_range = Vector2(1.2, 2.0)
	burst.size_range = Vector2(20.0, 54.0)
	burst.tint = accent.lightened(0.45)
	burst.position = Vector2(360, 640)
	content.add_child(burst)

	var fmat := ShaderMaterial.new()
	fmat.shader = load("res://shaders/flash.gdshader")
	fmat.set_shader_parameter("amount", 0.0)
	fmat.set_shader_parameter("tint", Color(1, 0.97, 0.88) if ok else Color(0.75, 0.7, 1.0))
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.material = fmat
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_rect)

	title_lbl = UI.brush_lbl("突破成功" if ok else "突破失败", 120, accent)
	title_lbl.position = Vector2(0, 150)
	title_lbl.size = Vector2(720, 150)
	title_lbl.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.35, 0.95))
	title_lbl.add_theme_constant_override("outline_size", 16)
	title_lbl.pivot_offset = Vector2(360, 75)
	title_lbl.modulate.a = 0.0
	add_child(title_lbl)
	var to_name := Data.step_name(int(res["from"]) + 1) if ok else Data.step_name(int(res["from"]))
	var sub := "%s  →  %s" % [Data.step_name(int(res["from"])), to_name] if ok else "心魔扰神，损失 %s 修为\n下次成功率 +6%%" % Data.fmt(float(res.get("loss", 0)))
	if ok and res.get("major", false):
		sub = "踏入「%s」！\n%s" % [Data.realm_name(int(res["from"]) + 1), sub]
	sub_lbl = UI.lbl(sub, 34, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	sub_lbl.position = Vector2(0, 320)
	sub_lbl.size = Vector2(720, 110)
	sub_lbl.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.35, 0.9))
	sub_lbl.add_theme_constant_override("outline_size", 10)
	sub_lbl.modulate.a = 0.0
	add_child(sub_lbl)

	# 伙伴的话
	var who := Data.char_def(main_id)
	var line: String = Game.pools.get(main_id, {}).get("bt", "") if ok else FAIL_LINES.get(main_id, "")
	speech = PanelContainer.new()
	speech.position = Vector2(40, 980)
	speech.size = Vector2(640, 180)
	speech.add_theme_stylebox_override("panel", UI.panel(Color(1, 0.985, 0.95, 0.95), who["color"], 28, 3))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	speech.add_child(vb)
	vb.add_child(UI.lbl("%s · %s" % [who["name"], who["title"]], 26, who["color"].darkened(0.25), true))
	var t := UI.lbl(line, 28, UI.INK)
	t.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	t.custom_minimum_size = Vector2(600, 0)
	vb.add_child(t)
	speech.modulate.a = 0.0
	add_child(speech)
	tap_hint = UI.lbl("轻触屏幕继续", 24, Color(1, 1, 1, 0.85), false, HORIZONTAL_ALIGNMENT_CENTER)
	tap_hint.position = Vector2(0, 1176)
	tap_hint.size = Vector2(720, 36)
	tap_hint.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.3, 0.9))
	tap_hint.add_theme_constant_override("outline_size", 8)
	tap_hint.modulate.a = 0.0
	add_child(tap_hint)
	_run(ok)

func _run(ok: bool) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(dark, "color:a", 0.78, 0.6)
	tw.tween_method(func(v): _set_spin(v), 0.0, 40.0, 6.0)
	conv.emitting = true
	var rm: ShaderMaterial = rays.material
	var pm: ShaderMaterial = pillar.material
	var charge := 1.8 if ok else 1.3
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_method(func(v): rm.set_shader_parameter("intensity", v), 0.0, 0.7, charge)
	tw2.tween_method(func(v): pm.set_shader_parameter("intensity", v), 0.0, 0.6, charge)
	for i in rings.size():
		_ring_pulse(rings[i], float(i) * 0.5, charge)
	await get_tree().create_timer(charge).timeout
	if not is_inside_tree():
		return
	# 爆发
	conv.emitting = false
	burst.burst(110)
	char_node.flash(1.0)
	if ok:
		char_node.bounce()
	else:
		char_node.shy()
	var fm: ShaderMaterial = flash_rect.material
	var tf := create_tween()
	tf.tween_method(func(v): fm.set_shader_parameter("amount", v), 0.0, 1.0 if ok else 0.55, 0.16)
	tf.tween_method(func(v): fm.set_shader_parameter("amount", v), 1.0 if ok else 0.55, 0.0, 1.0)
	var tb := create_tween().set_parallel(true)
	tb.tween_method(func(v): rm.set_shader_parameter("intensity", v), 1.4 if ok else 0.9, 0.55 if ok else 0.1, 1.6)
	tb.tween_method(func(v): pm.set_shader_parameter("intensity", v), 1.3 if ok else 0.7, 0.35 if ok else 0.0, 1.6)
	_shake(0.5 if ok else 0.3)
	var ring2 := create_tween().set_parallel(true)
	for r in rings:
		r.scale = Vector2(0.2, 0.2)
		r.modulate.a = 0.9
		ring2.tween_property(r, "scale", Vector2(5.5, 5.5), 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ring2.tween_property(r, "modulate:a", 0.0, 1.0)
	title_lbl.scale = Vector2(2.2, 2.2)
	var tt := create_tween().set_parallel(true)
	tt.tween_property(title_lbl, "modulate:a", 1.0, 0.3)
	tt.tween_property(title_lbl, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(sub_lbl, "modulate:a", 1.0, 0.5).set_delay(0.4)
	tt.tween_property(speech, "modulate:a", 1.0, 0.5).set_delay(0.9)
	tt.tween_property(tap_hint, "modulate:a", 1.0, 0.5).set_delay(1.5)
	await get_tree().create_timer(1.4).timeout
	_can_close = true

func _set_spin(v: float) -> void:
	if rays and rays.material:
		(rays.material as ShaderMaterial).set_shader_parameter("spin", v * 0.12)

func _ring_pulse(r: Sprite2D, delay: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		r.scale = Vector2(4.5, 4.5)
		r.modulate.a = 0.0)
	tw.set_parallel(true)
	tw.tween_property(r, "scale", Vector2(0.4, 0.4), maxf(0.4, dur - delay)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(r, "modulate:a", 0.8, maxf(0.4, dur - delay))

func _shake(strength: float) -> void:
	var tw := create_tween()
	for i in 12:
		var k := 1.0 - float(i) / 12.0
		tw.tween_property(content, "position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 22.0 * strength * 2.0 * k, 0.04)
	tw.tween_property(content, "position", Vector2.ZERO, 0.05)

func _gui_input(ev: InputEvent) -> void:
	if not _can_close:
		return
	if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
		_can_close = false
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.35)
		tw.tween_callback(func():
			closed.emit()
			queue_free())
