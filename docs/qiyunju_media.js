/* 栖云居网页媒体：麦克风 VAD、视频抽帧、Document Picture-in-Picture。 */
(function (global) {
  var media = global.qiyunjuMedia || {};
  var stream = null;
  var ctx = null;
  var processor = null;
  var source = null;
  var analyser = null;
  var recording = false;
  var mode = "push";
  var speakingOut = false;
  var samples = [];
  var sampleRate = 16000;
  var speechMs = 0;
  var silenceMs = 0;
  var started = false;
  var THRESH = 0.025;
  var BARGE = 0.06;
  var SILENCE = 900;
  var MIN_SPEECH = 280;
  var bargeMs = 0;
  var raf = 0;
  var busy = false;

  function emit(obj) {
    try {
      var s = JSON.stringify(obj);
      if (typeof global.qiyunjuOnMedia === "function") global.qiyunjuOnMedia(s);
    } catch (e) {}
  }

  function rms(arr) {
    if (!arr.length) return 0;
    var a = 0;
    for (var i = 0; i < arr.length; i++) a += arr[i] * arr[i];
    return Math.sqrt(a / arr.length);
  }

  function downsample(float32, fromRate, toRate) {
    if (fromRate === toRate) return float32;
    var step = fromRate / toRate;
    var out = [];
    for (var x = 0; x < float32.length; x += step) out.push(float32[Math.floor(x)] || 0);
    return out;
  }

  function encodeWav(floatArr, rate) {
    var n = floatArr.length;
    var buf = new ArrayBuffer(44 + n * 2);
    var v = new DataView(buf);
    function str(o, s) { for (var i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); }
    str(0, "RIFF");
    v.setUint32(4, 36 + n * 2, true);
    str(8, "WAVE");
    str(12, "fmt ");
    v.setUint32(16, 16, true);
    v.setUint16(20, 1, true);
    v.setUint16(22, 1, true);
    v.setUint32(24, rate, true);
    v.setUint32(28, rate * 2, true);
    v.setUint16(32, 2, true);
    v.setUint16(34, 16, true);
    str(36, "data");
    v.setUint32(40, n * 2, true);
    var o = 44;
    for (var i = 0; i < n; i++, o += 2) {
      var s = Math.max(-1, Math.min(1, floatArr[i]));
      v.setInt16(o, s < 0 ? s * 0x8000 : s * 0x7fff, true);
    }
    var bytes = new Uint8Array(buf);
    var bin = "";
    for (var j = 0; j < bytes.length; j++) bin += String.fromCharCode(bytes[j]);
    return btoa(bin);
  }

  function flushUtterance() {
    recording = false;
    started = false;
    speechMs = 0;
    silenceMs = 0;
    var arr = samples;
    samples = [];
    if (arr.length < sampleRate * 0.25) {
      emit({ type: "error", message: "说话时间太短" });
      if (mode === "handsfree") emit({ type: "state", state: "listening" });
      return;
    }
    if (arr.length > sampleRate * 15) arr = arr.slice(arr.length - sampleRate * 15);
    emit({ type: "audio", mime: "audio/wav", data: encodeWav(arr, sampleRate) });
  }

  function onAudio(floatFromRate, fromRate) {
    var mono = downsample(floatFromRate, fromRate, sampleRate);
    if (mode === "push") {
      if (recording) for (var i = 0; i < mono.length; i++) samples.push(mono[i]);
      return;
    }
    var level = rms(mono);
    var dt = 1000 * mono.length / sampleRate;
    if (speakingOut && !recording) {
      if (level >= BARGE) {
        bargeMs += dt;
        if (bargeMs >= 180) {
          bargeMs = 0;
          recording = true;
          started = true;
          samples = mono.slice();
          emit({ type: "barge" });
          emit({ type: "state", state: "listening", detail: "打断" });
        }
      } else bargeMs = 0;
      return;
    }
    if (busy && !recording) return;
    if (!recording) {
      if (level >= THRESH) {
        speechMs += dt;
        if (speechMs >= MIN_SPEECH) {
          recording = true;
          started = true;
          silenceMs = 0;
          samples = mono.slice();
          emit({ type: "state", state: "listening" });
        }
      } else speechMs = 0;
      return;
    }
    for (var k = 0; k < mono.length; k++) samples.push(mono[k]);
    if (level < THRESH) {
      silenceMs += dt;
      if (silenceMs >= SILENCE) flushUtterance();
    } else silenceMs = 0;
  }

  media.init = function () {};

  media.startMic = async function (opts) {
    opts = opts || {};
    mode = opts.mode || "handsfree";
    try {
      if (!stream) {
        stream = await navigator.mediaDevices.getUserMedia({
          audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
        });
      }
      if (!ctx) {
        ctx = new (window.AudioContext || window.webkitAudioContext)();
        source = ctx.createMediaStreamSource(stream);
        analyser = ctx.createAnalyser();
        analyser.fftSize = 2048;
        source.connect(analyser);
        processor = ctx.createScriptProcessor(4096, 1, 1);
        processor.onaudioprocess = function (ev) {
          var data = ev.inputBuffer.getChannelData(0);
          var copy = new Float32Array(data.length);
          copy.set(data);
          onAudio(copy, ev.inputBuffer.sampleRate || ctx.sampleRate || 48000);
        };
        analyser.connect(processor);
        var mute = ctx.createGain();
        mute.gain.value = 0;
        processor.connect(mute);
        mute.connect(ctx.destination);
      }
      if (ctx.state === "suspended") await ctx.resume();
      samples = [];
      recording = mode === "push";
      started = false;
      speechMs = 0;
      silenceMs = 0;
      emit({ type: "state", state: "listening", detail: mode === "push" ? "按住说话" : "免提" });
    } catch (err) {
      emit({ type: "error", message: "无法打开麦克风：" + (err && err.message ? err.message : err) });
    }
  };

  media.stopMic = function () {
    recording = false;
    samples = [];
    if (stream) {
      stream.getTracks().forEach(function (t) { t.stop(); });
      stream = null;
    }
    if (processor) {
      try { processor.disconnect(); } catch (e) {}
      processor = null;
    }
    if (source) {
      try { source.disconnect(); } catch (e) {}
      source = null;
    }
    if (ctx) {
      try { ctx.close(); } catch (e) {}
      ctx = null;
    }
  };

  media.pttDown = function () {
    mode = "push";
    recording = true;
    samples = [];
    emit({ type: "state", state: "listening", detail: "按住说话" });
  };

  media.pttUp = function () {
    if (recording) flushUtterance();
    recording = false;
  };

  media.setSpeaking = function (on) {
    speakingOut = !!on;
    bargeMs = 0;
  };

  media.setBusy = function (on) {
    busy = !!on;
  };

  media.sampleVideo = function (file, count) {
    count = count || 4;
    return new Promise(function (resolve, reject) {
      var url = URL.createObjectURL(file);
      var video = document.createElement("video");
      video.muted = true;
      video.preload = "auto";
      video.src = url;
      var done = false;
      function fail(msg) {
        if (done) return;
        done = true;
        URL.revokeObjectURL(url);
        reject(new Error(msg));
      }
      video.onerror = function () { fail("无法读取视频"); };
      video.onloadedmetadata = function () {
        var dur = video.duration || 0;
        var times = [];
        if (dur <= 0.2) times = [Math.max(0, dur / 2)];
        else {
          var a = dur * 0.12, b = dur * 0.88;
          for (var k = 0; k < count; k++) times.push(a + (b - a) * (k / Math.max(1, count - 1)));
        }
        var canvas = document.createElement("canvas");
        var w = video.videoWidth || 640;
        var h = video.videoHeight || 360;
        var scale = Math.min(1, 640 / Math.max(w, 1));
        canvas.width = Math.max(1, Math.round(w * scale));
        canvas.height = Math.max(1, Math.round(h * scale));
        var ctx2 = canvas.getContext("2d");
        var frames = [];
        var i = 0;
        function next() {
          if (i >= times.length) {
            done = true;
            URL.revokeObjectURL(url);
            resolve(frames);
            return;
          }
          var t = times[i++];
          var onSeek = function () {
            try {
              ctx2.drawImage(video, 0, 0, canvas.width, canvas.height);
              var dataUrl = canvas.toDataURL("image/jpeg", 0.7);
              var b64 = dataUrl.split(",")[1] || "";
              frames.push({ mime: "image/jpeg", data: b64, t: t });
            } catch (e) {}
            next();
          };
          video.onseeked = onSeek;
          try { video.currentTime = Math.min(Math.max(0, t), Math.max(0, dur - 0.05)); }
          catch (e) { next(); }
        }
        next();
      };
    });
  };

  media.pickVideo = function () {
    var input = document.createElement("input");
    input.type = "file";
    input.accept = "video/*";
    input.onchange = function () {
      var f = input.files && input.files[0];
      if (!f) {
        emit({ type: "error", message: "没有选择视频" });
        return;
      }
      if (f.size > 40 * 1024 * 1024) {
        emit({ type: "error", message: "视频过大，请选 40MB 以内的片段" });
        return;
      }
      emit({ type: "state", state: "thinking", detail: "正在抽帧" });
      media.sampleVideo(f, 4).then(function (frames) {
        emit({ type: "frames", frames: frames, name: f.name });
      }).catch(function (e) {
        emit({ type: "error", message: (e && e.message) || "抽帧失败" });
      });
    };
    input.click();
  };

  var pipWin = null;

  media.pipAvailable = function () {
    return !!(document.pictureInPictureEnabled && global.documentPictureInPicture);
  };

  media.openPip = async function () {
    if (!global.documentPictureInPicture) {
      emit({ type: "pip", event: "unsupported" });
      return;
    }
    try {
      pipWin = await documentPictureInPicture.requestWindow({ width: 380, height: 640 });
      var res = await fetch("pip.html", { cache: "no-store" });
      var html = await res.text();
      pipWin.document.open();
      pipWin.document.write(html);
      pipWin.document.close();
      pipWin.addEventListener("pagehide", function () {
        pipWin = null;
        emit({ type: "pip", event: "closed" });
      });
      function bind() {
        var send = pipWin.document.getElementById("send");
        var inp = pipWin.document.getElementById("inp");
        var ptt = pipWin.document.getElementById("ptt");
        if (send) send.addEventListener("click", function () {
          var t = (inp && inp.value || "").trim();
          if (!t) return;
          if (inp) inp.value = "";
          emit({ type: "pip", event: "send", text: t });
        });
        if (inp) inp.addEventListener("keydown", function (e) {
          if (e.key === "Enter") { e.preventDefault(); send && send.click(); }
        });
        if (ptt) {
          ptt.addEventListener("pointerdown", function () { emit({ type: "pip", event: "ptt_down" }); });
          ptt.addEventListener("pointerup", function () { emit({ type: "pip", event: "ptt_up" }); });
          ptt.addEventListener("pointerleave", function () { emit({ type: "pip", event: "ptt_up" }); });
        }
      }
      setTimeout(bind, 50);
      emit({ type: "pip", event: "opened" });
    } catch (e) {
      emit({ type: "pip", event: "error", message: (e && e.message) || "无法打开画中画" });
    }
  };

  media.updatePip = function (payload) {
    if (!pipWin) return;
    try {
      if (typeof pipWin.qiyunjuUpdate === "function") pipWin.qiyunjuUpdate(payload);
    } catch (e) {}
  };

  media.closePip = function () {
    try { if (pipWin) pipWin.close(); } catch (e) {}
    pipWin = null;
  };

  global.qiyunjuMedia = media;
})(window);
