# macOS ExGhostty Application

The Xcode project, target, and scheme retain the `Ghostty` name. The built
application bundle is `ExGhostty.app`.

- Use `swiftlint` for formatting and linting Swift code.
- Before the first wrapper build, or after modifying the underlying Zig core,
  use `zig build -Demit-macos-app=false` from the repository root to prepare
  `macos/GhosttyKit.xcframework` and the resources used by the Xcode project.
- Prefer `macos/build.nu` for Swift-only iteration. It requires Nushell and
  runs Xcode in a clean environment. The full `zig build` workflow is also
  supported and installs `zig-out/ExGhostty.app` (see the root `README.md`).
  - Build: `macos/build.nu [--scheme Ghostty] [--configuration Debug] [--action build]`
  - Output: `macos/build/<configuration>/ExGhostty.app` (e.g. `macos/build/Debug/ExGhostty.app`)
- Run unit tests with `macos/build.nu --action test` after preparing the library
  and resources. The wrapper skips `GhosttyUITests`, which need UI permissions.

## AppleScript

- The AppleScript scripting definition is in `macos/Ghostty.sdef`.
- Guard AppleScript entry points and object accessors with the
  `macos-applescript` configuration (use `NSApp.isAppleScriptEnabled`
  and `NSApp.validateScript(command:)` where applicable).
- In `macos/Ghostty.sdef`, keep top-level definitions in this order:
  1. Classes
  2. Records
  3. Enums
  4. Commands
- Test AppleScript support:
  (1) Build with `macos/build.nu`
  (2) Launch and activate the app via osascript using the absolute path
      to the built app bundle:
      `osascript -e 'tell application "<absolute path to macos/build/Debug/ExGhostty.app>" to activate'`
  (3) Wait a few seconds for the app to fully launch and open a terminal.
  (4) Run test scripts with `osascript`, always targeting the app by
      its absolute path (not by name) to avoid calling the wrong
      application.
  (5) When done, quit via:
      `osascript -e 'tell application "<absolute path to macos/build/Debug/ExGhostty.app>" to quit'`
