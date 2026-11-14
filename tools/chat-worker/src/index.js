/**
 * 栖云居畅聊 Worker。无密钥入仓。未设置 CHAT_TOKEN 时不鉴权，仅供本地开发。
 */

const DEFAULT_MODEL = "@cf/qwen/qwen3-30b-a3b-fp8";
const TTS_MODEL = "@cf/myshell-ai/melotts";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "qiyunju-chat" });
    }
    const authErr = unauthorized(request, env);
    if (authErr) return authErr;
    try {
      if (request.method === "POST" && url.pathname === "/v1/chat") {
        return await handleChat(request, env);
      }
      if (request.method === "POST" && url.pathname === "/v1/tts") {
        return await handleTts(request, env);
      }
      if (request.method === "POST" && url.pathname === "/v1/summarize") {
        return await handleSummarize(request, env);
      }
      return json({ error: "not found" }, 404);
    } catch (err) {
      return json({ error: String(err && err.message ? err.message : err) }, 500);
    }
  },
};

function unauthorized(request, env) {
  const token = env.CHAT_TOKEN;
  if (!token) return null;
  const header = request.headers.get("Authorization") || "";
  const got = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (got && got === token) return null;
  return json({ error: "unauthorized" }, 401);
}

async function handleChat(request, env) {
  const body = await readJson(request);
  const messages = Array.isArray(body.messages) ? body.messages : [];
  if (!messages.length) return json({ error: "messages required" }, 400);
  const model = body.model || env.MODEL || DEFAULT_MODEL;
  const text = await generateText(env, messages, model);
  return json({ text, model });
}

async function handleSummarize(request, env) {
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
  return json({ text, model });
}

async function handleTts(request, env) {
  const body = await readJson(request);
  const text = String(body.text || "").trim().slice(0, 400);
  if (!text) return json({ error: "text required" }, 400);
  if (!env.AI) return json({ error: "Workers AI binding missing" }, 500);
  const lang = body.lang || "ZH";
  const result = await env.AI.run(TTS_MODEL, { prompt: text, lang });
  const audio = result && (result.audio || result.result?.audio) ? result.audio || result.result.audio : "";
  if (!audio) return json({ error: "tts returned no audio" }, 502);
  return json({ audio, format: "mp3", model: TTS_MODEL, lang });
}

async function generateText(env, messages, model) {
  const clean = messages
    .filter((m) => m && m.content)
    .map((m) => ({
      role: m.role === "assistant" || m.role === "system" || m.role === "user" ? m.role : "user",
      content: String(m.content),
    }));
  if (env.GEMINI_API_KEY) {
    return geminiGenerate(env.GEMINI_API_KEY, clean, env.GEMINI_MODEL || "gemini-3.8-flash");
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

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS },
  });
}
