#!/usr/bin/env bash

# These probes run inside ep_git_stage's subshell. The selected settings are
# then used by configure, make all and make install without relying on .bashrc.
ep_git_toolchain()
{
    local tool base_cc
    if [ -n "${ENVPILOT_GIT_TOOLCHAIN_BIN:-}" ]; then
        [ -d "$ENVPILOT_GIT_TOOLCHAIN_BIN" ] || ep_die "Git toolchain directory does not exist: $ENVPILOT_GIT_TOOLCHAIN_BIN"
        export PATH="$ENVPILOT_GIT_TOOLCHAIN_BIN:$PATH"
    fi
    for tool in make tar; do command -v "$tool" >/dev/null || ep_die "Git build requires $tool on the maintenance PATH."; done
    base_cc="${CC:-}"
    if [ -z "$base_cc" ]; then base_cc=$(command -v cc || command -v gcc || command -v clang) || ep_die "Git build needs a C compiler on the maintenance PATH."; fi
    export EP_GIT_REAL_CC="$base_cc"
    # Pass library paths as individual compiler arguments. In particular,
    # embedded RUNPATHs must still work after the cron process has exited.
    cat > "$work/envpilot-git-cc" <<'SH' || ep_die "Could not prepare the Git compiler."
#!/usr/bin/env bash
set -eu
if command -v "$EP_GIT_REAL_CC" >/dev/null; then
    compiler=("$EP_GIT_REAL_CC")
else
    read -r -a compiler <<< "$EP_GIT_REAL_CC"
fi
if [ -n "${EP_GIT_DEP:-}" ]; then
    for arg do
        case "$arg" in -c|-E|-S|-M|-MM) exec "${compiler[@]}" "-I$EP_GIT_DEP/include" "$@" ;; esac
    done
    set -- "-I$EP_GIT_DEP/include" "-L$EP_GIT_LIB" -Xlinker -rpath -Xlinker "$EP_GIT_LIB" "$@"
fi
exec "${compiler[@]}" "$@"
SH
    chmod 700 "$work/envpilot-git-cc" || ep_die "Cannot execute files in the Git build directory."
    export CC=envpilot-git-cc PATH="$work:$PATH"
}

ep_git_has_library()
{
    local f
    for f in "$1/lib$2.so" "$1/lib$2.dylib" "$1/lib$2.a"; do [ ! -f "$f" ] || return 0; done
    return 1
}

ep_git_probe_cc()
{
    local opt
    local -a args=() words=()
    for opt in "${CPPFLAGS:-}" "${CFLAGS:-}" "${LDFLAGS:-}"; do
        if [ -n "$opt" ]; then
            read -r -a words <<< "$opt"
            args+=("${words[@]}")
        fi
    done
    "$CC" ${args[@]+"${args[@]}"} "$@"
}

ep_git_probe_libraries()
{
    export EP_GIT_DEP="$1" EP_GIT_LIB=""
    local lib
    if [ -n "$EP_GIT_DEP" ]; then
        [ -f "$EP_GIT_DEP/include/curl/curl.h" ] && [ -f "$EP_GIT_DEP/include/openssl/rand.h" ] || return 1
        for lib in "$EP_GIT_DEP/lib" "$EP_GIT_DEP/lib64"; do
            if ep_git_has_library "$lib" curl && ep_git_has_library "$lib" ssl && ep_git_has_library "$lib" crypto; then
                EP_GIT_LIB="$lib"; break
            fi
        done
        [ -n "$EP_GIT_LIB" ] || return 1
    fi
    # Start with zlib and an HTTPS-capable curl; Git can still use platform
    # TLS/RNG implementations on machines without OpenSSL development files.
    ep_git_probe_cc "$work/curl.c" -o "$work/check" "-DCURL_FLOOR=$curl_floor" -lcurl -lz && "$work/check" || return 1
    needs_iconv=""
    if [ -n "$EP_GIT_DEP" ] && [ -f "$EP_GIT_DEP/include/iconv.h" ]; then
        ep_git_has_library "$EP_GIT_LIB" iconv || return 1
        ep_git_probe_cc "$work/iconv.c" -o "$work/check-iconv" -liconv && "$work/check-iconv" || return 1
        needs_iconv=1
    fi
    rng=platform
    if [ "$EP_OS" = linux ]; then
        if { ep_git_probe_cc "$work/getrandom.c" -o "$work/rng" && "$work/rng"; } 2>/dev/null; then
            rng=getrandom
        else
            ep_git_probe_cc "$work/openssl.c" -o "$work/rng" -lcrypto -lssl && "$work/rng" || return 1
            rng=openssl
        fi
    fi
    return 0
}

