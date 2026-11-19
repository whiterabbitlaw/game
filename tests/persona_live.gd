extends SceneTree
## 线上多轮：一位同伴走完十余轮，其余八位各答一题。
## godot --headless --path . --script res://tests/persona_live.gd

const WORKER := "https://qiyunju-chat.whiterabbitlaw.workers.dev"

var failed := 0
var asm := ChatPromptAssembler.new()


func _initialize() -> void:
	print("== persona live ==")
	var mem := ChatMemory.new()
	mem.open("_test_persona_live")
	mem.data["messages"] = []
	mem.data["facts"] = []
	mem.data["forgotten"] = []
	mem.data["evidence_summary"] = ""
	mem.data["legacy_summary"] = ""
	mem.data["summary_kind"] = "evidence"
	var turns := [
		"我叫小舟。",
		"我喜欢雨天走路。",
		"1公里等于多少米？",
		"用三步说说白粥怎么煮，要能照着做。",
		"你觉得周一开会紧张，算正常吗？",
		"讲一个修表人的短故事，不要提到花。",
		"我有点失眠，给两个普通办法，不要讲故事。",
		"帮我列三个整理书桌的步骤。",
		"北京今天的天气你如果不知道，就说不知道。",
		"你还记得我叫什么，我喜欢做什么吗？",
		"我不喜欢雨天走路了。",
		"那我现在对雨天走路是什么态度？",
	]
	for i in turns.size():
		var q: String = turns[i]
		mem.append("user", q)
		for _pad in (6 if i == 7 else 0):
			mem.append("user", "垫一句闲聊 %d" % _pad)
			mem.append("assistant", "嗯。")
		var local := mem.answer_memory_question(q)
		if local != "":
			mem.append("assistant", local)
			print("  Q ", q)
			print("  A ", local.replace("\n", " / "))
			_ok(local.find("小舟") >= 0, "name question answered from the saved line")
			_ok(local.find("向日葵") < 0, "memory answer has no sunflower")
			continue
		var packed := asm.assemble("claude", mem.recent(16), q, mem, "", 3500, [])
		var raw := await _post("/v1/chat", {"messages": packed.get("messages", [])})
		var text := str(raw.get("text", "")).strip_edges()
		mem.append("assistant", text)
		print("  Q ", q)
		print("  A ", text.replace("\n", " / "))
		_ok(text != "", "claude turn answered: " + q.substr(0, 12))
		_ok(text.find("向日葵") < 0, "claude turn has no sunflower: " + q.substr(0, 12))
		if q.find("公里") >= 0:
			_ok(text.find("一千") >= 0 or text.find("1000") >= 0, "kilometer answered")
		if q.find("态度") >= 0:
			_ok(text.find("不喜欢") >= 0 or text.find("不想") >= 0, "later chat follows the corrected dislike")
	var others := [
		["chatgpt", "白龙司书"],
		["deepseek", "深海女仆"],
		["gemini", "幻星灵猫"],
		["grok", "黑曜公主"],
		["kimi", "月律奏者"],
		["llama", "绒云梦旅"],
		["qwen", "青岚雅士"],
		["seed", "灵感使者"],
	]
	for pair in others:
		var cid: String = pair[0]
		var q := "请用你自己的口气，用两三句回答：1公里等于多少米？先给数字。"
		var packed := asm.assemble(cid, [], q, null, "", 3500, [])
		var raw := await _post("/v1/chat", {"messages": packed.get("messages", [])})
		var text := str(raw.get("text", "")).strip_edges()
		print("  ", cid, " ", text.replace("\n", " / "))
		_ok(text != "", cid + " answered")
		_ok(text.find("一千") >= 0 or text.find("1000") >= 0, cid + " gives the distance")
		_ok(text.find("OpenAI") < 0 and text.find("Anthropic") < 0 and text.find("xAI") < 0, cid + " does not claim a vendor")
	var path := OS.get_user_data_dir().path_join("chat/_test_persona_live.json")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if failed == 0:
		print("persona_live: ALL OK")
	else:
		print("persona_live: FAILED ", failed)
	quit(1 if failed else 0)


func _post(path: String, payload: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	await process_frame
	http.timeout = 90.0
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Origin: https://whiterabbitlaw.github.io",
	])
	var err := http.request(WORKER + path, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http.queue_free()
		return {"text": ""}
	var result: Array = await http.request_completed
	http.queue_free()
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"text": ""}
	return parsed


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		failed += 1
		print("  FAIL ", msg)
