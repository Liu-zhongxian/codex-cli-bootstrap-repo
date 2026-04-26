**语言：** [English](./README.md) | 简体中文

# Codex CLI Bootstrap

这是一个用于 OpenAI Codex CLI 的 Windows 安装引导脚本。

这个项目会检测电脑上是否已经安装 `git`、`node` 和 `npm`，校验它们的版本是否满足当前 `@openai/codex` 的要求，在可能的情况下自动安装或升级缺失依赖，然后继续安装最新版本的 Codex CLI。

默认情况下，这个 Windows 安装器要求最低版本为：

- `Node.js 22.22.2`
- `Git 2.53.0`

## 文件说明

- `install-codex.cmd`：适合双击运行的 Windows 启动器
- `package.json`：npm 脚本入口
- `scripts/bootstrap-codex-cli.ps1`：主安装逻辑

## 使用方法

大多数 Windows 用户建议直接运行：

```cmd
install-codex.cmd
```

只预演、不真正安装：

```cmd
install-codex.cmd --dry-run
```

如果电脑上已经安装了 `npm`，也可以运行：

```powershell
npm run setup:codex
```

通过 npm 运行预演模式：

```powershell
npm run setup:codex:dry-run
```

如果电脑上还没有 `npm`，可以直接运行 PowerShell 安装脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-codex-cli.ps1
```

安装完成后可以检查版本：

```powershell
codex --version
```

## 运行要求

- Windows
- 需要联网
- 优先使用 `winget` 自动安装或升级 Git 和 Node.js
- 如果没有 `winget`，脚本会回退到 Node.js 和 Git 的官方安装包

## 脚本会做什么

1. 检测 `git`
2. 检测 `node` 和 `npm`
3. 确保 `Git` 版本至少为 `2.53.0`
4. 确保 `Node.js` 版本至少为 `22.22.2`
5. 从 npm 获取最新 `@openai/codex` 包的元数据
6. 对比当前本地环境与 Codex CLI 的要求
7. 安装最新版本的 `@openai/codex`

## 说明

- 当前脚本仅支持 Windows。
- 某些公司电脑或受限制环境中，安装过程可能需要管理员权限。
- 某些安全策略或终端防护软件可能会阻止静默安装。
