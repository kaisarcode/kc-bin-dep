#!/bin/bash
# dev/build/resvg.sh - resvg Builder
# Summary: Downloads and compiles resvg for all supported architectures.
#
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU GPL v3.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_ROOT="$(dirname "$SCRIPT_DIR")"

RESVG_VER="0.45.1"
RUST_VER="1.67.1"
RUSTUP_INIT_URL="https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
RESVG_URL="https://github.com/linebender/resvg/archive/refs/tags/v${RESVG_VER}.tar.gz"

resolve_toolchains_root() {
    if [ -n "${KC_TOOLCHAINS:-}" ]; then
        printf "%s\n" "$KC_TOOLCHAINS"
        return 0
    fi
    printf "/usr/local/share/kaisarcode/toolchains\n"
}

resolve_ndk_root() {
    if [ -n "${KC_NDK_ROOT:-}" ]; then
        printf "%s\n" "$KC_NDK_ROOT"
        return 0
    fi
    printf "%s/ndk/android-ndk-r27c\n" "$(resolve_toolchains_root)"
}

setup_rust() {
    TOOLCHAINS_ROOT="$(resolve_toolchains_root)"
    RUST_ROOT="$TOOLCHAINS_ROOT/rust"
    export RUSTUP_HOME="$RUST_ROOT/rustup"
    export CARGO_HOME="$RUST_ROOT/cargo"
    export PATH="$CARGO_HOME/bin:$PATH"
    mkdir -p "$RUSTUP_HOME" "$CARGO_HOME" "$RUST_ROOT/bin"
    if [ ! -x "$RUST_ROOT/bin/rustup-init" ]; then
        curl -L "$RUSTUP_INIT_URL" -o "$RUST_ROOT/bin/rustup-init"
        chmod +x "$RUST_ROOT/bin/rustup-init"
    fi
    if [ ! -x "$CARGO_HOME/bin/cargo" ]; then
        "$RUST_ROOT/bin/rustup-init" -y --default-toolchain "$RUST_VER" --profile minimal --no-modify-path
    fi
    rustup toolchain install "$RUST_VER" --profile minimal >/dev/null
    rustup default "$RUST_VER" >/dev/null
    rustup target add x86_64-unknown-linux-gnu x86_64-pc-windows-gnu aarch64-unknown-linux-gnu aarch64-linux-android >/dev/null
}

fetch() {
    mkdir -p "$DEPS_ROOT/src"
    cd "$DEPS_ROOT/src"
    if [ ! -d "resvg" ]; then
        curl -L "$RESVG_URL" -o "resvg-${RESVG_VER}.tar.gz"
        tar -xf "resvg-${RESVG_VER}.tar.gz"
        mv "resvg-${RESVG_VER}" resvg
        rm "resvg-${RESVG_VER}.tar.gz"
    fi
}

build_arch() {
    arch="$1"
    src_dir="$DEPS_ROOT/src/resvg"
    prefix="$DEPS_ROOT/lib/obj/resvg/$arch"
    rm -rf "$prefix"
    mkdir -p "$prefix"
    unset RUSTFLAGS
    unset CARGO_BUILD_TARGET CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER \
        CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER
    case "$arch" in
        "x86_64")
            target="x86_64-unknown-linux-gnu"
            bin_name="resvg"
            out_name="resvg"
            ;;
        "win64")
            target="x86_64-pc-windows-gnu"
            export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="x86_64-w64-mingw32-gcc"
            bin_name="resvg.exe"
            out_name="resvg.exe"
            ;;
        "aarch64")
            target="aarch64-unknown-linux-gnu"
            export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="aarch64-linux-gnu-gcc"
            bin_name="resvg"
            out_name="resvg"
            ;;
        "arm64-v8a")
            toolchains_root="$(resolve_toolchains_root)"
            ndk_base="$(resolve_ndk_root)"
            ndk_root="$ndk_base/toolchains/llvm/prebuilt/linux-x86_64/bin"
            compat_dir="$toolchains_root/rust/android-compat/aarch64-linux-android"
            builtins="$ndk_base/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/18/lib/linux/libclang_rt.builtins-aarch64-android.a"
            unwind="$ndk_base/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/18/lib/linux/aarch64/libunwind.a"
            target="aarch64-linux-android"
            mkdir -p "$compat_dir"
            ln -sf "$builtins" "$compat_dir/libgcc.a"
            ln -sf "$unwind" "$compat_dir/libunwind.a"
            export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$ndk_root/aarch64-linux-android24-clang"
            export RUSTFLAGS="-L native=$compat_dir -C link-arg=-lunwind"
            bin_name="resvg"
            out_name="resvg"
            ;;
        *)
            printf "\033[31m[FAIL]\033[0m Unsupported architecture: %s\n" "$arch"
            exit 1
            ;;
    esac
    cd "$src_dir"
    cargo build --release --target "$target" -p resvg
    cp "target/$target/release/$bin_name" "$prefix/$out_name"
    chmod +x "$prefix/$out_name"
    printf "\033[32m[OK]\033[0m resvg built for %s\n" "$arch"
}

run_build() {
    setup_rust
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
