/**
 * Loaded web build, not a splash and not a synthetic input.value assignment.
 * Requires the game server URL as argv[2]. Launches headless Chrome with touch emulation.
 * Proves the HTML field is the hit target, accepts a composition commit of 你好，
 * and that a touch drag plus a scrollbar drag move the history.
 */
import { spawn } from "node:child_process";
import { writeFileSync } from "node:fs";

const url = process.argv[2];
if (!url) {
  console.error("usage: node tests/web_chat_interact.mjs http://host/index.html?demo=chat");
  process.exit(2);
}

const chrome = spawn("google-chrome", [
  "--user-data-dir=/tmp/chrome-chat-interact",
  "--headless=new",
  "--disable-gpu",
  "--no-sandbox",
  "--enable-unsafe-swiftshader",
  "--remote-debugging-port=9333",
  "--window-size=390,844",
  "about:blank",
], { stdio: "ignore" });

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function waitCdp() {
  for (let i = 0; i < 40; i++) {
    try {
      const res = await fetch("http://127.0.0.1:9333/json/version");
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

try {
  await waitCdp();
  const tab = await (await fetch("http://127.0.0.1:9333/json/new?" + encodeURIComponent(url), { method: "PUT" })).json();
  const cdp = connect(tab.webSocketDebuggerUrl);
  await cdp.ready;
  await cdp.send("Runtime.enable");
  await cdp.send("Page.enable");
  await cdp.send("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
  await cdp.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 1 });

  let state = null;
  const t0 = Date.now();
  while (Date.now() - t0 < 90000) {
    const ev = await cdp.send("Runtime.evaluate", { expression: `(() => {
      const ime = document.getElementById('qiyunju-ime');
      const shell = document.getElementById('qiyunju-log');
      const log = document.getElementById('qiyunju-log-body') || shell;
      const badge = document.getElementById('qiyunju-build');
      const shown = shell && shell.style.display !== 'none';
      const shellBox = shown && shell ? shell.getBoundingClientRect() : null;
      const badgeBox = badge && badge.style.display !== 'none' ? badge.getBoundingClientRect() : null;
      const ir = ime && ime.style.display !== 'none' ? ime.getBoundingClientRect() : null;
      const lr = shown && log ? log.getBoundingClientRect() : null;
      const hit = ir ? document.elementFromPoint(ir.left + ir.width / 2, ir.top + Math.min(ir.height / 2, ir.height - 2)) : null;
      return JSON.stringify({
        build: badge ? badge.textContent : '',
        badge: badgeBox && shellBox ? { y: badgeBox.top, shellTop: shellBox.top, shellBottom: shellBox.bottom } : null,
        onIme: typeof window.qiyunjuOnIme,
        ime: ime && ime.style.display === 'block' ? { x: ir.left, y: ir.top, w: ir.width, h: ir.height, bg: getComputedStyle(ime).backgroundColor, hit: hit && (hit.id || hit.tagName) } : null,
        log: shown && lr ? { x: lr.left, y: lr.top, w: lr.width, h: lr.height, text: log.textContent.slice(0, 80), hscroll: log.scrollHeight, client: log.clientHeight } : null,
        splash: !!document.getElementById('status')
      });
    })()`, returnByValue: true });
    state = JSON.parse(ev.result.value);
    if (state.ime && state.log && state.log.text.includes("热茶") && state.onIme === "function") break;
    await sleep(1000);
  }
  console.log("state", JSON.stringify(state));
  ok(state && state.build === "chat-11", "visible build chat-11");
  ok(state && state.badge && state.badge.y > state.badge.shellTop + 40 && state.badge.y < state.badge.shellBottom + 2, "build id sits in the log footer, not on the title");
  ok(state && state.ime && state.log && state.log.y + state.log.h <= state.ime.y + 2, "history ends above the composer");
  ok(state && state.ime && state.ime.h <= 40, "composer is not an oversized slab " + (state && state.ime && state.ime.h));
  ok(state && state.ime && state.ime.h >= 24, "composer stays a tappable row " + (state && state.ime && state.ime.h));
  ok(state && state.ime && String(state.ime.bg).indexOf("42, 38, 54") < 0, "composer is not the dark slab " + (state && state.ime && state.ime.bg));
  ok(state && state.onIme === "function", "Godot installed qiyunjuOnIme");
  ok(state && state.ime && state.ime.hit === "qiyunju-ime", "tap target is the HTML field " + (state && state.ime && state.ime.hit));
  ok(state && state.log && state.log.text.includes("热茶"), "HTML history shows the real greeting");
  ok(state && !state.splash, "Godot splash is gone");

  if (state && state.ime) {
    const cx = state.ime.x + state.ime.w / 2;
    const cy = state.ime.y + state.ime.h / 2;
    await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", x: cx, y: cy, button: "left", clickCount: 1 });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", x: cx, y: cy, button: "left", clickCount: 1 });
    await cdp.send("Runtime.evaluate", { expression: "document.getElementById('qiyunju-ime').focus()" });
    try {
      await cdp.send("Input.imeSetComposition", { text: "nihao", selectionStart: 5, selectionEnd: 5 });
    } catch (e) {
      console.log("  note imeSetComposition", String(e.message || e).slice(0, 160));
    }
    await cdp.send("Input.insertText", { text: "你好，" });
    await cdp.send("Input.insertText", { text: "world!" });
    const read = await cdp.send("Runtime.evaluate", { expression: "document.getElementById('qiyunju-ime').value", returnByValue: true });
    ok(read.result.value === "你好，world!", "field accepted 你好，world! got " + JSON.stringify(read.result.value));
  }

  if (state && state.log) {
    await cdp.send("Runtime.evaluate", { expression: "window.qiyunjuChat.debugFill(40)" });
    await sleep(200);
    const before = await cdp.send("Runtime.evaluate", { expression: "document.getElementById('qiyunju-log-body').scrollTop", returnByValue: true });
    const box = await cdp.send("Runtime.evaluate", { expression: `(() => { const r = document.getElementById('qiyunju-log-body').getBoundingClientRect(); return JSON.stringify({x:r.left,y:r.top,w:r.width,h:r.height,sh:document.getElementById('qiyunju-log-body').scrollHeight}); })()`, returnByValue: true });
    const b = JSON.parse(box.result.value);
    const x = b.x + b.w * 0.45;
    const y1 = b.y + b.h * 0.75;
    const y2 = b.y + 30;
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y: y1, id: 1 }] });
    for (let i = 1; i <= 6; i++) {
      const y = y1 + (y2 - y1) * (i / 6);
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x, y, id: 1 }] });
    }
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await sleep(100);
    const afterSwipe = await cdp.send("Runtime.evaluate", { expression: "document.getElementById('qiyunju-log-body').scrollTop", returnByValue: true });
    ok(Number(afterSwipe.result.value) > Number(before.result.value) + 20, "swipe moved history " + before.result.value + " -> " + afterSwipe.result.value);

    const barBox = JSON.parse((await cdp.send("Runtime.evaluate", { expression: `(() => { const r = document.getElementById('qiyunju-bar').getBoundingClientRect(); const hit = document.elementFromPoint(r.left + r.width/2, r.top + r.height*0.8); return JSON.stringify({x:r.left,y:r.top,w:r.width,h:r.height,hit:hit&&hit.id}); })()`, returnByValue: true })).result.value);
    ok(barBox.hit === "qiyunju-bar", "scrollbar is the touch target " + barBox.hit);
    const sx = barBox.x + barBox.w / 2;
    const sy1 = barBox.y + barBox.h * 0.8;
    const sy2 = barBox.y + barBox.h * 0.2;
    const mid = await cdp.send("Runtime.evaluate", { expression: "document.getElementById('qiyunju-log-body').scrollTop", returnByValue: true });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: sx, y: sy1, id: 2 }] });
    for (let i = 1; i <= 6; i++) {
      const y = sy1 + (sy2 - sy1) * (i / 6);
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: sx, y, id: 2 }] });
    }
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await sleep(80);
    const afterBar = await cdp.send("Runtime.evaluate", { expression: "document.getElementById('qiyunju-log-body').scrollTop", returnByValue: true });
    ok(Math.abs(Number(afterBar.result.value) - Number(mid.result.value)) > 10, "scrollbar drag moved history " + mid.result.value + " -> " + afterBar.result.value);
    const shot = await cdp.send("Page.captureScreenshot", { format: "png" });
    writeFileSync("/tmp/chat-interact.png", Buffer.from(shot.data, "base64"));
  }
  cdp.close();
} catch (err) {
  console.error(err);
  fails.push(String(err && err.message || err));
} finally {
  chrome.kill("SIGKILL");
}

if (fails.length) {
  console.log("web_chat_interact: FAILED", fails.length);
  process.exit(1);
}
console.log("web_chat_interact: ALL OK");
