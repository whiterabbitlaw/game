class_name Sparks
extends Node2D
## 轻量粒子系统（自绘）：灵气上升 / 聚拢 / 爆发。避免依赖 CPUParticles 在部分 Web 后端的颜色问题。

var tex: Texture2D = preload("res://assets/fx/spark.png")
var tint := Color.WHITE
var kind := "rise"           # rise | converge | burst
var radius := 150.0
var rate := 12.0             # 每秒生成数量
var emitting := false
var life_range := Vector2(1.6, 2.6)
var size_range := Vector2(10.0, 24.0)
var parts: Array = []
var _acc := 0.0

func _process(delta: float) -> void:
	if emitting and kind != "burst":
		_acc += delta * rate
		while _acc >= 1.0:
			_acc -= 1.0
			_spawn()
	var alive: Array = []
	for p in parts:
		p["t"] += delta
		if p["t"] >= p["life"]:
			continue
		p["v"] = p["v"] * maxf(0.0, 1.0 - p["damp"] * delta) + p["g"] * delta
		p["p"] += p["v"] * delta
		alive.append(p)
	parts = alive
	queue_redraw()

func _spawn() -> void:
	var life := randf_range(life_range.x, life_range.y)
	var sz := randf_range(size_range.x, size_range.y)
	var p := {"t": 0.0, "life": life, "size": sz, "damp": 0.0, "g": Vector2.ZERO}
	match kind:
		"rise":
			var a := randf() * TAU
			var r := sqrt(randf()) * radius
			p["p"] = Vector2(cos(a) * r, sin(a) * r * 0.9)
			p["v"] = Vector2(randf_range(-8, 8), randf_range(-46, -18))
		"converge":
			var a2 := randf() * TAU
			p["p"] = Vector2(cos(a2), sin(a2)) * radius
			p["v"] = -p["p"] / life * 1.15
		_:
			var a3 := randf() * TAU
			var sp := randf_range(240.0, 720.0)
			p["p"] = Vector2.ZERO
			p["v"] = Vector2(cos(a3), sin(a3)) * sp
			p["damp"] = 1.7
			p["g"] = Vector2(0, 150)
	parts.append(p)

func burst(n: int) -> void:
	for i in n:
		_spawn()

func _draw() -> void:
	for p in parts:
		var k: float = p["t"] / p["life"]
		var a := sin(PI * clampf(k, 0.0, 1.0)) if kind != "burst" else (1.0 - k)
		var s: float = p["size"] * (0.5 + 0.7 * sin(PI * clampf(k, 0.0, 1.0)))
		var c := Color(tint.r, tint.g, tint.b, clampf(a, 0.0, 1.0) * tint.a)
		draw_texture_rect(tex, Rect2(p["p"] - Vector2(s, s) * 0.5, Vector2(s, s)), false, c)
