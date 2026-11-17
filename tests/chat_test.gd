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
	_test_lorebook_st()
	_test_memory_p2()
	_test_events_p2()
	_test_registry()
	_test_voice_p3()
	_test_layout_math()
	_test_vision_and_length()
	await _test_chat_panel_layout()
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



func _test_lorebook_st() -> void:
	print("== lorebook ST ==")
	var lore := ChatLorebook.new()
	lore.book = {
		"scan_depth": 2,
		"token_budget": 40,
		"recursive_scanning": false,
		"entries": [
			{"id": "p1", "name": "and_any", "keys": ["桂花"], "secondary_keys": ["糕", "茶"], "selective": true, "selective_logic": "and_any", "content": "桂花点心条目，用来测预算ABCDEFGHIJK", "enabled": true, "priority": 10, "insertion_order": 20, "position": "after_char"},
			{"id": "p2", "name": "and_all", "keys": ["承诺"], "secondary_keys": ["月色", "茶"], "selective": true, "selective_logic": "and_all", "content": "三重约定", "enabled": true, "insertion_order": 10, "position": "after_char"},
			{"id": "p3", "name": "not_any", "keys": ["灵田"], "secondary_keys": ["打架"], "selective_logic": "not_any", "content": "灵田安宁", "enabled": true, "position": "before_char"},
			{"id": "p4", "name": "never", "keys": ["桂花"], "content": "不应出现", "probability": 0, "enabled": true},
			{"id": "p5", "name": "depth_old", "keys": ["旧词"], "content": "不该扫到", "enabled": true},
			{"id": "p6", "name": "at_depth", "keys": ["云籍阁"], "content": "插在深处", "position": "at_depth", "depth": 1, "enabled": true},
		],
	}
	lore.force_probability = true
	var names := func(hits: Array) -> PackedStringArray:
		var n := PackedStringArray()
		for e in hits:
			n.append(str(e.get("name", "")))
		return n
	var h1 := lore.scan([], "今晚的桂花糕真香")
	_ok("and_any" in names.call(h1), "selective and_any hits with one secondary")
	_ok("never" not in names.call(h1), "probability 0 never activates")
	var h1b := lore.scan([], "桂花开了")
	_ok("and_any" not in names.call(h1b), "selective and_any misses without secondary")
	var h2 := lore.scan([], "我承诺在月色下请你喝茶")
	_ok("and_all" in names.call(h2), "selective and_all needs every secondary")
	var h2b := lore.scan([], "我承诺看月色")
	_ok("and_all" not in names.call(h2b), "and_all fails if a secondary is missing")
	var h3 := lore.scan([], "去灵田走走")
	_ok("not_any" in names.call(h3), "not_any passes when secondary absent")
	var h3b := lore.scan([], "灵田里打架可不行")
	_ok("not_any" not in names.call(h3b), "not_any blocked by secondary")
	var hist: Array = [
		{"role": "user", "content": "旧词只出现在很早以前"},
		{"role": "assistant", "content": "嗯"},
		{"role": "user", "content": "今天去云籍阁吧"},
	]
	var hd := lore.scan(hist, "再看看", 2)
	_ok("depth_old" not in names.call(hd), "scan_depth skips older turns")
	_ok("at_depth" in names.call(hd), "at_depth entry still triggers from recent text")
	var tight := lore.scan([], "桂花糕 承诺 月色 茶 灵田 云籍阁")
	var tokens := 0
	for e in tight:
		tokens += ChatLorebook.estimate_tokens(str(e.get("content", "")))
	_ok(tokens <= 40 + 20, "token budget still caps insertions (%d)" % tokens)
	# 角色书合并
	lore.add_character_book({"token_budget": 0, "entries": [{"id": "char1", "name": "角色书", "keys": ["小云"], "content": "她袖里的小云。", "enabled": true, "position": "after_char"}]})
	var hc := lore.scan([], "小云钻出来了")
	_ok("角色书" in names.call(hc), "per-character lorebook merges")


