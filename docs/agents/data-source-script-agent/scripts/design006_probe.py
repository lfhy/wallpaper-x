#!/usr/bin/env python3
import argparse
import json
import re
import ssl
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Dict, List
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urljoin, urlparse
from urllib.request import Request, urlopen


USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/135.0.0.0 Safari/537.36"
)


class LinkParser(HTMLParser):
    def __init__(self, base_url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.title_parts: List[str] = []
        self.in_title = False
        self.links: List[Dict[str, str]] = []
        self.forms: List[Dict[str, str]] = []
        self.scripts: List[str] = []
        self.meta: List[Dict[str, str]] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        attr_map = {k: v for k, v in attrs}
        if tag == "title":
            self.in_title = True
        elif tag == "a":
            href = attr_map.get("href")
            if href:
                self.links.append(
                    {
                        "href": urljoin(self.base_url, href),
                        "class": attr_map.get("class", ""),
                        "text": "",
                    }
                )
        elif tag == "form":
            action = attr_map.get("action")
            if action:
                self.forms.append(
                    {
                        "action": urljoin(self.base_url, action),
                        "method": attr_map.get("method", "GET").upper(),
                        "class": attr_map.get("class", ""),
                        "id": attr_map.get("id", ""),
                    }
                )
        elif tag == "script":
            src = attr_map.get("src")
            if src:
                self.scripts.append(urljoin(self.base_url, src))
        elif tag == "meta":
            item = {k: v for k, v in attr_map.items() if v}
            if item:
                self.meta.append(item)

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


def build_headers(referer: str = "", cookie: str = "", accept: str = "") -> Dict[str, str]:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    }
    if accept:
        headers["Accept"] = accept
    if referer:
        headers["Referer"] = referer
    if cookie:
        headers["Cookie"] = cookie
    return headers


