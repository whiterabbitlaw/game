# Story authoring helpers. Lines are "speaker[:emote]|text". speaker: n=旁白, p=你, or a character id.
SCENES = []
POOLS = {}

def O(text, bond, lines):
    return {"t": text, "b": bond, "r": lines}

def C(*opts):
    return {"c": list(opts)}

def S(char, n, title, place, tone, bond, step, lines):
    SCENES.append({"id": f"{char}_s{n}", "char": char, "n": n, "title": title, "place": place,
                   "tone": tone, "req_bond": bond, "req_step": step, "lines": lines})

def P(char, chat, tea, star, med_start, med_done, gift_like, gift_ok, poke, letters, bt):
    """chat: list of (line, [(opt, reply),(opt, reply)])"""
    POOLS[char] = {
        "chat": [{"l": l, "c": [[a, b] for a, b in c]} for l, c in chat],
        "tea": tea, "star": star, "med_start": med_start, "med_done": med_done,
        "gift_like": gift_like, "gift_ok": gift_ok, "poke": poke, "letters": letters, "bt": bt}
