#!/usr/bin/env python3
"""Update envpilot manifests from upstream stable release metadata."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_DIR = ROOT / "manifests"
PRERELEASE_RE = re.compile(r"(^|[._+\-/])(alpha|beta|rc|pre|prerelease|nightly|snapshot)([0-9._+\-/]|$)", re.I)


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise RuntimeError(f"Manifest must be a JSON object: {path}")
    return data


def write_json(path: Path, data: dict[str, Any]) -> None:
    try:
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    except OSError as exc:
        raise RuntimeError(f"Could not write {path}: {exc}") from exc


def fetch_json(url: str) -> Any:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "envpilot-manifest-updater",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.load(response)


def validate_manifest(path: Path, data: dict[str, Any]) -> None:
    if not data.get("name"):
        raise RuntimeError(f"Manifest missing name: {path}")
    rules = data.get("asset_rules", [])
    if rules is not None and not isinstance(rules, list):
        raise RuntimeError(f"asset_rules must be a list: {path}")
    for index, rule in enumerate(rules or []):
        if not isinstance(rule, dict):
            raise RuntimeError(f"asset_rules[{index}] must be an object: {path}")
        if "regex" in rule:
            re.compile(str(rule["regex"]))
    latest = data.get("latest")
    if latest is not None and not isinstance(latest, dict):
        raise RuntimeError(f"latest must be an object when present: {path}")


def strip_volatile(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: strip_volatile(item) for key, item in value.items() if key != "checked_at"}
    if isinstance(value, list):
        return [strip_volatile(item) for item in value]
    return value
def stable_release(releases: list[dict[str, Any]]) -> dict[str, Any]:
    for release in releases:
        tag = str(release.get("tag_name", ""))
        if release.get("draft") or release.get("prerelease"):
            continue
        if PRERELEASE_RE.search(tag):
            continue
        return release
    raise RuntimeError("No stable release found")


def stable_tag(tags: list[dict[str, Any]]) -> dict[str, Any]:
    for tag in tags:
        name = str(tag.get("name", ""))
        if name and not PRERELEASE_RE.search(name):
            return tag
    raise RuntimeError("No stable tag found")


def stable_asset(assets: list[dict[str, Any]], regex: str) -> dict[str, Any] | None:
    pattern = re.compile(regex)
    for asset in assets:
        name = str(asset.get("name", ""))
        if PRERELEASE_RE.search(name):
            continue
        if pattern.search(name):
            return asset
    return None


def update_github_release_manifest(data: dict[str, Any]) -> bool:
    api = data.get("api")
    rules = data.get("asset_rules")
    if not api or not isinstance(rules, list):
        return False

    release = stable_release(fetch_json(str(api)))
    assets = release.get("assets") or []
    resolved: dict[str, Any] = {}
    for rule in rules:
        if not isinstance(rule, dict) or "regex" not in rule:
            continue
        key = f"{rule.get('os', 'unknown')}-{rule.get('arch', 'unknown')}"
        asset = stable_asset(assets, str(rule["regex"]))
        if asset is None:
            resolved[key] = {"status": "missing", "regex": rule["regex"]}
            continue
        resolved[key] = {
            "name": asset.get("name", ""),
            "url": asset.get("browser_download_url", ""),
            "size": asset.get("size", 0),
            "digest": asset.get("digest", ""),
            "content_type": asset.get("content_type", ""),
            "updated_at": asset.get("updated_at", ""),
        }

    data["latest"] = {
        "version": release.get("tag_name", ""),
        "name": release.get("name", ""),
        "published_at": release.get("published_at", ""),
        "html_url": release.get("html_url", ""),
        "checked_at": now_iso(),
        "assets": resolved,
    }
    return True


def update_npm_manifest(data: dict[str, Any]) -> bool:
    package = data.get("package")
    if not package:
        return False
    escaped = urllib.parse.quote(str(package), safe="")
    meta = fetch_json(f"https://registry.npmjs.org/{escaped}")
    latest_version = meta.get("dist-tags", {}).get("latest")
    if not latest_version:
        raise RuntimeError(f"No npm latest dist-tag for {package}")
    version_meta = meta.get("versions", {}).get(latest_version, {})
    dist = version_meta.get("dist", {})
    data["latest"] = {
        "version": latest_version,
        "published_at": meta.get("time", {}).get(latest_version, ""),
        "checked_at": now_iso(),
        "tarball": dist.get("tarball", ""),
        "integrity": dist.get("integrity", ""),
        "shasum": dist.get("shasum", ""),
    }
    return True


def update_conda_manifest(data: dict[str, Any]) -> bool:
    assets = data.get("assets")
    if not isinstance(assets, list):
        return False
    data["latest"] = {
        "checked_at": now_iso(),
        "policy": "vendor latest URLs are used directly on platforms that can run them; Linux glibc 2.17-2.27 falls back to Miniforge latest; installer version is resolved by upstream at download time",
        "assets": [
            {
                "os": item.get("os"),
                "arch": item.get("arch"),
                "url": item.get("url"),
                "offline_pattern": item.get("offline_pattern"),
            }
            for item in assets
            if isinstance(item, dict)
        ],
    }
    return True


def update_tmux_manifest(data: dict[str, Any]) -> bool:
    releases = fetch_json("https://api.github.com/repos/tmux/tmux/releases")
    if releases:
        release = stable_release(releases)
        data["latest"] = {
            "version": release.get("tag_name", ""),
            "name": release.get("name", ""),
            "published_at": release.get("published_at", ""),
            "html_url": release.get("html_url", ""),
            "checked_at": now_iso(),
            "note": "source_versions remain pinned until maintainer review",
        }
        return True

    tag = stable_tag(fetch_json("https://api.github.com/repos/tmux/tmux/tags"))
    version = str(tag.get("name", ""))
    data["latest"] = {
        "version": version,
        "html_url": f"https://github.com/tmux/tmux/tree/{version}",
        "checked_at": now_iso(),
        "note": "GitHub tags are used because this repository has no release assets; source_versions remain pinned until maintainer review",
    }
    return True


def update_manifest(path: Path) -> bool:
    original = load_json(path)
    validate_manifest(path, original)
    data = json.loads(json.dumps(original))
    name = data.get("name", path.stem)
    if name in {"mihomo", "github-cli"}:
        routed = update_github_release_manifest(data)
    elif name == "codex":
        routed = update_npm_manifest(data)
    elif name == "conda":
        routed = update_conda_manifest(data)
    elif name == "tmux":
        routed = update_tmux_manifest(data)
    else:
        data["latest"] = {"checked_at": now_iso(), "status": "no updater implemented"}
        routed = True
    if not routed or strip_volatile(original) == strip_volatile(data):
        return False
    write_json(path, data)
    return True


def manifest_paths(values: list[str] | None) -> list[Path]:
    if not values:
        return sorted(MANIFEST_DIR.glob("*.json"))
    paths = []
    for item in values:
        path = Path(item)
        if not path.exists():
            path = MANIFEST_DIR / f"{item}.json"
        if not path.exists():
            raise RuntimeError(f"Manifest not found: {item}")
        paths.append(path)
    return paths


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate manifest JSON and updater routing without network writes.")
    parser.add_argument("--manifest", action="append", help="Manifest name or path to update. Defaults to all manifests.")
    args = parser.parse_args()

    try:
        paths = manifest_paths(args.manifest)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    for path in paths:
        try:
            data = load_json(path)
            validate_manifest(path, data)
            if args.check:
                print(f"valid: {path.relative_to(ROOT)} ({data.get('name', path.stem)})")
                continue
            changed = update_manifest(path)
            status = "updated" if changed else "unchanged"
            print(f"{status}: {path.relative_to(ROOT)}")
        except (json.JSONDecodeError, re.error, urllib.error.URLError, TimeoutError, RuntimeError) as exc:
            print(f"error: {path.relative_to(ROOT)}: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())