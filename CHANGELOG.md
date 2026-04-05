# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [KaisarCode Standards](https://kaisarcode.com).

## [1.1.1] - 2026-04-05

### Added
- Modular `stable-diffusion.cpp` packaging with separate `stable-diffusion.cpp` and `ggml` runtime exports.
- Vendored `ggml` public headers for downstream application builds.
- Multi-architecture export support for `x86_64`, `win64`, `aarch64`, and `arm64-v8a`.

### Changed
- Standardized exported shared libraries for downstream packaging and runtime resolution.

### Fixed
- Restored canonical CPU runtime exports for downstream consumers.
- Fixed Windows and Android shared-library linkage for modular `stable-diffusion.cpp` builds.

## [1.1.0] - 2026-04-03

### Added
- Modular backend support for the `llama.cpp` build pipeline.
- Standalone runtime libraries for CUDA and CPU backends.
- Broader CPU variant coverage for portable `x86_64` builds.

### Changed
- Updated the `llama.cpp` packaging flow to match the modular runtime layout.
- Standardized `ggml` shared-library naming for more predictable runtime resolution.
- Favored generic compatibility over host-specific native optimizations.

### Fixed
- Fixed CUDA backend symbol resolution in modular builds.
- Corrected shared-library linkage paths for downstream packaging.
