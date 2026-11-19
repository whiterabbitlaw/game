/* 畅聊记录的真实滚动层。Godot 的 ScrollContainer 在 Android 上经常吃掉触摸，
   活动条拖不动。这一层用浏览器自己的 overflow 滚动，支持滑动和拖动滚动条。 */
(function (root) {
  "use strict";
  var BUILD = "chat-14";
  var log = null;
  var scroller = null;
  var bar = null;
  var badge = null;

  function ensureBadge() {
    if (badge || typeof document === "undefined") return;
    ensureLog();
    badge = document.createElement("div");
    badge.id = "qiyunju-build";
    badge.textContent = BUILD;
    badge.setAttribute("data-build", BUILD);
    badge.style.flex = "0 0 auto";
    badge.style.padding = "0 8px 3px";
    badge.style.color = "#7a7690";
    badge.style.font = "10px/1.2 sans-serif";
    badge.style.pointerEvents = "none";
    badge.style.display = "none";
    log.appendChild(badge);
  }

  function trackThumb() {
    if (!scroller || !bar) return;
    var thumb = bar.firstChild;
    var max = Math.max(1, scroller.scrollHeight - scroller.clientHeight);
    var ratio = scroller.clientHeight / Math.max(scroller.scrollHeight, 1);
    var h = Math.max(48, bar.clientHeight * Math.min(1, ratio));
    var travel = Math.max(0, bar.clientHeight - h);
    thumb.style.height = h + "px";
    thumb.style.transform = "translateY(" + (travel * (scroller.scrollTop / max)) + "px)";
  }

  function scrollFromBar(clientY) {
    if (!scroller || !bar) return;
    var r = bar.getBoundingClientRect();
    var t = Math.min(1, Math.max(0, (clientY - r.top) / Math.max(1, r.height)));
    scroller.scrollTop = t * Math.max(0, scroller.scrollHeight - scroller.clientHeight);
    trackThumb();
  }

  function ensureLog() {
    if (log || typeof document === "undefined") return log;
    log = document.createElement("div");
    log.id = "qiyunju-log";
    log.setAttribute("role", "log");
    log.setAttribute("aria-label", "畅聊记录");
    log.style.position = "fixed";
    log.style.zIndex = "60";
    log.style.display = "none";
    log.style.boxSizing = "border-box";
    log.style.background = "rgba(255,253,248,0.96)";
    log.style.borderRadius = "12px";
    log.style.pointerEvents = "auto";
    log.style.display = "none";
    log.style.flexDirection = "column";
    log.style.overflow = "hidden";
    var row = document.createElement("div");
    row.style.display = "flex";
    row.style.flex = "1";
    row.style.minHeight = "0";
    row.style.flexDirection = "row";
    scroller = document.createElement("div");
    scroller.id = "qiyunju-log-body";
    scroller.style.flex = "1";
    scroller.style.minWidth = "0";
    scroller.style.overflowX = "hidden";
    scroller.style.overflowY = "scroll";
    scroller.style.webkitOverflowScrolling = "touch";
    scroller.style.touchAction = "pan-y";
    scroller.style.overscrollBehavior = "contain";
    scroller.style.padding = "6px";
    scroller.addEventListener("scroll", trackThumb);
    bar = document.createElement("div");
    bar.id = "qiyunju-bar";
    bar.setAttribute("role", "scrollbar");
    bar.setAttribute("aria-controls", "qiyunju-log-body");
    bar.setAttribute("aria-label", "聊天记录滚动条");
    bar.style.width = "22px";
    bar.style.flex = "0 0 22px";
    bar.style.touchAction = "none";
    bar.style.background = "transparent";
    bar.style.borderRadius = "0 12px 12px 0";
    bar.style.position = "relative";
    var thumb = document.createElement("div");
    thumb.style.position = "absolute";
    thumb.style.left = "8px";
    thumb.style.right = "8px";
    thumb.style.top = "0";
    thumb.style.height = "48px";
    thumb.style.borderRadius = "8px";
    thumb.style.background = "#b9a07a";
    bar.appendChild(thumb);
    bar.addEventListener("pointerdown", function (e) {
      try { bar.setPointerCapture(e.pointerId); } catch (err) {}
      scrollFromBar(e.clientY);
      e.preventDefault();
      e.stopPropagation();
    });
    bar.addEventListener("pointermove", function (e) {
      if (e.buttons === 0 && e.pointerType !== "touch") return;
      scrollFromBar(e.clientY);
      e.preventDefault();
    });
    bar.addEventListener("touchstart", function (e) {
      if (!e.touches[0]) return;
      scrollFromBar(e.touches[0].clientY);
      e.preventDefault();
    }, { passive: false });
    bar.addEventListener("touchmove", function (e) {
      if (!e.touches[0]) return;
      scrollFromBar(e.touches[0].clientY);
      e.preventDefault();
    }, { passive: false });
    row.appendChild(scroller);
    row.appendChild(bar);
    log.appendChild(row);
    var note = document.createElement("div");
    note.id = "qiyunju-note";
    note.style.display = "none";
    note.style.flex = "0 0 auto";
    note.style.maxHeight = "2.8em";
    note.style.overflow = "hidden";
    note.style.padding = "2px 8px 0";
    note.style.color = "#3d8b7a";
    note.style.font = "12px/1.35 sans-serif";
    note.style.pointerEvents = "none";
    log.appendChild(note);
    document.body.appendChild(log);
    return log;
  }

  function canvasBox() {
    var c = document.getElementById("canvas");
    if (!c || !c.getBoundingClientRect) {
      return { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight };
    }
    var r = c.getBoundingClientRect();
    return { left: r.left, top: r.top, width: r.width, height: r.height };
  }

  function placeCss(x, y, w, h, vpW, vpH) {
    if (root.qiyunjuIme && root.qiyunjuIme.placeCss) {
      var box = canvasBox();
      return root.qiyunjuIme.placeCss(+x, +y, +w, +h, +vpW, +vpH, box.left, box.top, box.width, box.height);
    }
    return { left: +x, top: +y, width: +w, height: +h };
  }

  function setLines(raw) {
    var el = ensureLog();
    if (!el) return;
    var lines = raw;
    if (typeof raw === "string") {
      try { lines = JSON.parse(raw); } catch (e) { lines = []; }
    }
    if (!Array.isArray(lines)) lines = [];
    ensureLog();
    var nearBottom = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 48;
    var atTop = scroller.scrollTop < 2;
    scroller.replaceChildren();
    lines.forEach(function (line) {
      var row = document.createElement("div");
      row.style.margin = "0 0 8px";
      row.style.padding = "8px 10px";
      row.style.borderRadius = "10px";
      row.style.background = line && line.role === "user" ? "#e7f6f1" : "#fff";
      var who = document.createElement("div");
      who.textContent = (line && line.who) || "";
      who.style.font = "12px/1.3 sans-serif";
      who.style.color = "#7a7690";
      var body = document.createElement("div");
      body.textContent = (line && line.text) || "";
      body.style.font = "13px/1.4 sans-serif";
      body.style.color = "#3b3752";
      body.style.whiteSpace = "pre-wrap";
      body.style.wordBreak = "break-word";
      row.appendChild(who);
      row.appendChild(body);
      scroller.appendChild(row);
    });
    if (nearBottom || atTop) scroller.scrollTop = scroller.scrollHeight;
    trackThumb();
  }

  if (typeof document !== "undefined") {
    if (document.body) ensureBadge();
    else document.addEventListener("DOMContentLoaded", ensureBadge);
  }

  root.QIYUNJU_BUILD = BUILD;
  root.qiyunjuChat = {
    BUILD: BUILD,
    setLines: setLines,
    place: function (x, y, w, h, vpW, vpH) {
      var el = ensureLog();
      if (!el) return;
      if (+w < 40 || +h < 40) {
        el.style.display = "none";
        return;
      }
      var css = placeCss(x, y, w, h, vpW, vpH);
      el.style.display = "flex";
      if (badge) badge.style.display = "block";
      el.style.left = css.left + "px";
      el.style.top = css.top + "px";
      el.style.width = Math.max(0, css.width) + "px";
      el.style.height = Math.max(0, css.height) + "px";
    },
    setNote: function (text) {
      var el = ensureLog();
      if (!el) return;
      var note = document.getElementById("qiyunju-note");
      if (!note) return;
      var t = text == null ? "" : String(text).replace(/\s+/g, " ").trim();
      note.textContent = t;
      note.style.display = t ? "block" : "none";
    },
    hide: function () {
      if (log) log.style.display = "none";
      if (badge) badge.style.display = "none";
    },
    debugFill: function (n) {
      var lines = [];
      for (var i = 0; i < n; i++) lines.push({ role: i % 2 ? "user" : "assistant", who: i % 2 ? "你" : "暖阳学者", text: "第" + (i + 1) + "行 你好，world! 用来检查滑动和滚动条。" });
      setLines(lines);
      if (scroller) scroller.scrollTop = 0;
      trackThumb();
    }
  };
})(typeof window !== "undefined" ? window : globalThis);
