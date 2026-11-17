#!/usr/bin/env python3
"""Copy PWA / media assets next to a Godot web export and inject head tags."""
import re
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
<script src="qiyunju_ime.js"></script>
<script src="qiyunju_files.js"></script>
<script>
if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js').catch(function () {});
  });
}
</script>
<style id="qiyunju-viewport-lock">
html, body { overflow: hidden !important; overscroll-behavior: none; width: 100%; height: 100%; }
</style>
"""

VIEWPORT = (
    '<meta name="viewport" content="width=device-width, initial-scale=1, '
    'minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover, '
    'interactive-widget=resizes-content">'
)


def inject(dest: Path) -> None:
    dest = dest.resolve()
    if not dest.is_dir():
        raise SystemExit(f"not a directory: {dest}")
    html_path = dest / "index.html"
    if not html_path.exists():
        raise SystemExit(f"missing {html_path}")
    for name in ("qiyunju_media.js", "qiyunju_ime.js", "qiyunju_files.js", "manifest.webmanifest", "sw.js", "pip.html"):
        src = WEB / name
        if src.exists():
            shutil.copy2(src, dest / name)
    html = html_path.read_text(encoding="utf-8")
    if "manifest.webmanifest" not in html:
        html = html.replace("</head>", HEAD + "</head>", 1)
    if "qiyunju_ime.js" not in html:
        html = html.replace("</head>", '<script src="qiyunju_ime.js"></script>\n</head>', 1)
    if "qiyunju_files.js" not in html:
        html = html.replace("</head>", '<script src="qiyunju_files.js"></script>\n</head>', 1)
    if "qiyunju-viewport-lock" not in html:
        html = html.replace(
            "</head>",
            '<style id="qiyunju-viewport-lock">html, body { overflow: hidden !important; overscroll-behavior: none; width: 100%; height: 100%; }</style>\n</head>',
            1,
        )
    html = re.sub(r"<meta name=\"viewport\"[^>]*>\s*", "", html, flags=re.IGNORECASE)
    html = html.replace("<head>", "<head>\n\t\t" + VIEWPORT, 1)
    html_path.write_text(html, encoding="utf-8")
    print("pwa injected:", dest)


if __name__ == "__main__":
    inject(Path(sys.argv[1] if len(sys.argv) > 1 else "docs"))
