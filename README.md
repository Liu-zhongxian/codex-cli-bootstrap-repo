# Codex CLI Bootstrap

Windows installer bootstrap for OpenAI Codex CLI.

This project checks whether `git`, `node`, and `npm` are installed, verifies that their versions meet the current `@openai/codex` package requirements, upgrades missing or outdated dependencies when possible, and then installs the latest Codex CLI automatically.

By default, the Windows bootstrap targets:

- `Node.js 22.22.2` when Node/npm are missing or too old
- `Git 2.53.0` when Git is missing or too old

## Files

- `install-codex.cmd`: double-click friendly Windows launcher
- `package.json`: npm entrypoints
- `scripts/bootstrap-codex-cli.ps1`: main installer logic

## Usage

Recommended for most Windows users:

```cmd
install-codex.cmd
```

Preview actions without installing:

```cmd
install-codex.cmd --dry-run
```

If `npm` is already installed:

```powershell
npm run setup:codex
```

Equivalent dry-run through npm:

```powershell
npm run setup:codex:dry-run
```

If `npm` is not installed yet, run the PowerShell bootstrap directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-codex-cli.ps1
```

After installation:

```powershell
codex --version
```

## Requirements

- Windows
- Internet access
- `winget` is preferred for automatic installation or upgrade of Git and Node.js
- If `winget` is unavailable, the script falls back to the official Node.js and Git installers

## What the script does

1. Detects `git`
2. Detects `node` and `npm`
3. Installs `Git 2.53.0` when Git is missing or below the target version
4. Installs `Node.js 22.22.2` when Node/npm are missing or below the target version
5. Fetches the latest `@openai/codex` package metadata from npm
6. Compares the current local environment against the current Codex CLI requirements
7. Installs the latest `@openai/codex`

## Notes

- The current script is Windows-only.
- Some corporate or locked-down machines may require Administrator approval.
- Some environments may still block unattended installers through group policy or endpoint security.
