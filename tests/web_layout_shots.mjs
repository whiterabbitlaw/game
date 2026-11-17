/**
 * Loaded web build at phone widths. Checks the HTML composer and history
 * stay inside the reserved rows, and the character page has no chat overlay.
 * Writes screenshots under /tmp/qiyunju-shots.
 *
 * usage: node tests/web_layout_shots.mjs http://127.0.0.1:8765
 */
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";

const origin = (process.argv[2] || "http://127.0.0.1:8765").replace(/\/$/, "");
const outDir = "/tmp/qiyunju-shots";
mkdirSync(outDir, { recursive: true });

const chrome = spawn("google-chrome", [
  "--user-data-dir=/tmp/chrome-layout-shots",
  "--headless=new",
  "--disable-gpu",
  "--no-sandbox",
  "--enable-unsafe-swiftshader",
  "--remote-debugging-port=9444",
  "--window-size=430,932",
  "about:blank",
], { stdio: "ignore" });

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function waitCdp() {
  for (let i = 0; i < 40; i++) {
    try {
      const res = await fetch("http://127.0.0.1:9444/json/version");
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

const MEASURE = `(() => {
  const ime = document.getElementById('qiyunju-ime');
  const shell = document.getElementById('qiyunju-log');
  const log = document.getElementById('qiyunju-log-body');
  const badge = document.getElementById('qiyunju-build');
  const canvas = document.getElementById('canvas');
  const cr = canvas ? canvas.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0, right: 0, bottom: 0 };
  const shown = shell && shell.style.display !== 'none';
  const imeOn = ime && ime.style.display === 'block';
  const ir = imeOn ? ime.getBoundingClientRect() : null;
  const lr = shown && log ? log.getBoundingClientRect() : null;
  const sr = shown && shell ? shell.getBoundingClientRect() : null;
  const br = badge && shown ? badge.getBoundingClientRect() : null;
  const belowY = ir ? ir.bottom + 6 : 0;
  const below = ir ? document.elementFromPoint(ir.left + 12, belowY) : null;
  return JSON.stringify({
    build: badge ? badge.textContent : '',
    splash: !!document.getElementById('status'),
    canvas: { x: cr.left, y: cr.top, w: cr.width, h: cr.height, bottom: cr.bottom },
    ime: ir ? {
      x: ir.left, y: ir.top, w: ir.width, h: ir.height, bottom: ir.bottom,
      bg: getComputedStyle(ime).backgroundColor
    } : null,
    log: lr ? { x: lr.left, y: lr.top, w: lr.width, h: lr.height, bottom: lr.bottom, text: (log.textContent || '').slice(0, 40) } : null,
    shell: sr ? { y: sr.top, bottom: sr.bottom } : null,
    badge: br ? { y: br.top, bottom: br.bottom } : null,
    below: below ? (below.id || below.tagName) : '',
    belowInside: !!(ir && belowY < cr.bottom - 1 && belowY > cr.top)
  });
})()`;

async function measure(cdp) {
  const ev = await cdp.send("Runtime.evaluate", { expression: MEASURE, returnByValue: true });
  return JSON.parse(ev.result.value);
}

async function waitReady(cdp, want) {
  const t0 = Date.now();
  let state = null;
  while (Date.now() - t0 < 90000) {
    state = await measure(cdp);
    if (state.splash) { await sleep(500); continue; }
    if (want === "chat" && state.ime && state.log && state.log.text) return state;
    if (want === "detail" && !state.ime && !state.log) return state;
    await sleep(500);
  }
  return state;
}

async function shot(cdp, name) {
  const png = await cdp.send("Page.captureScreenshot", { format: "png" });
  const path = outDir + "/" + name + ".png";
  writeFileSync(path, Buffer.from(png.data, "base64"));
  console.log("  shot", path);
}

try {
  await waitCdp();
  const tab = await (await fetch("http://127.0.0.1:9444/json/new?" + encodeURIComponent(origin + "/index.html?demo=chat"), { method: "PUT" })).json();
  const cdp = connect(tab.webSocketDebuggerUrl);
  await cdp.ready;
  await cdp.send("Runtime.enable");
  await cdp.send("Page.enable");

  const sizes = [
    { name: "chat-390", w: 390, h: 844, want: "chat" },
    { name: "chat-430", w: 430, h: 932, want: "chat" },
    { name: "chat-land", w: 844, h: 390, want: "chat" },
  ];
  for (const size of sizes) {
    console.log("==", size.name, size.w + "x" + size.h);
    await cdp.send("Emulation.setDeviceMetricsOverride", {
      width: size.w, height: size.h, deviceScaleFactor: 2, mobile: true,
    });
    await sleep(700);
    const state = await waitReady(cdp, "chat");
    console.log("  state", JSON.stringify(state));
    ok(state && state.ime && state.log, size.name + " chat overlays present");
    if (state && state.ime && state.log) {
      ok(state.log.bottom <= state.ime.y + 2, size.name + " history above composer");
      ok(state.shell && state.log.bottom <= state.shell.bottom + 1, size.name + " history inside shell");
      ok(state.badge && state.badge.y >= state.log.bottom - 2 && state.badge.bottom <= state.shell.bottom + 2, size.name + " build id in log footer");
      ok(state.ime.bottom <= state.canvas.bottom + 1, size.name + " composer inside canvas");
      ok(state.below !== "qiyunju-ime" && state.below !== "qiyunju-log" && state.below !== "qiyunju-log-body", size.name + " row under composer is not the field (" + state.below + ")");
      ok(state.belowInside, size.name + " tool row still inside the canvas");
      ok(String(state.ime.bg).indexOf("255, 250, 243") >= 0, size.name + " parchment field");
      ok(state.ime.h < 42, size.name + " field is not an inflated slab " + state.ime.h);
      ok(state.build === "chat-10", size.name + " build");
    }
    await shot(cdp, size.name);
  }

  console.log("== chat-390 keyboard inset");
  await cdp.send("Emulation.setDeviceMetricsOverride", {
    width: 390, height: 844, deviceScaleFactor: 2, mobile: true,
  });
  await sleep(600);
  const closed = await measure(cdp);
  await cdp.send("Runtime.evaluate", { expression: `(() => {
    const ime = window.qiyunjuIme;
    if (!ime || ime.__shotWrapped) return 'no';
    const orig = ime.inset.bind(ime);
    ime.inset = function () { return 420; };
    ime.__shotWrapped = orig;
    return 'yes';
  })()`, returnByValue: true });
  await sleep(900);
  const keyed = await measure(cdp);
  console.log("  state", JSON.stringify(keyed));
  ok(keyed && keyed.ime && keyed.log, "keyboard chat overlays present");
  if (keyed && keyed.ime && keyed.log && closed && closed.ime) {
    ok(keyed.log.bottom <= keyed.ime.y + 2, "keyboard history above composer");
    ok(keyed.ime.bottom <= keyed.canvas.bottom + 1, "keyboard composer inside canvas");
    ok(keyed.below !== "qiyunju-ime" && keyed.belowInside, "keyboard tool row still tappable inside canvas (" + keyed.below + ")");
    ok(keyed.ime.y < closed.ime.y - 40, "keyboard moved the composer up " + closed.ime.y + " -> " + keyed.ime.y);
  }
  await shot(cdp, "chat-390-keyboard");
  await cdp.send("Runtime.evaluate", { expression: `(() => {
    const ime = window.qiyunjuIme;
    if (ime && ime.__shotWrapped) ime.inset = ime.__shotWrapped;
    return 'restored';
  })()` });

  console.log("== detail pages");
  await cdp.send("Emulation.setDeviceMetricsOverride", {
    width: 390, height: 844, deviceScaleFactor: 2, mobile: true,
  });
  await cdp.send("Page.navigate", { url: origin + "/index.html?demo=detail" });
  {
    const t0 = Date.now();
    let sawSplash = false;
    while (Date.now() - t0 < 90000) {
      const state = await measure(cdp);
      if (state.splash) sawSplash = true;
      if (sawSplash && !state.splash) break;
      await sleep(300);
    }
    await sleep(1600);
  }
  for (const size of [
    { name: "detail-390", w: 390, h: 844 },
    { name: "detail-430", w: 430, h: 932 },
    { name: "detail-land", w: 844, h: 390 },
  ]) {
    console.log("==", size.name);
    await cdp.send("Emulation.setDeviceMetricsOverride", {
      width: size.w, height: size.h, deviceScaleFactor: 2, mobile: true,
    });
    await sleep(900);
    const state = await measure(cdp);
    console.log("  state", JSON.stringify(state));
    ok(state && !state.splash, size.name + " left the splash");
    ok(state && !state.ime && !state.log, size.name + " chat overlays hidden");
    const top = await cdp.send("Runtime.evaluate", { expression: `(() => {
      const hit = document.elementFromPoint(window.innerWidth / 2, 18);
      return hit ? (hit.id || hit.tagName) : '';
    })()`, returnByValue: true });
    ok(top.result.value !== "qiyunju-build" && top.result.value !== "qiyunju-ime", size.name + " title area is not a chat badge (" + top.result.value + ")");
    await shot(cdp, size.name);
  }
  cdp.close();
} catch (err) {
  console.error(err);
  fails.push(String(err && err.message || err));
} finally {
  chrome.kill("SIGKILL");
}

if (fails.length) {
  console.log("web_layout_shots: FAILED", fails.length);
  process.exit(1);
}
console.log("web_layout_shots: ALL OK");