func _test_memory_p2() -> void:
	print("== memory P2 ==")
	var mem := ChatMemory.new()
	mem.open("_test_chat_p2")
	mem.data["messages"] = []
	mem.data["summary"] = ""
	mem.data["facts"] = []
	mem.merge_fact({"kind": "like", "text": "玩家喜欢桂花糕", "keys": ["桂花糕", "喜欢"]})
	mem.merge_fact({"kind": "promise", "text": "答应下次一起看月", "keys": ["月"]})
	mem.merge_fact({"kind": "like", "text": "玩家喜欢桂花糕", "keys": ["桂花糕"]})
	_ok(mem.facts().size() == 2, "structured facts dedupe")
	var hit := mem.retrieve("今晚想吃桂花糕")
	var blob := mem.format_facts_block(hit)
	_ok(blob.find("桂花糕") >= 0, "keyword retrieval injects like")
	_ok(mem.delete_fact(str(mem.facts()[0].get("id", ""))), "delete fact")
	_ok(mem.facts().size() == 1, "fact removed")
	mem.apply_llm_summary("你们第一次谈到桂花糕。")
	_ok(mem.summary().find("桂花糕") >= 0, "llm summary stored")
	_ok(not mem.needs_llm_summary(), "pending flag cleared")
	var profile := ChatProfile.new()
	profile.local_path = "user://chat/_test_persona_local.json"
	profile.profile_path = "user://chat/_test_profile.json"
	profile.save_persona({"name": "测试道友", "birthday": "05-20"})
	_ok(str(profile.load_persona().get("name", "")) == "测试道友", "local persona override")
	profile.add_shared_fact({"kind": "name", "text": "玩家希望被叫作测试道友", "keys": ["测试道友"]})
	_ok(profile.shared_facts().size() == 1, "shared profile fact")
	DirAccess.remove_absolute(OS.get_user_data_dir().path_join("chat/_test_chat_p2.json"))
	DirAccess.remove_absolute(OS.get_user_data_dir().path_join("chat/_test_persona_local.json"))
	DirAccess.remove_absolute(OS.get_user_data_dir().path_join("chat/_test_profile.json"))


func _test_events_p2() -> void:
	print("== events P2 ==")
	var a := ChatAnniversary.new()
	a.claims_path = "user://chat/_test_event_claims.json"
	a.persona = {"name": "道友", "birthday": ""}
	a.custom = []
	a.claims = {}
	a.festivals = {
		"fixed": [{"id": "yuandan", "title": "元旦", "month": 1, "day": 1, "hint": "新年好"}],
		"lunar": [{"id": "chunjie", "title": "春节", "dates": {"2026": "02-17"}, "hint": "拜年"}],
	}
	var fest := a.due_today({"year": 2026, "month": 2, "day": 17}, 0)
	var types := PackedStringArray()
	for e in fest:
		types.append(str(e.get("type", "")))
		types.append(str(e.get("id", "")))
	_ok("festival" in types and "chunjie" in types, "spring festival table")
	var y := a.due_today({"year": 2026, "month": 1, "day": 1}, 0)
	_ok(not y.is_empty() and str(y[0].get("id", "")) == "yuandan", "yuan dan fixed date")
	var bond_at := Time.get_unix_time_from_datetime_dict({"year": 2024, "month": 11, "day": 14, "hour": 8, "minute": 0, "second": 0})
	var evb := a.due_today({"year": 2026, "month": 11, "day": 14}, 0, {"recruited_at": int(bond_at)})
	var tb := PackedStringArray()
	for e in evb:
		tb.append(str(e.get("type", "")))
	_ok("bond_day" in tb, "结缘日 anniversary")
	var evs := a.due_today({"year": 2026, "month": 3, "day": 1}, 0, {"streak": 30})
	var ts := PackedStringArray()
	for e in evs:
		ts.append(str(e.get("id", "")))
	_ok("streak:7" in ts and "streak:30" in ts, "streak milestones 7 and 30")
	_ok("streak:100" not in ts, "higher streak not due")
	a.claim(evs[0])
	var again := a.unclaimed_today({"year": 2026, "month": 3, "day": 1}, 0, {"streak": 30})
	var ts2 := PackedStringArray()
	for e in again:
		ts2.append(str(e.get("key", "")))
	_ok(str(evs[0].get("key", "")) not in ts2, "claimed event hidden for the year")
	a.ignore_asked_flag = true
	_ok(a.birthday_prompt_needed(), "ask birthday when unset")
	DirAccess.remove_absolute(OS.get_user_data_dir().path_join("chat/_test_event_claims.json"))


