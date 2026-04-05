#!/usr/bin/env python3
import argparse
import json
import re
import ssl
import sys
import time
from html.parser import HTMLParser
from pathlib import Path
from typing import Dict, List
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urljoin, urlparse
from urllib.request import Request, urlopen


USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/135.0.0.0 Safari/537.36"
)


class ImageParser(HTMLParser):
    def __init__(self, base_url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.title_parts: List[str] = []
        self.in_title = False
        self.images: List[Dict[str, str]] = []
        self.links: List[str] = []
        self.link_items: List[Dict[str, str]] = []
        self.meta: List[Dict[str, str]] = []
        self.current_link_index = -1

    def handle_starttag(self, tag: str, attrs) -> None:
        attr_map = {k: v for k, v in attrs}
        if tag == "title":
            self.in_title = True
        elif tag == "img":
            src = (
                attr_map.get("src")
                or attr_map.get("data-src")
                or attr_map.get("data-original")
                or attr_map.get("data-lazy-src")
                or attr_map.get("data-thumb")
            )
            if src:
                self.images.append(
                    {
                        "src": urljoin(self.base_url, src),
                        "alt": attr_map.get("alt", ""),
                        "class": attr_map.get("class", ""),
                    }
                )
        elif tag == "a":
            href = attr_map.get("href")
            if href:
                absolute_href = urljoin(self.base_url, href)
                self.links.append(absolute_href)
                self.link_items.append(
                    {
                        "href": absolute_href,
                        "class": attr_map.get("class", ""),
                        "rel": attr_map.get("rel", ""),
                        "text": "",
                    }
                )
                self.current_link_index = len(self.link_items) - 1
        elif tag == "meta":
            item = {k: v for k, v in attr_map.items() if v}
            if item:
                self.meta.append(item)

        style = attr_map.get("style", "")
        if style:
            for bg in re.findall(r'url\((["\']?)(.*?)\1\)', style, flags=re.IGNORECASE):
                self.images.append(
                    {
                        "src": urljoin(self.base_url, bg[1]),
                        "alt": "",
                        "class": attr_map.get("class", ""),
                    }
                )

    def handle_data(self, data: str) -> None:
        text = data.strip()
        if text and self.in_title:
            self.title_parts.append(text)
        if text and self.current_link_index >= 0:
            self.link_items[self.current_link_index]["text"] += text

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self.in_title = False
        elif tag == "a":
            self.current_link_index = -1


def build_request(url: str, referer: str = "") -> Request:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    }
    if referer:
        headers["Referer"] = referer
    return Request(url, headers=headers)


def fetch(url: str, timeout: float, referer: str = "") -> Dict[str, object]:
    last_error = None
    for attempt in range(3):
        try:
            request = build_request(url, referer=referer)
            with urlopen(request, timeout=timeout, context=ssl.create_default_context()) as response:
                body = response.read()
                headers = dict(response.headers.items())
                return {
                    "status": getattr(response, "status", None) or response.getcode(),
                    "final_url": response.geturl(),
                    "headers": headers,
                    "body": body,
                }
        except URLError as exc:
            last_error = exc
            if "EOF occurred in violation of protocol" not in str(exc.reason) or attempt == 2:
                raise
            time.sleep(0.6 * (attempt + 1))
    if last_error:
        raise last_error
    raise RuntimeError("fetch failed without error")


def decode_body(body: bytes, headers: Dict[str, str]) -> str:
    content_type = headers.get("Content-Type", "")
    match = re.search(r"charset=([^\s;]+)", content_type, flags=re.IGNORECASE)
    encoding = match.group(1).strip("\"'") if match else "utf-8"
    aliases = {"utf8mb4": "utf-8", "utf8": "utf-8"}
    encoding = aliases.get(encoding.lower(), encoding)
    return body.decode(encoding, errors="replace")


def dedupe_images(images: List[Dict[str, str]]) -> List[Dict[str, str]]:
    seen = set()
    out = []
    for item in images:
        src = item["src"]
        if not src or src.startswith("data:") or src in seen:
            continue
        seen.add(src)
        out.append(item)
    return out


def derive_origin_image_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.netloc.endswith("wp.com"):
        path = parsed.path.lstrip("/")
        if path.startswith("pic.4khd.com/"):
            return "https://" + unquote(path)
    return ""


def dedupe_links(links: List[Dict[str, str]]) -> List[Dict[str, str]]:
    seen = set()
    out = []
    for item in links:
        href = item["href"]
        if not href or href in seen:
            continue
        seen.add(href)
        item["text"] = re.sub(r"\s+", " ", item.get("text", "")).strip()
        out.append(item)
    return out


