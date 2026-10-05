<!-- LOGO -->
<h1>
<p align="center">
  <img src="images/newicon/icon_1024.png" alt="ExGhostty" width="160">
  <br>ExGhostty
</h1>
<p align="center">
  <b>A brand-new SSH tool based on Ghostty.</b>
</p>
<p align="center">
   <b>English</b> · <a href="README_zh.md">简体中文</a>
</p>

---

## Why ExGhostty?

ExGhostty was born out of a genuine love for [Ghostty](https://ghostty.org) —
a fast, native, beautiful terminal emulator. But as much as we love Ghostty,
it was never designed to be a traditional **SSH tool**:

- **Ghostty doesn't fit the SSH-tool workflow.** Managing many remote hosts,
  jumping between them, transferring files, and keeping port forwards alive are
  things a plain terminal emulator simply doesn't help you with.
- **Ghostty's configuration is intimidating.** Everything is done by editing a
  text configuration file, which is a real barrier for newcomers who just want
  to connect to a server and get work done.
- **Terminals are falling behind the AI era.** With the rise of large language
  models, a traditional terminal that only echoes text can no longer keep up
  with how people actually want to work.

ExGhostty is **not** an attempt to build a bloated, do-everything tool. It
focuses on doing **SSH really well**, adds a small set of commonly needed
capabilities around it, and keeps a close, practical integration with **AI
models**.

It is **free and open source** — no subscriptions, no ads, ever. The goal is
simply to offer another option, so that people who love Ghostty have one more
choice that fits the way they work.

---

## Features

### Core: SSH made easy
- **SSH connection manager** — organize hosts in groups, with password or
  key-based authentication, jump-host (bastion) support, per-host encoding,
  timeouts and keep-alive.
- **One-click connect** — double-click a host to open a session. Passwords are
  stored **AES-encrypted**, never in plain text.
- **Connection testing** — verify reachability and authentication before saving.
- **Local terminal** — a full Ghostty terminal is always one click away.

### SFTP file manager
- Browse remote directories alongside the terminal (follows `cd` in the shell).
- Upload / download files and folders with **rsync**, with **resume support**
  for unstable networks.
- Task window with per-task progress, pause / resume / cancel, and error
  details you can copy.

### Port forwarding
- Create **local (-L)**, **remote (-R)** and **dynamic (-D)** forwards.
- Start / stop with one click, automatic keep-alive and restart.
- Port-conflict detection with an option to kill the occupying process.

### Session reuse
- Attach to existing **tmux** and **zellij** sessions, create new ones, or
  detach — on both local and remote hosts.

### Code snippets
- Save frequently used shell / Python snippets in groups.
- Run a snippet in the current terminal with a double-click.

### System monitor
- Live CPU / memory / disk / network / GPU cards for local and remote hosts,
  powered by [xtop](https://github.com/rarnu/xtop).

### AI assistant
- Chat with an LLM (OpenAI-compatible endpoint) with your **current terminal
  context** (directory, SSH host, title) included automatically.
- Commands and scripts in replies are shown in runnable blocks — copy them into
  the terminal with one click.

### And more
- **Settings window** — configure everything through a native GUI (no hand
  editing of config files), including themes with previews and keybindings.
- **iCloud sync** — synchronize configuration, SSH hosts, port-forward rules
  and code snippets across your Macs via iCloud Drive.
- Built on the fast, native **Ghostty** terminal engine.

---

## Architecture

ExGhostty is a native macOS desktop SSH client built on Ghostty's terminal
engine. The main layers are:

| Layer | Source | Responsibility |
| --- | --- | --- |
| Terminal engine | `src/terminal/`, `src/termio/`, `src/renderer/` | Terminal emulation, PTY and process I/O, and rendering |
| Native bridge | `include/ghostty.h`, `macos/Sources/Ghostty/` | C embedding API and Swift bindings, linked through `macos/GhosttyKit.xcframework` |
| macOS application | `macos/Sources/App/macOS/`, `macos/Sources/Features/` | App lifecycle, SwiftUI/AppKit windows, SSH tools, settings, and sync |
| Build and resources | `build.zig`, `src/build/`, `pkg/`, `po/`, `src/shell-integration/` | Zig dependencies, Xcode integration, translations, themes, and shell integration |

SSH tools use macOS processes and OpenSSH; `SSHCommandExecutor` shares remote
command execution and SSH control channels with the file browser and other
tools. The file browser runs remote commands over SSH and uses rsync for
transfers. The AI assistant streams replies from an OpenAI-compatible
`chat/completions` endpoint. Settings use Ghostty configuration and
UserDefaults; iCloud sync copies configuration and tool data to iCloud Drive.

The repository also retains Ghostty's GTK runtime in `src/apprt/gtk/` and the
standalone `libghostty-vt` terminal library. The SSH-focused UI described above
is implemented in the macOS application.

## Requirements and setup

- **macOS** for the ExGhostty application. The app target has a macOS 13.0
  deployment minimum; building requires a host compatible with the Xcode
  toolchain below.
- **Zig 0.15.2**, as specified by `minimum_zig_version` in
  [build.zig.zon](build.zig.zon). The version check accepts the same major/minor
  with a patch version at least this high; a newer minor series is not accepted.
- **Full Xcode 26**, including the macOS 26 SDK, iOS SDK, and Metal Toolchain,
  as documented in [HACKING.md](HACKING.md#xcode-version-and-sdks). Command Line
  Tools alone are insufficient. That document also records a Zig 0.15.x
  linking caveat for Xcode 26.4.
- Network access for the initial Zig dependency downloads.
- **Nushell** only if using the optional `macos/build.nu` wrapper.

Clone this fork and check that the selected tools are available:

```bash
git clone https://github.com/vruru/ExGhostty.git
cd ExGhostty
zig version
xcode-select -p
xcodebuild -version
```

If the selected developer directory points to Command Line Tools instead of
full Xcode, select your Xcode installation before building.

## Build

Run commands from the repository root. A debug build is:

```bash
zig build
```

For a clean optimized build, use the repository's release script:

```bash
./release.sh
```

`release.sh` deletes `zig-out/` and `.zig-cache/`, then runs
`zig build -Doptimize=ReleaseSmall`. To build incrementally without clearing
these directories, run that Zig command directly.

Both builds install the bundle at `zig-out/ExGhostty.app`. Zig builds the
GhosttyKit XCFramework and resources before invoking Xcode. The internal Xcode
project, target, and scheme retain the **Ghostty** name; the app product is
**ExGhostty**. Debug builds use Xcode's `Debug` configuration; optimized builds
use `ReleaseLocal`.

For Swift-only iteration with Nushell, first prepare the library and resources,
then build the app with the wrapper:

```bash
zig build -Demit-macos-app=false
macos/build.nu
open macos/build/Debug/ExGhostty.app
```

The wrapper defaults to scheme `Ghostty`, configuration `Debug`, and action
`build`. Rebuild the Zig library when changing the core. Further macOS guidance
is in [macos/AGENTS.md](macos/AGENTS.md).

## Run and install

Launch the bundle built by Zig:

```bash
open zig-out/ExGhostty.app
```

For local installation, drag `zig-out/ExGhostty.app` into Applications using
Finder. ExGhostty runs as a desktop app and has no server deployment step.
`release.sh` builds a local app bundle; it does not package a DMG, notarize the
app, or publish a release.

## Configuration and environment

**Required application-specific environment variables: none** for a standard
build or launch. The shell supplies the usual `PATH` and `HOME`. Optional
variables are listed by name only:

| Name | Purpose |
| --- | --- |
| `GHOSTTY_CONFIG_PATH` | Select an alternate configuration file when launching the macOS app |
| `GHOSTTY_LOG` | Control logging destinations in the terminal core |
| `DISPLAY`, `XAUTHORITY` | X11 environment used when SSH X11 forwarding is enabled |

SSH connection details and credentials are entered in the app. Password helpers
set `GHOSTTY_ASKPASS_PASSWORD`, `SSH_ASKPASS`, `SSH_ASKPASS_REQUIRE`, and `SSHPASS`
for child processes internally; users do not need to export them.

Configure the AI assistant in Settings with `ai-endpoint`, `ai-apikey`, and
`ai-model`. All three are required for the assistant. The endpoint is the base
API URL: the app appends `chat/completions`. These are configuration keys;
the service reads them from the config file or UserDefaults, rather than an
`OPENAI_API_KEY` environment variable.

Optional features have their own dependencies:

- SSH sessions and password helpers use `/usr/bin/ssh` and `/usr/bin/expect`.
- File transfers use `/usr/bin/rsync` locally and require rsync on the remote
  host; archive operations also use tar.
- Session reuse needs the chosen `tmux` or `zellij` executable on the machine
  hosting that session.
- System monitoring needs `xtop` on the monitored machine. The panel links to
  its installation instructions if it is missing.
- Cross-Mac sync needs iCloud Drive available on each Mac. Its Settings toggle
  defaults to enabled; the sync directory is
  `~/Library/Mobile Documents/com~apple~CloudDocs/ExGhostty/`.

## Usage

1. Launch **ExGhostty**.
2. Use the **left sidebar** to create and manage SSH connections and local
   terminals.
3. Use the **right sidebar** to open the tools: SFTP, port forwarding, session
   reuse, system monitor, code snippets, and the AI assistant.
4. Open **Settings** to adjust appearance, themes, keybindings, sync and
   language.

## Development documentation and checks

Start with [AGENTS.md](AGENTS.md) and the guide for the directory being changed.
Use targeted Zig tests when working on the engine:

```bash
zig build test -Dtest-filter='<test name>'
zig build test-lib-vt -Dtest-filter='<filter>'
```

For macOS unit tests after preparing the library and resources:

```bash
macos/build.nu --action test
```

The wrapper skips `GhosttyUITests`, which require additional UI permissions.
Library usage examples are under [example/](example/).

This checkout has no `docs/` directory. [HACKING.md](HACKING.md),
[PACKAGING.md](PACKAGING.md), and [CONTRIBUTING.md](CONTRIBUTING.md) retain
upstream Ghostty guidance. Their upstream release URLs and references to the
absent `nix/` directory or `flake.nix` are not ExGhostty setup or release steps.
Use this README, the checked-in build scripts, and `build.zig.zon` for this
fork's build instructions and dependency versions.

## License

ExGhostty is distributed under the [MIT License](LICENSE).
