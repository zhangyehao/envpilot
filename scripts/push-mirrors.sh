#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="$(git -C "$ROOT" branch --show-current)"

[ "$BRANCH" = "main" ] || {
    printf '[ERROR] mirror publishing must run from main; current branch: %s\n' "$BRANCH" >&2
    exit 1
}
if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet || [ -n "$(git -C "$ROOT" ls-files --others --exclude-standard)" ]; then
    printf '[ERROR] working tree is not clean. Commit or remove local changes first.\n' >&2
    exit 1
fi

for remote in origin gitee; do
    git -C "$ROOT" remote get-url "$remote" >/dev/null 2>&1 || {
        printf '[ERROR] missing git remote: %s\n' "$remote" >&2
        exit 1
    }
done

printf '[INFO] pushing main and tags to GitHub (origin).\n'
git -C "$ROOT" push origin main --follow-tags
printf '[INFO] pushing main and tags to Gitee (gitee).\n'
git -C "$ROOT" push gitee main --follow-tags
printf '[OK] GitHub and Gitee are synchronized.\n'
