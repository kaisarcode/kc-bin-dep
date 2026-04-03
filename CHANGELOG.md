# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [KaisarCode Standards](https://kaisarcode.com).

## [1.1.0] - 2026-04-03

### Added
- Modular backend support enabled via `GGML_BACKEND_DL=ON` in the `llama.cpp` build pipeline.
- Standalone dynamic libraries for backends: `libggml-cuda.so` and `libggml-cpu.so`.
- Full-variant CPU support via `GGML_CPU_ALL_VARIANTS=ON`, ensuring portability across different x86_64 instruction sets.

### Changed
- Updated `bin/llama.sh` to support the new modular library architecture.
- Re-labeled all `ggml` shared libraries to include base components (`libggml-base.so`, `libggml.so`) for better runtime resolution.
- Disabled `GGML_NATIVE` to prevent the compiler from generating host-specific instructions, favoring generic compatibility with runtime dispatch.

### Fixed
- Resolved missing symbol issues in CUDA backend by ensuring `GGML_BACKEND_DL_IMPL` is correctly propagated through the build system.
- Corrected shared library linkage paths to support standardized `RPATH` in downstream projects.
