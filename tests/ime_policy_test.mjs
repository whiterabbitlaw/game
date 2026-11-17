import { createRequire } from "module";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const ime = require("../web/qiyunju_ime.js");

const vp = { x: 720, y: 1280 };

function overlap(canvasW, canvasH, vvH, canvasTop = 0, vvTop = 0) {
  return ime.keyboardOverlapViewport(vp.x, vp.y, canvasW, canvasH, canvasTop, vvTop, vvH);
}

assert.equal(overlap(360, 800, 800), 0, "360 closed keyboard");
assert.ok(Math.abs(overlap(360, 800, 400) - 640) < 0.02, "360 open keyboard");
assert.equal(overlap(390, 844, 844), 0, "390 closed keyboard");
assert.equal(overlap(430, 932, 932), 0, "430 closed keyboard");
assert.equal(overlap(390, 420, 420), 0, "canvas already resized, no double inset");

const landScale = 390 / 1280;
const landExpect = (390 - 180) / landScale;
assert.ok(Math.abs(overlap(844, 390, 180) - landExpect) < 0.02, "landscape keyboard");

const css390 = ime.placeCss(20, 1100, 640, 56, 720, 1280, 0, 0, 390, 844);
assert.ok(css390.left >= 0 && css390.left + css390.width <= 390 + 0.01, "390 field inside width");
assert.ok(css390.top >= 0 && css390.top + css390.height <= 844 + 0.01, "390 field inside height");
const css360 = ime.placeCss(12, 1000, 696, 52, 720, 1280, 0, 0, 360, 640);
assert.ok(css360.left >= -0.01 && css360.left + css360.width <= 360 + 0.01, "360 field inside");
const css430 = ime.placeCss(12, 1100, 696, 52, 720, 1280, 0, 0, 430, 932);
assert.ok(css430.left >= -0.01 && css430.left + css430.width <= 430 + 0.01, "430 field inside");
const cssLand = ime.placeCss(12, 1100, 696, 52, 720, 1280, 0, 0, 844, 390);
assert.ok(cssLand.left >= -0.01 && cssLand.left + cssLand.width <= 844 + 0.01, "landscape field inside width");
assert.ok(cssLand.top >= -0.01 && cssLand.top + cssLand.height <= 390 + 0.01, "landscape field inside height");

const st = ime.createState();
ime.noteCompositionStart(st);
assert.equal(ime.shouldSendOnEnter(st, { key: "Enter", isComposing: true, keyCode: 229 }, 1000), false);
assert.equal(ime.shouldSendOnEnter(st, { key: "Unidentified", keyCode: 229 }, 1000), false);
ime.noteCompositionEnd(st, 1000);
assert.equal(ime.shouldSendOnEnter(st, { key: "Enter", isComposing: false, keyCode: 13 }, 1000 + ime.ENTER_SUPPRESS_MS - 1), false);
assert.equal(ime.shouldSendOnEnter(st, { key: "Enter", isComposing: false, keyCode: 13 }, 1000 + ime.ENTER_SUPPRESS_MS), true);
assert.equal(ime.shouldSendOnEnter(st, { key: "Enter", isComposing: false, keyCode: 229 }, 5000), false);
assert.equal(ime.shouldSendOnEnter(ime.createState(), { key: "Enter", keyCode: 13 }, 0), true);

const edited = ime.createState();
assert.equal(ime.applyEdit(edited, "你好，world! (ok)."), "你好，world! (ok).");
assert.equal(ime.applyEdit(edited, "你好world"), "你好world");
assert.equal(ime.applyEdit(edited, "粘贴：你好，ABC！"), "粘贴：你好，ABC！");
assert.equal(ime.applyEdit(edited, ""), "");

console.log("ime_policy_test: ALL OK");
