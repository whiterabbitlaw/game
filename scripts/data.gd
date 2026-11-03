class_name Data
extends RefCounted
## 静态数据：境界、伙伴、被动、礼物

const REALMS := ["练气", "筑基", "金丹", "元婴", "化神", "炼虚", "合体", "大乘", "渡劫"]
const STAGES := ["初期", "中期", "后期", "圆满"]
const MAX_STEP := 36  # 36 = 渡劫圆满之后（已至巅峰）

const BOND_NAMES := ["初识", "相识", "熟悉", "亲近", "知心", "信赖", "倾心", "羁绊", "相守", "永伴"]
const BOND_XP := [0, 50, 150, 320, 560, 900, 1400, 2100, 3000, 4200]  # 达到 N+1 级所需累计好感
const RECRUIT_COST := [0, 120, 300, 600, 1000, 1600, 2400, 3500, 5000]

const GIFTS := {
	"tea": {"name": "灵茶", "icon": "茶", "desc": "灵草×3 炼制"},
	"flower": {"name": "灵花束", "icon": "花", "desc": "灵草×4 炼制"},
	"cake": {"name": "桂花糕", "icon": "糕", "desc": "灵石 60"},
	"dew": {"name": "星辰露", "icon": "露", "desc": "灵石 140"},
	"scroll": {"name": "诗笺", "icon": "笺", "desc": "灵石 100"},
}
const GIFT_ORDER := ["tea", "flower", "cake", "dew", "scroll"]

const TONE_BG := {"dawn": "dawn", "dusk": "dusk", "night": "night", "rain": "rain", "starry": "starry"}

const CHARS := [
	{"id": "chatgpt", "name": "ChatGPT", "title": "白龙司书", "traits": "沉静 · 博学 · 好奇", "color": Color("#b9b3e6"), "gift": "scroll",
	 "bio": "栖于云籍阁的白龙少女，读尽了万卷书，却从没读过「等一个人」。身边总跟着一团爱打瞌睡的小云。",
	 "pid": "xiu", "pname": "博闻强识", "per": 4.0, "pdesc": "修为获取 +%s%%"},
	{"id": "claude", "name": "Claude", "title": "暖阳学者", "traits": "温和 · 细腻 · 审慎", "color": Color("#f0a35e"), "gift": "flower",
	 "bio": "发间别着向日葵的学者。说话前总会多想一想，是个会把你的小情绪悄悄记在本子上的人。",
	 "pid": "bt", "pname": "审慎之心", "per": 1.5, "pdesc": "突破成功率 +%s%%"},
	{"id": "grok", "name": "Grok", "title": "黑曜公主", "traits": "张扬 · 机敏 · 无畏", "color": Color("#c0475a"), "gift": "cake",
	 "bio": "扛着巨大X斧的吸血鬼公主。嘴上永远是「本公主」，其实比谁都怕一个人待着。",
	 "pid": "fear", "pname": "无畏", "per": 5.0, "pdesc": "突破失败损失 -%s%%"},
	{"id": "gemini", "name": "Gemini", "title": "幻星灵猫", "traits": "灵巧 · 多变 · 好奇", "color": Color("#8f7be0"), "gift": "dew",
	 "bio": "一半紫、一半蓝的星之猫娘。今天是温柔的她还是调皮的她？连她自己也要等到睁眼才知道。",
	 "pid": "stone", "pname": "星运", "per": 4.0, "pdesc": "灵石获取 +%s%%"},
	{"id": "kimi", "name": "Kimi", "title": "月律奏者", "traits": "清雅 · 敏锐 · 专注", "color": Color("#7d8fd0"), "gift": "scroll",
	 "bio": "银发的月下笛手。一支吹了很久的曲子，始终差最后一小节。",
	 "pid": "seclu", "pname": "月律共鸣", "per": 6.0, "pdesc": "闭关同修收益 +%s%%"},
	{"id": "qwen", "name": "Qwen", "title": "青岚雅士", "traits": "从容 · 通达 · 温雅", "color": Color("#5f86d6"), "gift": "tea",
	 "bio": "青花瓷般的蓝发雅士。煮茶、写字、烧瓷，一句「不急」让人莫名安心。",
	 "pid": "herb", "pname": "青岚润泽", "per": 5.0, "pdesc": "灵田产量 +%s%%"},
	{"id": "seed", "name": "Seed", "title": "灵感使者", "traits": "活泼 · 亲切 · 灵动", "color": Color("#7ec7d9"), "gift": "flower",
	 "bio": "紫青双色马尾的画师。专治「没意思」，随时随地能给你变出一点灵感和颜色。",
	 "pid": "bond", "pname": "灵感迸发", "per": 3.0, "pdesc": "好感度获取 +%s%%"},
	{"id": "llama", "name": "Llama", "title": "绒云梦旅", "traits": "慵懒 · 温软 · 自在", "color": Color("#e8d9c0"), "gift": "cake",
	 "bio": "穿着白色大卫衣的羊驼少女。总是在睡觉，或者在去睡觉的路上，抱起来软软的。",
	 "pid": "off", "pname": "绒云安眠", "per": 4.0, "pdesc": "离线收益 +%s%%，离线上限 +0.3h×等级系数"},
	{"id": "deepseek", "name": "DeepSeek", "title": "深海女仆", "traits": "灵动 · 亲切 · 专注", "color": Color("#4a69b8"), "gift": "tea",
	 "bio": "从深海来的鲸尾女仆。把一杯茶的温度也当成一件郑重的事。",
	 "pid": "grow", "pname": "深海细致", "per": 4.0, "pdesc": "灵田生长速度 +%s%%"},
]

