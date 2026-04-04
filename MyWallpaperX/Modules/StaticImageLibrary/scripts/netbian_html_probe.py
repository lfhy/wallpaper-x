#!/usr/bin/env python3

"""
Minimal probe for pic.netbian.com public HTML pages.

Purpose:
- Fetch a public Netbian page with a browser-like UA
- Report whether we received real page HTML or a WAF interception page
- Extract obvious image / original-image hints from the response body

This script is diagnostic only. It does not bypass anti-bot protections.
"""

from __future__ import annotations

import argparse
import html
import re
import sys
import urllib.error
import urllib.request
from typing import Iterable


DEFAULT_URL = "https://pic.netbian.com/"
DEFAULT_TIMEOUT = 30.0
DEFAULT_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/135.0.0.0 Safari/537.36"
)


def fetch(url: str, timeout: float) -> tuple[str, int, dict[str, str]]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": DEFAULT_UA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "Referer": "https://pic.netbian.com/",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            headers = {key.lower(): value for key, value in response.headers.items()}
            return body, response.status, headers
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        headers = {key.lower(): value for key, value in error.headers.items()}
        return body, error.code, headers


def extract_title(body: str) -> str | None:
    match = re.search(r"<title>(.*?)</title>", body, flags=re.IGNORECASE | re.DOTALL)
    if not match:
        return None
    return html.unescape(re.sub(r"\s+", " ", match.group(1)).strip())


def looks_like_baidu_waf(body: str, status: int) -> bool:
    markers = [
        "baidu_waf_intercept_page",
        "由于您的访问存在安全风险，已经被拦截",
        "cloud.baidu.com/product/waf.html",
        "request-id:",
    ]
    return status == 403 and any(marker in body for marker in markers)


def extract_candidate_urls(body: str) -> list[str]:
    candidates = set()
    for match in re.findall(r'https?://[^"\'<>\s]+', body):
        candidates.add(match)
    for match in re.findall(r'["\'](/[^"\']+)["\']', body):
        if any(token in match for token in ("tupian", "uploads", "down", "pic", "jpg", "png", "webp")):
            candidates.add(match)
    return sorted(candidates)


def extract_original_image_hints(body: str) -> list[str]:
    hints = set()
    patterns: Iterable[str] = [
        r"高清原图(?:\([^)]*\))?",
        r"/uploads/[A-Za-z0-9_./%-]+\.(?:jpg|jpeg|png|webp)",
        r"/downpic/[A-Za-z0-9_./%-]+",
        r"/tupian/\d+\.html",
        r"img src=\"([^\"]+)\"",
    ]
    for pattern in patterns:
        for match in re.findall(pattern, body, flags=re.IGNORECASE):
            if isinstance(match, tuple):
                for item in match:
                    if item:
                        hints.add(item)
            elif match:
                hints.add(match)
    return sorted(hints)


def print_section(title: str) -> None:
    print(f"\n== {title} ==")


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe pic.netbian.com HTML page accessibility.")
    parser.add_argument("url", nargs="?", default=DEFAULT_URL, help="URL to probe")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="Network timeout in seconds")
    args = parser.parse_args()

    try:
        body, status, headers = fetch(args.url, args.timeout)
    except urllib.error.URLError as error:
        print(f"request failed: {error.reason}", file=sys.stderr)
        return 1

    title = extract_title(body) or "(no title)"
    waf = looks_like_baidu_waf(body, status)
    candidate_urls = extract_candidate_urls(body)
    image_hints = extract_original_image_hints(body)

    print(f"url: {args.url}")
    print(f"status: {status}")
    print(f"server: {headers.get('server', '(unknown)')}")
    print(f"title: {title}")
    print(f"content-length: {len(body)}")
    print(f"baidu_waf_intercept: {'yes' if waf else 'no'}")

    if waf:
        print_section("Diagnosis")
        print("Received a Baidu WAF interception page instead of the real Netbian HTML.")
        print("This means the current client/request fingerprint cannot inspect the real DOM directly.")

    if image_hints:
        print_section("Original Image Hints")
        for item in image_hints[:40]:
            print(item)

    if candidate_urls:
        print_section("Candidate URLs")
        for item in candidate_urls[:40]:
            print(item)

    print_section("Body Preview")
    preview = re.sub(r"\s+", " ", body[:1200]).strip()
    print(preview)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
