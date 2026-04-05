#!/usr/bin/env python3
"""
匿名探测 Steam 作者工坊页的分页数量。

只抓作者工坊分页 HTML，不抓详情。
输出每页抓到的 publishedfileid 数量、累计数量和下一页线索。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass


ITEM_ID_RE = re.compile(r'data-publishedfileid="(\d+)"')
TOTAL_HINT_RE = re.compile(r"Showing\s+([\d,]+)-([\d,]+)\s+of\s+([\d,]+)", re.IGNORECASE)
HOVER_PAYLOAD_RE = re.compile(
    r'SharedFileBindMouseHover\(\s*"sharedfile_(\d+)"\s*,\s*false\s*,\s*(\{.*?\})\s*\);',
    re.IGNORECASE | re.DOTALL,
)


@dataclass
class PageResult:
    page: int
    count: int
    unique_count: int
    cumulative_unique_count: int
    video_like_count: int
    other_type_count: int
    unknown_type_count: int
    total_hint: str | None
    next_page_hint: bool
    url: str
    error: str | None = None


def build_author_url(base_url: str, page: int, app_id: str | None, page_size: int) -> str:
    parsed = urllib.parse.urlparse(base_url)
    query = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
    filtered = [(k, v) for (k, v) in query if k not in {"appid", "p", "numperpage"}]
    if app_id:
        filtered.insert(0, ("appid", app_id))
    filtered.append(("p", str(max(1, page))))
    filtered.append(("numperpage", str(page_size)))
    updated = parsed._replace(query=urllib.parse.urlencode(filtered))
    return urllib.parse.urlunparse(updated)


def fetch_html(url: str, timeout: float, retries: int, pause: float, cookie: str | None) -> str:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX/1.0"
        ),
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
    }
    if cookie:
        headers["Cookie"] = cookie
    request = urllib.request.Request(url, headers=headers)
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                data = response.read()
                return data.decode("utf-8", errors="replace")
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(pause)
    raise RuntimeError(f"request failed after {retries} attempts: {last_error}")


def parse_total_hint(html: str) -> str | None:
    match = TOTAL_HINT_RE.search(html)
    if not match:
        return None
    return f"Showing {match.group(1)}-{match.group(2)} of {match.group(3)}"


def has_next_page_hint(html: str, next_page: int) -> bool:
    patterns = [
        rf'[?&]p={next_page}\b',
        rf'data-panel=\".*?[?&]p={next_page}\b.*?\"',
        rf'href=\"[^\"]*?[?&]p={next_page}\b[^\"]*\"',
    ]
    return any(re.search(pattern, html, re.IGNORECASE) for pattern in patterns)


def collect_string_values(value: object) -> list[str]:
    strings: list[str] = []
    if isinstance(value, str):
        strings.append(value)
    elif isinstance(value, dict):
        for nested in value.values():
            strings.extend(collect_string_values(nested))
    elif isinstance(value, list):
        for nested in value:
            strings.extend(collect_string_values(nested))
    return strings


def parse_type_hints(html: str) -> dict[str, str]:
    type_by_id: dict[str, str] = {}
    for match in HOVER_PAYLOAD_RE.finditer(html):
        item_id = match.group(1)
        payload = match.group(2).replace(r"\/", "/")
        try:
            data = json.loads(payload)
        except Exception:
            continue
        values = [value.strip() for value in collect_string_values(data) if value.strip()]
        lowered = [value.lower() for value in values]
        if any(value == "video" or " type: video" in value or value.startswith("video") for value in lowered):
            type_by_id[item_id] = "video"
            continue
        type_candidates = []
        for value in values:
            lowered_value = value.lower()
            if lowered_value in {"video", "scene", "web", "application", "preset"}:
                type_candidates.append(lowered_value)
            elif lowered_value.startswith("type:"):
                type_candidates.append(lowered_value.split(":", 1)[1].strip())
        if type_candidates:
            candidate = type_candidates[0]
            type_by_id[item_id] = "video" if candidate == "video" else candidate
    return type_by_id


def probe_author_pages(
    base_url: str,
    app_id: str | None,
    page_size: int,
    start_page: int,
    max_pages: int,
    timeout: float,
    retries: int,
    pause: float,
    cookie: str | None,
) -> list[PageResult]:
    results: list[PageResult] = []
    seen_ids: set[str] = set()

    for offset in range(max_pages):
        page = start_page + offset
        url = build_author_url(base_url, page=page, app_id=app_id, page_size=page_size)
        try:
            html = fetch_html(url, timeout=timeout, retries=retries, pause=pause, cookie=cookie)
        except Exception as exc:
            results.append(
                PageResult(
                    page=page,
                    count=0,
                    unique_count=0,
                    cumulative_unique_count=len(seen_ids),
                    video_like_count=0,
                    other_type_count=0,
                    unknown_type_count=0,
                    total_hint=None,
                    next_page_hint=False,
                    url=url,
                    error=str(exc),
                )
            )
            break

        page_ids = ITEM_ID_RE.findall(html)
        type_hints = parse_type_hints(html)
        unique_page_ids = [item_id for item_id in page_ids if item_id not in seen_ids]
        seen_ids.update(page_ids)
        next_hint = has_next_page_hint(html, next_page=page + 1)
        video_like_count = sum(1 for item_id in page_ids if type_hints.get(item_id) == "video")
        other_type_count = sum(
            1 for item_id in page_ids if item_id in type_hints and type_hints.get(item_id) not in {None, "video"}
        )
        unknown_type_count = max(0, len(page_ids) - video_like_count - other_type_count)
        result = PageResult(
            page=page,
            count=len(page_ids),
            unique_count=len(unique_page_ids),
            cumulative_unique_count=len(seen_ids),
            video_like_count=video_like_count,
            other_type_count=other_type_count,
            unknown_type_count=unknown_type_count,
            total_hint=parse_total_hint(html),
            next_page_hint=next_hint,
            url=url,
        )
        results.append(result)

        if len(page_ids) == 0 and not next_hint:
            break
        if len(page_ids) < page_size and not next_hint:
            break

    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe Steam author workshop page counts without fetching item details.")
    parser.add_argument(
        "--url",
        default="https://steamcommunity.com/profiles/76561198166819349/myworkshopfiles/",
        help="Author workshop base URL.",
    )
    parser.add_argument("--appid", default="431960", help="Workshop app id. Pass empty string to probe all app types.")
    parser.add_argument("--page-size", type=int, default=30, help="numperpage value. Default: 30")
    parser.add_argument("--start-page", type=int, default=1, help="Start page. Default: 1")
    parser.add_argument("--max-pages", type=int, default=40, help="Maximum pages to probe. Default: 40")
    parser.add_argument("--timeout", type=float, default=20.0, help="Per-request timeout in seconds. Default: 20")
    parser.add_argument("--retries", type=int, default=3, help="Retries per page. Default: 3")
    parser.add_argument("--pause", type=float, default=1.0, help="Pause between retries in seconds. Default: 1")
    parser.add_argument("--cookie", default=None, help="Optional Steam Community Cookie header value.")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text.")
    args = parser.parse_args()
    app_id = args.appid.strip() or None

    results = probe_author_pages(
        base_url=args.url,
        app_id=app_id,
        page_size=args.page_size,
        start_page=args.start_page,
        max_pages=args.max_pages,
        timeout=args.timeout,
        retries=args.retries,
        pause=args.pause,
        cookie=args.cookie,
    )

    if args.json:
        payload = {
            "base_url": args.url,
            "appid": app_id,
            "page_size": args.page_size,
            "results": [asdict(item) for item in results],
            "final_unique_count": results[-1].cumulative_unique_count if results else 0,
            "final_video_like_count": sum(item.video_like_count for item in results),
            "final_other_type_count": sum(item.other_type_count for item in results),
            "final_unknown_type_count": sum(item.unknown_type_count for item in results),
        }
        json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
        return 0

    print(f"Author URL: {args.url}")
    print(f"AppID: {app_id if app_id else 'ALL'}")
    print(f"Page size: {args.page_size}")
    print("---")
    for item in results:
        line = (
            f"page={item.page} count={item.count} unique={item.unique_count} "
            f"cumulative={item.cumulative_unique_count} next={item.next_page_hint} "
            f"video_like={item.video_like_count} other={item.other_type_count} unknown={item.unknown_type_count}"
        )
        if item.total_hint:
            line += f" total_hint={item.total_hint}"
        if item.error:
            line += f" error={item.error}"
        print(line)
    if results:
        print("---")
        print(f"final_unique_count={results[-1].cumulative_unique_count}")
        print(f"final_video_like_count={sum(item.video_like_count for item in results)}")
        print(f"final_other_type_count={sum(item.other_type_count for item in results)}")
        print(f"final_unknown_type_count={sum(item.unknown_type_count for item in results)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
