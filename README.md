**Language:** English | [简体中文](./README.zh-CN.md)

# Codex CLI Bootstrap

Windows and macOS installer bootstrap for OpenAI Codex CLI.

This project checks whether `git`, `node`, and `npm` are installed, verifies that their versions meet the current `@openai/codex` package requirements, upgrades missing or outdated dependencies when possible, and then installs the latest Codex CLI automatically.

By default, the bootstrap requires at least:

- `Node.js 22.22.2`
- `Git 2.53.0`

These are minimum versions, not pinned versions. If a machine is missing dependencies or is below the minimum, the bootstrap tries to install or upgrade to the current available version that satisfies the requirement.

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

Recommended for macOS users:

```bash
./install-codex.sh
```

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
5. Fetches the latest `@openai/codex` package metadata from npm
6. Compares the current local environment against the current Codex CLI requirements
7. Installs the latest `@openai/codex`

## Notes

- Windows uses PowerShell and `winget` or official installers.
- macOS uses Bash and Homebrew.
- Some corporate or locked-down machines may require Administrator approval.
- Some environments may still block unattended installers through group policy or endpoint security.
