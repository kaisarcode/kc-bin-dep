#!/bin/bash
# dev/build/imagemagick.sh - ImageMagick Shared Library Builder
# Summary: Compiles MagickWand with vendored dependencies for full autonomy.
# Standard: KCS
#
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU GPL v3.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_ROOT="$(dirname "$SCRIPT_DIR")"

# Versions
IM_VER="6.9.13-16"
ZLIB_VER="1.3.1"
PNG_VER="1.6.43"

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

normalize_prefixes() {
    local arch="$1"
    local tmp_prefix="$2"
    local system_prefix="/usr/local/lib/kaisarcode/obj/imagemagick/$arch"
    local system_inc="/usr/local/lib/kaisarcode/inc/imagemagick"
    local ndk_root="$(resolve_ndk_root)"

    find "$tmp_prefix" -type f \
        \( -name "*.pc" -o -name "*-config" -o -name "*.xml" -o -name "*.h" -o -name "*.la" \) \
        -exec perl -0pi \
            -e 's{\Q'"$tmp_prefix"'/include\E}{'"$system_inc"'}g; s{\Q'"$tmp_prefix"'\E}{'"$system_prefix"'}g; s{(?:/[^"'"'"'\\s]+)+/src/toolchains/ndk/android-ndk-r27c}{'"$ndk_root"'}g' \
            {} +
}

sanitize_runtime_paths() {
    local binary_dir="$1"
    find "$binary_dir" -type f \( -name "*.so" -o -name "*.so.*" -o -perm -111 \) | while read -r binary_path; do
        patchelf --print-rpath "$binary_path" >/dev/null 2>&1 || continue
        patchelf --remove-rpath "$binary_path"
    done
}

# @brief Downloads source if not present.
fetch() {
    mkdir -p "$DEPS_ROOT/src"
    cd "$DEPS_ROOT/src"
    [ -d "ImageMagick" ] || (curl -L -o im.tar.gz "https://github.com/ImageMagick/ImageMagick6/archive/refs/tags/${IM_VER}.tar.gz" && tar -xf im.tar.gz && mv "ImageMagick6-${IM_VER}" "ImageMagick" && rm im.tar.gz)
    [ -d "zlib" ] || (curl -L -o zlib.tar.gz "https://github.com/madler/zlib/releases/download/v${ZLIB_VER}/zlib-${ZLIB_VER}.tar.gz" && tar -xf zlib.tar.gz && mv "zlib-${ZLIB_VER}" "zlib" && rm zlib.tar.gz)
    [ -d "libpng" ] || (curl -L -o libpng.tar.gz "https://download.sourceforge.net/libpng/libpng-${PNG_VER}.tar.gz" && tar -xf libpng.tar.gz && mv "libpng-${PNG_VER}" "libpng" && rm libpng.tar.gz)
}

