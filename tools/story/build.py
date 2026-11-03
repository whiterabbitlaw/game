import json, sys
sys.path.insert(0, ".")
import lib, s1, s2, s3
out = "../../data"
import os; os.makedirs(out, exist_ok=True)
json.dump(lib.SCENES, open(f"{out}/story.json", "w"), ensure_ascii=False, indent=1)
json.dump(lib.POOLS, open(f"{out}/pools.json", "w"), ensure_ascii=False, indent=1)
chars = set()
txt = ""
for s in lib.SCENES: txt += json.dumps(s, ensure_ascii=False)
txt += json.dumps(lib.POOLS, ensure_ascii=False)
print(len(lib.SCENES), "scenes;", len(lib.POOLS), "pools;", len(txt), "chars")
open("/workspace/story_text.txt", "w").write(txt)
