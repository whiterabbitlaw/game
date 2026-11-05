#!/bin/bash
# Cloudflare Pages 单文件上限 25MiB：主包不含配音（WebLite），配音单独成 voices.pck，wasm 以 .gz 存放并由 index.html 里的小脚本解压。
set -e
cd "$(dirname "$0")/.."
G=${GODOT:-/workspace/tools/Godot_v4.7.2-stable_linux.x86_64}
rm -rf build/web_lite && mkdir -p build/web_lite
$G --headless --path . --export-release WebLite build/web_lite/index.html
$G --headless --path . --export-pack Voices build/web_lite/voices.pck
rm -rf build/cf && cp -r build/web_lite build/cf && cd build/cf
gzip -9 -n index.wasm
python3 - <<'PY'
s=open('index.html',encoding='utf-8').read()
patch='''<script>
(function(){var of=window.fetch.bind(window);window.fetch=function(i,o){var u=(typeof i==='string')?i:(i&&i.url)||'';
if(/index\\.wasm(\\?.*)?$/.test(u)){return of(u.replace(/index\\.wasm/,'index.wasm.gz'),o).then(function(r){
var ds=r.body.pipeThrough(new DecompressionStream('gzip'));return new Response(ds,{status:200,headers:{'Content-Type':'application/wasm'}});});}
return of(i,o);};})();
</script>
'''
open('index.html','w',encoding='utf-8').write(s.replace('</head>',patch+'</head>',1))
PY
echo "output: build/cf"
