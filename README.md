**Language:** English | [简体中文](./README.zh-CN.md)

# Codex CLI Bootstrap

Windows and macOS installer bootstrap for OpenAI Codex CLI.

## Quick Start

Repository URL:

```text
https://github.com/Liu-zhongxian/codex-cli-bootstrap-repo
```

If you know how to use `git`, clone the repository and run the launcher for your platform.

If you do not use `git`, download the repository as a ZIP from GitHub and extract it locally.

This is usually simpler for beginners.

This project checks whether `git`, `node`, and `npm` are installed, verifies that their versions meet the current `@openai/codex` package requirements, upgrades missing or outdated dependencies when possible, and then installs Codex CLI automatically.

By default, the bootstrap requires at least:

- `Node.js 22.22.2`
- `Git 2.53.0`

These are minimum versions, not pinned versions. If a machine is missing dependencies or is below the minimum, the bootstrap tries to install or upgrade to the current available version that satisfies the requirement.

## Warning

- On Windows, both `install-codex.cmd` and the npm entrypoints run PowerShell with `ExecutionPolicy Bypass`.
- The bootstrap may install or upgrade system-wide Git, Node.js, and npm.
- On macOS, if Homebrew is missing, the bootstrap installs Homebrew automatically before continuing.
- By default, Codex CLI is installed from the official npm package `@openai/codex@latest`.
- When Windows falls back to direct Node.js or Git installer downloads, the script verifies the downloaded file with SHA256 before running it.

## Files

- `install-codex.cmd`: double-click friendly Windows launcher
- `install-codex.sh`: macOS shell launcher
- `package.json`: npm entrypoints
- `scripts/bootstrap-codex-cli.ps1`: Windows installer logic
- `scripts/bootstrap-codex-cli-macos.sh`: macOS installer logic
- `scripts/run-bootstrap.js`: cross-platform npm entrypoint dispatcher

## Usage

Recommended for Windows users:

```cmd
install-codex.cmd
```

This is the Windows launcher you can double-click after extracting the ZIP.

Recommended for macOS users:

```bash
./install-codex.sh
```

This is the macOS launcher you run from Terminal after extracting the ZIP.

If you downloaded the repository as a ZIP and the shell script is not executable yet:

```bash
chmod +x ./install-codex.sh ./scripts/bootstrap-codex-cli-macos.sh
```

Preview actions without installing:

```cmd
install-codex.cmd --dry-run
```

```bash
./install-codex.sh --dry-run
```

Common options:

```text
--skip-git
--skip-node
--skip-npm
--codex-version latest
--codex-version 0.125.0
```

If a `--skip-*` option is used and the existing tool does not meet the minimum version requirement, the bootstrap stops with an error instead of upgrading it automatically.

If `npm` is already installed, the generic cross-platform entrypoint is:

```bash
npm run setup:codex
```

Equivalent dry-run through npm:

```bash
npm run setup:codex:dry-run
```

Platform-specific npm entrypoints:

```powershell
npm run setup:codex:windows
npm run setup:codex:windows:dry-run
```

```bash
npm run setup:codex:macos
npm run setup:codex:macos:dry-run
```

If `npm` is not installed yet, run the platform bootstrap directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-codex-cli.ps1
```

```bash
/bin/bash ./scripts/bootstrap-codex-cli-macos.sh
```

After installation:

```bash
codex --version
```

## Requirements

- Windows or macOS
- Internet access
- On Windows, `winget` is preferred for automatic installation or upgrade of Git and Node.js
- On Windows, if `winget` is unavailable, the script falls back to the official Node.js and Git installers
- On macOS, Homebrew is preferred and will be installed automatically when missing
- On macOS, if you clone with Git, the executable bit for `.sh` files is preserved automatically

## What the script does

1. Detects `git`
2. Detects `node` and `npm`
3. Ensures `Git` is at least `2.53.0`
4. Ensures `Node.js` is at least `22.22.2`
5. Fetches the current `@openai/codex` package metadata from npm
6. Compares the local environment against the active Codex CLI requirements
7. Installs `@openai/codex@latest` by default, or a requested exact version through `--codex-version`
8. Re-validates the resolved command path and version after every install or upgrade step
9. Validates direct Windows fallback downloads with SHA256 before launching them

## Notes

- Windows uses PowerShell and `winget` or official installers.
- macOS uses Bash and Homebrew.
- `--codex-version` defaults to `latest`, which follows the current official Codex CLI release on npm.
- Some corporate or locked-down machines may require Administrator approval.
- Some environments may still block unattended installers through group policy or endpoint security.