ep_git_build_probes()
{
    local dep candidate
    cat > "$work/curl.c" <<'C'
#include <string.h>
#include <curl/curl.h>
#include <zlib.h>
#if LIBCURL_VERSION_NUM < CURL_FLOOR
#error libcurl development headers are too old for this Git version
#endif
int main(void) {
    const curl_version_info_data *info = curl_version_info(CURLVERSION_NOW);
    const char *const *p;
    if (!info || info->version_num < CURL_FLOOR || !zlibVersion()) return 1;
    for (p = info->protocols; p && *p; p++) if (!strcmp(*p, "https")) return 0;
    return 1;
}
C
    cat > "$work/getrandom.c" <<'C'
#include <sys/random.h>
int main(void) { char b; return getrandom(&b, 1, 0) != 1; }
C
    cat > "$work/openssl.c" <<'C'
#include <openssl/rand.h>
int main(void) { unsigned char b; return RAND_pseudo_bytes(&b, 1) != 1; }
C
    cat > "$work/iconv.c" <<'C'
#include <iconv.h>
int main(void) { iconv_t cd = iconv_open("UTF-8", "UTF-8"); return cd == (iconv_t)-1 || iconv_close(cd); }
C
    # Explicit settings must succeed as supplied. Automatic discovery prefers
    # the system toolchain, then only existing user Conda prefixes.
    dep="${ENVPILOT_GIT_DEPENDENCY_PREFIX:-}"
    if [ -n "$dep" ]; then
        ep_git_probe_libraries "$dep" || ep_die "Git dependencies failed to compile, link or run using $dep (curl, OpenSSL, zlib, iconv)."
    elif ! ep_git_probe_libraries "" > "$work/probe.log" 2>&1; then
        for candidate in "${BASHRC_CONDA_PRIMARY_PREFIX:-}" "$EP_PREFIX/miniconda3" "$EP_PREFIX/anaconda3" "$HOME/miniconda3" "$HOME/anaconda3"; do
            [ -n "$candidate" ] && [ -d "$candidate" ] || continue
            if ep_git_probe_libraries "$candidate" >> "$work/probe.log" 2>&1; then dep="$candidate"; break; fi
        done
        if [ -z "$dep" ]; then
            cat "$work/probe.log" >&2
            ep_die "Git compiler/dependency probe failed. Check the build directory, git.toolchain_bin and git.dependency_prefix."
        fi
    fi
    "$CC" "$ENVPILOT_ROOT/lib/git-publish.c" -o "$work/publish" || ep_die "Could not compile the Git activation helper."
    ep_log "Git build probe: compiler=$EP_GIT_REAL_CC dependencies=${dep:-system} random=$rng optional-rust=off."
}

ep_git_verify_generation()
(
    local root="$1" repo="$2/git-smoke" cmd="$1/bin/git" helper
    mkdir -p "$repo/home" || return 1
    # Exercise the installed helpers without inheriting Git config, hooks, SSH
    # agents or process-only library overrides from the invoking account.
    local -a clean=(env -i "PATH=$PATH" "HOME=$repo/home" "TMPDIR=$repo" GIT_CONFIG_NOSYSTEM=1)
    [ "$("${clean[@]}" "$cmd" --version)" = "git version $version" ] || return 1
    helper=$("${clean[@]}" "$cmd" --exec-path) || return 1
    [ "$helper" = "$root/libexec/git-core" ] || return 1
    printf 'capabilities\n\n' | "${clean[@]}" "$helper/git-remote-https" origin https://localhost/ > "$repo/caps" || return 1
    grep -qx fetch "$repo/caps" || return 1
    "${clean[@]}" "$cmd" init -q "$repo/origin" &&
        "${clean[@]}" "$cmd" -C "$repo/origin" -c user.name=envpilot -c user.email=envpilot@localhost commit -q --allow-empty -m probe &&
        "${clean[@]}" "$cmd" clone -q --no-hardlinks "$repo/origin" "$repo/clone" &&
        "${clean[@]}" "$cmd" -C "$repo/clone" fsck --no-dangling
)

