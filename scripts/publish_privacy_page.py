#!/usr/bin/env python3
"""Publish PRIVACY.md as https://divinedavis.com/barrel/privacy/.

    python3 scripts/publish_privacy_page.py            # build, copy to the web host, check it is live
    python3 scripts/publish_privacy_page.py --build    # only write the page into the website checkout

The app, the App Store listing and the README all link to that page
(LegalLinks.privacyPolicy), so run this in the same change as any edit to
PRIVACY.md. The page is static, with a content-security policy that allows no
scripts. Needs pandoc (brew install pandoc) and the Personal-Website checkout
beside this one; commit the regenerated page there too.
"""
from __future__ import annotations

import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = Path(sys.argv[sys.argv.index("--site") + 1]) if "--site" in sys.argv else ROOT.parent / "Personal-Website"
PAGE = SITE / "barrel" / "privacy" / "index.html"
HOST = "root@104.236.120.144"
DOCROOT = "/var/www/divinedavis/barrel/privacy/"
URL = "https://divinedavis.com/barrel/privacy/"
CSP = ("default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; script-src 'none'; "
       "connect-src 'none'; object-src 'none'; base-uri 'self'; form-action 'none'")

SHELL = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Privacy Policy — Barrel Baseball</title>
    <meta http-equiv="Content-Security-Policy" content="%(csp)s">
    <link rel="stylesheet" href="/style.css">
    <style>
        .container { max-width: 760px; }
        h1 { font-size: 1.8em; font-weight: 600; margin-bottom: 8px; color: #000; }
        h2 { font-size: 1.2em; font-weight: 600; margin-top: 28px; margin-bottom: 10px; color: #000; }
        h3 { font-size: 1.05em; font-weight: 600; margin-top: 20px; margin-bottom: 8px; color: #000; }
        p, ul { margin-bottom: 14px; color: #444; }
        ul { padding-left: 24px; }
        li { margin-bottom: 6px; }
        .lede { font-size: 1.05em; color: #333; margin-bottom: 24px; }
        a { color: #0066cc; text-decoration: none; }
        a:hover { text-decoration: underline; }
        code { font-size: 0.92em; background: #f3f3f3; padding: 1px 4px; border-radius: 3px; }
        .contact-card { background: #f7f7f7; border-radius: 8px; padding: 20px 24px; margin-top: 32px; }
        .contact-card p { margin-bottom: 6px; }
        .table-wrap { overflow-x: auto; margin-bottom: 18px; }
        table { border-collapse: collapse; width: 100%%; font-size: 0.92em; }
        th, td { border: 1px solid #ddd; padding: 8px 10px; text-align: left; vertical-align: top; color: #444; }
        th { background: #f7f7f7; color: #000; font-weight: 600; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h2 class="site-title">Divine Davis</h2>
            <nav>
                <a href="/">Home</a> &raquo;
                <a href="/barrel/privacy/">Barrel privacy</a> &raquo;
            </nav>
        </header>

        <main>
%(body)s
        </main>
    </div>
</body>
</html>
"""


def build() -> str:
    body = subprocess.run(["pandoc", "-f", "gfm", "-t", "html5", "--wrap=none", str(ROOT / "PRIVACY.md")],
                          check=True, capture_output=True, text=True).stdout
    body = re.sub(r"<h1[^>]*>.*?</h1>", "<h1>Barrel Baseball — Privacy Policy</h1>", body, count=1, flags=re.S)
    body = re.sub(r' id="[^"]*"', "", body)
    body = re.sub(r"<colgroup>.*?</colgroup>", "", body, flags=re.S)
    body = re.sub(r' style="[^"]*"', "", body)          # the CSP allows styles, but the page needs none inline
    body = re.sub(r"<strong>([\w.+-]+@[\w.-]+\.\w+)</strong>", r'<a href="mailto:\1">\1</a>', body)
    body = body.replace("<table>", '<div class="table-wrap"><table>').replace("</table>", "</table></div>")
    return SHELL % {"csp": CSP, "body": body}


def main() -> int:
    if not SITE.is_dir():
        raise SystemExit(f"website checkout not found: {SITE} (pass --site <path>)")
    html = build()
    if "<script" in html.lower():
        raise SystemExit("the policy must not carry a script")
    PAGE.parent.mkdir(parents=True, exist_ok=True)
    changed = not PAGE.exists() or PAGE.read_text() != html
    PAGE.write_text(html)
    print(f"{'wrote' if changed else 'unchanged'}: {PAGE}")
    if "--build" in sys.argv:
        return 0
    subprocess.run(["ssh", "-o", "BatchMode=yes", HOST, f"mkdir -p {DOCROOT}"], check=True)
    subprocess.run(["scp", "-q", str(PAGE), f"{HOST}:{DOCROOT}index.html"], check=True)
    subprocess.run(["ssh", "-o", "BatchMode=yes", HOST,
                    f"chown www-data:www-data {DOCROOT}index.html && chmod 644 {DOCROOT}index.html"], check=True)
    live = urllib.request.urlopen(URL, timeout=30).read().decode("utf-8")
    if live != html:
        raise SystemExit(f"{URL} does not serve the page just copied")
    print(f"live: {URL}")
    print(f"now commit {PAGE.relative_to(SITE)} in {SITE.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
