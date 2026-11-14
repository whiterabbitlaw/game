extends SceneTree
# 运行：godot --headless --path . --script res://tests/chat_test.gd

var failed := 0


func _initialize() -> void:
	await create_timer(0.15).timeout
	_test_cards()
	_test_lorebook()
	_test_assembler()
	_test_memory()
	_test_anniversary()
	_test_custom_api()
	if failed == 0:
		print("chat_test: ALL OK")
	else:
		print("chat_test: FAILED ", failed)
	quit(1 if failed else 0)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		failed += 1
		print("  FAIL ", msg)


func _test_cards() -> void:
	print("== cards ==")
	var ids := Data.char_ids()
	_ok(ids.size() == 9, "nine characters")
	for id in ids:
		var path := "res://data/chat/cards/%s.json" % id
		_ok(FileAccess.file_exists(path), "card exists " + id)
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_ok(typeof(parsed) == TYPE_DICTIONARY, "json " + id)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var card: Dictionary = parsed
		_ok(card.get("spec") == "chara_card_v2", "spec v2 " + id)
		_ok(str(card.get("spec_version", "")) == "2.0", "spec_version " + id)
		var data: Dictionary = card.get("data", {})
		for k in ["name", "description", "personality", "scenario", "first_mes", "mes_example", "system_prompt", "post_history_instructions", "creator_notes"]:
			_ok(str(data.get(k, "")).strip_edges() != "", "%s.%s filled" % [id, k])
		_ok(typeof(data.get("alternate_greetings", [])) == TYPE_ARRAY, "greetings " + id)
		_ok(typeof(data.get("extensions", {})) == TYPE_DICTIONARY, "extensions " + id)
		_ok(bool(data.get("extensions", {}).get("qiyunju", {}).get("draft", false)), "draft flag " + id)
		_ok(str(data.get("creator_notes", "")).find("草稿") >= 0, "notes say 草稿 " + id)


func _test_lorebook() -> void:
	print("== lorebook ==")
	var lore := ChatLorebook.new()
	lore.load_default()
	_ok(not lore.book.is_empty(), "lorebook loaded")
	var hit_cloud := lore.scan([], "小云钻进了衣袖")
	var names := PackedStringArray()
	for e in hit_cloud:
		names.append(str(e.get("name", "")))
	_ok("小云" in names, "keyword 小云 triggers")
	_ok("栖云居" in names, "constant 栖云居 always on")
	_ok("无战斗" in names, "constant 无战斗 always on")
	var hit_x := lore.scan([], "今天的 X 是一个字母")
	var names_x := PackedStringArray()
	for e in hit_x:
		names_x.append(str(e.get("name", "")))
	_ok("X斧" not in names_x, "bare letter X does not trigger X斧")
	var hit_axe := lore.scan([], "她把 X斧 擦得很亮")
	var names_a := PackedStringArray()
	for e in hit_axe:
		names_a.append(str(e.get("name", "")))
	_ok("X斧" in names_a, "X斧 keyword triggers")
	var before := lore.contents_for_position(hit_cloud, "before_char")
	_ok(before.size() >= 1, "before_char contents")
	var tight := lore.scan([], "灵田里的向日葵和闭关同修", -1)
	var tokens := 0
	for e in tight:
		tokens += ChatLorebook.estimate_tokens(str(e.get("content", "")))
	_ok(tokens <= int(lore.book.get("token_budget", 800)) + 80, "budget roughly respected (%d)" % tokens)


