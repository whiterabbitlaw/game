extends SceneTree
# 运行：godot --headless --path . --script res://tests/voice_test.gd
# 统计：游戏数据里的每句台词是否都能通过 Voice.say 的查表逻辑找到音频；以及映射表里每个 ID 是否都能从游戏代码路径到达。

func _initialize() -> void:
	await create_timer(0.2).timeout
	var G = root.get_node("Game")
	var V = root.get_node("Voice")
	var reached := {}
	var miss: Array = []
	var chars: Array = []
	for c in Data.CHARS:
		chars.append(c["id"])
	var look := func(who: String, text: String, tag: String) -> void:
		var id: String = V.id_for(who, text)
		if id != "" and V.has_voice(id):
			reached[id] = true
		else:
			miss.append("%s %s %s" % [tag, who, text.substr(0, 20)])
	# pools（互动）
	for c in chars:
		var p: Dictionary = G.pools[c]
		for t in p["chat"]:
			look.call(c, t["l"], "chat_q")
			for o in t["c"]:
				look.call(c, o[1], "chat_a")
		for k in ["tea", "star", "poke", "letters"]:
			for t in p.get(k, []):
				look.call(c, t, k)
		for k in ["med_start", "med_done", "gift_like", "gift_ok", "bt"]:
			look.call(c, p[k], k)
		look.call(c, "「早安！今天也一起好好修行吧。」", "greet")
	var bt = load("res://scripts/breakthrough.gd")
	for c in bt.FAIL_LINES.keys():
		look.call(c, bt.FAIL_LINES[c], "btfail")
	# story：与 Dialogue._say 相同的解析
	var story_total := [0]
	var walk := func(line: String, sid: String) -> void:
		var parts := line.split("|", true, 1)
		var who := parts[0].split(":", true, 1)[0]
		if who == "n" or who == "p" or not (who in chars):
			return
		story_total[0] += 1
		look.call(who, parts[1] if parts.size() > 1 else "", "story:" + sid)
	for sc in G.scenes:
		for e in sc["lines"]:
			if typeof(e) == TYPE_STRING:
				walk.call(e, sc["id"])
			elif typeof(e) == TYPE_DICTIONARY and e.has("c"):
				for ch in e["c"]:
					for r in ch.get("r", []):
						walk.call(r, sc["id"])
	# 映射表里的 ID 是否都被到达
	var ids := {}
	for k in V.map.keys():
		ids[V.map[k]] = true
	var unreached: Array = []
	for id in ids.keys():
		if not reached.has(id):
			unreached.append(id)
	print("VOICE map ids=", ids.size(), " reached=", reached.size(), " story_lines=", story_total[0])
	print("VOICE game lines without voice: ", miss.size(), " ", miss)
	print("VOICE ids unreachable from game data: ", unreached.size(), " ", unreached)
	# 播放烟测
	V.play_id("pl_grok_bt")
	print("VOICE play ok: ", V.cur_id == "pl_grok_bt", " missing silently: ", not V.play_id("pl_grok_nonexistent"))
	quit()
