#!/bin/bash
# dev/build/pcre2.sh - PCRE2 Shared Library Builder
# Summary: Downloads and compiles PCRE2 10.47 for supported architectures.
# Standard: KCS
#
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU GPL v3.0
#
# © 2026 KaisarCode

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_ROOT="$(dirname "$SCRIPT_DIR")"
PCRE2_VER="10.47"
PCRE2_TAG="pcre2-${PCRE2_VER}"
PCRE2_URL="https://github.com/PCRE2Project/pcre2/archive/refs/tags/${PCRE2_TAG}.tar.gz"

resolve_ndk_root() {
    if [ -n "${KC_NDK_ROOT:-}" ]; then
        printf "%s\n" "$KC_NDK_ROOT"
        return 0
    fi
    if [ -n "${KC_TOOLCHAINS:-}" ]; then
        printf "%s/ndk/android-ndk-r27c\n" "$KC_TOOLCHAINS"
        return 0
    fi
    printf "/usr/local/share/kaisarcode/toolchains/ndk/android-ndk-r27c\n"
}

fetch() {
    mkdir -p "$DEPS_ROOT/src"
    cd "$DEPS_ROOT/src"
    if [ ! -d "pcre2" ]; then
        curl -L "$PCRE2_URL" -o "${PCRE2_TAG}.tar.gz"
        tar -xf "${PCRE2_TAG}.tar.gz"
        mv "pcre2-${PCRE2_TAG}" pcre2
        rm "${PCRE2_TAG}.tar.gz"
    fi
}

build_arch() {
    arch="$1"
    src_dir="$DEPS_ROOT/src/pcre2"
    build_dir="$src_dir/build-$arch"
    tmp_install="/tmp/pcre2-$arch"
    common_flags="-DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DPCRE2_BUILD_PCRE2_8=ON \
        -DPCRE2_BUILD_PCRE2_16=OFF \
        -DPCRE2_BUILD_PCRE2_32=OFF \
        -DPCRE2_BUILD_PCRE2GREP=OFF \
        -DPCRE2_BUILD_TESTS=OFF \
        -DPCRE2_SUPPORT_JIT=OFF \
        -DPCRE2_SUPPORT_LIBBZ2=OFF \
        -DPCRE2_SUPPORT_LIBZ=OFF \
        -DPCRE2_SUPPORT_LIBEDIT=OFF \
        -DPCRE2_SUPPORT_LIBREADLINE=OFF \
        -DCMAKE_INSTALL_PREFIX=$tmp_install \
        -DCMAKE_INSTALL_LIBDIR=lib"

    printf "\n\033[1;34m[BUILD] PCRE2 (%s)\033[0m\n" "$arch"
    rm -rf "$build_dir"

    case "$arch" in
        "x86_64")
            cmake -S "$src_dir" -B "$build_dir" $common_flags
            ;;
        "win64")
            cmake -S "$src_dir" -B "$build_dir" \
                -DCMAKE_SYSTEM_NAME=Windows \
                -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
                -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
                -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres \
                -DCMAKE_C_FLAGS="-D_WIN32_WINNT=0x0601" \
                -DCMAKE_CXX_FLAGS="-D_WIN32_WINNT=0x0601" \
                $common_flags
            ;;
        "aarch64")
            cmake -S "$src_dir" -B "$build_dir" \
                -DCMAKE_SYSTEM_NAME=Linux \
                -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
                -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
                -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
                $common_flags
            ;;
        "arm64-v8a")
            ndk_root="$(resolve_ndk_root)"
            cmake -S "$src_dir" -B "$build_dir" \
                -DCMAKE_TOOLCHAIN_FILE="$ndk_root/build/cmake/android.toolchain.cmake" \
                -DANDROID_ABI=arm64-v8a \
                -DANDROID_PLATFORM=android-24 \
                -DPCRE2_SYMVERS=OFF \
                $common_flags
            ;;
        *)
            printf "\033[31m[ERROR]\033[0m Unsupported architecture: %s\n" "$arch"
            exit 1
            ;;
    esac

    cmake --build "$build_dir" --config Release -j"$(nproc)"
    rm -rf "$tmp_install"
    cmake --install "$build_dir"
    
    mkdir -p "$DEPS_ROOT/lib/inc/pcre2"
    mkdir -p "$DEPS_ROOT/lib/obj/pcre2/$arch"
    
    cp -r "$tmp_install/include/"* "$DEPS_ROOT/lib/inc/pcre2/"
    if [ -d "$tmp_install/lib" ]; then
        find "$tmp_install/lib" \( -type f -o -type l \) \( -name "*.so*" -o -name "*.dll*" \) -exec cp -d {} "$DEPS_ROOT/lib/obj/pcre2/$arch/" \;
    fi
    if [ -d "$tmp_install/lib64" ]; then
        find "$tmp_install/lib64" \( -type f -o -type l \) \( -name "*.so*" -o -name "*.dll*" \) -exec cp -d {} "$DEPS_ROOT/lib/obj/pcre2/$arch/" \;
    fi
    if [ "$arch" = "win64" ]; then
        find "$build_dir" -maxdepth 1 \( -type f -o -type l \) \
            \( -name "libpcre2*.dll*" -o -name "libpcre2*.a" \) \
            -exec cp -d {} "$DEPS_ROOT/lib/obj/pcre2/$arch/" \;
    fi
    
    rm -rf "$tmp_install"
    printf "\033[32m[OK]\033[0m pcre2 built for %s\n" "$arch"
}

run_build() {
    fetch
    if [ -n "$1" ]; then
        build_arch "$1"
        return 0
    fi
    build_arch "x86_64"
    build_arch "win64"
    build_arch "aarch64"
    build_arch "arm64-v8a"
}

run_build "$1"
