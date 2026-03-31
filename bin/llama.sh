#!/bin/bash
# dev/build/llama.sh - llama.cpp Library Sniper Builder
# Summary: Forced engine-only build using CMake target isolation.
# Standard: KCS

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
    local l_dst="$DEPS_ROOT/lib/inc/llama.cpp"
    local g_dst="$DEPS_ROOT/lib/inc/ggml"
    mkdir -p "$l_dst"
    mkdir -p "$g_dst"
    cp "$DEPS_ROOT/src/llama.cpp/include/"*.h "$l_dst/"
    cp "$DEPS_ROOT/src/llama.cpp/tools/mtmd/mtmd.h" "$l_dst/"
    cp "$DEPS_ROOT/src/llama.cpp/ggml/include/"*.h "$g_dst/"
}

sanitize_runtime_paths() {
    local arch="$1"
    for lib_dir in "$DEPS_ROOT/lib/obj/llama.cpp/$arch" "$DEPS_ROOT/lib/obj/ggml/$arch"; do
        [ -d "$lib_dir" ] || continue
        find "$lib_dir" -type f \( -name "*.so" -o -name "*.so.*" \) | while read -r lib_path; do
            patchelf --print-rpath "$lib_path" >/dev/null 2>&1 || continue
            patchelf --remove-rpath "$lib_path"
        done
    done
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
    printf "\n\033[1;34m[BUILD] llama.cpp (%s)\033[0m\n" "$arch"
    cd "$DEPS_ROOT/src/llama.cpp"
    build_dir="build-$arch"

    printf "\033[33m[CLEAN]\033[0m Wiping build directory: %s\n" "$build_dir"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    common_flags=(
        -DBUILD_SHARED_LIBS=ON
        -DLLAMA_BUILD_EXAMPLES=OFF
        -DLLAMA_BUILD_SERVER=OFF
        -DLLAMA_BUILD_TESTS=OFF
        -DLLAMA_SERVER=OFF
        -DGGML_BUILD_EXAMPLES=OFF
        -DGGML_BUILD_TESTS=OFF
        -DCMAKE_SKIP_RPATH=ON
        -DCMAKE_SKIP_INSTALL_RPATH=ON
    )

    case "$arch" in
        "win64")
            printf "  Configuring for Windows (MinGW)...\n"
            cmake -B "$build_dir" -DCMAKE_SYSTEM_NAME=Windows \
                  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
                  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
                  -DCMAKE_C_FLAGS="-D_WIN32_WINNT=0x0601" \
                  -DCMAKE_CXX_FLAGS="-D_WIN32_WINNT=0x0601" \
                  "${common_flags[@]}"
            ;;
        "x86_64")
            cmake -B "$build_dir" -DGGML_CUDA=ON "${common_flags[@]}"
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

    printf "  Starting targeted build (Targets: llama, mtmd)...\n"
    cmake --build "$build_dir" --config Release --target llama --verbose -j"$jobs"
    cmake --build "$build_dir" --config Release --target mtmd --verbose -j"$jobs"

    printf "  Exporting artifacts to global lib/obj/...\n"
    local obj_dst="$DEPS_ROOT/lib/obj/llama.cpp/$arch"
    local ggml_dst="$DEPS_ROOT/lib/obj/ggml/$arch"
    rm -rf "$obj_dst" "$ggml_dst"
    mkdir -p "$obj_dst" "$ggml_dst"

    # Separate GGML from Llama binaries.
    # Windows emits ggml*.dll without the "lib" prefix, so include both
    # naming forms when exporting the runtime set.
    find "$build_dir" \( -name "libggml*" -o -name "ggml*.dll*" \) -exec cp -d {} "$ggml_dst/" \;
    find "$build_dir" \( -name "libllama*" -o -name "llama.dll*" -o -name "libmtmd*" -o -name "mtmd.dll*" \) -exec cp -d {} "$obj_dst/" \;
    if [ "$arch" = "win64" ]; then
        copy_win64_runtime_dlls "$ggml_dst"
    fi
    
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
