# kc-bin-dep

`kc-bin-dep` is the standalone repository for compiled third-party runtime libraries, dependency artifacts, and installers for the KaisarCode ecosystem.

It manages compiled third-party runtime libraries, their production
installers, and common development toolchains required for KaisarCode
projects. It does not contain KaisarCode application sources.

## Layout

- `bin/`: Build and maintenance scripts for dependencies.
- `etc/`: Shared installer manifests and distribution metadata.
- `lib/inc/<dep>/`: Consolidated development headers.
- `lib/obj/<dep>/<arch>/`: Compiled binaries and runtime libraries.
- `src/`: Upstream source trees (local build cache).
- `tmp/`: Temporary build worktrees.

## Supported Architectures

- `x86_64`: Standard 64-bit Linux.
- `aarch64`: ARM64 Linux (e.g., Raspberry Pi, Server-side ARM).
- `arm64-v8a`: Android ARM64 (built via NDK).
- `win64`: Windows 64-bit (cross-compiled via Mingw-w64).

## Runtime Libraries

The following libraries are built and managed by `kc-bin-dep`:

- `llama.cpp` & `ggml`: High-performance LLM inference.
- `stable-diffusion.cpp`: GGUF-based image generation.
- `imagemagick`: Image processing and conversion (v6).
- `resvg`: Fast SVG rendering.
- `pcre2`: Perl Compatible Regular Expressions.
- `parson`: Lightweight JSON parser.
- `libpng`: Portable Network Graphics library.
- `zlib`: Compression library.

## Managed Toolchains

For developers, `install-dev.sh` provides managed toolchains installed under `/usr/local/share/kaisarcode/toolchains`:

- **Android NDK**: r27c for mobile cross-compilation.
- **Rust**: 1.67.1 with multi-target support.

## Installers

### Production Installer
Installs compiled artifacts from `lib/` into `/usr/local/lib/kaisarcode`.
Invocable locally or remotely:

```bash
# Install specific dependencies
./install.sh llama.cpp imagemagick libpng

# Remote one-liner
wget -qO- https://raw.githubusercontent.com/kaisarcode/kc-bin-dep/slave/install.sh | sudo bash -s -- llama.cpp
```

### Developer Installer
Installs all compiled artifacts plus the global build toolchains and verified source trees.

```bash
sudo ./install-dev.sh
```

---

**Author:** KaisarCode

**Email:** <kaisar@kaisarcode.com>

**Website:** [https://kaisarcode.com](https://kaisarcode.com)

**License:** [GNU GPL v3.0](https://www.gnu.org/licenses/gpl-3.0.html)

© 2026 KaisarCode
