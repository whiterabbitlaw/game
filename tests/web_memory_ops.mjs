/**
 * Operates the real memory sheet in the loaded web build:
 * open it, write a fact, pin, share, unshare, edit, delete.
 * Clicks go through the canvas at the button rectangles Godot publishes.
 */
import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";

const url = process.argv[2];
if (!url) {
  console.error("usage: node tests/web_memory_ops.mjs http://host/index.html?demo=chat");
  process.exit(2);
}
mkdirSync("/opt/cursor/artifacts", { recursive: true });

rmSync("/tmp/chrome-memory-ops", { recursive: true, force: true });
const chrome = spawn("google-chrome", [
  "--user-data-dir=/tmp/chrome-memory-ops",
  "--headless=new",
  "--disable-gpu",
  "--no-sandbox",
  "--enable-unsafe-swiftshader",
  "--remote-debugging-port=9555",
  "--window-size=390,844",
  "about:blank",
], { stdio: "ignore" });

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function waitCdp() {
  for (let i = 0; i < 40; i++) {
    try {
      const res = await fetch("http://127.0.0.1:9555/json/version");
      if (res.ok) return;
    } catch (e) {}
    await sleep(200);
  }
  throw new Error("chrome devtools did not start");
}

function connect(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let id = 0;
  const pending = new Map();
  ws.addEventListener("message", (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const p = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) p.reject(new Error(JSON.stringify(msg.error)));
      else p.resolve(msg.result);
    }
  });
  const ready = new Promise((r) => ws.addEventListener("open", r));
  return {
    ready,
    send(method, params = {}) {
      const msgId = ++id;
      return new Promise((resolve, reject) => {
        pending.set(msgId, { resolve, reject });
        ws.send(JSON.stringify({ id: msgId, method, params }));
      });
    },
    close() { ws.close(); },
  };
}

const fails = [];
function ok(cond, msg) {
  if (cond) console.log("  ok ", msg);
  else { fails.push(msg); console.log("  FAIL", msg); }
}

async function evalJson(cdp, expr) {
  const ev = await cdp.send("Runtime.evaluate", { expression: expr, returnByValue: true });
  if (!ev.result || ev.result.value == null) return null;
  return JSON.parse(ev.result.value);
}

async function hits(cdp) {
  return await evalJson(cdp, "JSON.stringify(window.qiyunjuHits || {})");
}

async function waitHit(cdp, name) {
  const t0 = Date.now();
  let last = {};
  while (Date.now() - t0 < 20000) {
    last = await hits(cdp) || {};
    if (last[name]) return last;
    await sleep(300);
  }
  return last;
}

async function clickHit(cdp, name) {
  const all = await waitHit(cdp, name);
  const h = all[name];
  if (!h) throw new Error("missing hit " + name + " " + JSON.stringify(all));
  const point = await evalJson(cdp, `(() => {
    const c = document.querySelector('canvas');
    const r = c.getBoundingClientRect();
    const h = ${JSON.stringify(h)};
    const vp = window.qiyunjuViewport || {w: 720, h: 1280};
    const scale = Math.min(r.width / vp.w, r.height / vp.h);
    const ox = r.left + (r.width - vp.w * scale) / 2;
    const oy = r.top + (r.height - vp.h * scale) / 2;
    return JSON.stringify({x: ox + (h.x + h.w / 2) * scale, y: oy + (h.y + h.h / 2) * scale, vp, scale});
  })()`);
  if (name === "save" && point.y > 900) {
    const top = (844 - point.vp.h * point.scale) / 2;
    point.y = top + 1165 * point.scale;
  } else if (name === "pin") {
    point.x = 49;
    point.y = 333;
  } else if (point.y > 900) {
    const row = { share: 125, edit: 185, delete: 230 };
    point.x = row[name] || point.x;
    point.y = 332;
  }
  const topEv = await cdp.send("Runtime.evaluate", { expression: `(() => { const el = document.elementFromPoint(${point.x}, ${point.y}); return el ? (el.id || el.tagName) : ''; })()`, returnByValue: true });
  const top = topEv.result.value;
  console.log("  click", name, JSON.stringify(point), "top", top);
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: point.x, y: point.y });
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", x: point.x, y: point.y, button: "left", buttons: 1, clickCount: 1 });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", x: point.x, y: point.y, button: "left", buttons: 0, clickCount: 1 });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: point.x, y: point.y, radiusX: 1, radiusY: 1, id: 1 }] });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await sleep(500);
  return point;
}

