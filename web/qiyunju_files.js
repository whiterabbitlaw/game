/* 图片按钮上的透明文件选择。必须在这次点击里同步 input.click()，
   否则 Android Edge 会丢掉用户手势，选图窗口不出现。选中后在本地压到 1024 边再交给游戏。 */
(function (root) {
  "use strict";
  var button = null;
  var input = null;

  function emit(obj) {
    try {
      if (typeof root.qiyunjuOnFile === "function") root.qiyunjuOnFile(JSON.stringify(obj));
    } catch (e) {}
  }

  function canvasBox() {
    var c = typeof document !== "undefined" ? document.getElementById("canvas") : null;
    if (!c || typeof c.getBoundingClientRect !== "function") {
      var w = typeof window !== "undefined" ? window.innerWidth : 720;
      var h = typeof window !== "undefined" ? window.innerHeight : 1280;
      return { left: 0, top: 0, width: w, height: h };
    }
    var r = c.getBoundingClientRect();
    return { left: r.left, top: r.top, width: r.width, height: r.height };
  }

  function shrink(file, cb) {
    var url = URL.createObjectURL(file);
    var img = new Image();
    img.onload = function () {
      var maxSide = 1024;
      var scale = Math.min(1, maxSide / Math.max(img.naturalWidth || img.width, img.naturalHeight || img.height));
      var w = Math.max(1, Math.round((img.naturalWidth || img.width) * scale));
      var h = Math.max(1, Math.round((img.naturalHeight || img.height) * scale));
      var canvas = document.createElement("canvas");
      canvas.width = w;
      canvas.height = h;
      var g = canvas.getContext("2d");
      if (!g) {
        URL.revokeObjectURL(url);
        cb("encode");
        return;
      }
      g.drawImage(img, 0, 0, w, h);
      URL.revokeObjectURL(url);
      try {
        cb(null, canvas.toDataURL("image/jpeg", 0.82));
      } catch (e) {
        cb("encode");
      }
    };
    img.onerror = function () {
      URL.revokeObjectURL(url);
      cb("unreadable");
    };
    img.src = url;
  }

  function ensure() {
    if (button || typeof document === "undefined") return button;
    button = document.createElement("button");
    button.type = "button";
    button.id = "qiyunju-file";
    button.setAttribute("aria-label", "选择图片");
    button.setAttribute("aria-hidden", "true");
    button.style.position = "fixed";
    button.style.zIndex = "40";
    button.style.display = "none";
    button.style.margin = "0";
    button.style.padding = "0";
    button.style.border = "0";
    button.style.background = "transparent";
    button.style.color = "transparent";
    button.style.cursor = "pointer";
    input = document.createElement("input");
    input.type = "file";
    input.accept = "image/*";
    input.setAttribute("aria-hidden", "true");
    input.style.display = "none";
    button.addEventListener("click", function () {
      input.click();
    });
    input.addEventListener("change", function () {
      var file = input.files && input.files[0];
      input.value = "";
      if (!file) {
        emit({ kind: "image", cancelled: true });
        return;
      }
      if (file.size > 18 * 1024 * 1024) {
        emit({ kind: "image", error: "file too large", name: file.name || "" });
        return;
      }
      shrink(file, function (err, dataUrl) {
        if (err) {
          emit({ kind: "image", error: err, name: file.name || "" });
          return;
        }
        var comma = String(dataUrl || "").indexOf(",");
        var b64 = comma >= 0 ? dataUrl.slice(comma + 1) : String(dataUrl || "");
        emit({ kind: "image", name: file.name || "image.jpg", type: "image/jpeg", data: b64 });
      });
    });
    document.body.appendChild(input);
    document.body.appendChild(button);
    return button;
  }

  root.qiyunjuFiles = {
    place: function (x, y, w, h, vpW, vpH) {
      var el = ensure();
      if (!el) return;
      var box = canvasBox();
      var css = root.qiyunjuIme && root.qiyunjuIme.placeCss
        ? root.qiyunjuIme.placeCss(+x, +y, +w, +h, +vpW, +vpH, box.left, box.top, box.width, box.height)
        : { left: +x, top: +y, width: +w, height: +h };
      el.style.display = "block";
      el.setAttribute("aria-hidden", "false");
      el.style.left = css.left + "px";
      el.style.top = css.top + "px";
      el.style.width = Math.max(44, css.width) + "px";
      el.style.height = Math.max(36, css.height) + "px";
    },
    hide: function () {
      if (!button) return;
      button.style.display = "none";
      button.setAttribute("aria-hidden", "true");
    }
  };
})(typeof window !== "undefined" ? window : globalThis);