install_win64_imagemagick() {
    src_root="$DEPS_ROOT/src/ImageMagick"
    mkdir -p "$prefix/bin" "$prefix/include/ImageMagick-6/magick" \
        "$prefix/include/ImageMagick-6/wand" "$prefix/lib" \
        "$prefix/lib/ImageMagick-6.9.13/config-Q16" "$prefix/lib/pkgconfig"
    cp "$src_root"/magick/*.h "$prefix/include/ImageMagick-6/magick/"
    cp "$src_root"/wand/*.h "$prefix/include/ImageMagick-6/wand/"
    cp "$src_root"/magick/Magick-config "$src_root"/magick/MagickCore-config \
        "$src_root"/wand/Wand-config "$src_root"/wand/MagickWand-config \
        "$prefix/bin/"
    cp "$src_root"/magick/ImageMagick.pc "$src_root"/magick/ImageMagick-6.Q16.pc \
        "$src_root"/magick/MagickCore.pc "$src_root"/magick/MagickCore-6.Q16.pc \
        "$src_root"/wand/MagickWand.pc "$src_root"/wand/Wand.pc \
        "$src_root"/wand/MagickWand-6.Q16.pc "$src_root"/wand/Wand-6.Q16.pc \
        "$prefix/lib/pkgconfig/"
    cp "$src_root"/config/configure.xml "$prefix/lib/ImageMagick-6.9.13/config-Q16/"
    cp "$src_root"/magick/.libs/libMagickCore-6.Q16.a "$prefix/lib/"
    cp "$src_root"/wand/.libs/libMagickWand-6.Q16.a "$prefix/lib/"
}

fetch
require_patchelf

for arch in x86_64 win64 aarch64 arm64-v8a; do
    jobs="$(nproc)"
    tmp_prefix="/tmp/imagemagick-$arch"
    prefix="$tmp_prefix"
    rm -rf "$tmp_prefix" && mkdir -p "$tmp_prefix"
    unset AR CC CPPFLAGS CFLAGS CXX CXXFLAGS LD LDFLAGS LIBS NM OBJCOPY PKG_CONFIG PKG_CONFIG_LIBDIR PKG_CONFIG_PATH RANLIB STRIP

    case "$arch" in
        "win64") 
            host="--host=x86_64-w64-mingw32"
            cross="x86_64-w64-mingw32-"
            export CC="${cross}gcc"
            sys_libs="-lws2_32 -ladvapi32 -lurlmon -lpthread"
            ;;
        "aarch64") 
            host="--host=aarch64-linux-gnu"
            cross="aarch64-linux-gnu-"
            export CC="${cross}gcc"
            sys_libs="-lpthread -lm"
            ;;
        "arm64-v8a") 
            host="--host=aarch64-linux-android"
            cross="aarch64-linux-android-"
            ndk_root="$(resolve_ndk_root)/toolchains/llvm/prebuilt/linux-x86_64"
            ndk_sysroot="$ndk_root/sysroot"
            export CC="$ndk_root/bin/aarch64-linux-android24-clang"
            export CXX="$ndk_root/bin/aarch64-linux-android24-clang++"
            export AR="$ndk_root/bin/llvm-ar"
            export RANLIB="$ndk_root/bin/llvm-ranlib"
            export STRIP="$ndk_root/bin/llvm-strip"
            export LD="$ndk_root/bin/ld.lld"
            export NM="$ndk_root/bin/llvm-nm"
            export OBJCOPY="$ndk_root/bin/llvm-objcopy"
            sys_libs="-lm -ldl"
            ;;
        *) 
            host=""
            cross=""
            export CC="gcc"
            sys_libs="-lpthread -lm"
            ;;
    esac
    
    # Build zlib (Static + fPIC)
    cd "$DEPS_ROOT/src/zlib"
    make clean >/dev/null 2>&1 || true
    if [ "$arch" = "win64" ]; then
        make -f win32/Makefile.gcc PREFIX="$cross" DESTDIR="$prefix/" INCLUDE_PATH=include LIBRARY_PATH=lib BINARY_PATH=bin install
        perl -0pi -e "s|prefix=/usr/local|prefix=$prefix|g; s|exec_prefix=/usr/local|exec_prefix=$prefix|g; s|libdir=lib|libdir=$prefix/lib|g; s|sharedlibdir=lib|sharedlibdir=$prefix/lib|g; s|includedir=include|includedir=$prefix/include|g" \
            "$prefix/lib/pkgconfig/zlib.pc"
    else
        if [ "$arch" = "arm64-v8a" ]; then
            CHOST="${cross%-}" CFLAGS="-O3 -fPIC --sysroot=$ndk_sysroot" ./configure --prefix="$prefix" --static
        else
            CHOST="${cross%-}" CFLAGS="-O3 -fPIC" ./configure --prefix="$prefix" --static
        fi
        make -j"$jobs" install
    fi

    # Build libpng (Static + fPIC)
    cd "$DEPS_ROOT/src/libpng"
    make distclean >/dev/null 2>&1 || true
    if [ "$arch" = "arm64-v8a" ]; then
        ./configure $host --prefix="$prefix" --enable-static --disable-shared \
            CPPFLAGS="--sysroot=$ndk_sysroot -I$prefix/include" \
            LDFLAGS="--sysroot=$ndk_sysroot -L$prefix/lib" \
            CFLAGS="-O3 -fPIC --sysroot=$ndk_sysroot" \
            --with-zlib-prefix="$prefix"
    else
        ./configure $host --prefix="$prefix" --enable-static --disable-shared \
            CPPFLAGS="-I$prefix/include" LDFLAGS="-L$prefix/lib" CFLAGS="-O3 -fPIC" \
            --with-zlib-prefix="$prefix"
    fi
    make -j"$jobs" install

    # Build ImageMagick
    cd "$DEPS_ROOT/src/ImageMagick"
    make distclean >/dev/null 2>&1 || true
    
    # PREMIUM BUILD PROTOCOL
    export PKG_CONFIG="pkg-config --static"
    export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
    export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
    if [ "$arch" = "arm64-v8a" ]; then
        ./configure $host --prefix="$prefix" \
            --enable-shared --disable-static \
            --without-modules --without-perl --without-x --without-magick-plus-plus \
            --without-utilities --disable-docs --disable-opencl --disable-openmp \
            --with-png=yes --with-zlib=yes \
            CPPFLAGS="--sysroot=$ndk_sysroot -I$prefix/include" \
            LDFLAGS="--sysroot=$ndk_sysroot -L$prefix/lib" \
            LIBS="$sys_libs" \
            CFLAGS="-O3 -fPIC --sysroot=$ndk_sysroot -Wno-deprecated-declarations" \
            PNG_CFLAGS="--sysroot=$ndk_sysroot -I$prefix/include" \
            PNG_LIBS="--sysroot=$ndk_sysroot -L$prefix/lib -lpng16 -lz -lm" \
            ZLIB_CFLAGS="--sysroot=$ndk_sysroot -I$prefix/include" \
            ZLIB_LIBS="--sysroot=$ndk_sysroot -L$prefix/lib -lz"
    else
        ./configure $host --prefix="$prefix" \
            --enable-shared --disable-static \
            --without-modules --without-perl --without-x --without-magick-plus-plus \
            --without-utilities --disable-docs --disable-opencl --disable-openmp \
            --with-png=yes --with-zlib=yes \
            CPPFLAGS="-I$prefix/include" \
            LDFLAGS="-L$prefix/lib" \
            LIBS="$sys_libs" \
            CFLAGS="-O3 -fPIC -Wno-deprecated-declarations" \
            PNG_CFLAGS="-I$prefix/include" \
            PNG_LIBS="-L$prefix/lib -lpng16 -lz -lm" \
            ZLIB_CFLAGS="-I$prefix/include" \
            ZLIB_LIBS="-L$prefix/lib -lz"
    fi
    if [ "$arch" = "win64" ]; then
        perl -0pi -e 's/#define MAGICKCORE_HAVE_NETINET_IN_H 1/\/\* #undef MAGICKCORE_HAVE_NETINET_IN_H \*\//g; s/#define MAGICKCORE_HAVE_SYS_SOCKET_H 1/\/\* #undef MAGICKCORE_HAVE_SYS_SOCKET_H \*\//g; s/#define MAGICKCORE_HAVE_SOCKET 1/\/\* #undef MAGICKCORE_HAVE_SOCKET \*\//g' \
            config/config.h magick/magick-baseconfig.h
    fi
    
    # Compile and install, ignoring errors in incompatible utilities (make -k forces continuation)
    make -k || true
    make -k install || true
    if [ "$arch" = "win64" ]; then
        # Handle win64 manual installation
        install_win64_imagemagick
    fi
    normalize_prefixes "$arch" "$tmp_prefix"
    sanitize_runtime_paths "$tmp_prefix"
    
    # Export to global
    mkdir -p "$DEPS_ROOT/lib/inc/imagemagick"
    rm -rf "$DEPS_ROOT/lib/obj/imagemagick/$arch"
    mkdir -p "$DEPS_ROOT/lib/obj/imagemagick/$arch"
    
    # Copy headers only
    if [ -d "$tmp_prefix/include" ]; then
        cp -r "$tmp_prefix/include/"* "$DEPS_ROOT/lib/inc/imagemagick/"
    fi
    
    # Copy binaries and config files explicitly
    if [ -d "$tmp_prefix/lib" ]; then
        find "$tmp_prefix/lib" -maxdepth 1 \( -type f -o -type l \) \( -name "*.so*" -o -name "*.dll*" -o -name "*.a" \) -exec cp -d {} "$DEPS_ROOT/lib/obj/imagemagick/$arch/" \;
    fi
    if [ -d "$tmp_prefix/lib64" ]; then
        find "$tmp_prefix/lib64" -maxdepth 1 \( -type f -o -type l \) \( -name "*.so*" -o -name "*.dll*" -o -name "*.a" \) -exec cp -d {} "$DEPS_ROOT/lib/obj/imagemagick/$arch/" \;
    fi
    if [ -d "$tmp_prefix/bin" ]; then
        find "$tmp_prefix/bin" -maxdepth 1 \( -type f -o -type l \) -exec cp -d {} "$DEPS_ROOT/lib/obj/imagemagick/$arch/" \;
    fi
    if [ -d "$tmp_prefix/lib/pkgconfig" ]; then
        mkdir -p "$DEPS_ROOT/lib/obj/imagemagick/$arch/pkgconfig"
        cp -r "$tmp_prefix/lib/pkgconfig/"* "$DEPS_ROOT/lib/obj/imagemagick/$arch/pkgconfig/"
    fi
    
    rm -rf "$tmp_prefix"
    
    # Cleanup and Patches
    find "$DEPS_ROOT/lib/obj/imagemagick/$arch/" -name "*.la" -delete 2>/dev/null || true
    if [ "$arch" = "win64" ]; then
        for lib in "$DEPS_ROOT/lib/obj/imagemagick/$arch"/*.dll.a; do [ -e "$lib" ] && cp "$lib" "${lib%.dll.a}.a"; done
    fi
    printf "\033[32m[OK]\033[0m %s architecture complete.\n" "$arch"
done