def image_probe(url: str, timeout: float, referer: str) -> Dict[str, object]:
    try:
        result = fetch(url, timeout=timeout, referer=referer)
        return {
            "url": url,
            "status": result["status"],
            "final_url": result["final_url"],
            "content_type": result["headers"].get("Content-Type", ""),
            "content_length": len(result["body"]),
        }
    except HTTPError as exc:
        return {"url": url, "error_type": "HTTPError", "status": exc.code, "reason": str(exc)}
    except URLError as exc:
        return {"url": url, "error_type": "URLError", "reason": str(exc.reason)}
    except Exception as exc:
        return {"url": url, "error_type": exc.__class__.__name__, "reason": str(exc)}


def extract_article_links(base_url: str, parser: ImageParser) -> List[Dict[str, str]]:
    domain = urlparse(base_url).netloc
    primary = []
    secondary = []
    for item in dedupe_links(parser.link_items):
        parsed = urlparse(item["href"])
        if parsed.netloc != domain:
            continue
        path = parsed.path.rstrip("/")
        if not path or path in {"", "/"}:
            continue
        if path.startswith("/page/") or path.startswith("/wp-") or path.startswith("/feed") or path.startswith("/tag/"):
            continue
        if any(part in path for part in ["/category/", "/author/", "/comments", "/search"]):
            continue
        if path.startswith("/content/"):
            primary.append(item)
        elif path.startswith("/pages/"):
            secondary.append(item)
        elif re.search(r"/\d{4}/\d{2}/", path) or re.search(r"/[^/]+/?$", path):
            secondary.append(item)
    return dedupe_links(primary + secondary)


def extract_srcset_candidates(html: str, base_url: str) -> List[Dict[str, str]]:
    out = []
    for match in re.findall(r'srcset=["\'](.*?)["\']', html, flags=re.IGNORECASE | re.DOTALL):
        parts = [part.strip() for part in match.split(",")]
        for part in parts:
            if not part:
                continue
            url = part.split()[0]
            if url:
                out.append({"src": urljoin(base_url, url), "alt": "", "class": "srcset"})
    return out


def extract_same_gallery_pages(page_url: str, parser: ImageParser) -> List[str]:
    out = []
    base = page_url.rstrip("/")
    for item in dedupe_links(parser.link_items):
        href = item["href"].rstrip("/")
        if href == base:
            continue
        if href.startswith(base + "/") and re.search(r"/\d+$", href):
            out.append(href)
    seen = set()
    deduped = []
    for href in out:
        if href in seen:
            continue
        seen.add(href)
        deduped.append(href)
    return deduped


def fetch_detail_summary(url: str, timeout: float) -> Dict[str, object]:
    try:
        result = fetch(url, timeout=timeout, referer="https://www.4khd.com/")
    except HTTPError as exc:
        return {"url": url, "error_type": "HTTPError", "status": exc.code, "reason": str(exc)}
    except URLError as exc:
        return {"url": url, "error_type": "URLError", "reason": str(exc.reason)}
    except Exception as exc:
        return {"url": url, "error_type": exc.__class__.__name__, "reason": str(exc)}

    html = decode_body(result["body"], result["headers"])
    parser = ImageParser(str(result["final_url"]))
    parser.feed(html)
    css_images = []
    for css_url in re.findall(r'url\((["\']?)(.*?)\1\)', html, flags=re.IGNORECASE):
        src = css_url[1]
        if src and not src.startswith("data:") and not src.startswith("#"):
            css_images.append({"src": urljoin(str(result["final_url"]), src), "alt": "", "class": "css-url"})

    images = dedupe_images(parser.images + css_images + extract_srcset_candidates(html, str(result["final_url"])))
    real_images = []
    for img in images:
        parsed = urlparse(img["src"])
        if parsed.fragment:
            continue
        if img["src"].endswith(".css") or img["src"].endswith(".js"):
            continue
        real_images.append(img)

    normalized_images = []
    for img in real_images:
        normalized_images.append(img)
        origin = derive_origin_image_url(img["src"])
        if origin:
            normalized_images.append(
                {
                    "src": origin,
                    "alt": img.get("alt", ""),
                    "class": (img.get("class", "") + " origin-derived").strip(),
                }
            )
    real_images = dedupe_images(normalized_images)
    gallery_pages = extract_same_gallery_pages(str(result["final_url"]), parser)

    image_tests = [image_probe(img["src"], timeout=timeout, referer=str(result["final_url"])) for img in real_images[:5]]
    return {
        "url": url,
        "final_url": result["final_url"],
        "status": result["status"],
        "title": " ".join(parser.title_parts).strip(),
        "image_count": len(real_images),
        "gallery_page_count": len(gallery_pages),
        "gallery_pages": gallery_pages[:20],
        "image_sample": real_images[:20],
        "origin_image_sample": [img for img in real_images if "origin-derived" in img.get("class", "")][:10],
        "image_probe_results": image_tests,
    }


