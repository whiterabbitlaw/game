extends SceneTree
# 运行：godot --headless --path . --script res://tests/logic_test.gd

func _initialize() -> void:
	await create_timer(0.2).timeout
	var G = root.get_node("Game")
	G.reset_all()
	var ok := true
	G.recruit("kimi", true)
	G.set_main("kimi")
	print("recruited: ", G.recruited_ids(), " main=", G.s["main"])
	G.s["xiu"] = Data.req(0) + 1.0
	print("can bt: ", G.can_breakthrough(), " chance ", G.success_chance())
	G.debug_force = 1
	var r = G.attempt_breakthrough()
	print("bt: ", r, " step=", G.s["step"])
	# bond / unlock
	G.add_bond("kimi", 400.0)
	print("bond lv ", G.bond_lv("kimi"), " scene2 ", G.scene_status("kimi_s2"), " scene3 ", G.scene_status("kimi_s3"))
	G.s["step"] = 12
	print("scene3 after step12 bond ", G.scene_status("kimi_s3"))
	G.add_bond("kimi", 1200.0)
	print("scene3 now: ", G.scene_status("kimi_s3"), " bondlv ", G.bond_lv("kimi"))
	# offline
	G.s["last_save"] = Time.get_unix_time_from_system() - 7200.0
	var off = G.process_offline()
	print("offline: xiu=", off.get("xiu"), " stone=", off.get("stone"), " letter? ", off.get("letter", "") != "")
	# seclusion
	G.start_seclusion("kimi", 1.0)
	G.s["sec"]["end"] = Time.get_unix_time_from_system() - 1.0
	G.check_seclusion()
	print("sec active after: ", G.sec_active())
	# garden
	G.s["plots"][0] = {"t": Time.get_unix_time_from_system() - 999.0, "g": true}
	print("plot0 ", G.plot_state(0), " harvest ", G.harvest(0), " herb ", G.s["herb"])
	print("craft tea: ", G.craft("tea"), " gifts ", G.s["gifts"])
	# daily
	print("daily: ", G.daily_claim())
	print("daily again: ", G.daily_claim())
	# save/load roundtrip
	G.save_game()
	var before = G.s["step"]
	G.load_game()
	print("roundtrip step ", before, "->", G.s["step"], " kimi bond ", G.bond_xp("kimi"))
	# every scene: line count
	var n := 0
	for sc in G.scenes:
		n += sc["lines"].size()
	print("scenes ", G.scenes.size(), " entries ", n)
	G.reset_all()
	quit()
