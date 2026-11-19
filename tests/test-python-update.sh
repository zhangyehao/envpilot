#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export HOME="$fixture/home" ENVPILOT_LANG=en
unset ENVPILOT_CONFIG_DIR ENVPILOT_CONFIG_FILE ENVPILOT_OVERRIDES EP_PYTHON_VERSION
mkdir -p "$HOME/.config/envpilot" "$fixture/pkg/python/bin" "$fixture/assets"
printf 'version: 1\nshell:\n  prefer_managed: [python]\n' > "$HOME/.config/envpilot/config.yaml"
case "$(uname -s):$(uname -m)" in
    Linux:x86_64) target=x86_64-unknown-linux-gnu ;;
    Linux:aarch64) target=aarch64-unknown-linux-gnu ;;
    Darwin:x86_64) target=x86_64-apple-darwin ;;
    Darwin:arm64) target=aarch64-apple-darwin ;;
    *) exit 0 ;;
esac
# A tiny, valid package with the upstream bin/python3 -> python3.15 layout.
cat > "$fixture/pkg/python/bin/python3.15" <<'EOF'
#!/bin/sh
case "$1" in --version) echo 'Python 3.15.2' ;; *) echo '3.15.2' ;; esac
EOF
chmod +x "$fixture/pkg/python/bin/python3.15"
ln -s python3.15 "$fixture/pkg/python/bin/python3"
name="cpython-3.15.2+20261110-$target-install_only.tar.gz"
archive="$fixture/assets/$name"
tar -czf "$archive" -C "$fixture/pkg" python
if command -v sha256sum >/dev/null; then digest="$(sha256sum < "$archive")"; else digest="$(shasum -a 256 < "$archive")"; fi
printf '%s  %s\n' "${digest%% *}" "$name" > "$fixture/assets/SHA256SUMS"
update() {
    bash "$ROOT/envpilot.sh" update python --mode offline --prefix "$fixture/install" --asset-path "$archive" --yes --non-interactive
}
update > "$fixture/first.log" 2>&1 || { cat "$fixture/first.log"; exit 1; }
grep -Fq 'Python archive SHA-256 verified.' "$fixture/first.log"
current="$fixture/install/python/current"
old="$(readlink "$current")"
test "$("$current/bin/python3" --version)" = 'Python 3.15.2'
# A missing digest or corruption leaves the same tested generation active.
mv "$fixture/assets/SHA256SUMS" "$fixture/assets/sums.bak"
if update > "$fixture/missing.log" 2>&1; then echo 'unverified package accepted'; exit 1; fi
grep -Fq 'No trusted Python checksum' "$fixture/missing.log"
mv "$fixture/assets/sums.bak" "$fixture/assets/SHA256SUMS"
printf 'corruption' >> "$archive"
if update > "$fixture/mismatch.log" 2>&1; then echo 'corrupt package accepted'; exit 1; fi
grep -Fq 'Python archive SHA-256 mismatch' "$fixture/mismatch.log"
test "$(readlink "$current")" = "$old"
test "$("$current/bin/python3" --version)" = 'Python 3.15.2'
echo '[TEST] offline Python SHA-256 verification, archive symlinks and preserved active interpreter passed.'
