#!/bin/bash
# install.sh - Global production runtime installer for KaisarCode dependencies.
# Summary: Installs compiled shared dependencies. Supports local and remote execution.
#
# Usage: 
#   ./install.sh [dep1 dep2 ...]
#   wget -qO- https://.../install.sh | bash -s -- [dep1 dep2 ...]
#
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU GPL v3.0

set -euo pipefail

SYS_LIB_ROOT="/usr/local/lib/kaisarcode"
REPO_ARCHIVE_ROOT="https://codeload.github.com/kaisarcode/kc-bin-dep/tar.gz/refs/heads"

# Prints a success message to stdout.
# @param $1 The message to print.
# @return 0 on success.
pass() { printf "\033[32m[PASS]\033[0m %s\n" "$1"; }

# Prints an error message to stderr and exits.
# @param $1 The error message to print.
# @return Does not return.
fail() { printf "\033[31m[FAIL]\033[0m %s\n" "$1" >&2; exit 1; }

# Ensures the installer runs with root privileges.
# @param $@ Original script arguments.
# @return Does not return when re-executing.
ensure_root() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    command -v sudo >/dev/null 2>&1 || fail "sudo is required."
    exec sudo bash "$0" "$@"
}

# Detects the current machine architecture.
# @return Writes the resolved architecture name to stdout.
detect_arch() {
    case "$(uname -m)" in
        x86_64) printf "x86_64" ;;
        aarch64|arm64) printf "aarch64" ;;
        armv8*|arm64-v8a) printf "arm64-v8a" ;;
        *) fail "Unsupported architecture: $(uname -m)" ;;
    esac
}

# Validates one explicit architecture override.
# @param $1 Candidate architecture.
# @return Writes the normalized architecture name to stdout.
normalize_arch() {
    case "$1" in
        x86_64) printf "x86_64" ;;
        aarch64|arm64) printf "aarch64" ;;
        arm64-v8a|armv8*) printf "arm64-v8a" ;;
        win64) printf "win64" ;;
        *) fail "Unsupported architecture override: $1" ;;
    esac
}

# Verifies whether one dependency already has usable runtime assets installed.
# @param $1 Dependency name.
# @param $2 Architecture name.
# @return 0 when usable assets are present.
has_installed_runtime() {
    local dep="$1"
    local arch="$2"
    local target_dir="${SYS_LIB_ROOT}/obj/${dep}/${arch}"
    [ -d "$target_dir" ] || return 1
    if [ "$arch" = "win64" ]; then
        find "$target_dir" -maxdepth 1 -type f \( -name "*.dll" -o -name "*.exe" \) | grep -q .
        return $?
    fi
    find "$target_dir" -maxdepth 1 \( -type f -o -type l \) \( -name "*.so" -o -name "*.so.*" \) | grep -q .
}

