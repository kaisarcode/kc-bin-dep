#!/bin/bash
# bin/zlib.sh - zlib Library Builder
# Summary: Compiles zlib and exports to internal lib/ tree.
# Standard: KCS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_ROOT="$(dirname "$SCRIPT_DIR")"
ZLIB_VER="1.3.1"

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
    [ -d "zlib" ] || (curl -L -o zlib.tar.gz "https://github.com/madler/zlib/releases/download/v${ZLIB_VER}/zlib-${ZLIB_VER}.tar.gz" && tar -xf zlib.tar.gz && mv "zlib-${ZLIB_VER}" "zlib" && rm zlib.tar.gz)
}

fetch

for arch in x86_64 win64 aarch64 arm64-v8a; do
    jobs="$(nproc)"
    prefix="/tmp/zlib-$arch"
    rm -rf "$prefix" && mkdir -p "$prefix"
    unset AR CC CPPFLAGS CFLAGS CXX CXXFLAGS LD LDFLAGS LIBS NM OBJCOPY PKG_CONFIG PKG_CONFIG_LIBDIR PKG_CONFIG_PATH RANLIB STRIP

    case "$arch" in
        "win64") 
            cross="x86_64-w64-mingw32-"
            cd "$DEPS_ROOT/src/zlib"
            make clean >/dev/null 2>&1 || true
            make -f win32/Makefile.gcc PREFIX="$cross" DESTDIR="$prefix/" INCLUDE_PATH=include LIBRARY_PATH=lib BINARY_PATH=bin install
            perl -0pi -e "s|prefix=/usr/local|prefix=$prefix|g; s|exec_prefix=/usr/local|exec_prefix=$prefix|g; s|libdir=lib|libdir=$prefix/lib|g; s|sharedlibdir=lib|sharedlibdir=$prefix/lib|g; s|includedir=include|includedir=$prefix/include|g" \
                "$prefix/lib/pkgconfig/zlib.pc"
            ;;
        "aarch64") 
            cross="aarch64-linux-gnu-"
            cd "$DEPS_ROOT/src/zlib"
            make clean >/dev/null 2>&1 || true
            CHOST="${cross%-}" CFLAGS="-O3 -fPIC" ./configure --prefix="$prefix" --static
            make -j"$jobs" install
            ;;
        "arm64-v8a") 
            cross="aarch64-linux-android-"
            ndk_root="$(resolve_ndk_root)/toolchains/llvm/prebuilt/linux-x86_64"
            ndk_sysroot="$ndk_root/sysroot"
            cd "$DEPS_ROOT/src/zlib"
            make clean >/dev/null 2>&1 || true
            export CC="$ndk_root/bin/aarch64-linux-android24-clang"
            CHOST="${cross%-}" CFLAGS="-O3 -fPIC --sysroot=$ndk_sysroot" ./configure --prefix="$prefix" --static
            make -j"$jobs" install
            ;;
        *) 
            cd "$DEPS_ROOT/src/zlib"
            make clean >/dev/null 2>&1 || true
            CFLAGS="-O3 -fPIC" ./configure --prefix="$prefix" --static
            make -j"$jobs" install
            ;;
    esac
    
    # Export
    mkdir -p "$DEPS_ROOT/lib/inc/zlib"
    rm -rf "$DEPS_ROOT/lib/obj/zlib/$arch"
    mkdir -p "$DEPS_ROOT/lib/obj/zlib/$arch"
    
    if [ -d "$prefix/include" ]; then
        cp -r "$prefix/include/"* "$DEPS_ROOT/lib/inc/zlib/"
    fi
    if [ -d "$prefix/lib" ]; then
        find "$prefix/lib" -maxdepth 1 \( -type f -o -type l \) \( -name "*.so*" -o -name "*.dll*" -o -name "*.a" \) -exec cp -d {} "$DEPS_ROOT/lib/obj/zlib/$arch/" \;
        if [ -d "$prefix/lib/pkgconfig" ]; then
            mkdir -p "$DEPS_ROOT/lib/obj/zlib/$arch/pkgconfig"
            cp -r "$prefix/lib/pkgconfig/"* "$DEPS_ROOT/lib/obj/zlib/$arch/pkgconfig/"
        fi
    fi
    if [ -d "$prefix/bin" ]; then
        find "$prefix/bin" -maxdepth 1 \( -type f -o -type l \) -exec cp -d {} "$DEPS_ROOT/lib/obj/zlib/$arch/" \;
    fi
    
    rm -rf "$prefix"
    printf "\033[32m[OK]\033[0m zlib (%s) complete.\n" "$arch"
done