ep_git_stage()
(
    local mode="$1" version="${2:-${EP_GIT_VERSION:-$(ep_git_manifest_version)}}" source="${3:-}"
    local work probe target="" base="$EP_PREFIX/git" destination jobs dep_bin
    local curl_floor=0 needs_iconv="" rng="" keep=0
    local -a flags=(NO_RUST=YesPlease NO_GETTEXT=YesPlease NO_TCLTK=YesPlease NO_PERL=YesPlease NO_PYTHON=YesPlease)
    work=$(mktemp -d "${TMPDIR:-/tmp}/envpilot-git.XXXXXXXX") || ep_die "Git needs a writable temporary build directory."
    probe=""
    trap 'rm -rf -- "$work"; if [ -n "$probe" ]; then rm -rf -- "$probe"; fi; if [ -n "$target" ] && [ "$keep" = 0 ]; then rm -rf -- "$target"; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    ep_git_toolchain
    if ep_version_at_least "$version" "2.56.0"; then curl_floor=0x073d00; fi
    ep_git_build_probes
    destination="$base"
    if [ "$mode" = preflight ]; then
        while [ ! -d "$destination" ]; do
            [ ! -e "$destination" ] && [ ! -L "$destination" ] || ep_die "Git installation path is not a directory: $destination"
            destination=$(dirname "$destination")
        done
    else
        mkdir -p "$base" || ep_die "Git install directory is not writable: $base"
    fi
    probe=$(mktemp -d "$destination/.git-publish.XXXXXXXX") || ep_die "Git install directory is not writable: $destination"
    if ! cp "$work/check" "$probe/exec" || ! "$probe/exec"; then
        ep_die "Git cannot run executables under $destination."
    fi
    # Exercise the same namespace operation as the actual activation, without
    # touching current. A no-symlink filesystem uses a staged physical copy.
    if ! ln -s test "$probe/link" 2>/dev/null || { [ -d "$base/current" ] && [ ! -L "$base/current" ]; }; then
        if ! mkdir "$probe/a" "$probe/b" || ! touch "$probe/b/marker" || ! "$work/publish" "$probe/a" "$probe/b"; then
            ep_die "Filesystem cannot atomically exchange populated Git directories at $destination; choose an install prefix with symlink or atomic exchange support."
        fi
    fi
    ep_log "Git install directory supports executing and activating a candidate: $destination"
    [ "$mode" != preflight ] || return 0

    target=$(mktemp -d "$base/$version.XXXXXXXX") || ep_die "Could not stage the Git installation."
    if [ -f "$source" ]; then cp "$source" "$work/source.tar.xz" || ep_die "Cannot read Git archive."; else ep_fetch_url "$source" "$work/source.tar.xz" || ep_die "Could not fetch Git source."; fi
    if ! mkdir "$work/src" || ! tar -xf "$work/source.tar.xz" -C "$work/src"; then ep_die "Could not extract Git source."; fi
    local -a roots=("$work/src"/*)
    [ "${#roots[@]}" = 1 ] && cd "${roots[0]}" && [ -x ./configure ] || ep_die "Git source archive did not contain a configured source distribution."
    jobs="${ENVPILOT_GIT_BUILD_JOBS:-${ENVPILOT_BUILD_JOBS:-}}"
    if [ -z "$jobs" ]; then
        jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
        if [ "$jobs" -gt 8 ]; then jobs=8; fi
    fi
    case "$jobs" in ''|0|*[!0-9]*) ep_die "Git build jobs must be a positive integer." ;; esac
    if [ "$rng" = openssl ]; then flags+=(CSPRNG_METHOD=openssl); fi
    if [ -n "$needs_iconv" ]; then flags+=(NEEDS_LIBICONV=YesPlease); fi
    if [ -n "$EP_GIT_DEP" ]; then
        dep_bin="$EP_GIT_DEP/bin"
        if [ -x "$dep_bin/curl-config" ]; then export CURL_CONFIG="$dep_bin/curl-config"; fi
        flags+=("CURL_LIBCURL=-lcurl" "CURL_CFLAGS=")
    fi
    ep_log "Building Git with $jobs job(s); this can take several minutes on a login node."
    if ! ./configure --prefix="$target" --with-curl --with-openssl ||
        ! make -j"$jobs" "${flags[@]}" all || ! make "${flags[@]}" install; then
        ep_die "User-space Git build failed. Check compiler/development libraries, or use a system/module Git."
    fi
    ep_git_verify_generation "$target" "$work" || ep_die "Git candidate failed version, HTTPS-helper, repository or fsck verification. Previous Git retained."
    if ! ln -s "$target" "$probe/next" 2>/dev/null; then
        cp -Rp "$target" "$probe/next" || ep_die "Unable to prepare Git directory copy. Previous Git retained."
        cmp "$target/bin/git" "$probe/next/bin/git" || ep_die "Staged Git copy did not verify."
    fi
    # An interruption after rename must never clean up the active generation.
    keep=1
    if ! "$work/publish" "$probe/next" "$base/current"; then
        keep=0
        ep_die "Atomic Git activation failed. Previous Git retained."
    fi
)

ep_git_preflight()
{
    ep_require_unix_runtime
    case "$EP_OS" in linux|darwin) ep_git_stage preflight ;; *) ep_die "Managed Git source builds require Linux or macOS." ;; esac
}
