"""Bounded HTTP and transactional file replacement for maintenance jobs."""
from __future__ import annotations

import email.utils
import json
import os
from pathlib import Path
import random
import shutil
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected is not None and urllib.parse.urlsplit(newurl).hostname != "api.github.com":
            redirected.remove_header("Authorization")
        return redirected


def request(url: str, timeout: int = 30, attempts: int = 4):
    headers = {"User-Agent": "envpilot/0.4 maintenance", "Accept": "application/json"}
    if urllib.parse.urlsplit(url).hostname == "api.github.com":
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
    opener = urllib.request.build_opener(SafeRedirect())
    for attempt in range(attempts):
        try:
            return opener.open(urllib.request.Request(url, headers=headers), timeout=timeout)
        except urllib.error.HTTPError as exc:
            retryable = exc.code in (408, 429, 500, 502, 503, 504) or (
                exc.code == 403 and exc.headers.get("X-RateLimit-Remaining") == "0"
            )
            if not retryable or attempt == attempts - 1:
                raise
            retry_after = exc.headers.get("Retry-After", "")
            try:
                delay = float(retry_after)
            except ValueError:
                try:
                    delay = email.utils.parsedate_to_datetime(retry_after).timestamp() - time.time()
                except (TypeError, ValueError):
                    delay = 2 ** attempt + random.random()
            # Do not hammer a server whose requested wait exceeds the job budget.
            if delay > 60:
                raise RuntimeError("Upstream rate limit requires a later maintenance run") from exc
            exc.close()
            time.sleep(max(0, delay))
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == attempts - 1:
                raise
            time.sleep(2 ** attempt + random.random())
    raise RuntimeError("HTTP retry budget exhausted")


def fetch_json(url: str):
    with request(url) as response:
        return json.load(response)


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    partial = dest.with_name(dest.name + ".part")
    try:
        with request(url, timeout=60) as response, partial.open("wb") as output:
            expected = response.headers.get("Content-Length")
            shutil.copyfileobj(response, output)
        if expected is not None and partial.stat().st_size != int(expected):
            raise RuntimeError("Incomplete upstream download")
        partial.replace(dest)
    finally:
        partial.unlink(missing_ok=True)


def commit_files(pairs: list[tuple[Path, Path]]) -> None:
    """Replace a validated set; restore prior files if any replacement fails."""
    if not pairs:
        return
    with tempfile.TemporaryDirectory(prefix="envpilot-rollback-", dir=pairs[0][1].parent) as backup:
        previous: list[tuple[Path, Path | None]] = []
        for index, (_, dest) in enumerate(pairs):
            old = Path(backup) / str(index) if dest.exists() else None
            if old is not None:
                shutil.copy2(dest, old)
            previous.append((dest, old))
        changed = 0
        try:
            for source, dest in pairs:
                source.replace(dest)
                changed += 1
        except OSError:
            for dest, old in reversed(previous[:changed]):
                if old is None:
                    dest.unlink(missing_ok=True)
                else:
                    old.replace(dest)
            raise
