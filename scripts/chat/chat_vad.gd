class_name ChatVAD
extends RefCounted
## 简单能量 VAD：超过阈值开始说话，静音超时后结束。供桌面采集与单元测试使用。

var threshold := 0.025
var barge_threshold := 0.06
var silence_ms := 900
var min_speech_ms := 280
var sample_rate := 16000
var speaking := false
var barge_in := false

var _speech_ms := 0.0
var _silence_ms := 0.0
var _barge_ms := 0.0


func reset() -> void:
	speaking = false
	barge_in = false
	_speech_ms = 0.0
	_silence_ms = 0.0
	_barge_ms = 0.0


func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var acc := 0.0
	for v in samples:
		acc += v * v
	return sqrt(acc / float(samples.size()))


## 喂入一帧。返回 "" 或 "start" / "end" / "barge"。
func feed(samples: PackedFloat32Array, tts_playing: bool = false) -> String:
	var level := rms(samples)
	var dt := 1000.0 * float(samples.size()) / float(maxi(sample_rate, 1))
	if tts_playing and not speaking:
		if level >= barge_threshold:
			_barge_ms += dt
			if _barge_ms >= 180.0:
				_barge_ms = 0.0
				speaking = true
				_speech_ms = 0.0
				_silence_ms = 0.0
				barge_in = true
				return "barge"
		else:
			_barge_ms = 0.0
		return ""
	if not speaking:
		if level >= threshold:
			_speech_ms += dt
			if _speech_ms >= min_speech_ms:
				speaking = true
				_silence_ms = 0.0
				return "start"
		else:
			_speech_ms = 0.0
		return ""
	if level < threshold:
		_silence_ms += dt
		if _silence_ms >= float(silence_ms) and _speech_ms >= min_speech_ms:
			speaking = false
			_speech_ms = 0.0
			_silence_ms = 0.0
			return "end"
	else:
		_silence_ms = 0.0
		_speech_ms += dt
	return ""


static func write_wav(pcm: PackedByteArray, rate: int = 16000) -> PackedByteArray:
	var data_size := pcm.size()
	var out := PackedByteArray()
	out.resize(44 + data_size)
	# RIFF header
	out.encode_u32(0, 0x46464952)  # will overwrite properly below via ascii
	# Use raw append for clarity
	out = PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	_u32(out, 36 + data_size)
	out.append_array("WAVEfmt ".to_ascii_buffer())
	_u32(out, 16)
	_u16(out, 1)
	_u16(out, 1)
	_u32(out, rate)
	_u32(out, rate * 2)
	_u16(out, 2)
	_u16(out, 16)
	out.append_array("data".to_ascii_buffer())
	_u32(out, data_size)
	out.append_array(pcm)
	return out


static func floats_to_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	var i := 0
	for s in samples:
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		pcm.encode_s16(i, v)
		i += 2
	return pcm


static func _u16(out: PackedByteArray, v: int) -> void:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, v)
	out.append_array(b)


static func _u32(out: PackedByteArray, v: int) -> void:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	out.append_array(b)
