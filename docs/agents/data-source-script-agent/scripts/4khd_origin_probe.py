#!/usr/bin/env python3
import argparse
import json
import ssl
import sys
import time
from pathlib import Path
from typing import Dict, List
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlparse
from urllib.request import Request, urlopen


USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/135.0.0.0 Safari/537.36"
)


def build_request(url: str, referer: str = "") -> Request:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
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
                body = response.read(512)
                return {
                    "status": getattr(response, "status", None) or response.getcode(),
                    "final_url": response.geturl(),
                    "content_type": response.headers.get("Content-Type", ""),
                    "content_length": response.headers.get("Content-Length", ""),
                    "body_sample_len": len(body),
                }
        except URLError as exc:
            last_error = exc
            if "EOF occurred in violation of protocol" not in str(exc.reason) or attempt == 2:
                raise
            time.sleep(0.5 * (attempt + 1))
    if last_error:
        raise last_error
    raise RuntimeError("fetch failed without error")


def derive_variants(proxy_url: str) -> List[str]:
    parsed = urlparse(proxy_url)
    path = parsed.path.lstrip("/")
    variants = [proxy_url]
    if path.startswith("pic.4khd.com/"):
        origin_path = unquote(path[len("pic.4khd.com/"):])
        variants.append("https://pic.4khd.com/" + origin_path)

        parts = origin_path.split("/")
        if len(parts) >= 2 and parts[-2].startswith("w") and parts[-2].endswith("-rw"):
            variants.append("https://pic.4khd.com/" + "/".join(parts[:-2] + [parts[-1]]))
        if len(parts) >= 2 and parts[-2].startswith("w"):
            variants.append("https://pic.4khd.com/" + "/".join(parts[:-2] + [parts[-1]]))
    deduped = []
    seen = set()
    for item in variants:
        if item not in seen:
            seen.add(item)
            deduped.append(item)
    return deduped


def probe_urls(urls: List[str], timeout: float, referer: str) -> List[Dict[str, object]]:
    out = []
    for url in urls:
        try:
            result = fetch(url, timeout=timeout, referer=referer)
            out.append({"url": url, **result})
        except HTTPError as exc:
            out.append({"url": url, "error_type": "HTTPError", "status": exc.code, "reason": str(exc)})
        except URLError as exc:
            out.append({"url": url, "error_type": "URLError", "reason": str(exc.reason)})
        except Exception as exc:
            out.append({"url": url, "error_type": exc.__class__.__name__, "reason": str(exc)})
    return out


def main() -> int:
    argp = argparse.ArgumentParser(description="Probe possible origin image URLs for 4khd proxy images.")
    argp.add_argument("--input-file", required=True)
    argp.add_argument("--referer", default="https://www.4khd.com/")
    argp.add_argument("--sample-count", type=int, default=5)
    argp.add_argument("--timeout", type=float, default=20.0)
    argp.add_argument("--output-dir", default="outputs/4khd_origin_probe")
    args = argp.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    urls = [
        line.strip()
        for line in Path(args.input_file).read_text(encoding="utf-8").splitlines()
        if line.strip()
    ][: args.sample_count]

    summary = {"input_file": args.input_file, "sample_count": len(urls), "probes": []}
    for proxy_url in urls:
        variants = derive_variants(proxy_url)
        summary["probes"].append(
            {
                "proxy_url": proxy_url,
                "variants": variants,
                "results": probe_urls(variants, timeout=args.timeout, referer=args.referer),
            }
        )

    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
