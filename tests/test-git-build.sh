#!/usr/bin/env bash
# Deterministic Git update regression: real local Git operations and native
# publication, with a small substitute for compiling an entire Git release.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
export REAL_GIT REAL_CC REAL_LN REAL_CP
REAL_GIT=$(command -v git)
REAL_CC=$(command -v cc)
REAL_LN=$(command -v ln)
REAL_CP=$(command -v cp)
export HOME="$scratch/home" EP_PREFIX="$scratch/managed" ENVPILOT_ROOT="$ROOT"
export ENVPILOT_GIT_TOOLCHAIN_BIN="$scratch/compiler" ENVPILOT_GIT_BUILD_JOBS=2
export ENVPILOT_GIT_DEPENDENCY_PREFIX="$HOME/anaconda3" TMPDIR="$scratch/tmp"
export TRACE="$scratch/flags" ENVPILOT_LANG=en
dep="$ENVPILOT_GIT_DEPENDENCY_PREFIX"
mkdir -p "$HOME" "$TMPDIR" "$scratch/compiler" "$scratch/git-2.56.1" "$dep/include/curl" "$dep/include/openssl" "$dep/lib"
touch "$dep/include/curl/curl.h" "$dep/include/openssl/rand.h" "$dep/include/iconv.h"
touch "$dep/lib/libcurl.so" "$dep/lib/libssl.so" "$dep/lib/libcrypto.so" "$dep/lib/libiconv.so"
cat > "$scratch/compiler/cc" <<'CC'
#!/usr/bin/env bash
set -eu
out=''
source=''
while (($#)); do
    case "$1" in -o) shift; out=$1 ;; *.c) source=$1 ;; esac
    shift
done
case "$source" in
    */getrandom.c)
        [ "${NATIVE_RNG:-}" = 1 ] || exit 1 # Simulate older libc headers.
        printf '#!/bin/sh\nexit 0\n' > "$out"; chmod +x "$out" ;;
    */git-publish.c) exec "$REAL_CC" "$source" -o "$out" ;;
    */curl.c|*/openssl.c|*/iconv.c)
        [ "${FAIL_DEPS:-}" != 1 ] || exit 1
        [ "${REQUIRE_PREFIX:-}" != 1 ] || [ -n "${EP_GIT_DEP:-}" ] || exit 1
        printf '#!/bin/sh\nexit 0\n' > "$out"; chmod +x "$out" ;;
    *) exit 2 ;;
esac
CC
cat > "$scratch/compiler/ln" <<'SH'
#!/bin/sh
if [ "${LINKLESS:-}" = 1 ] && [ "$1" = -s ]; then exit 1; fi
exec "$REAL_LN" "$@"
SH
cat > "$scratch/compiler/cp" <<'SH'
#!/usr/bin/env bash
if [[ ${FAIL_COPY:-} == 1 && ${!#} == */next ]]; then exit 1; fi
exec "$REAL_CP" "$@"
SH
cat > "$scratch/git-2.56.1/configure" <<'SH'
#!/bin/sh
set -eu
for arg do case "$arg" in --prefix=*) echo "${arg#--prefix=}" > prefix ;; esac; done
SH
cat > "$scratch/compiler/make" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$TRACE"
if [ "${FAIL_BUILD:-}" = 1 ]; then exit 1; fi
if [[ ${!#} == install ]]; then
    p=$(cat prefix)
    mkdir -p "$p/bin" "$p/libexec/git-core"
    {
        echo '#!/usr/bin/env bash'
        echo 'if [[ "$1" == --version ]]; then echo "git version 2.56.1"; exit; fi'
        printf 'if [[ "$1" == --exec-path ]]; then echo %q; exit; fi\n' "$p/libexec/git-core"
        printf 'exec %q "$@"\n' "$REAL_GIT"
    } > "$p/bin/git"
    helper=$("$REAL_GIT" --exec-path)/git-remote-https
    printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$helper" > "$p/libexec/git-core/git-remote-https"
    chmod 755 "$p/bin/git" "$p/libexec/git-core/git-remote-https"
fi
SH
chmod +x "$scratch/compiler/"* "$scratch/git-2.56.1/configure"
tar -cJf "$scratch/git-2.56.1.tar.xz" -C "$scratch" git-2.56.1
. "$ROOT/lib/common.sh"
. "$ROOT/lib/platform.sh"
. "$ROOT/lib/manifest.sh"
. "$ROOT/components/git.sh"
export EP_OS=linux EP_ARCH=amd64 EP_GIT_VERSION=2.56.1
base="$EP_PREFIX/git"
mkdir -p "$base/current/bin"
echo legacy > "$base/current/bin/marker"
ep_git_preflight
test -f "$base/current/bin/marker"
NATIVE_RNG=1 ENVPILOT_GIT_DEPENDENCY_PREFIX="" ep_git_preflight > "$scratch/native"
grep -q "dependencies=system random=getrandom" "$scratch/native"
REQUIRE_PREFIX=1 ENVPILOT_GIT_DEPENDENCY_PREFIX="" ep_git_preflight > "$scratch/auto"
grep -Fq "dependencies=$dep random=openssl" "$scratch/auto"
if FAIL_DEPS=1 ENVPILOT_GIT_DEPENDENCY_PREFIX="" ep_git_preflight; then exit 1; fi
ep_git_stage install "$EP_GIT_VERSION" "$scratch/git-2.56.1.tar.xz"
grep -q -- '-j2 .*CSPRNG_METHOD=openssl .*NEEDS_LIBICONV=YesPlease .* all$' "$TRACE"
grep -q -- '^NO_RUST=YesPlease .*CSPRNG_METHOD=openssl .* install$' "$TRACE"
test "$("$base/current/bin/git" --version)" = 'git version 2.56.1'
prev=$(readlink "$base/current")
if FAIL_BUILD=1 ep_git_stage install "$EP_GIT_VERSION" "$scratch/git-2.56.1.tar.xz"; then exit 1; fi
test "$(readlink "$base/current")" = "$prev"
if ENVPILOT_GIT_DEPENDENCY_PREFIX="$scratch/missing" ep_git_preflight; then exit 1; fi
LINKLESS=1 ep_git_stage install "$EP_GIT_VERSION" "$scratch/git-2.56.1.tar.xz"
test ! -L "$base/current"
expected=$("$base/current/bin/git" --exec-path)
if FAIL_COPY=1 LINKLESS=1 ep_git_stage install "$EP_GIT_VERSION" "$scratch/git-2.56.1.tar.xz"; then exit 1; fi
test "$("$base/current/bin/git" --exec-path)" = "$expected"
test "$("$base/current/bin/git" --version)" = 'git version 2.56.1'
echo 'Git build options, HTTPS helper, failed retry and linkless activation verified.'
