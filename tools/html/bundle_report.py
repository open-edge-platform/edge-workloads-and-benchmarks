# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

"""Bundle the HTML dashboard into a single self-contained HTML file.

Usage:
    python3 bundle_report.py [report_name]

Output is written to collateral/reports/<timestamp>/<report_name>.html.
Defaults to "report" if no name is provided.

The output file contains all CSS, JS (including Chart.js), and benchmark
data inlined — no external dependencies, no server required.
"""

from __future__ import annotations

import re
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

HTML_DIR = Path(__file__).resolve().parent
CHARTJS_URL = "https://cdn.jsdelivr.net/npm/chart.js@4.4.9/dist/chart.umd.min.js"
CHARTJS_CACHE = HTML_DIR / ".chartjs_cache.js"


def fetch_chartjs() -> str:
    """Download Chart.js (cached locally to avoid repeated downloads)."""
    if CHARTJS_CACHE.exists():
        return CHARTJS_CACHE.read_text(encoding="utf-8")
    if not CHARTJS_URL.startswith(("https://",)):
        raise ValueError(f"Refusing to fetch from non-HTTPS URL: {CHARTJS_URL}")
    print(f"[ Info ] Downloading Chart.js from {CHARTJS_URL}")
    req = urllib.request.Request(CHARTJS_URL)
    with urllib.request.urlopen(req, timeout=30) as resp:  # nosec B310
        js = resp.read().decode("utf-8")
    CHARTJS_CACHE.write_text(js, encoding="utf-8")
    return js


def bundle(output_path: Path) -> None:
    html = (HTML_DIR / "index.html").read_text(encoding="utf-8")
    css = (HTML_DIR / "styles.css").read_text(encoding="utf-8")
    dashboard_js = (HTML_DIR / "dashboard.js").read_text(encoding="utf-8")
    data_json = (HTML_DIR / "data.json").read_text(encoding="utf-8")
    system_info_json = (HTML_DIR / "system_info.json").read_text(encoding="utf-8")
    chartjs = fetch_chartjs()

    # --- Patch dashboard.js to use inlined data instead of fetch() ---
    # Replace loadData: use window.__BUNDLE_DATA__ if present
    dashboard_js = dashboard_js.replace(
        "const response = await fetch('data.json');",
        "const response = window.__BUNDLE_DATA__"
        " ? { ok: true, json: async () => window.__BUNDLE_DATA__ }"
        " : await fetch('data.json');",
    )
    # Replace loadSystemInfo: use window.__BUNDLE_SYSTEM_INFO__ if present
    dashboard_js = dashboard_js.replace(
        "const response = await fetch('system_info.json');",
        "const response = window.__BUNDLE_SYSTEM_INFO__"
        " ? { ok: true, json: async () => window.__BUNDLE_SYSTEM_INFO__ }"
        " : await fetch('system_info.json');",
    )

    # --- Inline CSS ---
    html = html.replace(
        '<link rel="stylesheet" href="styles.css">',
        f"<style>\n{css}\n</style>",
    )

    # --- Remove Google Fonts preconnect + stylesheet (offline fallback via CSS) ---
    html = re.sub(
        r"<link\s+rel=['\"]preconnect['\"].*?>\s*\n?",
        "",
        html,
    )
    html = re.sub(
        r"<link\s+href=['\"]https://fonts\.googleapis\.com/.*?>\s*\n?",
        "",
        html,
    )

    # --- Inline Chart.js ---
    chartjs_tag = re.search(
        r"<script\s+src=['\"]https://cdn\.jsdelivr\.net/npm/chart\.js['\"]>\s*</script>",
        html,
    )
    if chartjs_tag:
        html = html[:chartjs_tag.start()] + f"<script>\n{chartjs}\n</script>" + html[chartjs_tag.end():]

    # --- Inline data + system_info as JS globals, then dashboard.js ---
    inline_scripts = (
        f"<script>\nwindow.__BUNDLE_DATA__ = {data_json};\n"
        f"window.__BUNDLE_SYSTEM_INFO__ = {system_info_json};\n</script>\n"
        f"<script>\n{dashboard_js}\n</script>"
    )
    dashboard_tag = re.search(
        r"<script\s+src=['\"]dashboard\.js['\"]>\s*</script>",
        html,
    )
    if dashboard_tag:
        html = html[:dashboard_tag.start()] + inline_scripts + html[dashboard_tag.end():]

    # --- Write output ---
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(html, encoding="utf-8")
    size_kb = output_path.stat().st_size / 1024
    print(f"[ Info ] Bundled report: {output_path}  ({size_kb:.0f} KB)")


def main() -> int:
    reports_root = Path(__file__).resolve().parent.parent.parent / "collateral" / "reports"
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    name = sys.argv[1] if len(sys.argv) > 1 else "report"
    output = reports_root / timestamp / f"{name}.html"
    bundle(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
