# Agent Development Guide

## Project and documentation

- ExGhostty is a macOS SSH client built on Ghostty's Zig terminal engine.
  SSH tools, settings, AI, and iCloud sync live in `macos/Sources/Features/`.
- Start with `README.md` (English) or `README_zh.md` (Simplified Chinese)
  for setup, architecture, build outputs, and local installation.
- There is no `docs/` directory. `HACKING.md`, `PACKAGING.md`, and
  `CONTRIBUTING.md` retain upstream Ghostty material, including references
  to absent `nix/` files and upstream releases. Use this fork's build scripts
  and `build.zig.zon` for build instructions and dependency versions.
- Read the applicable directory's `AGENTS.md` before changing its files.

## Commands

- **Build:** `zig build`
  - Use Zig 0.15.2 and the full Xcode toolchain described in `README.md`.
  - On macOS, the app bundle is `zig-out/ExGhostty.app`; the internal
    Xcode project, target, and scheme are still named `Ghostty`.
  - If you're on macOS and don't need to build the macOS app, use
    `-Demit-macos-app=false` to skip building the app bundle and speed up
    compilation.
- **Optimized build:** `zig build -Doptimize=ReleaseSmall`
  - `./release.sh` runs this after deleting `zig-out/` and `.zig-cache/`.
- **Run (macOS):** `open zig-out/ExGhostty.app`
- **Swift iteration and tests:** See `macos/AGENTS.md` for `macos/build.nu`.
- **Test (Zig):** `zig build test`
  - Prefer to run targeted tests with `-Dtest-filter` because the full
    test suite is slow to run.
- **Test filter (Zig)**: `zig build test -Dtest-filter=<test name>`
- **Formatting (Zig)**: `zig fmt <changed files>`
- **Formatting (Swift)**: `swiftlint lint --strict --fix`
- **Formatting (other)**: `prettier -w <changed files>`
- Limit formatting to changed files; use repository-wide formatting only
  for an explicitly scoped formatting task.

## libghostty-vt

- Build: `zig build -Demit-lib-vt`
- Build WASM: `zig build -Demit-lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall`
- Test: `zig build test-lib-vt -Dtest-filter=<filter>`
  - Prefer this when the change is in a libghostty-vt file
- All C enums in `include/ghostty/vt/` must have a `_MAX_VALUE = GHOSTTY_ENUM_MAX_VALUE`
  sentinel as the last entry to force int enum sizing (pre-C23 portability).

## Directory Structure

- Shared Zig core: `src/`
- macOS app: `macos/`
- macOS SSH tools and other features: `macos/Sources/Features/`
- C embedding API: `include/ghostty.h`; standalone VT API: `include/ghostty/vt/`
- Standalone library examples: `example/` (see `example/AGENTS.md`)
- GTK (Linux and FreeBSD) app: `src/apprt/gtk`
  - This is the retained upstream runtime; the ExGhostty SSH UI lives in macOS.

## Issue and PR Guidelines

- Never create an issue.
- Never create a PR.
- If a request conflicts with these publication restrictions, explain the
  restriction and provide the proposed issue or PR text for review. Do not
  create unrelated files or modify code in response to that conflict.
