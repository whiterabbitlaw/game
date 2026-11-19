/**
 * 时事检索。默认关闭。
 * rss 只拉固定的 BBC 世界新闻 RSS，不是全网搜索。
 * 问题正文不会拼进对外部的 URL。
 */

export const RSS_FEED = {
  id: "bbc-world",
  source: "BBC News",
  label: "BBC 世界新闻 RSS。这不是全网搜索，只含这一份公开标题源。",
  url: "https://feeds.bbci.co.uk/news/world/rss.xml",
  host: "feeds.bbci.co.uk",
};

const MAX_QUERY = 160;
const MAX_ITEMS = 6;
const MAX_REDIRECTS = 2;
const FETCH_MS = 8000;

export function newsCapability(env) {
  const provider = String((env && env.NEWS_PROVIDER) || "").trim().toLowerCase();
  if (provider === "rss") {
    return {
      enabled: true,
      kind: "headlines",
      label: RSS_FEED.label,
      source: RSS_FEED.id,
    };
  }
  return {
    enabled: false,
    kind: "none",
    label: "未配置公开检索",
    missing:
      "Worker 变量 NEWS_PROVIDER 未设置。设为 rss 也只接通 BBC 世界新闻标题，不是全网搜索。一般网页检索没有可免密钥使用的官方接口；Brave、Bing 或其他搜索需要协调者单独同意账号、费用和密钥，密钥不能放进客户端。",
  };
}

export function isBlockedTarget(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return true;
  }
  if (url.protocol !== "https:") return true;
  if (url.username || url.password) return true;
  const host = url.hostname.toLowerCase().replace(/\.+$/, "");
  if (!host || host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local")) return true;
  if (host === "metadata.google.internal" || host.includes("metadata")) return true;
  if (host === "::1" || host === "[::1]") return true;
  const v4 = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (v4) {
    const a = Number(v4[1]);
    const b = Number(v4[2]);
    if (a === 0 || a === 10 || a === 127) return true;
    if (a === 169 && b === 254) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 100 && b >= 64 && b <= 127) return true;
  }
  return false;
}

export function sanitizeExcerpt(raw) {
  return String(raw || "")
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/[\u0000-\u001f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 280);
}

export function parseRss(xml, nowMs) {
  const items = [];
  const chunks = String(xml || "").split(/<item\b/i).slice(1);
  for (const chunk of chunks) {
    if (items.length >= MAX_ITEMS) break;
    const title = sanitizeExcerpt(tag(chunk, "title"));
    const link = String(tag(chunk, "link") || "").trim();
    const published = String(tag(chunk, "pubDate") || "").trim();
    const excerpt = sanitizeExcerpt(tag(chunk, "description"));
    if (!title || isBlockedTarget(link)) continue;
    let host = "";
    try { host = new URL(link).hostname.toLowerCase(); } catch { continue; }
    const publishedMs = Date.parse(published);
    items.push({
      title,
      url: link,
      source: RSS_FEED.source,
      published: Number.isFinite(publishedMs) ? new Date(publishedMs).toISOString() : "",
      published_raw: published,
      excerpt,
      host,
      age_hours: Number.isFinite(publishedMs) && nowMs ? (nowMs - publishedMs) / 36e5 : null,
    });
  }
  return items;
}

export function coversQuery(items, query) {
  const tokens = queryTokens(query);
  if (!tokens.length) return [];
  return items.filter((item) => {
    const hay = (item.title + " " + item.excerpt).toLowerCase();
    return tokens.every((token) => hay.includes(token));
  });
}

export function queryTokens(query) {
  const text = String(query || "").toLowerCase();
  const latin = text.match(/[a-z0-9]{3,}/g) || [];
  const cjk = text.match(/[\u4e00-\u9fff]{2,}/g) || [];
  const stop = new Set(["什么", "是否", "已经", "今天", "刚刚", "最新", "新闻", "消息", "现在", "这个", "那个"]);
  return [...latin, ...cjk].map((t) => t.trim()).filter((t) => t && !stop.has(t)).slice(0, 6);
}

function tag(chunk, name) {
  const m = chunk.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`, "i"));
  return m ? m[1] : "";
}

async function fetchAllowlisted(url, hops) {
  if (isBlockedTarget(url)) throw new Error("blocked url");
  const host = new URL(url).hostname.toLowerCase();
  if (host !== RSS_FEED.host && hops === 0) throw new Error("feed host not allowlisted");
  if (host !== RSS_FEED.host && host !== "www.bbc.com" && host !== "bbc.co.uk" && !host.endsWith(".bbci.co.uk")) {
    throw new Error("redirect host not allowlisted");
  }
  const response = await fetch(url, {
    method: "GET",
    redirect: "manual",
    headers: { "Accept": "application/rss+xml, application/xml, text/xml" },
    signal: AbortSignal.timeout(FETCH_MS),
  });
  if (response.status >= 300 && response.status < 400) {
    if (hops >= MAX_REDIRECTS) throw new Error("too many redirects");
    const next = response.headers.get("Location");
    if (!next) throw new Error("redirect missing location");
    return fetchAllowlisted(new URL(next, url).toString(), hops + 1);
  }
  if (!response.ok) throw new Error("feed http " + response.status);
  const text = await response.text();
  if (text.length > 1_500_000) throw new Error("feed too large");
  return text;
}

export async function retrieveHeadlines(query, nowMs, fetchXml) {
  const q = String(query || "").trim().slice(0, MAX_QUERY);
  const loader = fetchXml || ((url) => fetchAllowlisted(url, 0));
  const xml = await loader(RSS_FEED.url);
  const items = parseRss(xml, nowMs || Date.now());
  const matched = coversQuery(items, q);
  return {
    enabled: true,
    kind: "headlines",
    label: RSS_FEED.label,
    source: RSS_FEED.id,
    query: q,
    retrieved_at: new Date(nowMs || Date.now()).toISOString(),
    covers: matched.length > 0,
    items: matched.length ? matched : items.slice(0, 3),
    note: matched.length
      ? "只转述标题源里能对上问题用词的条目，标题不是已经核实的结论。"
      : "这份标题源的最近条目对不上这个问题。不能据此确认，也没有改用别的搜索。",
  };
}

export async function answerNewsRequest(env, query, nowMs, fetchXml) {
  const capability = newsCapability(env);
  const q = String(query || "").trim().slice(0, MAX_QUERY);
  if (!q) return { ...capability, enabled: false, items: [], error: "query required" };
  if (!capability.enabled) return { ...capability, items: [], query: q, retrieved_at: new Date(nowMs || Date.now()).toISOString() };
  try {
    return await retrieveHeadlines(q, nowMs, fetchXml);
  } catch (err) {
    return {
      ...capability,
      items: [],
      covers: false,
      query: q,
      retrieved_at: new Date(nowMs || Date.now()).toISOString(),
      error: "feed_unavailable",
      note: String(err && err.message ? err.message : err).slice(0, 160),
    };
  }
}
