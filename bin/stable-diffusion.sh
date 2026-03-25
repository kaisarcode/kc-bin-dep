#!/bin/bash
# dev/build/stable-diffusion.sh - stable-diffusion.cpp Shared Library Builder
# Summary: Forced engine-only build using CMake target isolation.
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

require_patchelf() {
    if ! command -v patchelf >/dev/null 2>&1; then
        printf "\033[31m[ERROR]\033[0m patchelf is required\n"
        exit 1
    fi
}

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

copy_headers() {
    local dst="$DEPS_ROOT/lib/inc/stable-diffusion.cpp"
    mkdir -p "$dst"
    cp "$DEPS_ROOT/src/stable-diffusion.cpp/include/"*.h "$dst/"
}

sanitize_runtime_paths() {
    arch="$1"
    lib_dir="$DEPS_ROOT/lib/obj/stable-diffusion.cpp/$arch"
    find "$lib_dir" -type f \( -name "*.so" -o -name "*.so.*" \) | while read -r lib_path; do
        patchelf --print-rpath "$lib_path" >/dev/null 2>&1 || continue
        patchelf --remove-rpath "$lib_path"
    done
}

compile() {
    arch=$1
    jobs="$(nproc)"
    printf "\n\033[1;34m[BUILD] stable-diffusion.cpp (%s)\033[0m\n" "$arch"
    cd "$DEPS_ROOT/src/stable-diffusion.cpp"
    build_dir="build-$arch"

    printf "\033[33m[CLEAN]\033[0m Wiping build directory: %s\n" "$build_dir"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    common_flags=(
        -DSD_BUILD_SHARED_LIBS=ON
        -DSD_BUILD_EXAMPLES=OFF
        -DSD_BUILD_TESTS=OFF
        -DCMAKE_SKIP_RPATH=ON
        -DCMAKE_SKIP_INSTALL_RPATH=ON
    )

    case "$arch" in
        "x86_64")
            cmake -B "$build_dir" -DSD_CUDA=ON "${common_flags[@]}"
            ;;
        "win64")
            printf "  Configuring for Windows (MinGW)...\n"
            cmake -B "$build_dir" -DCMAKE_SYSTEM_NAME=Windows \
                  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
                  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
                  -DCMAKE_C_FLAGS="-D_WIN32_WINNT=0x0601" \
                  -DCMAKE_CXX_FLAGS="-D_WIN32_WINNT=0x0601" \
                  "${common_flags[@]}"
            ;;
        "arm64-v8a")
            ndk_root="$(resolve_ndk_root)"
            cmake -B "$build_dir" -DCMAKE_TOOLCHAIN_FILE="$ndk_root/build/cmake/android.toolchain.cmake" \
                  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 "${common_flags[@]}"
            ;;
        "aarch64")
            cmake -B "$build_dir" -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
                  -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
                  "${common_flags[@]}"
            ;;
        *)
            printf "\033[31m[ERROR]\033[0m Unsupported architecture: %s\n" "$arch"
            exit 1
            ;;
    esac

    printf "  Starting targeted build (Target: stable-diffusion)...\n"
    cmake --build "$build_dir" --config Release --target stable-diffusion --verbose -j"$jobs"

    printf "  Exporting artifacts to global lib/obj/...\n"
    local obj_dst="$DEPS_ROOT/lib/obj/stable-diffusion.cpp/$arch"
    rm -rf "$obj_dst"
    mkdir -p "$obj_dst"

    find "$build_dir" \( -name "*.so*" -o -name "*.dll*" -o -name "*.dll.a" \) -exec cp -d {} "$obj_dst/" \;
    sanitize_runtime_paths "$arch"
    copy_headers
}

run_build() {
    require_patchelf
    if [ -z "$1" ]; then
        for a in x86_64 win64 aarch64 arm64-v8a; do
            compile "$a"
        done
    else
        compile "$1"
    fi
}

run_build "$1"
