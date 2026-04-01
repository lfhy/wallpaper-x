#!/usr/bin/env python3
"""Capture raw Steam Workshop pages for offline analysis.

Usage examples:
  python3 scripts/steam_workshop_snapshot.py
  python3 scripts/steam_workshop_snapshot.py \
    --output-dir /Users/songziqiang/Downloads/steam-snapshots \
    --detail-id 3694015003

This script intentionally uses only the Python standard library so it can run
on a stock macOS install without extra dependencies.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Dict, List, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, build_opener, HTTPCookieProcessor
import http.cookiejar


LIST_URL = (
    "https://steamcommunity.com/workshop/browse/"
    "?appid=431960&requiredtags%5B0%5D=Video&actualsort=trend&browsesort=trend&p=1&days=7"
)
DETAIL_URL_TEMPLATE = "https://steamcommunity.com/sharedfiles/filedetails/?id={detail_id}&searchtext="


class AssetParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.inline_scripts: List[str] = []
        self.current_script: Optional[List[str]] = None
        self.current_title: Optional[List[str]] = None
        self.current_workshop_title: Optional[List[str]] = None
        self.current_author: Optional[List[str]] = None
        self.assets: Dict[str, List[str]] = {
            "scripts": [],
            "stylesheets": [],
            "images": [],
            "links": [],
            "meta_images": [],
            "videos": [],
            "iframes": [],
        }
        self.page_title: str = ""
        self.canonical_url: Optional[str] = None
        self.og_url: Optional[str] = None
        self.og_type: Optional[str] = None
        self.workshop_item_ids: List[str] = []
        self.hover_bind_ids: List[str] = []
        self.preview_image_urls: List[str] = []
        self.preview_video_urls: List[str] = []
        self.detected_title: Optional[str] = None
        self.detected_author: Optional[str] = None
        self.page_kind_hints: List[str] = []

    def handle_starttag(self, tag: str, attrs: List[tuple[str, Optional[str]]]) -> None:
        attrs_map = dict(attrs)
        classes = set((attrs_map.get("class") or "").split())
        if tag == "script":
            src = attrs_map.get("src")
            if src:
                self.assets["scripts"].append(src)
                self.current_script = None
            else:
                self.current_script = []
        elif tag == "link":
            href = attrs_map.get("href")
            rel = (attrs_map.get("rel") or "").lower()
            if href:
                if "canonical" in rel:
                    self.canonical_url = href
                if "stylesheet" in rel:
                    self.assets["stylesheets"].append(href)
                else:
                    self.assets["links"].append(href)
        elif tag == "img":
            src = attrs_map.get("src")
            if src:
                self.assets["images"].append(src)
            if "workshopItemPreviewImage" in classes and src:
                self.preview_image_urls.append(src)
        elif tag == "meta":
            content = attrs_map.get("content")
            prop = (attrs_map.get("property") or attrs_map.get("name") or "").lower()
            if content and ("image" in prop or prop in {"og:image", "twitter:image"}):
                self.assets["meta_images"].append(content)
            if content and prop == "og:url":
                self.og_url = content
            if content and prop == "og:type":
                self.og_type = content
        elif tag == "a":
            href = attrs_map.get("href")
            if href:
                self.assets["links"].append(href)
            published_file_id = attrs_map.get("data-publishedfileid")
            if published_file_id:
                self.workshop_item_ids.append(published_file_id)
        elif tag == "video":
            src = attrs_map.get("src")
            if src:
                self.assets["videos"].append(src)
                self.preview_video_urls.append(src)
        elif tag == "source":
            src = attrs_map.get("src")
            if src:
                self.assets["videos"].append(src)
                self.preview_video_urls.append(src)
        elif tag == "iframe":
            src = attrs_map.get("src")
            if src:
                self.assets["iframes"].append(src)
        elif tag == "title":
            self.current_title = []

        if "workshopItemTitle" in classes:
            self.current_workshop_title = []
        if "friendBlockContent" in classes:
            self.current_author = []

    def handle_data(self, data: str) -> None:
        if self.current_script is not None:
            self.current_script.append(data)
        if self.current_title is not None:
            self.current_title.append(data)
        if self.current_workshop_title is not None:
            self.current_workshop_title.append(data)
        if self.current_author is not None:
            self.current_author.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self.current_script is not None:
            script = "".join(self.current_script).strip()
            if script:
                self.inline_scripts.append(script)
                self.hover_bind_ids.extend(re.findall(r'SharedFileBindMouseHover\(\s*"sharedfile_(\d+)"', script))
            self.current_script = None
        elif tag == "title" and self.current_title is not None:
            self.page_title = " ".join("".join(self.current_title).split())
            self.current_title = None
        elif tag == "div" and self.current_workshop_title is not None:
            title = " ".join("".join(self.current_workshop_title).split())
            if title and not self.detected_title:
                self.detected_title = title
            self.current_workshop_title = None
        elif tag == "div" and self.current_author is not None:
            author = " ".join("".join(self.current_author).split())
            if author and not self.detected_author:
                self.detected_author = author
            self.current_author = None

    def build_summary(self, snapshot: "SnapshotResult") -> Dict[str, object]:
        html_lower = snapshot.html.lower()
        detail_stats = self.extract_detail_stats(snapshot.html)
        detail_tags = self.extract_detail_tags(snapshot.html)
        detected_author = self.detected_author or self.extract_detail_author(snapshot.html)
        page_kind = "unknown"
        if "workshop/browse" in snapshot.final_url:
            page_kind = "browse"
        elif "sharedfiles/filedetails" in snapshot.final_url:
            if "agecheck" in snapshot.final_url or "Please enter your birth date" in snapshot.html:
                page_kind = "age-check"
            else:
                page_kind = "detail"

        if page_kind == "browse":
            self.page_kind_hints.append("browse-html")
        if page_kind == "detail":
            self.page_kind_hints.append("detail-html")
        if "sharedfilebindmousehover" in html_lower:
            self.page_kind_hints.append("hover-json-inline")
        if self.preview_image_urls:
            self.page_kind_hints.append("preview-image")
        if self.preview_video_urls:
            self.page_kind_hints.append("preview-video-tag")

        return {
            "page_kind": page_kind,
            "page_title": self.page_title,
            "detected_title": self.detected_title,
            "detected_author": detected_author,
            "canonical_url": self.canonical_url,
            "og_url": self.og_url,
            "og_type": self.og_type,
            "page_kind_hints": sorted(set(self.page_kind_hints)),
            "workshop_item_count": len(set(self.workshop_item_ids)),
            "workshop_item_ids": sorted(set(self.workshop_item_ids)),
            "hover_bind_ids": sorted(set(self.hover_bind_ids)),
            "preview_image_urls": self.preview_image_urls[:50],
            "preview_video_urls": self.preview_video_urls[:50],
            "detail_stats": detail_stats,
            "detail_tags": detail_tags,
            "contains_login_gate": "login" in html_lower and "steam" in html_lower,
            "contains_age_gate": page_kind == "age-check",
        }

    @staticmethod
    def extract_detail_stats(html: str) -> List[Dict[str, str]]:
        labels = re.findall(r'<div class="detailsStatLeft">\s*(.*?)\s*</div>', html, flags=re.S)
        values = re.findall(r'<div class="detailsStatRight">\s*(.*?)\s*</div>', html, flags=re.S)
        count = min(len(labels), len(values))
        return [
            {
                "label": " ".join(re.sub(r"<.*?>", " ", labels[index]).split()),
                "value": " ".join(re.sub(r"<.*?>", " ", values[index]).split()),
            }
            for index in range(count)
        ]

    @staticmethod
    def extract_detail_tags(html: str) -> List[Dict[str, str]]:
        matches = re.findall(
            r'<div[^>]*class="workshopTags"[^>]*>\s*<span[^>]*class="workshopTagsTitle"[^>]*>(.*?)</span>\s*(.*?)</div>',
            html,
            flags=re.S,
        )
        results: List[Dict[str, str]] = []
        for raw_label, raw_value in matches:
            label = " ".join(re.sub(r"<.*?>", " ", raw_label).replace("&nbsp;", " ").split()).rstrip(":")
            value = " ".join(re.sub(r"<.*?>", " ", raw_value).replace("&nbsp;", " ").split())
            if label or value:
                results.append({"label": label, "value": value})
        return results

    @staticmethod
    def extract_detail_author(html: str) -> Optional[str]:
        match = re.search(r'<div class="friendBlockContent">\s*(.*?)<br', html, flags=re.S)
        if not match:
            return None
        author = " ".join(re.sub(r"<.*?>", " ", match.group(1)).split())
        return author or None


@dataclass
class SnapshotResult:
    url: str
    final_url: str
    status_code: int
    headers: Dict[str, str]
    html: str


def make_request(url: str, cookies_path: Optional[str]) -> SnapshotResult:
    cookie_jar = http.cookiejar.MozillaCookieJar()
    if cookies_path:
        cookie_file = Path(cookies_path).expanduser()
        if cookie_file.exists():
            cookie_jar.load(str(cookie_file), ignore_discard=True, ignore_expires=True)

    opener = build_opener(HTTPCookieProcessor(cookie_jar))
    request = Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/605.1.15 (KHTML, like Gecko) "
                "MyWallpaperXSnapshot/1.0"
            ),
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
        },
    )

    try:
        with opener.open(request, timeout=30) as response:
            raw = response.read()
            content_type = response.headers.get_content_charset() or "utf-8"
            html = raw.decode(content_type, errors="replace")
            return SnapshotResult(
                url=url,
                final_url=response.geturl(),
                status_code=getattr(response, "status", 200),
                headers=dict(response.headers.items()),
                html=html,
            )
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} for {url}\n{body[:1200]}") from exc
    except URLError as exc:
        raise RuntimeError(f"Network error for {url}: {exc}") from exc


def safe_slug(label: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9._-]+", "-", label).strip("-")
    return slug or "snapshot"


def infer_label(url: str, explicit_label: Optional[str]) -> str:
    if explicit_label:
        return explicit_label
    parsed = urlparse(url)
    if "sharedfiles/filedetails" in parsed.path:
        match = re.search(r"[?&]id=(\d+)", parsed.query)
        return f"detail-{match.group(1)}" if match else "detail"
    return "browse"


def write_snapshot(output_dir: Path, label: str, snapshot: SnapshotResult) -> None:
    parser = AssetParser()
    parser.feed(snapshot.html)

    snapshot_dir = output_dir / safe_slug(label)
    snapshot_dir.mkdir(parents=True, exist_ok=True)

    (snapshot_dir / "page.html").write_text(snapshot.html, encoding="utf-8")
    (snapshot_dir / "headers.json").write_text(
        json.dumps(
            {
                "requested_url": snapshot.url,
                "final_url": snapshot.final_url,
                "status_code": snapshot.status_code,
                "captured_at": datetime.now(timezone.utc).isoformat(),
                "headers": snapshot.headers,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    (snapshot_dir / "assets.json").write_text(
        json.dumps(
            {
                "inline_script_count": len(parser.inline_scripts),
                "assets": parser.assets,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    (snapshot_dir / "page-summary.json").write_text(
        json.dumps(
            parser.build_summary(snapshot),
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    inline_dir = snapshot_dir / "inline-scripts"
    inline_dir.mkdir(exist_ok=True)
    for index, script in enumerate(parser.inline_scripts, start=1):
        (inline_dir / f"{index:03d}.js").write_text(script, encoding="utf-8")

    print(f"[saved] {snapshot_dir}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Capture Steam Workshop HTML snapshots.")
    parser.add_argument(
        "--output-dir",
        default="~/Downloads/steam-workshop-snapshots",
        help="Directory where the captured files will be written.",
    )
    parser.add_argument(
        "--detail-id",
        default="3694015003",
        help="Workshop detail ID to capture alongside the browse page.",
    )
    parser.add_argument(
        "--cookies",
        default="",
        help="Optional Netscape/Mozilla cookies.txt path for logged-in captures.",
    )
    parser.add_argument(
        "--url",
        action="append",
        default=[],
        help="Additional page URL(s) to capture. Can be passed multiple times.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_dir = Path(os.path.expanduser(args.output_dir))
    output_dir.mkdir(parents=True, exist_ok=True)

    urls: List[tuple[str, Optional[str]]] = [
        (LIST_URL, "browse-default"),
        (DETAIL_URL_TEMPLATE.format(detail_id=args.detail_id), f"detail-{args.detail_id}"),
    ]

    for extra_url in args.url:
        urls.append((extra_url, None))

    for url, label in urls:
        try:
            snapshot = make_request(url, args.cookies or None)
            write_snapshot(output_dir, infer_label(url, label), snapshot)
        except Exception as exc:  # noqa: BLE001
            print(f"[error] {url}\n{exc}\n", file=sys.stderr)
            return 1

    print(f"[done] snapshots written to {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
