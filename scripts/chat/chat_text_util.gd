class_name ChatTextUtil
extends RefCounted
## 把模型回复切成适合逐句 TTS 的短句。


static func split_sentences(text: String) -> PackedStringArray:
	var src := text.strip_edges()
	var out: PackedStringArray = []
	if src == "":
		return out
	var buf := ""
	var i := 0
	while i < src.length():
		var ch := src.substr(i, 1)
		buf += ch
		var punct := ch in ["。", "！", "？", "!", "?", "…", "\n"]
		var ellipsis := ch == "." and i + 2 < src.length() and src.substr(i, 3) == "..."
		if ellipsis:
			buf += src.substr(i + 1, 2)
			i += 2
			punct = true
		if punct:
			var piece := buf.strip_edges()
			# 去掉只剩换行的空段
			if piece != "":
				out.append(piece)
			buf = ""
		i += 1
	var tail := buf.strip_edges()
	if tail != "":
		if out.size() > 0 and tail.length() <= 2:
			out[out.size() - 1] = out[out.size() - 1] + tail
		else:
			out.append(tail)
	# 合并过短的碎片（如「嗯。」单独太碎则留下，少于 2 个汉字且后面还有则并到下一句前）
	var merged: PackedStringArray = []
	for s in out:
		if merged.size() > 0 and _is_tiny(merged[merged.size() - 1]):
			merged[merged.size() - 1] = merged[merged.size() - 1] + s
		else:
			merged.append(s)
	return merged


static func _is_tiny(s: String) -> bool:
	var n := 0
	for j in s.length():
		var cp := s.unicode_at(j)
		if cp > 32:
			n += 1
	return n <= 1


static func frame_times(duration: float, count: int = 4) -> PackedFloat32Array:
	## 在时长内均匀取 count 个采样点（避开片头片尾各 8%）。
	var n := clampi(count, 2, 6)
	var times := PackedFloat32Array()
	if duration <= 0.2:
		times.append(maxf(0.0, duration * 0.5))
		return times
	var start := duration * 0.12
	var end := duration * 0.88
	if end <= start:
		times.append(duration * 0.5)
		return times
	for k in n:
		var t := start + (end - start) * (float(k) / float(n - 1))
		times.append(t)
	return times