func _test_assembler() -> void:
	print("== assembler ==")
	var asm := ChatPromptAssembler.new()
	_ok(asm.user_name() == "道友", "default persona name")
	var hist: Array = [
		{"role": "assistant", "content": "你好，我是白龙司书。"},
		{"role": "user", "content": "小云今天乖不乖？"},
	]
	var packed := asm.assemble("chatgpt", hist, "再讲讲云籍阁吧")
	var msgs: Array = packed.get("messages", [])
	_ok(msgs.size() >= 3, "messages assembled")
	_ok(str(msgs[0].get("role", "")) == "system", "system first")
	var sys := str(msgs[0].get("content", ""))
	_ok(sys.find("白龙司书") >= 0, "card description in system")
	_ok(sys.find("道友") >= 0, "{{user}} macro")
	_ok(sys.find("云籍阁") >= 0 or sys.find("小云") >= 0, "lore injected")
	_ok(str(msgs[msgs.size() - 1].get("content", "")) == "再讲讲云籍阁吧", "user text last")
	_ok(str(packed.get("first_mes", "")).find("{{") < 0, "first_mes macros resolved")
	var long_hist: Array = []
	for i in 40:
		long_hist.append({"role": "user" if i % 2 == 0 else "assistant", "content": "这是一段用来测试裁剪的话 %d，还要再长一点。" % i})
	var slim := asm.assemble("kimi", long_hist, "你还在吗", null, "", 800)
	_ok(int(slim["meta"]["history_kept"]) < 40, "history trimmed under budget")
	_ok(int(slim["meta"]["tokens_est"]) > 0, "token estimate")


func _test_memory() -> void:
	print("== memory ==")
	var mem := ChatMemory.new()
	mem.open("_test_chat_mvp")
	mem.data["messages"] = []
	mem.data["summary"] = ""
	mem.data["facts"] = []
	mem.append("user", "记住，我喜欢桂花糕。")
	mem.append("assistant", "好，我记住了。")
	mem.add_fact("玩家喜欢桂花糕")
	_ok(mem.all_player_texts().size() == 1, "records every player message")
	_ok(mem.all_player_texts()[0].find("桂花糕") >= 0, "player text stored")
	_ok(mem.facts().size() == 1, "fact stored")
	_ok(mem.first_meet_unix() > 0, "first_meet stamped")
	# rolling summary hook
	for i in 24:
		mem.append("user", "第 %d 句" % i)
		mem.append("assistant", "收到 %d" % i)
	var rolled := mem.maybe_roll_summary()
	_ok(rolled, "summary hook fired")
	_ok(mem.summary().strip_edges() != "", "summary filled")
	_ok(mem.recent(30).size() <= ChatMemory.KEEP_RECENT, "recent window after roll")
	# cleanup
	var path := "user://chat/_test_chat_mvp.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(OS.get_user_data_dir().path_join("chat/_test_chat_mvp.json"))
		print("  cleaned test memory file")


func _test_anniversary() -> void:
	print("== anniversary ==")
	var a := ChatAnniversary.new()
	a.persona = {"name": "道友", "birthday": "1990-11-14"}
	a.custom = [{"type": "custom", "title": "品茶日", "date": "11-14", "hint": "一起喝茶"}]
	var ev := a.due_today({"year": 2026, "month": 11, "day": 14, "hour": 12}, 0)
	var types := PackedStringArray()
	for e in ev:
		types.append(str(e.get("type", "")))
	_ok("player_birthday" in types, "player birthday")
	_ok("custom" in types, "custom anniversary")
	var none := a.due_today({"year": 2026, "month": 1, "day": 1, "hour": 12}, 0)
	_ok(none.is_empty(), "no event on another day")
	var meet := Time.get_unix_time_from_datetime_dict({"year": 2024, "month": 11, "day": 14, "hour": 8, "minute": 0, "second": 0})
	var ev2 := a.due_today({"year": 2026, "month": 11, "day": 14, "hour": 12}, int(meet))
	var types2 := PackedStringArray()
	for e in ev2:
		types2.append(str(e.get("type", "")))
	_ok("first_meet" in types2, "first-meet anniversary after 2 years")
	var same_day := Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 11, "day": 14, "hour": 8, "minute": 0, "second": 0})
	var ev3 := a.due_today({"year": 2026, "month": 11, "day": 14, "hour": 12}, int(same_day))
	var types3 := PackedStringArray()
	for e in ev3:
		types3.append(str(e.get("type", "")))
	_ok("first_meet" not in types3, "first-meet day itself is not an anniversary")
	var note := a.format_system_note(ev2)
	_ok(note.find("纪念日") >= 0, "system note")


