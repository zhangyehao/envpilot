#!/usr/bin/env python3
"""Refresh bundled stable mihomo cache assets from upstream releases."""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DOWNLOADS = ROOT / "downloads"
API = "https://api.github.com/repos/MetaCubeX/mihomo/releases?per_page=100"
PRERELEASE_RE = re.compile(r"(^|[._+\-/])(alpha|beta|rc|pre|prerelease|nightly|snapshot)([0-9._+\-/]|$)", re.I)
RULES = (
    {
        "name": "linux-amd64",
        "regex": re.compile(r"^mihomo-linux-amd64-compatible-v[^/]+\.gz$"),
    },
    {
        "name": "windows-amd64",
        "regex": re.compile(r"^mihomo-windows-amd64-compatible-v[^/]+\.zip$"),
    },
)


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def request_json(url: str) -> Any:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "envpilot-mihomo-cache-updater",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read().decode("utf-8")


def fetch_json(url: str) -> Any:
    import json

    return json.loads(request_json(url))


def stable_release(releases: list[dict[str, Any]]) -> dict[str, Any]:
    for release in releases:
        tag = str(release.get("tag_name", ""))
        if release.get("draft") or release.get("prerelease"):
            continue
        if PRERELEASE_RE.search(tag):
            continue
        return release
    raise RuntimeError("No stable mihomo release found")


def select_asset(assets: list[dict[str, Any]], pattern: re.Pattern[str]) -> dict[str, Any]:
    for asset in assets:
        name = str(asset.get("name", ""))
        if PRERELEASE_RE.search(name):
            continue
        if pattern.match(name):
            return asset
    raise RuntimeError(f"No stable asset matched {pattern.pattern}")


def download_file(url: str, dest: Path) -> None:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "envpilot-mihomo-cache-updater"},
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(req, timeout=120) as response, tempfile.NamedTemporaryFile(delete=False, dir=str(dest.parent), suffix=".tmp") as tmp:
        shutil.copyfileobj(response, tmp)
        tmp_path = Path(tmp.name)
    tmp_path.replace(dest)


def prune_old_assets(pattern: re.Pattern[str], keep: Path) -> None:
    for path in DOWNLOADS.glob("*"):
        if not path.is_file():
            continue
        if path == keep:
            continue
        if pattern.match(path.name):
            path.unlink()


def refresh_cache() -> int:
    releases = fetch_json(API)
    if not isinstance(releases, list):
        raise RuntimeError("GitHub releases API returned unexpected data")

    release = stable_release(releases)
    tag = str(release.get("tag_name", ""))
    assets = release.get("assets") or []
    if not isinstance(assets, list):
        raise RuntimeError("Release assets payload is invalid")

    print(f"stable release: {tag}")
    DOWNLOADS.mkdir(parents=True, exist_ok=True)

    for rule in RULES:
        asset = select_asset(assets, rule["regex"])
        name = str(asset.get("name", ""))
        url = str(asset.get("browser_download_url", ""))
        if not url:
            raise RuntimeError(f"Asset missing download URL: {name}")
        dest = DOWNLOADS / name
        print(f"{rule['name']}: {name}")
        download_file(url, dest)
        prune_old_assets(rule["regex"], dest)

    print(f"updated_at: {now_iso()}")
    return 0


def check_cache() -> int:
    print("mihomo cache check")
    for rule in RULES:
        matches = sorted(DOWNLOADS.glob("*"), key=lambda path: path.name, reverse=True)
        found = [path.name for path in matches if path.is_file() and rule["regex"].match(path.name)]
        if found:
            print(f"{rule['name']}: {found[0]}")
        else:
            print(f"{rule['name']}: missing")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Inspect local mihomo cache files without fetching upstream metadata.")
    args = parser.parse_args()

    try:
        return check_cache() if args.check else refresh_cache()
    except (urllib.error.URLError, TimeoutError, RuntimeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