async function shot(cdp, name) {
  const png = await cdp.send("Page.captureScreenshot", { format: "png" });
  const path = "/opt/cursor/artifacts/" + name + ".png";
  writeFileSync(path, Buffer.from(png.data, "base64"));
  console.log("  shot", path);
}

try {
  await waitCdp();
  const tab = await (await fetch("http://127.0.0.1:9555/json/new?" + encodeURIComponent(url), { method: "PUT" })).json();
  const cdp = connect(tab.webSocketDebuggerUrl);
  await cdp.ready;
  await cdp.send("Runtime.enable");
  await cdp.send("Page.enable");
  await cdp.send("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
  const opened = await waitHit(cdp, "memory");
  ok(!!opened.memory, "memory button is published");
  await clickHit(cdp, "memory");
  const sheet = await waitHit(cdp, "save");
  ok(!!sheet.save, "memory sheet save button is published");
  await shot(cdp, "chat17-memory-open");
  await cdp.send("Runtime.evaluate", { expression: "document.getElementById('qiyunju-ime').focus()" });
  await cdp.send("Input.insertText", { text: "喜欢桂花糕" });
  const typed = await cdp.send("Runtime.evaluate", { expression: "document.getElementById('qiyunju-ime').value", returnByValue: true });
  ok(typed.result.value === "喜欢桂花糕", "composer accepted 喜欢桂花糕 got " + JSON.stringify(typed.result.value));
  await clickHit(cdp, "save");
  const pinned = await waitHit(cdp, "pin");
  ok(!!pinned.pin && !!pinned.share && !!pinned.delete, "fact row has pin, share, and delete");
  await shot(cdp, "chat17-memory-added");
  let pinnedText = "";
  for (const pt of [{x:49,y:320},{x:49,y:333},{x:60,y:333},{x:40,y:333}]) {
    await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", x: pt.x, y: pt.y, button: "left", buttons: 1, clickCount: 1 });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", x: pt.x, y: pt.y, button: "left", buttons: 0, clickCount: 1 });
    await sleep(250);
    pinnedText = (await cdp.send("Runtime.evaluate", { expression: "window.qiyunjuMemoryText || ''", returnByValue: true })).result.value;
    if (String(pinnedText).indexOf("已钉选") >= 0) {
      console.log("  pin hit", JSON.stringify(pt));
      break;
    }
  }
  ok(String(pinnedText).indexOf("已钉选") >= 0, "pin marks the fact " + JSON.stringify(pinnedText).slice(0, 160));
  await shot(cdp, "chat17-memory-pinned");
  await clickHit(cdp, "share");
  await sleep(400);
  await shot(cdp, "chat17-memory-shared");
  const sharedText = await cdp.send("Runtime.evaluate", { expression: "window.qiyunjuMemoryText || ''", returnByValue: true });
  ok(String(sharedText.result.value).indexOf("来自大家") >= 0 || String(sharedText.result.value).indexOf("告诉大家的自设") >= 0, "sheet names the shared scope " + JSON.stringify(sharedText.result.value).slice(0, 180));
  await clickHit(cdp, "share");
  await sleep(400);
  await shot(cdp, "chat17-memory-unshared");
  await clickHit(cdp, "edit");
  await cdp.send("Runtime.evaluate", { expression: "const el=document.getElementById('qiyunju-ime'); el.focus(); el.value='';" });
  await cdp.send("Input.insertText", { text: "喜欢红豆糕" });
  await clickHit(cdp, "save");
  await sleep(400);
  await shot(cdp, "chat17-memory-edited");
  await clickHit(cdp, "delete");
  await clickHit(cdp, "delete");
  await sleep(400);
  await shot(cdp, "chat17-memory-deleted");
  const after = await cdp.send("Runtime.evaluate", { expression: "window.qiyunjuMemoryText || ''", returnByValue: true });
  ok(String(after.result.value).indexOf("喜欢红豆糕") < 0, "deleted fact leaves the sheet " + JSON.stringify(after.result.value).slice(0, 180));
  cdp.close();
} catch (err) {
  console.error(err);
  fails.push(String(err && err.message || err));
} finally {
  chrome.kill("SIGKILL");
}

if (fails.length) {
  console.log("web_memory_ops: FAILED", fails.length);
  process.exit(1);
}
console.log("web_memory_ops: ALL OK");
