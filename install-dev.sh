#!/bin/bash
# install-dev.sh - Global development environment installer for deps.
# Summary: Installs compiled shared dependencies and build toolchains once.
#
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU GPL v3.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$SCRIPT_DIR/lib"
SYS_LIB_ROOT="/usr/local/lib/kaisarcode"
SYS_TOOLCHAINS_ROOT="/usr/local/share/kaisarcode/toolchains"
NDK_VER="android-ndk-r27c"
NDK_ZIP="android-ndk-r27c-linux.zip"
NDK_URL="https://dl.google.com/android/repository/${NDK_ZIP}"
RUST_VER="1.67.1"
RUSTUP_INIT_URL="https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
IM_VER="6.9.13-16"
ZLIB_VER="1.3.1"
PNG_VER="1.6.43"
RESVG_VER="0.45.1"

# Print a success message in green.
# @param $1 Message to display.
# @return 0
pass() {
    printf "\033[32m[PASS]\033[0m %s\n" "$1"
}

# Print a failure message in red and terminate the script.
# @param $1 Failure message to display.
# @return Does not return; exits with status 1.
fail() {
    printf "\033[31m[FAIL]\033[0m %s\n" "$1"
    exit 1
}

# Ensure sudo is available on the host.
# @return 0 if sudo exists.
# @exit 1 if sudo is not available.
require_sudo() {
    if ! command -v sudo >/dev/null 2>&1; then
        fail "sudo is required."
    fi
}

