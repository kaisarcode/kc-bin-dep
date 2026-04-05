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
PATCH_ROOT="$DEPS_ROOT/patches/stable-diffusion.cpp"

require_patchelf() {
    if ! command -v patchelf >/dev/null 2>&1; then
        printf "\033[31m[ERROR]\033[0m patchelf is required\n"
        exit 1
    fi
}

apply_git_patch() {
    local repo_dir="$1"
    local patch_path="$2"
    local patch_label="$3"

    if [ ! -f "$patch_path" ]; then
        printf "\033[31m[ERROR]\033[0m Missing patch: %s\n" "$patch_path"
        exit 1
    fi
    if git -C "$repo_dir" apply --check "$patch_path" >/dev/null 2>&1; then
        printf "\033[33m[PATCH]\033[0m Applying %s\n" "$patch_label"
        git -C "$repo_dir" apply "$patch_path"
        return 0
    fi
    if git -C "$repo_dir" apply -R --check "$patch_path" >/dev/null 2>&1; then
        printf "\033[32m[PATCH]\033[0m Already applied: %s\n" "$patch_label"
        return 0
    fi
    printf "\033[31m[ERROR]\033[0m Unable to apply patch cleanly: %s\n" "$patch_label"
    exit 1
}

sync_overlay_file() {
    local source_path="$1"
    local target_path="$2"

    mkdir -p "$(dirname "$target_path")"
    if [ -f "$target_path" ] && cmp -s "$source_path" "$target_path"; then
        printf "\033[32m[PATCH]\033[0m Already synced: %s\n" "$(basename "$target_path")"
        return 0
    fi
    printf "\033[33m[PATCH]\033[0m Syncing %s\n" "$(basename "$target_path")"
    cp "$source_path" "$target_path"
}

apply_stable_diffusion_overlays() {
    sync_overlay_file \
        "$PATCH_ROOT/files/src/backend_helper.hpp" \
        "$DEPS_ROOT/src/stable-diffusion.cpp/src/backend_helper.hpp"
    apply_git_patch \
        "$DEPS_ROOT/src/stable-diffusion.cpp" \
        "$PATCH_ROOT/0001-stable-diffusion-modular-ggml.patch" \
        "stable-diffusion.cpp modular ggml integration"
    apply_git_patch \
        "$DEPS_ROOT/src/stable-diffusion.cpp/ggml" \
        "$PATCH_ROOT/0002-ggml-shared-backends-win32-android.patch" \
        "ggml shared backends for win32/android"
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
    local sd_dst="$DEPS_ROOT/lib/inc/stable-diffusion.cpp"
    local ggml_dst="$DEPS_ROOT/lib/inc/ggml"
    mkdir -p "$sd_dst"
    mkdir -p "$ggml_dst"
    cp "$DEPS_ROOT/src/stable-diffusion.cpp/include/"*.h "$sd_dst/"
    cp "$DEPS_ROOT/src/stable-diffusion.cpp/ggml/include/"*.h "$ggml_dst/"
}

sanitize_runtime_paths() {
    local arch="$1"
    local lib_dir=""
    local lib_name=""
    local soname=""
    for lib_dir in "$DEPS_ROOT/lib/obj/stable-diffusion.cpp/$arch" "$DEPS_ROOT/lib/obj/ggml/$arch"; do
        [ -d "$lib_dir" ] || continue
        find "$lib_dir" -type f \( -name "*.so" -o -name "*.so.*" \) | while read -r lib_path; do
            lib_name="$(basename "$lib_path")"
            soname="$lib_name"
            case "$lib_name" in
                *.so.[0-9]*)
                    soname="$(printf '%s\n' "$lib_name" | sed -E 's/(\.so\.[0-9]+).*/\1/')"
                    ;;
            esac
            patchelf --set-soname "$soname" "$lib_path"
            patchelf --print-rpath "$lib_path" >/dev/null 2>&1 || continue
            patchelf --remove-rpath "$lib_path"
        done
    done
}

