/* 畅聊输入：真实 HTML input，覆盖在 Godot LineEdit 上。
   Android 网页的虚拟键盘往往不给标点/中文发可用的 keydown（key 为 Unidentified），
   Godot 画布只听 keydown 和 contentEditable 的 composition，所以英文偶尔能打、标点和中文 IME 不行。
   实验性 virtual keyboard 会在组合期间整段重写文本，并且 preventDefault Enter，不能用来确认候选。
   这里只服务畅聊输入框：组合中的 Enter 不发送，组合结束后的 Enter 才发送。 */
(function (root) {
  "use strict";

  var ENTER_SUPPRESS_MS = 120;

  function createState() {
    return { composing: false, suppressEnterUntil: 0, text: "" };
  }

  function noteCompositionStart(state) {
    state.composing = true;
  }

  function noteCompositionEnd(state, now) {
    state.composing = false;
    state.suppressEnterUntil = (now || 0) + ENTER_SUPPRESS_MS;
  }

  function applyEdit(state, value) {
    state.text = value == null ? "" : String(value);
    return state.text;
  }

  function shouldSendOnEnter(state, evt, now) {
    if (!evt || evt.key !== "Enter") return false;
    if (evt.isComposing || evt.keyCode === 229 || (state && state.composing)) return false;
    if (evt.shiftKey || evt.altKey || evt.ctrlKey || evt.metaKey) return false;
    if (state && now < state.suppressEnterUntil) return false;
    return true;
  }

  function keyboardOverlapViewport(vpW, vpH, canvasW, canvasH, canvasTop, vvOffsetTop, vvHeight) {
    vpW = +vpW;
    vpH = +vpH;
    canvasW = +canvasW;
    canvasH = +canvasH;
    canvasTop = +canvasTop || 0;
    vvOffsetTop = +vvOffsetTop || 0;
    vvHeight = +vvHeight;
    if (!(vpW > 1 && vpH > 1 && canvasW > 1 && canvasH > 1 && vvHeight >= 0)) return 0;
    var scale = Math.min(canvasW / vpW, canvasH / vpH);
    if (!(scale > 0)) return 0;
    var offsetY = (canvasH - vpH * scale) / 2;
    var contentBottom = canvasTop + offsetY + vpH * scale;
    var visibleBottom = vvOffsetTop + vvHeight;
    var overlap = contentBottom - visibleBottom;
    if (overlap <= 1) return 0;
    return overlap / scale;
  }

  function placeCss(vpX, vpY, vpWrect, vpHrect, vpW, vpH, canvasLeft, canvasTop, canvasW, canvasH) {
    var scale = Math.min(canvasW / vpW, canvasH / vpH);
    var ox = (canvasW - vpW * scale) / 2;
    var oy = (canvasH - vpH * scale) / 2;
    return {
      left: canvasLeft + ox + vpX * scale,
      top: canvasTop + oy + vpY * scale,
      width: Math.max(0, vpWrect * scale),
      height: Math.max(0, vpHrect * scale),
      scale: scale
    };
  }

  var state = createState();
  var input = null;
  var lastVpW = 720;
  var lastVpH = 1280;

  function emit(obj) {
    try {
      if (typeof root.qiyunjuOnIme === "function") root.qiyunjuOnIme(JSON.stringify(obj));
    } catch (e) {}
  }

  function ensure() {
    if (input || typeof document === "undefined") return input;
    var el = document.createElement("input");
    el.type = "text";
    el.id = "qiyunju-ime";
    el.lang = "zh-CN";
    el.enterKeyHint = "send";
    el.autocomplete = "off";
    el.autocapitalize = "off";
    el.spellcheck = false;
    el.setAttribute("autocorrect", "off");
    el.setAttribute("inputmode", "text");
    el.setAttribute("aria-label", "对她说点什么");
    el.setAttribute("aria-hidden", "true");
    el.style.position = "fixed";
    el.style.zIndex = "50";
    el.style.display = "none";
    el.style.boxSizing = "border-box";
    el.style.margin = "0";
    el.style.border = "1px solid rgba(217,164,65,0.9)";
    el.style.borderRadius = "12px";
    el.style.background = "#2a2636";
    el.style.color = "#f6f1e6";
    el.style.caretColor = "#f6f1e6";
    el.style.fontFamily = '"Noto Sans SC","PingFang SC","Microsoft YaHei","Noto Sans CJK SC",sans-serif';
    el.style.touchAction = "auto";
    el.style.webkitUserSelect = "text";
    el.style.userSelect = "text";
    el.style.outline = "none";
    el.style.padding = "0 12px";
    document.body.appendChild(el);
    el.addEventListener("compositionstart", function () {
      noteCompositionStart(state);
      emit({ type: "composition", text: el.value, composing: true });
    });
    el.addEventListener("compositionend", function () {
      noteCompositionEnd(state, Date.now());
      applyEdit(state, el.value);
      emit({ type: "input", text: el.value, composing: false });
    });
    el.addEventListener("input", function () {
      applyEdit(state, el.value);
      emit({ type: "input", text: el.value, composing: !!state.composing });
    });
    el.addEventListener("keydown", function (e) {
      if (!shouldSendOnEnter(state, e, Date.now())) return;
      e.preventDefault();
      e.stopPropagation();
      applyEdit(state, el.value);
      emit({ type: "submit", text: el.value, composing: false });
    });
    el.addEventListener("focus", function () {
      el.style.boxShadow = "0 0 0 2px rgba(111,181,166,0.95)";
      emit({ type: "focus", text: el.value, composing: !!state.composing });
    });
    el.addEventListener("blur", function () {
      el.style.boxShadow = "none";
      applyEdit(state, el.value);
      emit({ type: "blur", text: el.value, composing: false });
    });
    input = el;
    return el;
  }

  function canvasBox() {
    var c = typeof document !== "undefined" ? document.getElementById("canvas") : null;
    if (!c || typeof c.getBoundingClientRect !== "function") {
      var w = typeof window !== "undefined" ? window.innerWidth : lastVpW;
      var h = typeof window !== "undefined" ? window.innerHeight : lastVpH;
      return { left: 0, top: 0, width: w, height: h };
    }
    var r = c.getBoundingClientRect();
    return { left: r.left, top: r.top, width: r.width, height: r.height };
  }

  function currentInset() {
    if (typeof window === "undefined" || !window.visualViewport) return 0;
    var vv = window.visualViewport;
    var box = canvasBox();
    return keyboardOverlapViewport(lastVpW, lastVpH, box.width, box.height, box.top, vv.offsetTop, vv.height);
  }

  function emitInset() {
    emit({ type: "inset", inset: currentInset() });
  }

  if (typeof window !== "undefined") {
    if (window.visualViewport) {
      window.visualViewport.addEventListener("resize", emitInset);
      window.visualViewport.addEventListener("scroll", function () {
        emitInset();
        if (window.scrollX || window.scrollY) window.scrollTo(0, 0);
      });
    }
    window.addEventListener("resize", emitInset);
    window.addEventListener("orientationchange", emitInset);
  }

  function show(el) {
    el.style.display = "block";
    el.setAttribute("aria-hidden", "false");
  }

  var api = {
    ENTER_SUPPRESS_MS: ENTER_SUPPRESS_MS,
    createState: createState,
    noteCompositionStart: noteCompositionStart,
    noteCompositionEnd: noteCompositionEnd,
    applyEdit: applyEdit,
    shouldSendOnEnter: shouldSendOnEnter,
    keyboardOverlapViewport: keyboardOverlapViewport,
    placeCss: placeCss,
    open: function (placeholder, label) {
      var el = ensure();
      if (!el) return;
      el.placeholder = placeholder || "";
      if (label) el.setAttribute("aria-label", label);
      show(el);
    },
    place: function (x, y, w, h, vpW, vpH) {
      var el = ensure();
      if (!el) return;
      lastVpW = +vpW || lastVpW;
      lastVpH = +vpH || lastVpH;
      var box = canvasBox();
      var css = placeCss(+x, +y, +w, +h, lastVpW, lastVpH, box.left, box.top, box.width, box.height);
      var left = css.left;
      var top = css.top;
      var width = css.width;
      var height = css.height;
      if (typeof window !== "undefined" && window.visualViewport) {
        var vv = window.visualViewport;
        var visLeft = vv.offsetLeft;
        var visTop = vv.offsetTop;
        var visRight = vv.offsetLeft + vv.width;
        var visBottom = vv.offsetTop + vv.height;
        if (left + width > visRight - 4) left = Math.max(visLeft, visRight - width - 4);
        if (top + height > visBottom - 4) top = Math.max(visTop, visBottom - height - 4);
        if (left < visLeft) left = visLeft;
        if (top < visTop) top = visTop;
      }
      show(el);
      el.style.left = left + "px";
      el.style.top = top + "px";
      el.style.width = Math.max(48, width) + "px";
      el.style.height = Math.max(36, height) + "px";
      el.style.fontSize = Math.max(16, Math.min(22, height * 0.42)) + "px";
    },
    setText: function (text) {
      var el = ensure();
      if (!el) return;
      state.composing = false;
      applyEdit(state, text);
      if (el.value !== state.text) el.value = state.text;
    },
    value: function () {
      if (input) return input.value;
      return state.text;
    },
    hide: function () {
      if (!input) return;
      input.style.display = "none";
      input.setAttribute("aria-hidden", "true");
    },
    close: function () {
      if (!input) return;
      state.composing = false;
      state.suppressEnterUntil = 0;
      input.value = "";
      state.text = "";
      try { input.blur(); } catch (e) {}
      input.style.display = "none";
      input.setAttribute("aria-hidden", "true");
    },
    inset: function (vpW, vpH) {
      if (vpW) lastVpW = +vpW;
      if (vpH) lastVpH = +vpH;
      return currentInset();
    },
    focus: function () {
      var el = ensure();
      if (el) el.focus();
    }
  };

  root.qiyunjuIme = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof window !== "undefined" ? window : globalThis);