def aggregate_gallery(base_url: str, timeout: float) -> Dict[str, object]:
    first_page = fetch_detail_summary(base_url, timeout=timeout)
    if "error_type" in first_page:
        return {"base_url": base_url, "error": first_page}

    page_urls = [base_url]
    page_urls.extend(first_page.get("gallery_pages", []))

    pages = []
    all_images: List[Dict[str, str]] = []
    for page_url in page_urls:
        page = fetch_detail_summary(page_url, timeout=timeout)
        pages.append(page)
        if "image_sample" in page:
            for item in page["image_sample"]:
                all_images.append(item)

    deduped_images = dedupe_images(all_images)
    filename_samples = []
    for item in deduped_images:
        path = urlparse(item["src"]).path
        name = path.split("/")[-1]
        if name:
            filename_samples.append(name)

    return {
        "base_url": base_url,
        "page_count": len(page_urls),
        "page_urls": page_urls,
        "total_unique_image_candidates": len(deduped_images),
        "image_filename_sample": filename_samples[:50],
        "image_url_sample": [item["src"] for item in deduped_images[:50]],
        "pages": pages,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe images from 4khd.com home page.")
    parser.add_argument("--url", default="https://www.4khd.com")
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--output-dir", default="outputs/4khd_image_probe")
    parser.add_argument("--sample-count", type=int, default=10)
    parser.add_argument("--detail-count", type=int, default=3)
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        result = fetch(args.url, timeout=args.timeout)
    except HTTPError as exc:
        summary = {"requested_url": args.url, "error_type": "HTTPError", "status": exc.code, "reason": str(exc)}
        (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 1
    except URLError as exc:
        summary = {"requested_url": args.url, "error_type": "URLError", "reason": str(exc.reason)}
        (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 2
    except Exception as exc:
        summary = {"requested_url": args.url, "error_type": exc.__class__.__name__, "reason": str(exc)}
        (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 3

    html = decode_body(result["body"], result["headers"])
    (out_dir / "response.html").write_text(html, encoding="utf-8")

    html_parser = ImageParser(str(result["final_url"]))
    html_parser.feed(html)

    css_images = []
    for css_url in re.findall(r'url\((["\']?)(.*?)\1\)', html, flags=re.IGNORECASE):
        src = css_url[1]
        if src and not src.startswith("data:") and not src.startswith("#"):
            css_images.append({"src": urljoin(str(result["final_url"]), src), "alt": "", "class": "css-url"})

    all_images = dedupe_images(html_parser.images + css_images + extract_srcset_candidates(html, str(result["final_url"])))
    image_probes = [
        image_probe(item["src"], timeout=args.timeout, referer=str(result["final_url"]))
        for item in all_images[: args.sample_count]
    ]
    domain = urlparse(str(result["final_url"])).netloc
    internal_images = [img for img in all_images if urlparse(img["src"]).netloc in {"", domain}]
    article_links = extract_article_links(str(result["final_url"]), html_parser)
    detail_summaries = [
        fetch_detail_summary(item["href"], timeout=args.timeout)
        for item in article_links[: args.detail_count]
    ]

    summary = {
        "requested_url": args.url,
        "final_url": result["final_url"],
        "status": result["status"],
        "content_type": result["headers"].get("Content-Type", ""),
        "content_length": len(result["body"]),
        "title": " ".join(html_parser.title_parts).strip(),
        "meta_sample": html_parser.meta[:10],
        "image_count": len(all_images),
        "internal_image_count": len(internal_images),
        "article_link_count": len(article_links),
        "article_link_sample": article_links[:20],
        "image_sample": all_images[:50],
        "image_probe_results": image_probes,
        "detail_page_summaries": detail_summaries,
    }

    if "/content/" in str(result["final_url"]):
        summary["gallery_aggregation"] = aggregate_gallery(str(result["final_url"]), timeout=args.timeout)

    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
