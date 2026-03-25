#!/bin/bash
# bin/sqlite3.sh - SQLite3 Library Builder
# Summary: Compiles SQLite3 amalgamation and exports to internal lib/ tree.
# Standard: KCS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_ROOT="$(dirname "$SCRIPT_DIR")"

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
    if [ ! -d "sqlite3" ]; then
        mkdir -p sqlite3
        curl -L https://www.sqlite.org/2025/sqlite-amalgamation-3490100.zip -o sqlite3.zip
        unzip -q sqlite3.zip -d sqlite3-tmp
        cp sqlite3-tmp/*/sqlite3.c sqlite3-tmp/*/sqlite3.h sqlite3/
        rm -rf sqlite3-tmp sqlite3.zip
    fi
}

fetch

for arch in x86_64 win64 aarch64 arm64-v8a; do
    printf "\n\033[1;34m[BUILD] sqlite3 (%s)\033[0m\n" "$arch"
    cd "$DEPS_ROOT/src/sqlite3"
    
    case "$arch" in
        "win64") 
            cross="x86_64-w64-mingw32-"
            CC="${cross}gcc"
            output="sqlite3.dll"
            flags="-shared"
            ;;
        "aarch64") 
            cross="aarch64-linux-gnu-"
            CC="${cross}gcc"
            output="libsqlite3.so"
            flags="-shared -fPIC"
            ;;
        "arm64-v8a") 
            ndk_root="$(resolve_ndk_root)/toolchains/llvm/prebuilt/linux-x86_64"
            CC="$ndk_root/bin/aarch64-linux-android24-clang"
            output="libsqlite3.so"
            flags="-shared -fPIC"
            ;;
        *) 
            CC="gcc"
            output="libsqlite3.so"
            flags="-shared -fPIC"
            ;;
    esac
    
    $CC $flags -O3 sqlite3.c -lpthread -ldl -o "$output"
    
    # Export
    mkdir -p "$DEPS_ROOT/lib/inc/sqlite3"
    rm -rf "$DEPS_ROOT/lib/obj/sqlite3/$arch"
    mkdir -p "$DEPS_ROOT/lib/obj/sqlite3/$arch"
    
    cp sqlite3.h "$DEPS_ROOT/lib/inc/sqlite3/"
    cp "$output" "$DEPS_ROOT/lib/obj/sqlite3/$arch/"
    
    printf "\033[32m[OK]\033[0m sqlite3 (%s) complete.\n" "$arch"
done
