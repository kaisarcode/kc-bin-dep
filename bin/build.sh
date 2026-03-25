#!/bin/bash
# dev/build.sh - Global Library Builder
# Summary: Sequentially executes all atomic build scripts.
# Standard: KCS
#
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU GPL v3.0
#
# © 2026 KaisarCode

set -e

SCRIPTS="zlib.sh libpng.sh pcre2.sh llama.sh stable-diffusion.sh imagemagick.sh resvg.sh"
DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$DEV_DIR"
DEPS_ROOT="$(dirname "$DEV_DIR")"
FORCE_BUILD=0

resolve_vendor_dir() {
    case "$1" in
        "zlib.sh") printf "%s/lib/obj/zlib\n" "$DEPS_ROOT" ;;
        "libpng.sh") printf "%s/lib/obj/libpng\n" "$DEPS_ROOT" ;;
        "pcre2.sh") printf "%s/lib/obj/pcre2\n" "$DEPS_ROOT" ;;
        "llama.sh") printf "%s/lib/obj/llama.cpp\n" "$DEPS_ROOT" ;;
        "stable-diffusion.sh") printf "%s/lib/obj/stable-diffusion.cpp\n" "$DEPS_ROOT" ;;
        "imagemagick.sh") printf "%s/lib/obj/imagemagick\n" "$DEPS_ROOT" ;;
        "resvg.sh") printf "%s/lib/obj/resvg\n" "$DEPS_ROOT" ;;
        *) return 1 ;;
    esac
}

is_built() {
    vendor_dir="$(resolve_vendor_dir "$1")" || return 1
    for arch in x86_64 win64 aarch64 arm64-v8a; do
        if [ ! -d "$vendor_dir/$arch" ]; then
            return 1
        fi
        if ! find "$vendor_dir/$arch" -mindepth 1 -print -quit >/dev/null 2>&1; then
            return 1
        fi
    done
    return 0
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --force)
                FORCE_BUILD=1
                ;;
            *)
                printf "\033[31m[FAIL]\033[0m Unknown option: %s\n" "$1"
                exit 1
                ;;
        esac
        shift
    done
}

printf "\033[1;35m[START] External Libraries Build\033[0m\n"
parse_args "$@"

for script in $SCRIPTS; do
    if [ -f "$BUILD_DIR/$script" ]; then
        if [ "$FORCE_BUILD" -eq 0 ] && is_built "$script"; then
            printf "\033[33m[SKIP]\033[0m %s already built.\n" "$script"
            continue
        fi
        bash "$BUILD_DIR/$script"
    else
        printf "\033[33m[WARN]\033[0m Script $script not found in $BUILD_DIR. Skipping...\n"
    fi
done

printf "\n\033[1;32m[SUCCESS] All libraries built and exported to lib/.\033[0m\n"
