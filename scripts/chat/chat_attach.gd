class_name ChatAttach
extends Node
## 网页用 JS 文件选择器，桌面用系统文件对话框。视频抽帧走网页 canvas（见 ChatVoiceSession.frames_ready）。

signal file_picked(kind: String, bytes: PackedByteArray, mime: String, name: String)
signal cancelled
signal pick_failed(message: String)

var _js_cb: JavaScriptObject
var _busy := false


func _ready() -> void:
	if OS.has_feature("web"):
		_js_cb = JavaScriptBridge.create_callback(_on_js_file)
		JavaScriptBridge.eval("window.qiyunjuOnFile = window.qiyunjuOnFile || function(){};", true)
		var win = JavaScriptBridge.get_interface("window")
		if win:
			win.qiyunjuOnFile = _js_cb


func pick_image() -> void:
	_pick("image", "image/*", PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.gif;Images"]))


func pick_audio() -> void:
	_pick("audio", "audio/*", PackedStringArray(["*.wav,*.mp3,*.ogg,*.webm,*.m4a;Audio"]))


func pick_video() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qiyunjuMedia&&window.qiyunjuMedia.pickVideo){window.qiyunjuMedia.pickVideo();}", true)
		return
	cancelled.emit()


func pick_video_stub() -> void:
	pick_video()


func _pick(kind: String, accept: String, filters: PackedStringArray) -> void:
	if _busy:
		return
	if OS.has_feature("web"):
		_pick_web(kind, accept)
		return
	_pick_desktop(kind, filters)


func _pick_web(kind: String, accept: String) -> void:
	_busy = true
	var js := """
	(function(kind, accept){
	  var i = document.createElement('input');
	  i.type = 'file';
	  i.accept = accept;
	  i.onchange = function(){
	    var f = i.files && i.files[0];
	    if(!f){ if(window.qiyunjuOnFile) window.qiyunjuOnFile(JSON.stringify({kind:kind, cancelled:true})); return; }
	    if(f.size > 18*1024*1024){ if(window.qiyunjuOnFile) window.qiyunjuOnFile(JSON.stringify({kind:kind, error:'file too large'})); return; }
	    var r = new FileReader();
	    r.onload = function(){
	      var s = String(r.result||'');
	      var comma = s.indexOf(',');
	      var b64 = comma>=0 ? s.slice(comma+1) : s;
	      if(window.qiyunjuOnFile) window.qiyunjuOnFile(JSON.stringify({kind:kind, name:f.name, type:f.type, data:b64}));
	    };
	    r.readAsDataURL(f);
	  };
	  i.click();
	})
	"""
	JavaScriptBridge.eval("%s('%s','%s');" % [js.replace("\n", " "), kind, accept], true)


func _on_js_file(args: Array) -> void:
	_busy = false
	if args.is_empty():
		cancelled.emit()
		return
	var parsed: Variant = JSON.parse_string(str(args[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		cancelled.emit()
		return
	var d: Dictionary = parsed
	if bool(d.get("cancelled", false)):
		cancelled.emit()
		return
	var err := str(d.get("error", "")).strip_edges()
	if err != "":
		pick_failed.emit(ChatVision.picker_error(err))
		return
	var b64 := str(d.get("data", ""))
	var bytes := Marshalls.base64_to_raw(b64) if b64 != "" else PackedByteArray()
	if bytes.is_empty():
		cancelled.emit()
		return
	file_picked.emit(str(d.get("kind", "image")), bytes, str(d.get("type", "")), str(d.get("name", "file")))


func _pick_desktop(kind: String, filters: PackedStringArray) -> void:
	_busy = true
	if DisplayServer.has_method("file_dialog_show"):
		DisplayServer.file_dialog_show(
			"选择文件",
			OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS),
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			filters,
			func(status: bool, paths: PackedStringArray, _filter: int):
				_busy = false
				if not status or paths.is_empty():
					cancelled.emit()
					return
				_load_path(kind, paths[0])
		)
		return
	# 回退：嵌入式 FileDialog
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	add_child(dlg)
	dlg.file_selected.connect(func(path: String):
		_busy = false
		_load_path(kind, path)
		dlg.queue_free())
	dlg.canceled.connect(func():
		_busy = false
		cancelled.emit()
		dlg.queue_free())
	dlg.popup_centered_ratio(0.6)


func _load_path(kind: String, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		cancelled.emit()
		return
	var bytes := f.get_buffer(f.get_length())
	var mime := "application/octet-stream"
	var ext := path.get_extension().to_lower()
	var map := {
		"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp", "gif": "image/gif",
		"wav": "audio/wav", "mp3": "audio/mpeg", "ogg": "audio/ogg", "webm": "audio/webm", "m4a": "audio/mp4",
	}
	if map.has(ext):
		mime = map[ext]
	file_picked.emit(kind, bytes, mime, path.get_file())


func place_picker(rect: Rect2, viewport: Vector2) -> void:
	var files = _files_api()
	if files == null:
		return
	files.place(rect.position.x, rect.position.y, rect.size.x, rect.size.y, viewport.x, viewport.y)


func hide_picker() -> void:
	var files = _files_api()
	if files == null:
		return
	files.hide()


func _files_api() -> JavaScriptObject:
	if not OS.has_feature("web"):
		return null
	var has: Variant = JavaScriptBridge.eval("typeof window.qiyunjuFiles==='object'", true)
	if has != true and str(has) != "true":
		return null
	return JavaScriptBridge.get_interface("qiyunjuFiles")