refresh_arch_index() {
    local arch="$1"
    local arch_dir="${SYS_LIB_ROOT}/${arch}"
    mkdir -p "$arch_dir"
    find "$arch_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    
    for obj_root in "$SYS_LIB_ROOT/obj"/*; do
        [ -d "$obj_root/$arch" ] || continue
        if [ "$arch" = "win64" ]; then
            find "$obj_root/$arch" -maxdepth 1 \( -type f -o -type l \) \
                \( -name "*.dll" -o -name "*.exe" \) | while read -r lib_path; do
                ln -sfn "$lib_path" "$arch_dir/$(basename "$lib_path")"
            done
        else
            find "$obj_root/$arch" -maxdepth 1 \( -type f -o -type l \) \
                \( -name "*.so" -o -name "*.so.*" \) | while read -r lib_path; do
                ln -sfn "$lib_path" "$arch_dir/$(basename "$lib_path")"
            done
        fi
    done
}

register_arch_loader_path() {
    local arch="$1"
    local conf_path="/etc/ld.so.conf.d/kc-${arch}.conf"
    local tmp_file
    tmp_file=$(mktemp)
    
    # Register each obj/<dep>/<arch>
    for obj_root in "$SYS_LIB_ROOT/obj"/*; do
        [ -d "$obj_root/$arch" ] || continue
        printf "%s\n" "$obj_root/$arch" >>"$tmp_file"
    done
    install -m 0644 "$tmp_file" "$conf_path"
    rm -f "$tmp_file"
}

# Resolve LFS pointers in a directory using parallel downloads.
# @param $1 Directory path to scan.
# @param $2 Library base path (for relative URL calculation).
# @return 0 on success.
resolve_lfs() {
    local src_dir="$1"
    local base_path="$2"
    local pointers
    pointers=$(grep -rl '^version https://git-lfs.github.com/spec/v1' "$src_dir" 2>/dev/null || true)
    if [ -z "$pointers" ]; then return 0; fi
    printf "Resolving LFS pointers...\n"
    echo "$pointers" | xargs -r -P 8 -I {} bash -c '
        file="$1"
        base="$2"
        rel="${file#$base/}"
        url="https://media.githubusercontent.com/media/kaisarcode/kc-bin-dep/master/lib/${rel}"
        printf "  -> %s\n" "$rel"
        if wget --timeout=15 --tries=3 -qO "$file.tmp" "$url"; then
            mv "$file.tmp" "$file"
        else
            printf "  [WARN] Download failed for %s\n" "$rel"
            rm -f "$file" "$file.tmp"
        fi
    ' -- {} "$base_path" || true
}

# Installs one dependency into the system.
# @param $1 Dependency name.
# @param $2 Architecture name.
# @param $3 Source directory.
# @param $4 Is remote flag (true/false).
# @param $5 Library base path.
# @return 0 on success.
install_inc() {
    local dep=$1
    local src_dir=$2
    local dst_dir="${SYS_LIB_ROOT}/inc/${dep}"
    mkdir -p "$dst_dir"
    rsync -a --delete "$src_dir"/ "$dst_dir"/
    pass "Installed headers: $dep"
}

install_obj() {
    local dep=$1
    local arch=$2
    local src_dir="$3"
    local is_remote=$4
    local lib_base=$5
    if [ "$is_remote" = "true" ]; then
        # Note: LFS resolution might need adjustment for the new structure
        # but resolve_lfs is generic enough if passed the right paths.
        resolve_lfs "$src_dir" "$lib_base"
    fi
    local dst_dir="${SYS_LIB_ROOT}/obj/${dep}/${arch}"
    mkdir -p "$dst_dir"
    rsync -a --delete "$src_dir"/ "$dst_dir"/
    pass "Installed binaries: $dep ($arch)"
}

# Primary entry point for the installer.
# @param $@ Optional list of dependencies to install.
# @return 0 on success.
main() {
    ensure_root "$@"
    local arch=""
    local branch="master"
    local targets=()
    local tmp_dir=""
    local lib_source=""
    local is_remote="false"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [ $# -gt 0 ]; do
        case "$1" in
            --arch)
                [ $# -ge 2 ] || fail "Missing value for --arch"
                arch=$(normalize_arch "$2")
                shift 2
                ;;
            --arch=*)
                arch=$(normalize_arch "${1#--arch=}")
                shift
                ;;
            --branch)
                [ $# -ge 2 ] || fail "Missing value for --branch"
                branch="$2"
                shift 2
                ;;
            --branch=*)
                branch="${1#--branch=}"
                shift
                ;;
            *)
                targets+=("$1")
                shift
                ;;
        esac
    done
    [ -n "$arch" ] || arch=$(detect_arch)
    if [ -d "$script_dir/lib" ]; then
        lib_source="$script_dir/lib"
    else
        if [ ${#targets[@]} -gt 0 ]; then
            local missing=false
            for target in "${targets[@]}"; do
                if ! has_installed_runtime "$target" "$arch"; then
                    missing=true
                    break
                fi
            done
            if [ "$missing" = "false" ]; then
                pass "Requested dependencies already installed. Skipping pack download."
                return 0
            fi
        fi
        tmp_dir=$(mktemp -d)
        trap 'rm -rf "$tmp_dir"' EXIT
        printf "Downloading dependency pack...\n"
        wget -qO "$tmp_dir/core.tar.gz" "$REPO_ARCHIVE_ROOT/$branch"
        tar -xzf "$tmp_dir/core.tar.gz" -C "$tmp_dir"
        lib_source=$(ls -d "$tmp_dir"/*/lib 2>/dev/null | head -n 1)
        [ -n "$lib_source" ] || fail "Could not locate lib directory in archive."
        is_remote="true"
    fi
    if [ ${#targets[@]} -eq 0 ]; then
        # Install headers
        if [ -d "$lib_source/inc" ]; then
            for dep_dir in "$lib_source/inc"/*; do
                [ -d "$dep_dir" ] || continue
                install_inc "$(basename "$dep_dir")" "$dep_dir"
            done
        fi
        # Install objects
        if [ -d "$lib_source/obj" ]; then
            for dep_dir in "$lib_source/obj"/*; do
                [ -d "$dep_dir/$arch" ] || continue
                install_obj "$(basename "$dep_dir")" "$arch" "$dep_dir/$arch" "$is_remote" "$lib_source"
            done
        fi
    else
        for vendor in "${targets[@]}"; do
            # Special case for GGML/Llama split if requested specifically
            if [ -d "$lib_source/inc/$vendor" ]; then
                install_inc "$vendor" "$lib_source/inc/$vendor"
            fi
            if [ -d "$lib_source/obj/$vendor/$arch" ]; then
                install_obj "$vendor" "$arch" "$lib_source/obj/$vendor/$arch" "$is_remote" "$lib_source"
            fi
        done
    fi
    refresh_arch_index "$arch"
    if [ "$arch" != "win64" ]; then
        register_arch_loader_path "$arch"
        ldconfig
    fi
    printf "\n\033[1;32m[SUCCESS]\033[0m Dependencies installed.\n"
}

main "$@"
