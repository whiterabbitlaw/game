#!/usr/bin/env python3
"""Copy PWA / media assets next to a Godot web export and inject head tags."""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "web"
HEAD = """
<link rel="manifest" href="manifest.webmanifest">
<meta name="theme-color" content="#3d3358">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="栖云居">
<link rel="apple-touch-icon" href="index.apple-touch-icon.png">
<script src="qiyunju_media.js"></script>
<script>
if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js').catch(function () {});
  });
}
</script>
"""


def inject(dest: Path) -> None:
    dest = dest.resolve()
    if not dest.is_dir():
        raise SystemExit(f"not a directory: {dest}")
    html_path = dest / "index.html"
    if not html_path.exists():
        raise SystemExit(f"missing {html_path}")
    for name in ("qiyunju_media.js", "manifest.webmanifest", "sw.js", "pip.html"):
        src = WEB / name
        if src.exists():
            shutil.copy2(src, dest / name)
    html = html_path.read_text(encoding="utf-8")
    if "manifest.webmanifest" not in html:
        html = html.replace("</head>", HEAD + "</head>", 1)
        html_path.write_text(html, encoding="utf-8")
    print("pwa injected:", dest)


if __name__ == "__main__":
    inject(Path(sys.argv[1] if len(sys.argv) > 1 else "docs"))
