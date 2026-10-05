<!-- LOGO -->
<h1>
<p align="center">
  <img src="images/newicon/icon_1024.png" alt="ExGhostty" width="160">
  <br>ExGhostty
</h1>
<p align="center">
  <b>一款基于 Ghostty 的全新 SSH 工具</b>
</p>
<p align="center">
   <a href="README.md">English</a> · <b>简体中文</b>
</p>

---

## 为什么会有 ExGhostty？

开发这个项目，主要是出于对 [Ghostty](https://ghostty.org) 的喜爱——
它是一个快速、原生、漂亮的终端模拟器。但再怎么喜欢，也必须承认，
Ghostty 并不适合作为一个传统的 **SSH 工具** 来使用：

- **Ghostty 不符合 SSH 工具的使用场景。** 管理大量远程主机、跳板登录、
  文件传输、端口转发保活……这些是一个单纯的终端模拟器帮不了你的。
- **Ghostty 的配置门槛太高。** 一切配置都要手写配置文件，这对只想
  连上服务器干活的新人来说，是非常劝退的。
- **传统终端已经跟不上 AI 的节奏。** 在 AI 大模型快速发展的今天，
  一个只会回显文字的传统终端，已经很难满足人们真正的工作方式。

ExGhostty **并不是** 一个追求大而全的工具。它只希望在 **SSH 这件事上
做得更好**，配合一些常用的能力，并与 **AI 大模型** 保持实用的结合。

它 **免费且开源** —— 不会加入订阅，也不会加入广告。它的主旨只是提供
另一种选择，让喜欢 Ghostty 的用户，可以有更多适合自己工作方式的选择。

---

## 主要功能

### 核心：把 SSH 变简单
- **SSH 连接管理** —— 按分组管理主机，支持密码 / 密钥认证、跳板机、
  每台主机独立的编码、超时与心跳保活设置。
- **一键连接** —— 双击主机即可建立会话；密码 **AES 加密存储**，绝不明文保存。
- **连接测试** —— 保存前验证连通性与认证是否可用。
- **本地终端** —— 完整的 Ghostty 终端，一键即达。

### SFTP 文件管理
- 与终端联动浏览远程目录（跟随 shell 中的 `cd`）。
- 使用 **rsync** 上传 / 下载文件与文件夹，网络不稳定时支持 **断点续传**。
- 任务窗口显示每个任务的进度，支持暂停 / 恢复 / 取消，错误信息可直接复制。

### 端口转发
- 创建 **本地 (-L)**、**远程 (-R)**、**动态 (-D)** 三种转发。
- 一键启动 / 停止，自动保活与断线重启。
- 端口冲突检测，可选择结束占用进程。

### 会话复用
- 连接现有的 **tmux** / **zellij** 会话，新建会话或分离会话，本地与远程均支持。

### 代码片段
- 按分类保存常用 Shell / Python 片段。
- 双击即可在当前终端中执行。

### 系统监控
- 基于 [xtop](https://github.com/rarnu/xtop)，实时展示本地或远程主机的
  CPU / 内存 / 磁盘 / 网络 / GPU 卡片。

### AI 助手
- 与 LLM（兼容 OpenAI 接口）对话，自动携带 **当前终端上下文**
  （目录、SSH 主机、标题）。
- 应答中的命令与脚本以可运行块展示，一键复制到终端。

### 更多
- **设置窗口** —— 全部通过原生 GUI 配置（无需手写配置文件），
  含主题预览与快捷键设置。
- **iCloud 同步** —— 通过 iCloud Drive 在多台 Mac 间同步配置、
  SSH 主机、端口转发规则与代码片段。
- 基于快速、原生的 **Ghostty** 终端引擎构建。

---

## 架构

ExGhostty 是基于 Ghostty 终端引擎构建的 macOS 原生桌面 SSH 客户端，
主要分为以下几层：

| 层 | 源码位置 | 职责 |
| --- | --- | --- |
| 终端引擎 | `src/terminal/`、`src/termio/`、`src/renderer/` | 终端模拟、PTY 与进程输入输出、渲染 |
| 原生桥接 | `include/ghostty.h`、`macos/Sources/Ghostty/` | C 嵌入接口与 Swift 绑定，通过 `macos/GhosttyKit.xcframework` 链接 |
| macOS 应用 | `macos/Sources/App/macOS/`、`macos/Sources/Features/` | 应用生命周期、SwiftUI/AppKit 窗口、SSH 工具、设置和同步 |
| 构建与资源 | `build.zig`、`src/build/`、`pkg/`、`po/`、`src/shell-integration/` | Zig 依赖、Xcode 集成、翻译、主题和 shell 集成 |

SSH 工具调用 macOS 本地进程和 OpenSSH；`SSHCommandExecutor` 为文件浏览器
及其他工具提供共享的远程命令执行和 SSH 控制通道。文件浏览器通过 SSH
执行远程命令，使用 rsync 传输文件。AI 助手通过兼容 OpenAI 的
`chat/completions` 接口接收流式回复。设置使用 Ghostty 配置和 UserDefaults，
iCloud 同步将配置和工具数据复制到 iCloud Drive。

仓库还保留了 Ghostty 的 GTK 运行时 `src/apprt/gtk/` 和独立的
`libghostty-vt` 终端库。上述 SSH 界面功能实现在 macOS 应用中。

## 环境要求与准备

- **macOS**：ExGhostty 应用目标的最低部署版本为 macOS 13.0；构建主机需要
  能运行下方指定的 Xcode 工具链。
- **Zig 0.15.2**：版本依据为 [build.zig.zon](build.zig.zon) 中的
  `minimum_zig_version`。版本检查接受相同主版本、次版本且补丁版本不低于
  此值的 Zig，不接受更新的次版本系列。
- **完整的 Xcode 26**：需要 macOS 26 SDK、iOS SDK 和 Metal Toolchain，
  详见 [HACKING.md](HACKING.md#xcode-version-and-sdks)。仅安装 Command Line
  Tools 不足以构建；该文档还记录了 Zig 0.15.x 与 Xcode 26.4 的链接问题。
- 首次下载 Zig 依赖时需要网络连接。
- **Nushell**：仅使用可选的 `macos/build.nu` 构建脚本时需要。

克隆本项目并检查工具链：

```bash
git clone https://github.com/vruru/ExGhostty.git
cd ExGhostty
zig version
xcode-select -p
xcodebuild -version
```

如果当前开发目录指向 Command Line Tools，请在构建前切换到完整的 Xcode 安装。

## 编译

以下命令均从仓库根目录运行。调试构建：

```bash
zig build
```

使用仓库脚本进行干净的优化构建：

```bash
./release.sh
```

`release.sh` 会删除 `zig-out/` 和 `.zig-cache/`，再执行
`zig build -Doptimize=ReleaseSmall`。需要保留缓存进行增量构建时，
直接运行这条 Zig 命令。

两种构建均将应用包安装到 `zig-out/ExGhostty.app`。Zig 先构建 GhosttyKit
XCFramework 和资源，再调用 Xcode。内部 Xcode 工程、target 和 scheme
仍使用 **Ghostty** 名称，应用产物名为 **ExGhostty**。调试构建使用 Xcode
的 `Debug` 配置，优化构建使用 `ReleaseLocal` 配置。

仅修改 Swift 时，可使用 Nushell 脚本迭代。先准备底层库和资源，再构建应用：

```bash
zig build -Demit-macos-app=false
macos/build.nu
open macos/build/Debug/ExGhostty.app
```

脚本默认使用 `Ghostty` scheme、`Debug` 配置和 `build` 动作。修改底层 Zig
代码后需要重新构建库。更多 macOS 开发说明见 [macos/AGENTS.md](macos/AGENTS.md)。

## 运行与安装

启动 Zig 构建的应用包：

```bash
open zig-out/ExGhostty.app
```

本地安装时，通过 Finder 将 `zig-out/ExGhostty.app` 拖入 Applications。
ExGhostty 是桌面应用，无需部署服务端。`release.sh` 生成本地应用包，
不包含 DMG 打包、公证或发布步骤。

## 配置与环境变量

**标准构建与启动所需的项目专用环境变量：无。** shell 提供常规的 `PATH`
和 `HOME`。下表仅列出可选变量名称与用途：

| 名称 | 用途 |
| --- | --- |
| `GHOSTTY_CONFIG_PATH` | 启动 macOS 应用时指定其他配置文件 |
| `GHOSTTY_LOG` | 控制终端核心的日志输出目标 |
| `DISPLAY`、`XAUTHORITY` | 启用 SSH X11 转发时使用的 X11 环境 |

SSH 连接信息和凭据在应用中填写。密码辅助程序会在内部为子进程设置
`GHOSTTY_ASKPASS_PASSWORD`、`SSH_ASKPASS`、`SSH_ASKPASS_REQUIRE` 和 `SSHPASS`，
用户无需手动导出这些变量。

AI 助手需要在设置中填写 `ai-endpoint`、`ai-apikey` 和 `ai-model`。
三项均为启用助手的必要配置。endpoint 应填写 API 基础地址，应用会追加
`chat/completions`。这些是配置键；服务从配置文件或 UserDefaults 读取，
不读取 `OPENAI_API_KEY` 环境变量。

各项可选功能还需要对应的工具或服务：

- SSH 会话与密码辅助程序使用 `/usr/bin/ssh` 和 `/usr/bin/expect`。
- 文件传输在本机使用 `/usr/bin/rsync`，远端也需要 rsync；压缩包操作还会使用 tar。
- 会话复用需要在会话所在的机器上安装所选的 `tmux` 或 `zellij`。
- 系统监控需要在被监控的机器上安装 `xtop`；未检测到时，面板提供安装说明链接。
- 跨 Mac 同步需要各台 Mac 的 iCloud Drive 可用。设置中的同步开关默认开启，
  同步目录为 `~/Library/Mobile Documents/com~apple~CloudDocs/ExGhostty/`。

## 使用方法

1. 启动 **ExGhostty**。
2. 使用 **左侧栏** 创建和管理 SSH 连接与本地终端。
3. 使用 **右侧栏** 打开各项工具：SFTP、端口转发、会话复用、系统监控、
   代码片段与 AI 助手。
4. 打开 **设置** 调整外观、主题、快捷键、同步与语言。

## 开发文档与检查

先阅读 [AGENTS.md](AGENTS.md) 和待修改目录下的开发指南。
修改终端引擎时优先运行针对性的 Zig 测试：

```bash
zig build test -Dtest-filter='<test name>'
zig build test-lib-vt -Dtest-filter='<filter>'
```

准备好底层库和资源后，可运行 macOS 单元测试：

```bash
macos/build.nu --action test
```

该脚本跳过需要额外界面权限的 `GhosttyUITests`。终端库使用示例位于
[example/](example/)。

当前仓库没有 `docs/` 目录。[HACKING.md](HACKING.md)、
[PACKAGING.md](PACKAGING.md) 和 [CONTRIBUTING.md](CONTRIBUTING.md)
保留了上游 Ghostty 的开发说明，其中的上游发布地址和已不存在的 `nix/`
目录、`flake.nix` 引用不适用于 ExGhostty 的准备或发布流程。
本项目的构建步骤与依赖版本应以本 README、仓库内构建脚本和 `build.zig.zon` 为准。

## 许可证

ExGhostty 使用 [MIT 许可证](LICENSE)。
