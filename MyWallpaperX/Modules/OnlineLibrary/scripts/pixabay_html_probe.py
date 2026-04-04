#!/usr/bin/env python3

"""
Minimal probe for Pixabay public HTML pages.

Purpose:
- Fetch a public Pixabay page with a normal browser-like UA
- Report whether we received real page HTML or a Cloudflare challenge page
- Extract obvious URLs / endpoint hints from the response body for inspection

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


DEFAULT_URL = "https://pixabay.com/videos/search/?order=ec"
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
            "Accept-Language": "en-US,en;q=0.9",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
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


def looks_like_cloudflare_challenge(body: str, headers: dict[str, str]) -> bool:
    markers = [
        "Just a moment...",
        "Enable JavaScript and cookies to continue",
        "_cf_chl_opt",
        "/cdn-cgi/challenge-platform/",
    ]
    server = headers.get("server", "")
    return "cloudflare" in server.lower() or any(marker in body for marker in markers)


def extract_candidate_urls(body: str) -> list[str]:
    candidates = set()
    for match in re.findall(r'https?://[^"\'<>\s]+', body):
        candidates.add(match)
    for match in re.findall(r'["\'](/[^"\']+)["\']', body):
        if any(token in match for token in ("api", "video", "search", "graphql", "ajax", "cdn-cgi")):
            candidates.add(match)
    return sorted(candidates)


def extract_endpoint_hints(body: str) -> list[str]:
    hints = set()
    patterns: Iterable[str] = [
        r"/api/[A-Za-z0-9_./?=&%-]+",
        r"/videos/[A-Za-z0-9_./?=&%-]+",
        r"/search/[A-Za-z0-9_./?=&%-]+",
        r"/cdn-cgi/[A-Za-z0-9_./?=&%-]+",
        r"pixabay\.com/api/[A-Za-z0-9_./?=&%-]+",
        r"pixabay\.com/api/videos/[A-Za-z0-9_./?=&%-]+",
    ]
    for pattern in patterns:
        for match in re.findall(pattern, body):
            hints.add(match)
    return sorted(hints)


def print_section(title: str) -> None:
    print(f"\n== {title} ==")


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe Pixabay HTML page accessibility.")
    parser.add_argument("url", nargs="?", default=DEFAULT_URL, help="URL to probe")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="Network timeout in seconds")
    args = parser.parse_args()

    try:
        body, status, headers = fetch(args.url, args.timeout)
    except urllib.error.URLError as error:
        print(f"request failed: {error.reason}", file=sys.stderr)
        return 1

    title = extract_title(body) or "(no title)"
    cloudflare = looks_like_cloudflare_challenge(body, headers)
    candidate_urls = extract_candidate_urls(body)
    endpoint_hints = extract_endpoint_hints(body)

    print(f"url: {args.url}")
    print(f"status: {status}")
    print(f"server: {headers.get('server', '(unknown)')}")
    print(f"title: {title}")
    print(f"content-length: {len(body)}")
    print(f"cloudflare_challenge: {'yes' if cloudflare else 'no'}")

    if cloudflare:
        print_section("Diagnosis")
        print("Received a Cloudflare challenge page instead of the actual Pixabay search HTML.")
        print("This means direct script fetching cannot currently inspect the real DOM or discover page-fed JSON safely.")

    if endpoint_hints:
        print_section("Endpoint Hints")
        for item in endpoint_hints[:30]:
            print(item)

    if candidate_urls:
        print_section("Candidate URLs")
        for item in candidate_urls[:30]:
            print(item)

    print_section("Body Preview")
    preview = re.sub(r"\s+", " ", body[:1200]).strip()
    print(preview)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