func _test_registry() -> void:
	print("== registry ==")
	var reg := ChatRegistry.new()
	reg.load_default()
	_ok("persona" in reg.order and "memory" in reg.order and "events" in reg.order, "module order json loaded")
	var asm := ChatPromptAssembler.new()
	var packed := asm.assemble("chatgpt", [{"role": "user", "content": "你好"}], "看看这张图", null, "", 3500, [{"kind": "image", "description": "一只白猫趴在灯下"}])
	var sys := str(packed["messages"][0].get("content", ""))
	_ok(sys.find("白猫") >= 0 or sys.find("图") >= 0, "multimodal section injected")
	_ok(int(packed["meta"].get("sections", 0)) > 0, "assembler reports sections")
	_ok(FileAccess.file_exists("res://data/chat/module_order.json"), "order config in repo")
	_ok(ChatConfig.new().worker_path("/v1/memory/extract").ends_with("/v1/memory/extract"), "extract url")
	_ok(ChatConfig.new().worker_path("/v1/vision").find("/v1/vision") >= 0, "vision url")
	_ok(ChatConfig.new().worker_path("/v1/stt").find("/v1/stt") >= 0, "stt url")



func _test_voice_p3() -> void:
	print("== voice p3 ==")
	var parts: PackedStringArray = ChatTextUtil.split_sentences("你好。我是小云！今天好吗？还请多指教")
	_ok(parts.size() == 4, "split four sentences (%d)" % parts.size())
	_ok(parts[0].ends_with("。") and parts[1].ends_with("！") and parts[2].ends_with("？"), "punctuation kept")
	var merged: PackedStringArray = ChatTextUtil.split_sentences("好。\n然后我们去灵田。")
	_ok(merged.size() >= 2, "newline splits")
	var times: PackedFloat32Array = ChatTextUtil.frame_times(10.0, 4)
	_ok(times.size() == 4, "four frame times")
	_ok(is_equal_approx(times[0], 1.2) and is_equal_approx(times[3], 8.8), "12%%-88%% span")
	var shortt: PackedFloat32Array = ChatTextUtil.frame_times(0.1, 4)
	_ok(shortt.size() == 1, "short video one frame")
	var vad := ChatVAD.new()
	vad.sample_rate = 16000
	vad.threshold = 0.025
	vad.min_speech_ms = 280
	vad.silence_ms = 900
	var quiet := PackedFloat32Array()
	quiet.resize(1600)
	var ev := vad.feed(quiet, false)
	_ok(ev == "", "silence stays idle")
	var loud := PackedFloat32Array()
	loud.resize(1600)  # 100 ms
	for i in loud.size():
		loud[i] = 0.2
	var started := false
	for i in 4:
		if vad.feed(loud, false) == "start":
			started = true
			break
	_ok(started, "energy start after min speech")
	var ended := false
	for j in 10:
		if vad.feed(quiet, false) == "end":
			ended = true
			break
	_ok(ended, "silence timeout ends utterance")
	vad.reset()
	var barged := false
	for b in 3:
		if vad.feed(loud, true) == "barge":
			barged = true
			break
	_ok(barged, "barge-in while tts")
	var pcm := ChatVAD.floats_to_pcm16(loud)
	var wav := ChatVAD.write_wav(pcm, 16000)
	_ok(wav.size() == 44 + pcm.size(), "wav size")
	_ok(wav.slice(0, 4).get_string_from_ascii() == "RIFF", "RIFF header")
	_ok(wav.slice(8, 12).get_string_from_ascii() == "WAVE", "WAVE header")
	_ok(wav.decode_u16(22) == 1 and wav.decode_u32(24) == 16000 and wav.decode_u16(34) == 16, "mono 16k 16-bit")
	_ok(FileAccess.file_exists("res://web/manifest.webmanifest"), "pwa manifest")
	_ok(FileAccess.file_exists("res://web/sw.js"), "service worker")
	_ok(FileAccess.file_exists("res://web/qiyunju_media.js"), "media js")
	_ok(FileAccess.file_exists("res://web/pip.html"), "pip html")
	_ok(FileAccess.file_exists("res://android/README.md"), "android readme")
	_ok(FileAccess.file_exists("res://android/plugins/QiyunjuOverlay/src/org/qiyunju/overlay/QiyunjuOverlayPlugin.java"), "overlay plugin source")
	var manifest := FileAccess.get_file_as_string("res://web/manifest.webmanifest")
	_ok(manifest.find('"start_url": "./"') >= 0 or manifest.find('"start_url":"./"') >= 0, "relative start_url")
	var worker := FileAccess.get_file_as_string("res://tools/chat-worker/src/index.js")
	_ok(worker.find("language") >= 0 and worker.find("handleStt") >= 0, "worker stt language")
	_ok(worker.find("whisper-large-v3-turbo") >= 0 and worker.find("task") >= 0, "worker stt turbo + task")
	_ok(worker.find("toSimplified") >= 0 and worker.find("T2S_TRAD") >= 0, "worker zh-Hans map")
	var client_src := FileAccess.get_file_as_string("res://scripts/chat/chat_client.gd")
	_ok(client_src.find('language: String = "zh"') >= 0 and client_src.find("tts_push") >= 0, "client stt zh + tts queue")
	_ok(client_src.find("_stt_http") >= 0 and client_src.find("timeout = 20.0") >= 0, "dedicated stt timeout 20s")
	_ok(ChatTextUtil.to_simplified("小雲今日靈田可曾澆過？") == "小云今日灵田可曾浇过？", "traditional to simplified")
	_ok(ChatTextUtil.to_simplified("你好") == "你好", "already simplified stays")
	var sw := FileAccess.get_file_as_string("res://web/sw.js")
	_ok(sw.find("qiyunju-shell-v7") >= 0 and sw.find("qiyunju_chat.js") >= 0 and sw.find("qiyunju_ime.js") >= 0 and sw.find("NETWORK_FIRST") >= 0, "sw cache v7 network-first")
	var chat_js := FileAccess.get_file_as_string("res://web/qiyunju_chat.js")
	_ok(chat_js.find("chat-9") >= 0 and chat_js.find("qiyunju-log") >= 0 and chat_js.find("pan-y") >= 0, "visible build and touch log")
	var ime_src := FileAccess.get_file_as_string("res://scripts/chat/chat_web_input.gd")
	_ok(ime_src.find("?'yes':'no'") >= 0 and ime_src.find("qiyunjuOnIme") >= 0, "ime bridge uses string yes and installs callback")
	var ime := FileAccess.get_file_as_string("res://web/qiyunju_ime.js")
	_ok(ime.find("shouldSendOnEnter") >= 0 and ime.find("compositionend") >= 0 and ime.find("keyboardOverlapViewport") >= 0, "ime overlay policy")
	var media := FileAccess.get_file_as_string("res://web/qiyunju_media.js")
	_ok(media.find("warmAudio") >= 0 and media.find("pttDown") >= 0 and media.find("startMic") >= 0, "mic warm + ptt starts mic")
	_ok(media.find("0x8000") >= 0 or media.find("fromCharCode.apply") >= 0, "wav encode is chunked")
	var packed := ChatPromptAssembler.new().assemble("chatgpt", [{"role": "user", "content": "看"}], "看这段视频", null, "", 3500, [{"kind": "video", "description": "第1帧：一只白猫"}])
	var sys := str(packed["messages"][0].get("content", ""))
	_ok(sys.find("白猫") >= 0 and sys.find("尚未逐帧") < 0, "video frames injected, stub text gone")


