#!/bin/bash
# bin/libpng.sh - libpng Library Builder
# Summary: Compiles libpng and exports to internal lib/ tree.
# Standard: KCS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_ROOT="$(dirname "$SCRIPT_DIR")"
PNG_VER="1.6.43"

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
    [ -d "libpng" ] || (curl -L -o libpng.tar.gz "https://download.sourceforge.net/libpng/libpng-${PNG_VER}.tar.gz" && tar -xf libpng.tar.gz && mv "libpng-${PNG_VER}" "libpng" && rm libpng.tar.gz)
}

fetch

for arch in x86_64 win64 aarch64 arm64-v8a; do
    jobs="$(nproc)"
    prefix="/tmp/libpng-$arch"
    rm -rf "$prefix" && mkdir -p "$prefix"
    unset AR CC CPPFLAGS CFLAGS CXX CXXFLAGS LD LDFLAGS LIBS NM OBJCOPY PKG_CONFIG PKG_CONFIG_LIBDIR PKG_CONFIG_PATH RANLIB STRIP

    # Note: needs zlib
    zlib_prefix="/usr/local/lib/kaisarcode/obj/zlib/$arch"
    if [ ! -d "$zlib_prefix" ]; then
        # Try local build directory if global not installed
        zlib_prefix="$DEPS_ROOT/lib/obj/zlib/$arch"
    fi
    zlib_inc="/usr/local/lib/kaisarcode/inc/zlib"
    if [ ! -d "$zlib_inc" ]; then
        zlib_inc="$DEPS_ROOT/lib/inc/zlib"
    fi

    case "$arch" in
        "win64") 
            host="--host=x86_64-w64-mingw32"
            export CC="x86_64-w64-mingw32-gcc"
            ;;
        "aarch64") 
            host="--host=aarch64-linux-gnu"
            export CC="aarch64-linux-gnu-gcc"
            ;;
        "arm64-v8a") 
            host="--host=aarch64-linux-android"
            ndk_root="$(resolve_ndk_root)/toolchains/llvm/prebuilt/linux-x86_64"
            ndk_sysroot="$ndk_root/sysroot"
            export CC="$ndk_root/bin/aarch64-linux-android24-clang"
            export LDFLAGS="--sysroot=$ndk_sysroot -L$zlib_prefix"
            export CPPFLAGS="--sysroot=$ndk_sysroot -I$zlib_inc"
            export CFLAGS="-O3 -fPIC --sysroot=$ndk_sysroot"
            ;;
        *) 
            host=""
            export CC="gcc"
            ;;
    esac
    
    cd "$DEPS_ROOT/src/libpng"
    make distclean >/dev/null 2>&1 || true
    
    if [ "$arch" != "arm64-v8a" ]; then
        export LDFLAGS="-L$zlib_prefix"
        export CPPFLAGS="-I$zlib_inc"
        export CFLAGS="-O3 -fPIC"
    fi
    
    ./configure $host --prefix="$prefix" --enable-static --disable-shared \
        --with-zlib-prefix="$zlib_prefix"
        
    make -j"$jobs" install
    
    # Export
    mkdir -p "$DEPS_ROOT/lib/inc/libpng"
    rm -rf "$DEPS_ROOT/lib/obj/libpng/$arch"
    mkdir -p "$DEPS_ROOT/lib/obj/libpng/$arch"
    
    if [ -d "$prefix/include" ]; then
        cp -r "$prefix/include/"* "$DEPS_ROOT/lib/inc/libpng/"
    fi
    if [ -d "$prefix/lib" ]; then
        find "$prefix/lib" -maxdepth 1 \( -type f -o -type l \) \( -name "*.so*" -o -name "*.dll*" -o -name "*.a" \) -exec cp -d {} "$DEPS_ROOT/lib/obj/libpng/$arch/" \;
        if [ -d "$prefix/lib/pkgconfig" ]; then
            mkdir -p "$DEPS_ROOT/lib/obj/libpng/$arch/pkgconfig"
            cp -r "$prefix/lib/pkgconfig/"* "$DEPS_ROOT/lib/obj/libpng/$arch/pkgconfig/"
        fi
    fi
    if [ -d "$prefix/bin" ]; then
        find "$prefix/bin" -maxdepth 1 \( -type f -o -type l \) -exec cp -d {} "$DEPS_ROOT/lib/obj/libpng/$arch/" \;
    fi
    
    rm -rf "$prefix"
    printf "\033[32m[OK]\033[0m libpng (%s) complete.\n" "$arch"
done
