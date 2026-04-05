#!/usr/bin/env python3
import argparse
import json
import re
import ssl
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Dict, List, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen


USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/135.0.0.0 Safari/537.36"
)


class PageParser(HTMLParser):
    def __init__(self, base_url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.title_parts: List[str] = []
        self.in_title = False
        self.meta: List[Dict[str, str]] = []
        self.links: List[Dict[str, str]] = []
        self.images: List[Dict[str, str]] = []
        self.scripts: List[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        attr_map = {key: value for key, value in attrs}
        if tag == "title":
            self.in_title = True
        elif tag == "meta":
            item = {k: v for k, v in attr_map.items() if v}
            if item:
                self.meta.append(item)
        elif tag == "a":
            href = attr_map.get("href")
            if href:
                self.links.append(
                    {
                        "href": urljoin(self.base_url, href),
                        "text": "",
                        "class": attr_map.get("class", ""),
                    }
                )
        elif tag == "img":
            src = attr_map.get("src") or attr_map.get("data-src")
            if src:
                self.images.append(
                    {
                        "src": urljoin(self.base_url, src),
                        "alt": attr_map.get("alt", ""),
                    }
                )
        elif tag == "script":
            src = attr_map.get("src")
            if src:
                self.scripts.append(urljoin(self.base_url, src))

    def handle_data(self, data: str) -> None:
        text = data.strip()
        if not text:
            return
        if self.in_title:
            self.title_parts.append(text)
        if self.links:
            self.links[-1]["text"] += text

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self.in_title = False


def fetch(url: str, timeout: float) -> Dict[str, object]:
    request = Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    context = ssl.create_default_context()
    with urlopen(request, timeout=timeout, context=context) as response:
        body = response.read()
        headers = dict(response.headers.items())
        status = getattr(response, "status", None) or response.getcode()
        final_url = response.geturl()
    return {
        "status": status,
        "headers": headers,
        "body": body,
        "final_url": final_url,
    }


def normalize_links(links: List[Dict[str, str]]) -> List[Dict[str, str]]:
    seen = set()
    deduped: List[Dict[str, str]] = []
    for item in links:
        href = item["href"]
        if href in seen:
            continue
        seen.add(href)
        item["text"] = re.sub(r"\s+", " ", item["text"]).strip()
        deduped.append(item)
    return deduped


def summarize(url: str, final_url: str, html: str, parser: PageParser) -> Dict[str, object]:
    links = normalize_links(parser.links)
    domain = urlparse(final_url).netloc
    internal_links = [link for link in links if urlparse(link["href"]).netloc == domain]
    video_like_links = [
        link for link in internal_links if re.search(r"/(video|watch|play|dm\d+|[A-Za-z0-9_-]{6,})", link["href"])
    ]
    pagination_links = [
        link for link in internal_links if re.search(r"(page=|/page/|\bp=\d+)", link["href"])
    ]
    json_ld_blocks = re.findall(
        r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
        html,
        flags=re.IGNORECASE | re.DOTALL,
    )
    return {
        "requested_url": url,
        "final_url": final_url,
        "title": " ".join(parser.title_parts).strip(),
        "meta_sample": parser.meta[:10],
        "link_count": len(links),
        "internal_link_count": len(internal_links),
        "video_like_link_count": len(video_like_links),
        "video_like_links_sample": video_like_links[:20],
        "pagination_links_sample": pagination_links[:20],
        "image_count": len(parser.images),
        "image_sample": parser.images[:20],
        "script_count": len(parser.scripts),
        "script_sample": parser.scripts[:20],
        "json_ld_block_count": len(json_ld_blocks),
        "contains_hls": ".m3u8" in html,
        "contains_mp4": ".mp4" in html,
        "contains_next_data": "__NEXT_DATA__" in html,
        "contains_nuxt_data": "__NUXT__" in html,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe a website home page and summarize public data.")
    parser.add_argument("--url", default="https://missav.ai/")
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument(
        "--output-dir",
        default="outputs/missav_probe",
        help="Directory for raw HTML and summary JSON.",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        result = fetch(args.url, timeout=args.timeout)
    except HTTPError as exc:
        summary = {
            "requested_url": args.url,
            "error_type": "HTTPError",
            "status": exc.code,
            "reason": str(exc),
        }
        (output_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False))
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 1
    except URLError as exc:
        summary = {
            "requested_url": args.url,
            "error_type": "URLError",
            "reason": str(exc.reason),
        }
        (output_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False))
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 2
    except Exception as exc:
        summary = {
            "requested_url": args.url,
            "error_type": exc.__class__.__name__,
            "reason": str(exc),
        }
        (output_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False))
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 3

    body = result["body"]
    headers = result["headers"]
    final_url = str(result["final_url"])
    content_type = str(headers.get("Content-Type", ""))
    encoding: Optional[str] = None
    match = re.search(r"charset=([^\s;]+)", content_type, flags=re.IGNORECASE)
    if match:
        encoding = match.group(1).strip("\"'")
    html = body.decode(encoding or "utf-8", errors="replace")

    raw_path = output_dir / "response.html"
    raw_path.write_text(html, encoding="utf-8")

    html_parser = PageParser(final_url)
    html_parser.feed(html)
    summary = summarize(args.url, final_url, html, html_parser)
    summary["status"] = result["status"]
    summary["content_type"] = content_type
    summary["content_length"] = len(body)

    summary_path = output_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