def fetch(url: str, timeout: float, cookie: str = "") -> Dict[str, object]:
    request = Request(
        url,
        headers=build_headers(
            referer="https://www.design006.com/",
            cookie=cookie,
            accept="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ),
    )
    with urlopen(request, timeout=timeout, context=ssl.create_default_context()) as response:
        body = response.read()
        headers = dict(response.headers.items())
        return {
            "status": getattr(response, "status", None) or response.getcode(),
            "final_url": response.geturl(),
            "headers": headers,
            "body": body,
        }


def post_form(url: str, data: Dict[str, str], timeout: float, referer: str, cookie: str = "") -> Dict[str, object]:
    payload = urlencode(data).encode("utf-8")
    request = Request(
        url,
        data=payload,
        headers={
            **build_headers(
                referer=referer,
                cookie=cookie,
                accept="application/json, text/javascript, */*; q=0.01",
            ),
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Origin": "https://www.design006.com",
            "X-Requested-With": "XMLHttpRequest",
        },
        method="POST",
    )
    with urlopen(request, timeout=timeout, context=ssl.create_default_context()) as response:
        body = response.read()
        headers = dict(response.headers.items())
        return {
            "status": getattr(response, "status", None) or response.getcode(),
            "final_url": response.geturl(),
            "headers": headers,
            "body": body,
        }


def decode_body(body: bytes, headers: Dict[str, str]) -> str:
    content_type = headers.get("Content-Type", "")
    match = re.search(r"charset=([^\s;]+)", content_type, flags=re.IGNORECASE)
    encoding = match.group(1).strip("\"'") if match else "utf-8"
    encoding_aliases = {
        "utf8mb4": "utf-8",
        "utf8": "utf-8",
    }
    encoding = encoding_aliases.get(encoding.lower(), encoding)
    return body.decode(encoding, errors="replace")


def unique_links(links: List[Dict[str, str]]) -> List[Dict[str, str]]:
    seen = set()
    out = []
    for item in links:
        href = item["href"]
        if href in seen:
            continue
        seen.add(href)
        item["text"] = re.sub(r"\s+", " ", item["text"]).strip()
        out.append(item)
    return out


def extract_download_params(html: str) -> Dict[str, str]:
    work_id_match = re.search(r'var work_id = "(\d+)"', html)
    key_match = re.search(r'"key": "([^"]+)"', html)
    return {
        "work_id": work_id_match.group(1) if work_id_match else "",
        "key": key_match.group(1) if key_match else "",
    }


def decode_json_body(result: Dict[str, object]) -> object:
    text = decode_body(result["body"], result["headers"])
    try:
        return json.loads(text)
    except Exception:
        return {"raw_text": text[:2000]}


def extract_candidates(final_url: str, html: str, parser: LinkParser) -> Dict[str, object]:
    links = unique_links(parser.links)
    domain = urlparse(final_url).netloc
    internal = [x for x in links if urlparse(x["href"]).netloc == domain]
    keyword_pattern = re.compile(
        r"(download|down|xiazai|zip|rar|7z|psd|ai|eps|source|素材|下载)",
        flags=re.IGNORECASE,
    )
    direct_file_pattern = re.compile(r"\.(zip|rar|7z|psd|ai|eps|cdr|pdf)(?:[?#]|$)", flags=re.IGNORECASE)

    download_links = [
        item for item in links
        if keyword_pattern.search(item["href"]) or keyword_pattern.search(item["text"]) or keyword_pattern.search(item["class"])
    ]
    direct_files = [item for item in links if direct_file_pattern.search(item["href"])]
    window_open_urls = re.findall(r"""window\.open\((['"])(.*?)\1""", html, flags=re.IGNORECASE)
    location_urls = re.findall(r"""location(?:\.href)?\s*=\s*(['"])(.*?)\1""", html, flags=re.IGNORECASE)
    ajax_urls = re.findall(
        r"""(?:url|URL)\s*[:=]\s*(['"])(/[^'"]+|https?://[^'"]+)\1""",
        html,
        flags=re.IGNORECASE,
    )
    quoted_urls = re.findall(r"""https?://[^\s"'<>\\]+""", html)

    script_candidates = []
    for _, path in window_open_urls + location_urls + ajax_urls:
        script_candidates.append(urljoin(final_url, path))

    query_candidates = []
    for item in links:
        parsed = urlparse(item["href"])
        params = parse_qs(parsed.query)
        if any(k.lower() in {"url", "download", "downurl", "file", "src"} for k in params):
            query_candidates.append(item)

    return {
        "title": " ".join(parser.title_parts).strip(),
        "meta_sample": parser.meta[:10],
        "link_count": len(links),
        "internal_link_count": len(internal),
        "download_link_sample": download_links[:20],
        "direct_file_link_sample": direct_files[:20],
        "script_url_candidates": script_candidates[:30],
        "quoted_url_sample": quoted_urls[:30],
        "forms": parser.forms[:20],
        "scripts": parser.scripts[:20],
        "query_based_candidates": query_candidates[:20],
    }


def probe_candidates(candidates: List[str], timeout: float) -> List[Dict[str, object]]:
    out = []
    for url in candidates[:10]:
        try:
            request = Request(
                url,
                headers={"User-Agent": USER_AGENT, "Referer": "https://www.design006.com/"},
            )
            with urlopen(request, timeout=timeout, context=ssl.create_default_context()) as response:
                out.append(
                    {
                        "url": url,
                        "status": getattr(response, "status", None) or response.getcode(),
                        "final_url": response.geturl(),
                        "content_type": response.headers.get("Content-Type", ""),
                    }
                )
        except HTTPError as exc:
            out.append({"url": url, "error_type": "HTTPError", "status": exc.code, "reason": str(exc)})
        except URLError as exc:
            out.append({"url": url, "error_type": "URLError", "reason": str(exc.reason)})
        except Exception as exc:
            out.append({"url": url, "error_type": exc.__class__.__name__, "reason": str(exc)})
    return out


def load_cookie(cookie_header: str, cookie_file: str) -> str:
    if cookie_header.strip():
        return cookie_header.strip()
    if cookie_file.strip():
        return Path(cookie_file).read_text(encoding="utf-8").strip()
    return ""


def main() -> int:
    argp = argparse.ArgumentParser(description="Probe design006 detail page for download links.")
    argp.add_argument("--url", default="https://www.design006.com/detail-30143233332")
    argp.add_argument("--timeout", type=float, default=20.0)
    argp.add_argument("--output-dir", default="outputs/design006_probe")
    argp.add_argument("--cookie-header", default="", help="Raw Cookie header for a logged-in session.")
    argp.add_argument("--cookie-file", default="", help="Path to a file containing a raw Cookie header.")
    args = argp.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    cookie = load_cookie(args.cookie_header, args.cookie_file)

    try:
        result = fetch(args.url, args.timeout, cookie=cookie)
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

    parser = LinkParser(str(result["final_url"]))
    parser.feed(html)
    summary = extract_candidates(str(result["final_url"]), html, parser)
    summary["requested_url"] = args.url
    summary["final_url"] = result["final_url"]
    summary["status"] = result["status"]
    summary["content_type"] = result["headers"].get("Content-Type", "")
    summary["content_length"] = len(result["body"])
    summary["download_params"] = extract_download_params(html)

    probe_urls = []
    for item in summary["download_link_sample"]:
        probe_urls.append(item["href"])
    for item in summary["direct_file_link_sample"]:
        probe_urls.append(item["href"])
    for url in summary["script_url_candidates"]:
        probe_urls.append(url)
    deduped_probe_urls = []
    seen = set()
    for url in probe_urls:
        if url in seen:
            continue
        seen.add(url)
        deduped_probe_urls.append(url)

    summary["candidate_probe_results"] = probe_candidates(deduped_probe_urls, timeout=args.timeout)

    work_id = summary["download_params"].get("work_id", "")
    key = summary["download_params"].get("key", "")
    api_results = {}
    if work_id:
        confirm_url = urljoin(str(result["final_url"]), "/Home/Works/confirm_download")
        try:
            confirm_ret = post_form(
                confirm_url,
                {"work_id": work_id, "t": "0.123456"},
                timeout=args.timeout,
                referer=str(result["final_url"]),
                cookie=cookie,
            )
            api_results["confirm_download"] = {
                "status": confirm_ret["status"],
                "final_url": confirm_ret["final_url"],
                "content_type": confirm_ret["headers"].get("Content-Type", ""),
                "json": decode_json_body(confirm_ret),
            }
        except HTTPError as exc:
            api_results["confirm_download"] = {"error_type": "HTTPError", "status": exc.code, "reason": str(exc)}
        except URLError as exc:
            api_results["confirm_download"] = {"error_type": "URLError", "reason": str(exc.reason)}
        except Exception as exc:
            api_results["confirm_download"] = {"error_type": exc.__class__.__name__, "reason": str(exc)}

    if work_id and key:
        download_url = urljoin(str(result["final_url"]), "/Home/Works/download_api")
        try:
            download_ret = post_form(
                download_url,
                {"work_id": work_id, "key": key},
                timeout=args.timeout,
                referer=str(result["final_url"]),
                cookie=cookie,
            )
            api_results["download_api"] = {
                "status": download_ret["status"],
                "final_url": download_ret["final_url"],
                "content_type": download_ret["headers"].get("Content-Type", ""),
                "json": decode_json_body(download_ret),
            }
            download_json = api_results["download_api"]["json"]
            if isinstance(download_json, dict) and download_json.get("signed_url"):
                api_results["signed_url_present"] = True
                api_results["signed_url_preview"] = str(download_json["signed_url"])[:300]
            else:
                api_results["signed_url_present"] = False
        except HTTPError as exc:
            api_results["download_api"] = {"error_type": "HTTPError", "status": exc.code, "reason": str(exc)}
        except URLError as exc:
            api_results["download_api"] = {"error_type": "URLError", "reason": str(exc.reason)}
        except Exception as exc:
            api_results["download_api"] = {"error_type": exc.__class__.__name__, "reason": str(exc)}

    summary["download_api_results"] = api_results

    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
