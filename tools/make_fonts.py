import glob, io
from fontTools.ttLib import TTCollection, TTFont
from fontTools import subset
chars=set(chr(c) for c in range(0x20,0x7f))
for hi in range(0xB0,0xF8):
    for lo in range(0xA1,0xFF):
        try: chars.add(bytes([hi,lo]).decode("gb2312"))
        except: pass
for hi in range(0xA1,0xA8):
    for lo in range(0xA1,0xFF):
        try: chars.add(bytes([hi,lo]).decode("gb2312"))
        except: pass
for f in glob.glob("data/*.json")+glob.glob("scripts/*.gd"):
    chars|=set(open(f,encoding="utf8").read())
chars|=set("♥♡♪★☆✦✧·…—「」『』～×÷↑↓→←✓✔●○◆◇▲▼⭐")
chars={c for c in chars if c not in "\n\r\t"}
def sub(font, out, num=None):
    opts=subset.Options(); opts.layout_features=["*"]; opts.notdef_outline=True; opts.name_IDs=["*"]; opts.hinting=False
    if num is not None:
        f=TTCollection(font).fonts[num]
    else: f=TTFont(font)
    cm=f.getBestCmap(); miss=[c for c in "♥♡♪★☆✦✧" if ord(c) not in cm]
    print(out,"missing:",miss)
    s=subset.Subsetter(opts); s.populate(text="".join(chars)); s.subset(f); 
    f.flavor=None; f.save(out)
def sc_index(path):
    c=TTCollection(path)
    for i,f in enumerate(c.fonts):
        if "SC" in f["name"].getDebugName(1): return i
sub("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc","assets/fonts/NotoSansSC-Regular.otf",sc_index("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"))
sub("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc","assets/fonts/NotoSansSC-Bold.otf",sc_index("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"))
sub("/usr/share/fonts/truetype/sand-box/google/Ma Shan Zheng/MaShanZheng-Regular.ttf","assets/fonts/MaShanZheng.ttf")