func _test_custom_api() -> void:
	print("== custom api ==")
	_ok(ChatConfig.PATH.begins_with("user://"), "config lives in user://")
	_ok(ChatConfig.DEFAULT_WORKER_URL.find("qiyunju-chat") >= 0, "default worker url")
	_ok(ChatConfig.DEFAULT_WORKER_URL.begins_with("https://"), "default is https")
	var cfg := ChatConfig.new()
	cfg.path = "user://chat/_test_chat_config.json"
	# default: worker
	var plan := cfg.plan_chat([{"role": "user", "content": "你好"}])
	_ok(str(plan.get("kind", "")) == ChatConfig.PROVIDER_WORKER, "default routes to worker")
	_ok(str(plan.get("url", "")).ends_with("/v1/chat"), "worker chat path")
	var hdrs: PackedStringArray = plan.get("headers", PackedStringArray())
	var joined := " ".join(hdrs)
	_ok(joined.find("Bearer") < 0, "worker plan has no bearer key")
	# openai compatible
	cfg.provider = ChatConfig.PROVIDER_OPENAI
	cfg.openai_base_url = "https://example.com/v1"
	cfg.openai_model = "foo-bar"
	cfg.openai_api_key = "sk-test-not-real"
	_ok(cfg.uses_custom_chat(), "openai counts as custom")
	_ok(cfg.openai_chat_url() == "https://example.com/v1/chat/completions", "openai url join")
	cfg.openai_base_url = "https://example.com/v1/chat/completions"
	_ok(cfg.openai_chat_url() == "https://example.com/v1/chat/completions", "openai url already complete")
	cfg.openai_base_url = "https://example.com/v1"
	plan = cfg.plan_chat([{"role": "system", "content": "s"}, {"role": "user", "content": "hi"}])
	_ok(str(plan.get("kind", "")) == "openai", "openai kind")
	_ok(str(plan["url"]).ends_with("/chat/completions"), "openai path")
	_ok(str(plan["body"].get("model", "")) == "foo-bar", "openai model")
	var h2: PackedStringArray = plan.get("headers", PackedStringArray())
	_ok(" ".join(h2).find("Bearer sk-test-not-real") >= 0, "openai bearer present in request plan")
	# gemini
	cfg.provider = ChatConfig.PROVIDER_GEMINI
	cfg.gemini_api_key = "AIza-test-not-real"
	cfg.gemini_model = "gemini-2.5-flash"
	_ok(cfg.uses_custom_chat(), "gemini counts as custom")
	plan = cfg.plan_chat([{"role": "system", "content": "sys"}, {"role": "user", "content": "hi"}])
	_ok(str(plan.get("kind", "")) == "gemini", "gemini kind")
	_ok(str(plan.get("url", "")).find("generativelanguage.googleapis.com") >= 0, "gemini host")
	_ok(typeof(plan["body"].get("systemInstruction", {})) == TYPE_DICTIONARY, "gemini system")
	var extracted := cfg.extract_chat_text("openai", {"choices": [{"message": {"content": "  你好  "}}]})
	_ok(extracted == "你好", "extract openai text")
	extracted = cfg.extract_chat_text("gemini", {"candidates": [{"content": {"parts": [{"text": "喵"}]}}]})
	_ok(extracted == "喵", "extract gemini text")
	extracted = cfg.extract_chat_text("worker", {"text": "嗯"})
	_ok(extracted == "嗯", "extract worker text")
	# provider=worker even if a key is stored
	cfg.provider = ChatConfig.PROVIDER_WORKER
	cfg.apply_dict({"provider": "worker", "openai_api_key": "sk-should-not-switch"})
	_ok(cfg.provider == ChatConfig.PROVIDER_WORKER, "explicit worker not overridden by leftover key")
	cfg.save()
	_ok(FileAccess.file_exists(cfg.path), "saves only under user://")
	_ok(cfg.path.begins_with("user://"), "save path still user://")
	DirAccess.remove_absolute(OS.get_user_data_dir().path_join("chat/_test_chat_config.json"))
