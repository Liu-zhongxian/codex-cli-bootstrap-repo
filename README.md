# Codex CLI Bootstrap

Windows installer bootstrap for OpenAI Codex CLI.

This project checks whether `git`, `node`, and `npm` are installed, verifies that their versions meet the current `@openai/codex` package requirements, upgrades missing or outdated dependencies when possible, and then installs the latest Codex CLI automatically.

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
- `winget` available for automatic installation or upgrade of Git and Node.js

## What the script does

1. Detects `git`
2. Detects `node` and `npm`
3. Fetches the latest `@openai/codex` package metadata from npm
4. Compares the current local environment against the current Codex CLI requirements
5. Installs or upgrades missing tools
6. Installs the latest `@openai/codex`

## Notes

- The current script is Windows-only.
- Some corporate or locked-down machines may require Administrator approval.
- If `winget` is unavailable, install App Installer from Microsoft Store first.