func _test_layout_math() -> void:
	print("== chat layout ==")
	var vp := Vector2(720, 1280)
	var full := ChatLayout.fit_rect(vp, 12, 0)
	_ok(full.position.x >= 0.0 and full.end.x <= vp.x and full.size.x >= 640.0, "portrait panel uses width inside 720 (%s)" % full)
	_ok(full.end.y <= vp.y, "portrait panel inside height")
	var kb := ChatLayout.fit_rect(vp, 12, 420)
	_ok(kb.end.x <= vp.x and kb.end.y <= vp.y - 420.0 + 0.1, "keyboard inset keeps panel above keys (%s)" % kb)
	var bub := ChatLayout.bubble_rect(vp, 0)
	_ok(bub.end.x <= vp.x and bub.end.y <= vp.y and bub.size.x <= 520.0, "bubble stays inside (%s)" % bub)
	var clamped := ChatLayout.clamp_pos(Vector2(900, 1400), bub.size, vp)
	_ok(clamped.x + bub.size.x <= vp.x + 0.1 and clamped.y + bub.size.y <= vp.y + 0.1, "drag clamp")
	_ok(ChatLayout.keyboard_overlap(vp, Vector2(360, 800), 0, 0, 800) == 0.0, "360 closed keyboard")
	_ok(absf(ChatLayout.keyboard_overlap(vp, Vector2(360, 800), 0, 0, 400) - 640.0) < 0.05, "360 open keyboard")
	_ok(ChatLayout.keyboard_overlap(vp, Vector2(390, 844), 0, 0, 844) == 0.0, "390 closed keyboard")
	_ok(ChatLayout.keyboard_overlap(vp, Vector2(430, 932), 0, 0, 932) == 0.0, "430 closed keyboard")
	_ok(ChatLayout.keyboard_overlap(vp, Vector2(390, 420), 0, 0, 420) == 0.0, "resized canvas does not double-inset")
	var land := ChatLayout.keyboard_overlap(vp, Vector2(844, 390), 0, 0, 180)
	var land_expect := (390.0 - 180.0) / (390.0 / 1280.0)
	_ok(absf(land - land_expect) < 0.05, "landscape keyboard overlap")


