**语言：** [English](./README.md) | 简体中文

# Codex CLI Bootstrap

这是一个用于 OpenAI Codex CLI 的 Windows 和 macOS 安装引导脚本。

这个项目会检测电脑上是否已经安装 `git`、`node` 和 `npm`，校验它们的版本是否满足当前 `@openai/codex` 的要求，在可能的情况下自动安装或升级缺失依赖，然后继续自动安装 Codex CLI。

默认情况下，这个安装器要求最低版本为：

- `Node.js 22.22.2`
- `Git 2.53.0`

这里写的是最低版本，不是强制锁定版本。如果电脑上缺少依赖，或者版本低于下限，脚本会尽量安装或升级到当前可用、并且满足要求的版本。

## 重要提示

- 在 Windows 上，`install-codex.cmd` 和 npm 入口都会通过 `ExecutionPolicy Bypass` 调用 PowerShell。
- 这个脚本可能会安装或升级系统级的 Git、Node.js 和 npm。
- 在 macOS 上，如果机器还没有 Homebrew，脚本会先自动安装 Homebrew，再继续执行。
- 默认情况下，Codex CLI 会从官方 npm 包 `@openai/codex@latest` 安装。
- 当 Windows 回退到直接下载 Node.js 或 Git 官方安装包时，脚本会先做 SHA256 校验，再执行安装。

## 文件说明

- `install-codex.cmd`：适合双击运行的 Windows 启动器
- `install-codex.sh`：适合 macOS 终端运行的 Shell 启动器
- `package.json`：npm 脚本入口
- `scripts/bootstrap-codex-cli.ps1`：Windows 安装逻辑
- `scripts/bootstrap-codex-cli-macos.sh`：macOS 安装逻辑
- `scripts/run-bootstrap.js`：跨平台 npm 分发入口

## 使用方法

Windows 用户建议直接运行：

```cmd
install-codex.cmd
```

macOS 用户建议直接运行：

```bash
./install-codex.sh
```

如果你是直接下载 ZIP，而不是用 Git 克隆，发现脚本还没有执行权限，可以先运行：

```bash
chmod +x ./install-codex.sh ./scripts/bootstrap-codex-cli-macos.sh
```

只预演、不真正安装：

```cmd
install-codex.cmd --dry-run
```

```bash
./install-codex.sh --dry-run
```

常用参数：

```text
--skip-git
--skip-node
--skip-npm
--codex-version latest
--codex-version 0.125.0
```

如果使用了 `--skip-*` 参数，但本机现有工具版本又低于最低要求，脚本会直接报错退出，而不是继续帮你升级。

如果电脑上已经安装了 `npm`，也可以使用通用跨平台入口：

```bash
npm run setup:codex
```

通过 npm 运行预演模式：

```bash
npm run setup:codex:dry-run
```

平台专用 npm 入口：

```powershell
npm run setup:codex:windows
npm run setup:codex:windows:dry-run
```

```bash
npm run setup:codex:macos
npm run setup:codex:macos:dry-run
```

如果电脑上还没有 `npm`，可以直接运行平台脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-codex-cli.ps1
```

```bash
/bin/bash ./scripts/bootstrap-codex-cli-macos.sh
```

安装完成后可以检查版本：

```bash
codex --version
```

## 运行要求

- Windows 或 macOS
- 需要联网
- 在 Windows 上，优先使用 `winget` 自动安装或升级 Git 和 Node.js
- 在 Windows 上，如果没有 `winget`，脚本会回退到 Node.js 和 Git 的官方安装包
- 在 macOS 上，优先使用 Homebrew；如果没有安装，脚本会自动安装 Homebrew
- 在 macOS 上，如果你是通过 Git 克隆仓库，`.sh` 文件的可执行权限会自动保留

## 脚本会做什么

1. 检测 `git`
2. 检测 `node` 和 `npm`
3. 确保 `Git` 版本至少为 `2.53.0`
4. 确保 `Node.js` 版本至少为 `22.22.2`
5. 从 npm 获取当前 `@openai/codex` 包的元数据
6. 对比当前本地环境与 Codex CLI 的实际要求
7. 默认安装 `@openai/codex@latest`，也可以通过 `--codex-version` 指定精确版本
8. 每次安装或升级之后，再次校验最终命中的命令路径和版本
9. 在 Windows 的官方下载回退路径里，先做 SHA256 校验，再执行安装包

## 说明

- Windows 使用 PowerShell，以及 `winget` 或官方安装包。
- macOS 使用 Bash 和 Homebrew。
- `--codex-version` 默认是 `latest`，会跟随 npm 上当前官方发布的 Codex CLI 版本。
- 某些公司电脑或受限制环境中，安装过程可能需要管理员权限。
- 某些安全策略或终端防护软件可能会阻止静默安装。
