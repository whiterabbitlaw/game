class_name ChatWebInput
extends Node
## 网页畅聊输入桥。非网页平台 available() 为 false，调用方继续用 LineEdit。

signal text_event(text: String, kind: String, composing: bool)
signal submit_event(text: String)
signal inset_event(px: float)

var _cb: JavaScriptObject
var _installed := false


func supported() -> bool:
	return OS.has_feature("web")


func available() -> bool:
	return _js_says_yes("(window.qiyunjuIme&&typeof window.qiyunjuIme.place==='function')?'yes':'no'")


func _js_says_yes(expr: String) -> bool:
	if not supported():
		return false
	# eval 的布尔返回在网页里不可靠（可能变成整数 1，和 true 对不上）。只认字符串 yes。
	return str(JavaScriptBridge.eval(expr, true)) == "yes"


func setup() -> void:
	if _installed or not supported():
		return
	if not available():
		return
	# 先占一个函数，再换成 Godot 回调。麦克风和选文件都是这个顺序，缺这一步时属性写不进去。
	JavaScriptBridge.eval("window.qiyunjuOnIme=window.qiyunjuOnIme||function(){};", true)
	_cb = JavaScriptBridge.create_callback(_on_js)
	var win = JavaScriptBridge.get_interface("window")
	if win:
		win.qiyunjuOnIme = _cb
	_installed = true


func _ime() -> JavaScriptObject:
	if not _js_says_yes("(window.qiyunjuIme)?'yes':'no'"):
		return null
	return JavaScriptBridge.get_interface("qiyunjuIme")


func open_field(placeholder: String, aria_label: String) -> void:
	setup()
	var ime := _ime()
	if ime == null:
		return
	ime.open(placeholder, aria_label)


func place(rect: Rect2, viewport: Vector2) -> void:
	var ime := _ime()
	if ime == null:
		return
	ime.place(rect.position.x, rect.position.y, rect.size.x, rect.size.y, viewport.x, viewport.y)


func set_text(t: String) -> void:
	var ime := _ime()
	if ime == null:
		return
	ime.setText(t)


func value() -> String:
	var ime := _ime()
	if ime == null:
		return ""
	return str(ime.value())


func hide() -> void:
	var ime := _ime()
	if ime == null:
		return
	ime.hide()


func close() -> void:
	var ime := _ime()
	if ime == null:
		return
	ime.close()


func place_log(rect: Rect2, viewport: Vector2) -> void:
	var chat := _chat()
	if chat == null:
		return
	chat.place(rect.position.x, rect.position.y, rect.size.x, rect.size.y, viewport.x, viewport.y)


func set_lines(lines: Array) -> void:
	var chat := _chat()
	if chat == null:
		return
	chat.setLines(JSON.stringify(lines))


func set_note(text: String) -> void:
	if not _js_says_yes("(window.qiyunjuChat&&window.qiyunjuChat.setNote)?'yes':'no'"):
		return
	var chat := _chat()
	if chat:
		chat.setNote(text)


func hide_log() -> void:
	var chat := _chat()
	if chat == null:
		return
	chat.hide()


func _chat() -> JavaScriptObject:
	if not _js_says_yes("(window.qiyunjuChat&&window.qiyunjuChat.setLines)?'yes':'no'"):
		return null
	return JavaScriptBridge.get_interface("qiyunjuChat")


func poll_inset(viewport: Vector2) -> float:
	var ime := _ime()
	if ime == null:
		return 0.0
	return float(ime.inset(viewport.x, viewport.y))


func _on_js(args: Array) -> void:
	if args.is_empty():
		return
	var parsed: Variant = JSON.parse_string(str(args[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var typ := str(d.get("type", ""))
	var text := str(d.get("text", ""))
	match typ:
		"input", "blur", "composition", "focus":
			text_event.emit(text, typ, bool(d.get("composing", false)))
		"submit":
			submit_event.emit(text)
		"inset":
			inset_event.emit(float(d.get("inset", 0.0)))
