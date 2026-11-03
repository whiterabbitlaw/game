class_name Chibi
extends Node2D
## Q版角色：程序化动画（呼吸/漂浮、打坐光环与灵气粒子、突破闪光、弹跳、害羞）

var cid := ""
var height := 500.0
var mode := "idle"          # idle | meditate
var spr: Sprite2D
var aura: Sprite2D
var shadow: Sprite2D
var qi: Sparks
var orbit: Array[Sprite2D] = []
var _base_scale := 1.0
var _t := 0.0
var _phase := 0.0
var _tw: Tween
var _extra_rot := 0.0
var _extra_scale := Vector2.ONE
var _extra_y := 0.0
var _aura_alpha := 0.0
var color := Color.WHITE

func setup(id: String, h: float, with_fx: bool = true) -> Chibi:
	cid = id
	height = h
	_phase = randf() * 6.28
	color = Data.char_def(id).get("color", Color.WHITE)
	var tex: Texture2D = load("res://assets/chars/%s.png" % id)
	_base_scale = h / float(tex.get_height())
	var glow: Texture2D = load("res://assets/fx/glow.png")
	shadow = Sprite2D.new()
	shadow.texture = glow
	shadow.scale = Vector2(h * 0.0022, h * 0.0007)
	shadow.modulate = Color(0.15, 0.1, 0.3, 0.35)
	add_child(shadow)
	if with_fx:
		aura = Sprite2D.new()
		aura.texture = glow
		aura.position = Vector2(0, -h * 0.5)
		aura.scale = Vector2.ONE * (h / 128.0) * 1.15
		aura.modulate = Color(color.r, color.g, color.b, 0.0)
		add_child(aura)
	spr = Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height())
	spr.scale = Vector2.ONE * _base_scale
	add_child(spr)
	if with_fx:
		qi = Sparks.new()
		qi.kind = "rise"
		qi.radius = h * 0.34
		qi.rate = 16.0
		qi.position = Vector2(0, -h * 0.45)
		qi.size_range = Vector2(h * 0.025, h * 0.06)
		qi.tint = color.lightened(0.5)
		add_child(qi)
		for i in 4:
			var o := Sprite2D.new()
			o.texture = load("res://assets/fx/spark.png")
			o.scale = Vector2.ONE * 0.5
			o.modulate = Color(color.lightened(0.6), 0.0)
			add_child(o)
			orbit.append(o)
	return self

func _draw() -> void:
	if _aura_alpha <= 0.01:
		return
	# 地面法阵：旋转的符文圆环
	var a := _aura_alpha * 1.5
	var col := Color(color.lightened(0.25), clampf(a, 0.0, 0.9))
	var gold := Color(1.0, 0.85, 0.45, clampf(a, 0.0, 0.9))
	var R := height * 0.44
	draw_set_transform(Vector2(0, -4), 0.0, Vector2(1.0, 0.28))
	draw_arc(Vector2.ZERO, R, 0.0, TAU, 72, gold, 5.0, true)
	draw_arc(Vector2.ZERO, R * 0.82, 0.0, TAU, 72, col, 3.0, true)
	for i in 12:
		var ang := _t * 0.5 + float(i) * TAU / 12.0
		draw_line(Vector2(cos(ang), sin(ang)) * R * 0.84, Vector2(cos(ang), sin(ang)) * R * 0.97, gold, 4.0, true)
	var pts := PackedVector2Array()
	for i in 6:
		var ang2 := -_t * 0.35 + float(i) * TAU / 6.0
		pts.append(Vector2(cos(ang2), sin(ang2)) * R * 0.7)
	for i in 6:
		draw_line(pts[i], pts[(i + 2) % 6], col, 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func set_mode(m: String) -> void:
	if m == mode:
		return
	mode = m
	if qi:
		qi.emitting = (m == "meditate")
	var target := 0.55 if m == "meditate" else 0.0
	var tw := create_tween()
	tw.tween_property(self, "_aura_alpha", target, 0.8)

func set_dark(on: bool) -> void:
	spr.modulate = Color(0.16, 0.14, 0.24, 0.85) if on else Color.WHITE

func _process(delta: float) -> void:
	_t += delta
	var p := _t * 2.1 + _phase
	if mode == "meditate":
		var fl := -26.0 + sin(_t * 1.3 + _phase) * 9.0
		spr.position = Vector2(0, fl + _extra_y)
		spr.scale = Vector2(_base_scale * (1.0 + sin(p * 0.7) * 0.01), _base_scale * 0.96) * Vector2(_extra_scale.x, _extra_scale.y)
		spr.rotation = _extra_rot + sin(_t * 0.9 + _phase) * 0.012
		shadow.modulate.a = 0.22
		shadow.scale.x = height * 0.0020
	else:
		spr.position = Vector2(0, -absf(sin(p)) * height * 0.008 + _extra_y)
		spr.scale = Vector2(_base_scale * (1.0 - sin(p) * 0.006), _base_scale * (1.0 + sin(p) * 0.012)) * Vector2(_extra_scale.x, _extra_scale.y)
		spr.rotation = _extra_rot
		shadow.modulate.a = 0.35
	queue_redraw()
	if aura:
		var pulse := 0.85 + 0.15 * sin(_t * 2.4)
		aura.modulate.a = _aura_alpha * pulse
		for i in orbit.size():
			var a := _t * 1.2 + float(i) * TAU / float(orbit.size())
			var rr := height * 0.34
			orbit[i].position = Vector2(cos(a) * rr, -height * 0.5 + sin(a) * rr * 0.55 - 20.0)
			orbit[i].modulate.a = _aura_alpha * (0.5 + 0.5 * sin(a * 2.0)) * 1.4
			orbit[i].rotation = a

func bounce() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	_extra_scale = Vector2.ONE
	_extra_y = 0.0
	_tw = create_tween()
	_tw.set_parallel(false)
	_tw.tween_property(self, "_extra_scale", Vector2(1.08, 0.9), 0.08)
	_tw.tween_property(self, "_extra_scale", Vector2(0.94, 1.08), 0.12)
	_tw.parallel().tween_property(self, "_extra_y", -height * 0.06, 0.12)
	_tw.tween_property(self, "_extra_y", 0.0, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_property(self, "_extra_scale", Vector2.ONE, 0.2)

func shy() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	for i in 3:
		_tw.tween_property(self, "_extra_rot", 0.05, 0.07)
		_tw.tween_property(self, "_extra_rot", -0.05, 0.07)
	_tw.tween_property(self, "_extra_rot", 0.0, 0.07)

func flash(strength: float = 1.0) -> void:
	var tw := create_tween()
	var c := Color(1.0 + strength * 1.6, 1.0 + strength * 1.5, 1.0 + strength * 1.2, 1.0)
	tw.tween_property(spr, "modulate", c, 0.12)
	tw.tween_property(spr, "modulate", Color.WHITE, 0.7)

func enter(from_x: float = 60.0) -> void:
	modulate.a = 0.0
	var x0 := position.x
	position.x = x0 + from_x
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.3)
	tw.tween_property(self, "position:x", x0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