func _test_vision_and_length() -> void:
	print("== vision and length ==")
	var asm := ChatPromptAssembler.new()
	var story := asm.assemble("claude", [], "can you tell a story")
	var blob := JSON.stringify(story.get("messages", []))
	_ok(blob.find("两到六句") < 0, "story prompt has no hard sentence cap")
	_ok(blob.find("短回复") < 0, "story prompt does not demand a short reply")
	_ok(blob.find("八到十二句") >= 0, "story prompt asks for a fuller story")
	_ok(blob.find("没收到画面") >= 0, "image question without a picture must not be faked")
	var seen := "画面左边是红色方块，右边是蓝色方块，顶上有一条绿色。"
	var stored := ChatVision.compose_stored("can you understand the image?", [{"kind": "image", "description": seen}])
	_ok(stored.find("can you understand the image?") >= 0 and stored.find("真正看到的图片") >= 0 and stored.find("红色") >= 0, "stored turn keeps question and vision")
	var follow := asm.assemble("claude", [
		{"role": "user", "content": stored},
		{"role": "assistant", "content": "左边真的是红的。"},
	], "tell some more you know")
	var follow_blob := JSON.stringify(follow.get("messages", []))
	_ok(follow_blob.find("红色方块") >= 0 and follow_blob.find("蓝色方块") >= 0, "vision text survives the next turn")
	_ok(ChatVision.explain_vision_error("image too large").find("没有画面") >= 0, "oversize vision is a failure")
	_ok(ChatVision.picker_error("file too large").find("18MB") >= 0, "picker explains the size limit")
	var img := Image.create(1600, 900, false, Image.FORMAT_RGB8)
	img.fill(Color(0.8, 0.1, 0.1))
	var raw := img.save_jpg_to_buffer(0.9)
	var prepared := ChatVision.prepare_image(raw, "image/jpeg")
	_ok(bool(prepared.get("ok", false)), "large jpeg prepares")
	var back := Image.new()
	var bytes: PackedByteArray = Marshalls.base64_to_raw(str(prepared.get("b64", "")))
	_ok(back.load_jpg_from_buffer(bytes) == OK, "prepared jpeg decodes")
	_ok(back.get_width() <= 1024 and back.get_height() <= 1024, "prepared image is within 1024 (%dx%d)" % [back.get_width(), back.get_height()])
	_ok(int(prepared.get("bytes", 0)) < 400000, "prepared payload stays small (%s)" % prepared.get("bytes", 0))


