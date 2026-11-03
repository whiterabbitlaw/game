class_name UI
extends RefCounted
## 界面小工具：字体、配色、样式

const INK := Color("#3b3752")
const INK_SOFT := Color("#7a7690")
const GOLD := Color("#d9a441")
const GOLD_DEEP := Color("#b5822a")
const JADE := Color("#6fb5a6")
const JADE_DEEP := Color("#4d968a")
const ROSE := Color("#e58a9b")
const PAPER := Color(1.0, 0.985, 0.95, 0.92)
const PAPER_DIM := Color(0.97, 0.95, 0.92, 0.85)

static var _reg: Font
static var _bold: Font
static var _brush: Font

static func reg() -> Font:
	if _reg == null:
		_reg = load("res://assets/fonts/NotoSansSC-Regular.otf")
	return _reg

static func bold() -> Font:
	if _bold == null:
		_bold = load("res://assets/fonts/NotoSansSC-Bold.otf")
	return _bold

static func brush() -> Font:
	if _brush == null:
		_brush = load("res://assets/fonts/MaShanZheng.ttf")
	return _brush

static func panel(bg: Color = PAPER, border: Color = Color(0.85, 0.7, 0.4, 0.9), radius: int = 26, bw: int = 2, shadow: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	if shadow:
		sb.shadow_color = Color(0.2, 0.15, 0.35, 0.18)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 4)
	return sb

static func lbl(text: String, size: int = 26, color: Color = INK, is_bold: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if is_bold:
		l.add_theme_font_override("font", bold())
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func brush_lbl(text: String, size: int, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := lbl(text, size, color, false, align)
	l.add_theme_font_override("font", brush())
	return l

static func _btn_style(c: Color, radius: int, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0.2, 0.15, 0.35, 0.22)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb

static func btn(text: String, kind: String = "jade", size: int = 28, min_size: Vector2 = Vector2(0, 72)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", bold())
	b.focus_mode = Control.FOCUS_NONE
	var c: Color
	var bd: Color
	var fc := Color.WHITE
	match kind:
		"gold":
			c = GOLD
			bd = Color("#f6d98a")
		"rose":
			c = ROSE
			bd = Color("#ffc3cd")
		"ghost":
			c = Color(1, 1, 1, 0.55)
			bd = Color(0.85, 0.7, 0.4, 0.8)
			fc = INK
		"paper":
			c = Color(1.0, 0.985, 0.95, 0.96)
			bd = Color(0.85, 0.7, 0.4, 0.95)
			fc = INK
		"dark":
			c = Color(0.25, 0.22, 0.38, 0.8)
			bd = Color(1, 1, 1, 0.3)
		_:
			c = JADE
			bd = Color("#b8e6dc")
	b.add_theme_stylebox_override("normal", _btn_style(c, 26, bd))
	b.add_theme_stylebox_override("hover", _btn_style(c.lightened(0.08), 26, bd))
	b.add_theme_stylebox_override("pressed", _btn_style(c.darkened(0.12), 26, bd))
	b.add_theme_stylebox_override("focus", _btn_style(c, 26, bd))
	b.add_theme_stylebox_override("disabled", _btn_style(Color(0.7, 0.7, 0.75, 0.55), 26, Color(1, 1, 1, 0.3)))
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.75))
	return b

static func bar(h: int = 26, fill: Color = GOLD) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(0, h)
	p.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.3, 0.27, 0.45, 0.22)
	bg.set_corner_radius_all(h / 2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(h / 2)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func thumb(id: String, size: Vector2) -> TextureRect:
	## 头像：预先裁切好的 Q 版头部
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture = load("res://assets/thumbs/%s.png" % id)
	tr.custom_minimum_size = size
	tr.size = size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

static func chip(text: String, bg: Color, fg: Color = Color.WHITE, size: int = 20) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(lbl(text, size, fg, true))
	return pc
