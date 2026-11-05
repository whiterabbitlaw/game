#!/usr/bin/env python3
"""由 TTS 的 lines.json 生成 data/voice_map.json：{"角色|游戏原文": 台词ID}，仅包含 audio/voice 里存在的音频。"""
import json, os, sys
lines = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "/workspace/tts/colab/lines.json", encoding="utf-8"))["lines"]
root = os.path.join(os.path.dirname(__file__), "..")
m = {}
for r in lines:
    if os.path.exists(os.path.join(root, "audio/voice", r["character"], r["id"] + ".ogg")):
        m[r["character"] + "|" + r["text_src"].strip()] = r["id"]
json.dump(m, open(os.path.join(root, "data/voice_map.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print(len(m), "entries")
