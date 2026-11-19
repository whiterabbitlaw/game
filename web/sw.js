/* 栖云居 PWA：外壳网络优先，避免手机浏览器一直用旧缓存。 */
const SHELL = "qiyunju-shell-v12";
const SHELL_URLS = ["./", "./index.html", "./index.js", "./manifest.webmanifest", "./qiyunju_media.js", "./qiyunju_chat.js", "./qiyunju_ime.js", "./qiyunju_files.js", "./pip.html"];
const NETWORK_FIRST = /(?:\/$|index\.html$|index\.js$|qiyunju_media\.js$|qiyunju_chat\.js$|qiyunju_ime\.js$|qiyunju_files\.js$|sw\.js$|manifest\.webmanifest$|pip(?:\.html)?$)/;

self.addEventListener("install", function (e) {
  e.waitUntil(caches.open(SHELL).then(function (c) { return c.addAll(SHELL_URLS); }).then(function () { self.skipWaiting(); }));
});
self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return k !== SHELL; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { self.clients.claim(); }));
});
self.addEventListener("fetch", function (e) {
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  if (url.origin !== location.origin) return;
  if (NETWORK_FIRST.test(url.pathname)) {
    e.respondWith(
      fetch(req).then(function (res) {
        if (res && res.ok && res.type === "basic") {
          var copy = res.clone();
          caches.open(SHELL).then(function (c) { c.put(req, copy); });
        }
        return res;
      }).catch(function () { return caches.match(req).then(function (hit) { return hit || Promise.reject(); }); })
    );
    return;
  }
  e.respondWith(
    caches.match(req).then(function (hit) {
      if (hit) return hit;
      return fetch(req).then(function (res) {
        if (res && res.ok && res.type === "basic") {
          var copy = res.clone();
          caches.open(SHELL).then(function (c) { c.put(req, copy); });
        }
        return res;
      });
    })
  );
});