refresh_arch_index() {
    local arch="$1"
    local arch_dir="$SYS_LIB_ROOT/$arch"
    sudo mkdir -p "$arch_dir"
    sudo find "$arch_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    
    # Search in obj/<dep>/<arch>
    for obj_root in "$SYS_LIB_ROOT/obj"/*; do
        [ -d "$obj_root/$arch" ] || continue
        find "$obj_root/$arch" -maxdepth 1 \( -type f -o -type l \) \( -name "*.so" -o -name "*.so.*" \) | while read -r lib_path; do
            sudo ln -sfn "$lib_path" "$arch_dir/$(basename "$lib_path")"
        done
    done
}

register_loader_paths() {
    local tmp_file
    for arch in x86_64 aarch64 arm64-v8a; do
        tmp_file=$(mktemp)
        # Register each obj/<dep>/<arch>
        for obj_root in "$SYS_LIB_ROOT/obj"/*; do
            [ -d "$obj_root/$arch" ] || continue
            printf "%s\n" "$obj_root/$arch" >>"$tmp_file"
        done
        sudo install -m 0644 "$tmp_file" "/etc/ld.so.conf.d/kc-${arch}.conf"
        rm -f "$tmp_file"
        refresh_arch_index "$arch"
    done
    sudo ldconfig
}

# Resolve LFS pointers in a directory using parallel downloads.
# @param $1 Directory path to scan.
# @param $2 Library base path (for relative URL calculation).
# @return 0 on success.
resolve_lfs() {
    local src_dir="$1"
    local base_path="$2"
    local pointers
    pointers=$(sudo grep -rl '^version https://git-lfs.github.com/spec/v1' "$src_dir" 2>/dev/null || true)
    if [ -z "$pointers" ]; then return 0; fi
    printf "Resolving LFS pointers...\n"
    echo "$pointers" | xargs -r -P 8 -I {} bash -c '
        file="$1"
        base="$2"
        rel="${file#$base/}"
        url="https://media.githubusercontent.com/media/kaisarcode/kc-bin-dep/slave/lib/${rel}"
        printf "  -> %s\n" "$rel"
        if sudo wget --timeout=15 --tries=3 -qO "$file.tmp" "$url"; then
            sudo mv "$file.tmp" "$file"
        else
            printf "  [WARN] Download failed for %s\n" "$rel"
            sudo rm -f "$file" "$file.tmp"
        fi
    ' -- {} "$base_path" || true
}

# Install compiled dependency artifacts into the global system library root.
# @return 0 on success.
# @exit 1 on failure.
install_compiled_libs() {
    require_sudo
    sudo mkdir -p "$SYS_LIB_ROOT/inc" "$SYS_LIB_ROOT/obj"
    
    # Install inc/
    if [ -d "$LIB_ROOT/inc" ]; then
        sudo rsync -a --delete "$LIB_ROOT/inc"/ "$SYS_LIB_ROOT/inc"/
    fi
    
    # Install obj/
    if [ -d "$LIB_ROOT/obj" ]; then
        sudo rsync -a --delete "$LIB_ROOT/obj"/ "$SYS_LIB_ROOT/obj"/
        resolve_lfs "$SYS_LIB_ROOT/obj" "$SYS_LIB_ROOT"
    fi
    pass "Installed compiled artifacts to $SYS_LIB_ROOT."
}

# Install exported development headers for vendored libraries.
# @return 0 on success.
# @exit 1 on failure.
install_dev_headers() {
    require_sudo
    # Note: This function was previously duplicating headers from src/ to multiple arch dirs.
    # Now that we have a consolidated inc/ structure, we ensure the latest headers from src/
    # are in the global inc/ directory.
    if [ -d "$SCRIPT_DIR/src/llama.cpp/include" ]; then
        local g_inc="$SYS_LIB_ROOT/inc/ggml"
        local l_inc="$SYS_LIB_ROOT/inc/llama.cpp"
        sudo mkdir -p "$g_inc" "$l_inc"
        sudo rsync -a "$SCRIPT_DIR/src/llama.cpp/include/" "$l_inc/"
        if [ -f "$SCRIPT_DIR/src/llama.cpp/tools/mtmd/mtmd.h" ]; then
            sudo install -m 0644 "$SCRIPT_DIR/src/llama.cpp/tools/mtmd/mtmd.h" "$l_inc/mtmd.h"
        fi
        if [ -f "$SCRIPT_DIR/src/llama.cpp/tools/mtmd/mtmd-helper.h" ]; then
            sudo install -m 0644 "$SCRIPT_DIR/src/llama.cpp/tools/mtmd/mtmd-helper.h" "$l_inc/mtmd-helper.h"
        fi
        sudo rsync -a "$SCRIPT_DIR/src/llama.cpp/ggml/include/" "$g_inc/"
        pass "Installed development headers for llama.cpp and ggml."
    fi
    if [ -d "$SCRIPT_DIR/src/stable-diffusion.cpp/include" ]; then
        local sd_inc="$SYS_LIB_ROOT/inc/stable-diffusion.cpp"
        sudo mkdir -p "$sd_inc"
        sudo rsync -a "$SCRIPT_DIR/src/stable-diffusion.cpp/include/" "$sd_inc/"
        pass "Installed development headers for stable-diffusion.cpp."
    fi
}

# Fetch and verify local upstream source trees under src/.
# @return 0 on success.
# @exit 1 on download or extraction failure.
install_sources() {
    src_root="$SCRIPT_DIR/src"
    mkdir -p "$src_root"
    cd "$src_root"

    [ -d "llama.cpp" ] || git clone --recursive https://github.com/ggml-org/llama.cpp.git llama.cpp
    [ -d "stable-diffusion.cpp" ] || git clone --recursive https://github.com/leejet/stable-diffusion.cpp.git stable-diffusion.cpp

    if [ ! -d "ImageMagick" ]; then
        curl -L -o im.tar.gz "https://github.com/ImageMagick/ImageMagick6/archive/refs/tags/${IM_VER}.tar.gz"
        tar -xf im.tar.gz
        mv "ImageMagick6-${IM_VER}" "ImageMagick"
        rm im.tar.gz
    fi

    if [ ! -d "zlib" ]; then
        curl -L -o zlib.tar.gz "https://github.com/madler/zlib/releases/download/v${ZLIB_VER}/zlib-${ZLIB_VER}.tar.gz"
        tar -xf zlib.tar.gz
        mv "zlib-${ZLIB_VER}" "zlib"
        rm zlib.tar.gz
    fi

    if [ ! -d "libpng" ]; then
        curl -L -o libpng.tar.gz "https://download.sourceforge.net/libpng/libpng-${PNG_VER}.tar.gz"
        tar -xf libpng.tar.gz
        mv "libpng-${PNG_VER}" "libpng"
        rm libpng.tar.gz
    fi

    if [ ! -d "resvg" ]; then
        curl -L -o "resvg-${RESVG_VER}.tar.gz" "https://github.com/linebender/resvg/archive/refs/tags/v${RESVG_VER}.tar.gz"
        tar -xf "resvg-${RESVG_VER}.tar.gz"
        mv "resvg-${RESVG_VER}" resvg
        rm "resvg-${RESVG_VER}.tar.gz"
    fi

    pass "Source trees verified under $src_root."
}

# Install the Android NDK into the managed toolchain root.
# @return 0 on success.
# @exit 1 on download, extraction, or install failure.
install_ndk() {
    require_sudo
    ndk_root="$SYS_TOOLCHAINS_ROOT/ndk/$NDK_VER"
    if [ -x "$ndk_root/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang" ]; then
        pass "Android NDK already present."
        return 0
    fi
    tmp_dir="$(mktemp -d)"
    trap 'sudo rm -rf "$tmp_dir"' RETURN
    mkdir -p "$tmp_dir"
    sudo mkdir -p "$SYS_TOOLCHAINS_ROOT/ndk"
    curl -L "$NDK_URL" -o "$tmp_dir/$NDK_ZIP"
    unzip -q "$tmp_dir/$NDK_ZIP" -d "$tmp_dir"
    sudo rm -rf "$ndk_root"
    sudo mkdir -p "$SYS_TOOLCHAINS_ROOT/ndk"
    sudo mv "$tmp_dir/$NDK_VER" "$ndk_root"
    pass "Android NDK installed to $ndk_root."
}

# Install the managed Rust toolchain under the global toolchain root.
# @return 0 on success.
# @exit 1 on download or toolchain install failure.
install_rust() {
    require_sudo
    rust_root="$SYS_TOOLCHAINS_ROOT/rust"
    sudo mkdir -p "$rust_root/bin" "$rust_root/rustup" "$rust_root/cargo"
    if [ ! -x "$rust_root/bin/rustup-init" ]; then
        sudo curl -L "$RUSTUP_INIT_URL" -o "$rust_root/bin/rustup-init"
        sudo chmod +x "$rust_root/bin/rustup-init"
    fi
    export RUSTUP_HOME="$rust_root/rustup"
    export CARGO_HOME="$rust_root/cargo"
    export PATH="$CARGO_HOME/bin:$PATH"
    if [ ! -x "$CARGO_HOME/bin/cargo" ]; then
        sudo -E "$rust_root/bin/rustup-init" -y --default-toolchain "$RUST_VER" --profile minimal --no-modify-path
    fi
    sudo -E "$CARGO_HOME/bin/rustup" toolchain install "$RUST_VER" --profile minimal >/dev/null
    sudo -E "$CARGO_HOME/bin/rustup" default "$RUST_VER" >/dev/null
    sudo -E "$CARGO_HOME/bin/rustup" target add \
        x86_64-unknown-linux-gnu \
        x86_64-pc-windows-gnu \
        aarch64-unknown-linux-gnu \
        aarch64-linux-android >/dev/null
    if [ -n "$SUDO_USER" ]; then
        sudo chown -R "$SUDO_USER" "$rust_root"
    fi
    pass "Rust toolchain installed to $rust_root."
}

# Install all managed development runtime artifacts and toolchains.
# @return 0 on success.
# @exit 1 on any installation failure.
main() {
    install_compiled_libs
    register_loader_paths
    install_sources
    install_dev_headers
    install_ndk
    install_rust
    
    printf "\n\033[1;36m[BUILD] Compiling all dependencies natively...\033[0m\n"
    bash "$SCRIPT_DIR/bin/build.sh" --force

    printf "\n\033[1;32m[SUCCESS]\033[0m Development runtime, toolchains, and binaries installed.\n"
}

main "$@"
