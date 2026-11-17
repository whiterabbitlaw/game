class_name ChatLayout
extends RefCounted
## 畅聊面板的视口几何。逻辑坐标跟项目视口走（竖屏 720×1280，stretch keep）。
## 不要再用比视口更宽的 custom_minimum_size：PanelContainer 会被子节点最小宽度撑出屏幕。

const BUBBLE_MAX_W := 520.0
const BUBBLE_MAX_H := 820.0


static func fit_rect(viewport: Vector2, margin: float, keyboard_inset: float) -> Rect2:
	var m := maxf(0.0, margin)
	var inset := maxf(0.0, keyboard_inset)
	var w := maxf(120.0, viewport.x - m * 2.0)
	var y := m
	var bottom := viewport.y - m - inset
	var h := bottom - y
	if h < 0.0:
		h = 0.0
	if y + h > viewport.y:
		h = maxf(0.0, viewport.y - y)
	return Rect2(m, y, w, h)


static func bubble_rect(viewport: Vector2, keyboard_inset: float) -> Rect2:
	var m := 12.0
	var inset := maxf(0.0, keyboard_inset)
	var w := minf(BUBBLE_MAX_W, maxf(160.0, viewport.x - m * 2.0))
	var bottom_limit := viewport.y - m - inset
	var h := minf(BUBBLE_MAX_H, bottom_limit - m)
	if h < 0.0:
		h = 0.0
	var y := minf(120.0, maxf(m, bottom_limit - h))
	if y + h > viewport.y:
		h = maxf(0.0, viewport.y - y)
	return Rect2(m, y, w, h)


static func clamp_pos(pos: Vector2, size: Vector2, viewport: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, 0.0, maxf(0.0, viewport.x - size.x)),
		clampf(pos.y, 0.0, maxf(0.0, viewport.y - size.y))
	)


## 与 web/qiyunju_ime.js 的 keyboardOverlapViewport 使用同一公式。
## 返回值是 Godot 视口像素：软键盘挡住的逻辑高度。画布已经缩到视觉视口里时结果为 0，避免垫高两次。
static func keyboard_overlap(vp: Vector2, canvas: Vector2, canvas_top: float, vv_offset_top: float, vv_height: float) -> float:
	if vp.x <= 1.0 or vp.y <= 1.0 or canvas.x <= 1.0 or canvas.y <= 1.0 or vv_height < 0.0:
		return 0.0
	var scale := minf(canvas.x / vp.x, canvas.y / vp.y)
	if scale <= 0.0:
		return 0.0
	var offset_y := (canvas.y - vp.y * scale) / 2.0
	var content_bottom := canvas_top + offset_y + vp.y * scale
	var visible_bottom := vv_offset_top + vv_height
	var overlap := content_bottom - visible_bottom
	if overlap <= 1.0:
		return 0.0
	return overlap / scale


static func inside(outer: Rect2, inner: Rect2, slop: float = 1.0) -> bool:
	return inner.position.x >= outer.position.x - slop \
		and inner.position.y >= outer.position.y - slop \
		and inner.end.x <= outer.end.x + slop \
		and inner.end.y <= outer.end.y + slop
