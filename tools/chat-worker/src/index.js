/**
 * 栖云居畅聊 Worker。默认 Workers AI Qwen + MeloTTS。
 * 不依赖嵌入在公开网页里的 CHAT_TOKEN（那不算保密）。
 * 用 Origin 白名单 + 每 IP 限流保护免费额度。
 */

const DEFAULT_MODEL = "@cf/qwen/qwen3-30b-a3b-fp8";
const TTS_MODEL = "@cf/myshell-ai/melotts";
const VISION_MODEL = "@cf/meta/llama-3.2-11b-vision-instruct";
const STT_MODEL = "@cf/openai/whisper";
const MAX_MEDIA_CHARS = 1_800_000;
const ALLOWED_EXACT = [
  "https://whiterabbitlaw.github.io",
  "https://qiyunju.pages.dev",
];
const RATE_LIMIT = 45;
const RATE_WINDOW_MS = 60_000;
const hits = new Map();

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    if (origin && !isAllowedOrigin(origin)) {
      return json(origin, { error: "origin not allowed" }, 403);
    }
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }
    const url = new URL(request.url);
    if (request.method === "GET" && (url.pathname === "/health" || url.pathname === "/")) {
      return json(origin, {
        ok: true,
        service: "qiyunju-chat",
        routes: ["/v1/chat", "/v1/tts", "/v1/summarize", "/v1/memory/extract", "/v1/vision", "/v1/stt"],
      });
    }
    if (request.method === "POST") {
      const ip = request.headers.get("CF-Connecting-IP") || request.headers.get("CF-Connecting-IPv6") || "unknown";
      if (!allowIp(ip)) {
        return json(origin, { error: "rate limited" }, 429);
      }
    }
    try {
      if (request.method === "POST" && url.pathname === "/v1/chat") {
        return await handleChat(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/tts") {
        return await handleTts(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/summarize") {
        return await handleSummarize(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/memory/extract") {
        return await handleExtract(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/vision") {
        return await handleVision(request, env, origin);
      }
      if (request.method === "POST" && url.pathname === "/v1/stt") {
        return await handleStt(request, env, origin);
      }
      return json(origin, { error: "not found" }, 404);
    } catch (err) {
      return json(origin, { error: String(err && err.message ? err.message : err) }, 500);
    }
  },
};

function isAllowedOrigin(origin) {
  if (!origin) return true;
  if (ALLOWED_EXACT.includes(origin)) return true;
  try {
    const u = new URL(origin);
    return u.hostname === "localhost" || u.hostname === "127.0.0.1";
  } catch {
    return false;
  }
}

function corsHeaders(origin) {
  const headers = {
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  if (origin && isAllowedOrigin(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

function allowIp(ip) {
  const now = Date.now();
  const next = (hits.get(ip) || []).filter((t) => now - t < RATE_WINDOW_MS);
  if (next.length >= RATE_LIMIT) {
    hits.set(ip, next);
    return false;
  }
  next.push(now);
  hits.set(ip, next);
  return true;
}

async function handleChat(request, env, origin) {
  const body = await readJson(request);
  const messages = Array.isArray(body.messages) ? body.messages : [];
  if (!messages.length) return json(origin, { error: "messages required" }, 400);
  const model = body.model || env.MODEL || DEFAULT_MODEL;
  const text = await generateText(env, messages, model);
  return json(origin, { text, model });
}

async function handleSummarize(request, env, origin) {
  const body = await readJson(request);
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const packed = messages
    .map((m) => `${m.role === "user" ? "玩家" : "她"}：${m.content || ""}`)
    .join("\n")
    .slice(0, 8000);
  const model = body.model || env.MODEL || DEFAULT_MODEL;
  const text = await generateText(
    env,
    [
      {
        role: "system",
        content:
          "把以下对话压缩成简体中文要点摘要，保留承诺、喜好、约定日期和情绪变化。不超过 400 字。只输出摘要。",
      },
      { role: "user", content: packed || "（无对话）" },
    ],
    model,
  );
  return json(origin, { text, model });
}


function detectAudioFormat(audio) {
  if (!audio || typeof audio !== "string") return "mp3";
  try {
    const head = atob(audio.slice(0, 16));
    if (head.startsWith("RIFF") && head.includes("WAVE")) return "wav";
    if (head.startsWith("OggS")) return "ogg";
    if (head.startsWith("ID3") || (head.charCodeAt(0) === 0xff && (head.charCodeAt(1) & 0xe0) === 0xe0)) return "mp3";
  } catch (_) {}
  return "mp3";
}

async function handleTts(request, env, origin) {
  const body = await readJson(request);
  const text = String(body.text || "").trim().slice(0, 400);
  if (!text) return json(origin, { error: "text required" }, 400);
  if (!env.AI) return json(origin, { error: "Workers AI binding missing" }, 500);
  const lang = body.lang || "ZH";
  const result = await env.AI.run(TTS_MODEL, { prompt: text, lang });
  const audio = result && (result.audio || result.result?.audio) ? result.audio || result.result.audio : "";
  if (!audio) return json(origin, { error: "tts returned no audio" }, 502);
  return json(origin, { audio, format: detectAudioFormat(audio), model: TTS_MODEL, lang });
}

async function handleExtract(request, env, origin) {
  const body = await readJson(request);
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const packed = messages
    .map((m) => `${m.role === "user" ? "玩家" : "她"}：${m.content || ""}`)
    .join("\n")
    .slice(0, 8000);
  const model = body.model || env.MODEL || DEFAULT_MODEL;
  const text = await generateText(
    env,
    [
      {
        role: "system",
        content:
          '从对话里抽取关于玩家的长期事实。只输出 JSON，不要 markdown。格式：{"facts":[{"kind":"name|like|date|promise|other","text":"简短中文陈述","keys":["关键词"],"shared":true}]}。kind：name 称呼姓名，like 喜好，date 生日或约定日期，promise 承诺。没有就 {"facts":[]}。',
      },
      { role: "user", content: packed || "（无对话）" },
    ],
    model,
  );
  return json(origin, { facts: parseFacts(text), raw: text, model });
}

function parseFacts(text) {
  const raw = String(text || "").trim();
  const sliced = raw.replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
  const start = sliced.indexOf("{");
  const end = sliced.lastIndexOf("}");
  if (start < 0 || end <= start) return [];
  try {
    const obj = JSON.parse(sliced.slice(start, end + 1));
    const facts = Array.isArray(obj.facts) ? obj.facts : Array.isArray(obj) ? obj : [];
    return facts
      .filter((f) => f && (f.text || f.fact))
      .map((f) => ({
        kind: String(f.kind || "other"),
        text: String(f.text || f.fact || "").trim(),
        keys: Array.isArray(f.keys) ? f.keys.map(String) : [],
        shared: f.shared !== false,
        date: f.date ? String(f.date) : "",
      }))
      .filter((f) => f.text);
  } catch {
    return [];
  }
}

async function handleVision(request, env, origin) {
  const body = await readJson(request);
  const image = String(body.image || "").replace(/^data:[^;]+;base64,/, "");
  const prompt = String(body.prompt || "请用简体中文简要描述这张图片里有什么，不超过 120 字。").slice(0, 400);
  if (!image) return json(origin, { error: "image required" }, 400);
  if (image.length > MAX_MEDIA_CHARS) return json(origin, { error: "image too large" }, 413);
  if (!env.AI) return json(origin, { error: "Workers AI binding missing" }, 500);
  const mime = String(body.mime || "image/jpeg");
  let result;
  try {
    result = await env.AI.run(VISION_MODEL, {
      messages: [
        {
          role: "user",
          content: [
            { type: "image_url", image_url: { url: `data:${mime};base64,${image}` } },
            { type: "text", text: prompt },
          ],
        },
      ],
    });
  } catch (e1) {
    try {
      result = await env.AI.run(VISION_MODEL, { image, prompt });
    } catch (e2) {
      return json(origin, { error: String(e2 && e2.message ? e2.message : e2), model: VISION_MODEL }, 502);
    }
  }
  const text = extractText(result);
  if (!text) return json(origin, { error: "vision returned no text", model: VISION_MODEL }, 502);
  return json(origin, { text, model: VISION_MODEL });
}

async function handleStt(request, env, origin) {
  const body = await readJson(request);
  const audioB64 = String(body.audio || "").replace(/^data:[^;]+;base64,/, "");
  if (!audioB64) return json(origin, { error: "audio required" }, 400);
  if (audioB64.length > MAX_MEDIA_CHARS) return json(origin, { error: "audio too large" }, 413);
  if (!env.AI) return json(origin, { error: "Workers AI binding missing" }, 500);
  let bin;
  try {
    bin = Uint8Array.from(atob(audioB64), (c) => c.charCodeAt(0));
  } catch {
    return json(origin, { error: "invalid audio base64" }, 400);
  }
  if (bin.length > 1_200_000) return json(origin, { error: "audio too large" }, 413);
  const result = await env.AI.run(STT_MODEL, { audio: Array.from(bin) });
  const text = (result && (result.text || result.result?.text)) || extractText(result);
  return json(origin, { text: String(text || "").trim(), model: STT_MODEL, format: body.format || "" });
}

async function generateText(env, messages, model) {

  const clean = messages
    .filter((m) => m && m.content)
    .map((m) => ({
      role: m.role === "assistant" || m.role === "system" || m.role === "user" ? m.role : "user",
      content: String(m.content),
    }));
  if (env.GEMINI_API_KEY) {
    return geminiGenerate(env.GEMINI_API_KEY, clean, env.GEMINI_MODEL || "gemini-2.5-flash");
  }
  if (!env.AI) throw new Error("Workers AI binding missing, and no GEMINI_API_KEY");
  const result = await env.AI.run(model, { messages: clean });
  return extractText(result);
}

async function geminiGenerate(apiKey, messages, model) {
  const system = messages.filter((m) => m.role === "system").map((m) => m.content).join("\n\n");
  const contents = messages
    .filter((m) => m.role !== "system")
    .map((m) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.content }],
    }));
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: system ? { parts: [{ text: system }] } : undefined,
      contents,
      generationConfig: { maxOutputTokens: 512, temperature: 0.85 },
    }),
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data.error?.message || `Gemini HTTP ${res.status}`);
  }
  const text = data.candidates?.[0]?.content?.parts?.map((p) => p.text || "").join("") || "";
  return text.trim();
}

function extractText(result) {
  if (!result) return "";
  if (typeof result === "string") return stripThink(result);
  if (typeof result.response === "string") return stripThink(result.response);
  if (typeof result.result === "string") return stripThink(result.result);
  if (typeof result.result?.response === "string") return stripThink(result.result.response);
  const choice = result.choices?.[0];
  if (choice?.message?.content) return stripThink(choice.message.content);
  if (Array.isArray(result)) {
    return stripThink(result.map((x) => (typeof x === "string" ? x : x.response || x.text || "")).join(""));
  }
  return stripThink(JSON.stringify(result));
}

function stripThink(text) {
  return String(text || "")
    .replace(/<think>[\s\S]*?<\/think>/gi, "")
    .trim();
}

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    return {};
  }
}

function json(origin, obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...corsHeaders(origin) },
  });
}