func _test_chat_panel_layout() -> void:
	print("== chat panel controls ==")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	# 运行 --script 时过早引用 class_name 会在 Autoload 注册前编译 chat_panel.gd。
	var panel = load("res://scripts/chat/chat_panel.gd").new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(panel)
	panel.open_chat("claude")
	for _i in 6:
		await process_frame
	var vp_rect: Rect2 = panel.get_viewport_rect()
	_ok(vp_rect.size.x >= 700.0 and vp_rect.size.y >= 1200.0, "logical viewport is project size %s" % vp_rect.size)
	_assert_panel_fits(panel, vp_rect, "portrait")
	var bodies := _message_labels(panel)
	_ok(bodies.size() >= 1, "opening chat shows a message")
	if not bodies.is_empty():
		var body: Label = bodies[0]
		_ok(body.autowrap_mode == TextServer.AUTOWRAP_ARBITRARY, "messages wrap")
		_ok(body.custom_minimum_size.x <= 1.0, "message min width does not force overflow")
		_ok(body.get_line_count() >= 2, "long greeting wraps to more than one line (%d)" % body.get_line_count())
		_ok(ChatLayout.inside(vp_rect, body.get_global_rect(), 2.0), "greeting stays inside viewport %s" % body.get_global_rect())
	panel._bubble("user", "你好，world! 混合：标点。（ok）")
	for _j in 3:
		await process_frame
	var mixed := _message_labels(panel)
	if mixed.size() >= 2:
		var line: Label = mixed[mixed.size() - 1]
		_ok(ChatLayout.inside(vp_rect, line.get_global_rect(), 2.0), "mixed punctuation bubble inside %s" % line.get_global_rect())
	panel._keyboard_inset = 420.0
	panel._fit_panel()
	for _k in 3:
		await process_frame
	_assert_panel_fits(panel, vp_rect, "keyboard")
	if panel._panel:
		_ok(panel._panel.get_global_rect().end.y <= vp_rect.size.y - 420.0 + 2.0, "panel bottom above keyboard")
	if panel.input:
		_ok(ChatLayout.inside(vp_rect, panel.input.get_global_rect(), 2.0), "composer inside viewport with keyboard")
	panel._keyboard_inset = 0.0
	panel._web_bubble = true
	panel._panel.position = Vector2.ZERO
	panel._fit_panel()
	for _n in 3:
		await process_frame
	_assert_panel_fits(panel, vp_rect, "bubble")
	if panel._panel:
		_ok(panel._panel.size.x <= 520.0 + 1.0, "bubble width capped")
	var mem = load("res://scripts/chat/memory_view.gd").new()
	host.add_child(mem)
	mem.setup(panel.memory)
	for _m in 3:
		await process_frame
	if mem._panel:
		_ok(ChatLayout.inside(vp_rect, mem._panel.get_global_rect(), 2.0), "memory view inside viewport")
		_ok(mem._panel.get_combined_minimum_size().x <= vp_rect.size.x + 1.0, "memory min width fits")
	mem.queue_free()
	panel.queue_free()
	host.queue_free()


func _assert_panel_fits(panel, vp_rect: Rect2, tag: String) -> void:
	if panel._panel == null:
		_ok(false, tag + " panel exists")
		return
	var prect: Rect2 = panel._panel.get_global_rect()
	_ok(ChatLayout.inside(vp_rect, prect, 1.5), "%s panel inside viewport %s" % [tag, prect])
	_ok(panel._panel.get_combined_minimum_size().x <= vp_rect.size.x + 1.0, "%s panel min width %s <= viewport" % [tag, panel._panel.get_combined_minimum_size()])
	var buttons: Array = []
	_collect_buttons(panel._panel, buttons)
	_ok(buttons.size() >= 8, "%s has header and composer buttons (%d)" % [tag, buttons.size()])
	for b in buttons:
		var btn := b as BaseButton
		if not btn.visible:
			continue
		var br := btn.get_global_rect()
		if not ChatLayout.inside(prect, br, 2.0):
			_ok(false, "%s button '%s' outside panel %s" % [tag, btn.text, br])
		else:
			_ok(true, "%s button '%s' inside" % [tag, btn.text])
	if panel.scroll:
		_ok(panel.scroll.get_h_scroll_bar().max_value <= panel.scroll.size.x + 2.0, "%s no horizontal message scroll" % tag)


func _collect_buttons(n: Node, out: Array) -> void:
	if n is BaseButton:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)


func _message_labels(panel) -> Array:
	var out: Array = []
	if panel.log_box == null:
		return out
	for wrap in panel.log_box.get_children():
		for vb in wrap.get_children():
			for child in vb.get_children():
				if child is Label and (child as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
					var text := (child as Label).text
					if text != "你" and text != "暖阳学者":
						out.append(child)
	return out