ensure_canonical_ggml_cpu() {
    local arch="$1"
    local ggml_dst="$DEPS_ROOT/lib/obj/ggml/$arch"
    local canonical=""
    local source_variant=""

    [ -d "$ggml_dst" ] || return 0

    case "$arch" in
        x86_64)
            canonical="$ggml_dst/libggml-cpu.so"
            source_variant="$ggml_dst/libggml-cpu-x64.so"
            if [ ! -f "$canonical" ] && [ -f "$source_variant" ]; then
                cp "$source_variant" "$canonical"
                patchelf --set-soname libggml-cpu.so "$canonical"
            fi
            ;;
    esac
}

copy_win64_runtime_dlls() {
    local dst="$1"
    local dll_path=""
    local dll_name=""
    for dll_name in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll libgomp-1.dll; do
        dll_path="$(x86_64-w64-mingw32-gcc -print-file-name="$dll_name")"
        if [ -n "$dll_path" ] && [ "$dll_path" != "$dll_name" ] && [ -f "$dll_path" ]; then
            cp -d "$dll_path" "$dst/"
        fi
    done
}

compile() {
    arch=$1
    jobs="$(nproc)"
    printf "\n\033[1;34m[BUILD] stable-diffusion.cpp (%s)\033[0m\n" "$arch"
    cd "$DEPS_ROOT/src/stable-diffusion.cpp"
    apply_stable_diffusion_overlays
    build_dir="build-$arch"

    printf "\033[33m[CLEAN]\033[0m Wiping build directory: %s\n" "$build_dir"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    common_flags=(
        -DBUILD_SHARED_LIBS=ON
        -DSD_BUILD_SHARED_LIBS=ON
        -DSD_BUILD_SHARED_GGML_LIB=ON
        -DSD_BUILD_EXAMPLES=OFF
        -DSD_BUILD_TESTS=OFF
        -DCMAKE_SKIP_RPATH=ON
        -DCMAKE_SKIP_INSTALL_RPATH=ON
        -DGGML_BACKEND_DL=ON
        -DGGML_NATIVE=OFF
    )

    case "$arch" in
        "x86_64")
            cmake -B "$build_dir" -DSD_CUDA=ON -DGGML_CPU_ALL_VARIANTS=ON "${common_flags[@]}"
            ;;
        "win64")
            printf "  Configuring for Windows (MinGW)...\n"
            cmake -B "$build_dir" -DCMAKE_SYSTEM_NAME=Windows \
                  -DCMAKE_SYSTEM_PROCESSOR=x86_64 \
                  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
                  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
                  -DCMAKE_C_FLAGS="-D_WIN32_WINNT=0x0601" \
                  -DCMAKE_CXX_FLAGS="-D_WIN32_WINNT=0x0601" \
                  -DGGML_CPU_ALL_VARIANTS=OFF \
                  "${common_flags[@]}"
            ;;
        "arm64-v8a")
            ndk_root="$(resolve_ndk_root)"
            cmake -B "$build_dir" -DCMAKE_TOOLCHAIN_FILE="$ndk_root/build/cmake/android.toolchain.cmake" \
                  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DGGML_CPU_ALL_VARIANTS=OFF "${common_flags[@]}"
            ;;
        "aarch64")
            cmake -B "$build_dir" -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
                  -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
                  -DGGML_CPU_ALL_VARIANTS=OFF "${common_flags[@]}"
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
    local ggml_dst="$DEPS_ROOT/lib/obj/ggml/$arch"
    rm -rf "$obj_dst" "$ggml_dst"
    mkdir -p "$obj_dst" "$ggml_dst"

    find "$build_dir" \( -name "libggml*" -o -name "ggml*.dll*" \) -exec cp -d {} "$ggml_dst/" \;
    find "$build_dir" \( -name "libstable-diffusion*" -o -name "stable-diffusion.dll*" \) -exec cp -d {} "$obj_dst/" \;
    if [ "$arch" = "win64" ]; then
        copy_win64_runtime_dlls "$ggml_dst"
    fi
    ensure_canonical_ggml_cpu "$arch"
    sanitize_runtime_paths "$arch"
    copy_headers
}

run_build() {
    local arch_arg="${1:-}"
    require_patchelf
    if [ -z "$arch_arg" ]; then
        for a in x86_64 win64 aarch64 arm64-v8a; do
            compile "$a"
        done
    else
        compile "$arch_arg"
    fi
}

run_build "${1:-}"