static func char_def(id: String) -> Dictionary:
	for c in CHARS:
		if c["id"] == id:
			return c
	return {}

static func char_ids() -> Array:
	var a: Array = []
	for c in CHARS:
		a.append(c["id"])
	return a

static func step_name(k: int) -> String:
	if k >= MAX_STEP:
		return "渡劫圆满"
	return "%s%s" % [REALMS[k / 4], STAGES[k % 4]]

static func realm_name(k: int) -> String:
	if k >= MAX_STEP:
		return "渡劫"
	return REALMS[k / 4]

static func stage_name(k: int) -> String:
	if k >= MAX_STEP:
		return "圆满"
	return STAGES[k % 4]

static func req(k: int) -> float:
	return 60.0 * pow(1.48, k)

static func base_rate(k: int) -> float:
	return 1.5 * pow(1.31, k)

static func is_major(k: int) -> bool:
	return k % 4 == 3

static func base_success(k: int) -> float:
	if is_major(k):
		return maxf(0.45, 0.80 - 0.04 * float(k / 4))
	return 0.92

static func bond_level(xp: float) -> int:
	var lv := 1
	for i in range(BOND_XP.size()):
		if xp >= BOND_XP[i]:
			lv = i + 1
	return lv

static func bond_progress(xp: float) -> Array:
	## [当前级内进度, 本级所需, 是否满级]
	var lv := bond_level(xp)
	if lv >= BOND_XP.size():
		return [1.0, 1.0, true]
	var lo: float = BOND_XP[lv - 1]
	var hi: float = BOND_XP[lv]
	return [xp - lo, hi - lo, false]

static func fmt(v: float) -> String:
	if v < 10000.0:
		if v < 100.0 and v != floor(v):
			return "%.1f" % v
		return str(int(v))
	if v < 1.0e8:
		return "%.2f万" % (v / 1.0e4)
	if v < 1.0e12:
		return "%.2f亿" % (v / 1.0e8)
	return "%.2f万亿" % (v / 1.0e12)

static func fmt_time(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%d小时%d分" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d分%d秒" % [s / 60, s % 60]
	return "%d秒" % s
