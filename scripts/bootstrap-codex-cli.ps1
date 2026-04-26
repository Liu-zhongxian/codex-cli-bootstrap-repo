[CmdletBinding()]
param(
  [switch]$DryRun,
  [version]$MinGitVersion = [version]'2.30.0',
  [version]$MinNpmVersion = [version]'8.0.0',
  [version]$PreferredNodeVersion = [version]'20.0.0',
  [string]$NodeWingetId = 'OpenJS.NodeJS.LTS',
  [string]$GitWingetId = 'Git.Git'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:WorkspaceRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:NpmCacheDir = Join-Path $script:WorkspaceRoot '.npm-cache'

function Write-Step {
  param([string]$Message)
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Info {
  param([string]$Message)
  Write-Host "[info] $Message" -ForegroundColor DarkGray
}

function Invoke-Checked {
  param(
    [string]$Description,
    [scriptblock]$Action
  )

  if ($DryRun) {
    Write-Host "[dry-run] $Description" -ForegroundColor Yellow
    return
  }

  Write-Step $Description
  & $Action
}

function Ensure-Directory {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Ensure-PathEntry {
  param([string]$Entry)

  if ([string]::IsNullOrWhiteSpace($Entry)) {
    return
  }

  if (-not (Test-Path -LiteralPath $Entry)) {
    return
  }

  $parts = $env:PATH -split ';' | Where-Object { $_ }
  if ($parts -notcontains $Entry) {
    $env:PATH = "$Entry;$env:PATH"
  }
}

function Refresh-CommonToolPaths {
  Ensure-PathEntry (Join-Path $env:ProgramFiles 'nodejs')
  Ensure-PathEntry (Join-Path $env:LOCALAPPDATA 'Programs\nodejs')
  Ensure-PathEntry (Join-Path $env:ProgramFiles 'Git\cmd')
  Ensure-PathEntry (Join-Path $env:ProgramFiles 'Git\bin')
  Ensure-PathEntry (Join-Path $env:APPDATA 'npm')
}

function Get-CommandLocation {
  param([string]$Name)

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    return $null
  }

  return $command.Source
}

function Parse-VersionText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $null
  }

  $match = [regex]::Match($Text, '\d+(\.\d+){0,3}')
  if (-not $match.Success) {
    return $null
  }

  return [version]$match.Value
}

function ConvertTo-Version {
  param([string]$Value)

  $parts = $Value.Split('.')
  switch ($parts.Count) {
    1 { return [version]"$Value.0.0" }
    2 { return [version]"$Value.0" }
    default { return [version]$Value }
  }
}

function Get-ToolVersion {
  param(
    [string]$CommandName,
    [string[]]$Arguments
  )

  $commandPath = Get-CommandLocation -Name $CommandName
  if (-not $commandPath) {
    return $null
  }

  try {
    $output = & $commandPath @Arguments 2>&1 | Out-String
    return Parse-VersionText -Text $output
  }
  catch {
    return $null
  }
}

function Require-Winget {
  if (-not (Get-CommandLocation -Name 'winget.exe')) {
    throw 'winget.exe was not found. Install App Installer from Microsoft Store first, then rerun this script.'
  }
}

function Install-WingetPackage {
  param(
    [string]$Id,
    [string]$DisplayName
  )

  Invoke-Checked -Description "Installing $DisplayName via winget" -Action {
    winget.exe install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements --source winget
    if ($LASTEXITCODE -ne 0) {
      throw "winget install failed for $DisplayName."
    }
  }
}

function Upgrade-WingetPackage {
  param(
    [string]$Id,
    [string]$DisplayName
  )

  Invoke-Checked -Description "Upgrading $DisplayName via winget" -Action {
    winget.exe upgrade --id $Id --exact --silent --accept-package-agreements --accept-source-agreements --source winget
    if ($LASTEXITCODE -eq 0) {
      return
    }

    Write-Info "winget upgrade failed for $DisplayName, falling back to winget install."
    winget.exe install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements --source winget
    if ($LASTEXITCODE -ne 0) {
      throw "winget install fallback failed for $DisplayName."
    }
  }
}

function Ensure-NpmCache {
  Ensure-Directory -Path $script:NpmCacheDir
}

function Get-CodexMetadata {
  param([string]$NpmCommand)

  Ensure-NpmCache

  try {
    $raw = & $NpmCommand --cache $script:NpmCacheDir view @openai/codex version engines --json 2>&1
    $json = $raw | Out-String | ConvertFrom-Json
    return $json
  }
  catch {
    Write-Info 'Falling back to a safe default Codex requirement because npm registry metadata could not be fetched.'
    return [pscustomobject]@{
      version = 'latest'
      engines = [pscustomobject]@{
        node = '>=16'
      }
    }
  }
}

function Get-MinNodeVersionFromRange {
  param([string]$Range)

  if ([string]::IsNullOrWhiteSpace($Range)) {
    return [version]'16.0.0'
  }

  $matches = [regex]::Matches($Range, '>=\s*(\d+(?:\.\d+){0,2})')
  if ($matches.Count -eq 0) {
    return [version]'16.0.0'
  }

  $versions = foreach ($match in $matches) {
    ConvertTo-Version -Value $match.Groups[1].Value
  }

  return ($versions | Sort-Object | Select-Object -First 1)
}

function Test-VersionAtLeast {
  param(
    [version]$Current,
    [version]$Minimum
  )

  if ($null -eq $Current) {
    return $false
  }

  return $Current -ge $Minimum
}

function Ensure-NodeToolchain {
  $nodeVersion = Get-ToolVersion -CommandName 'node.exe' -Arguments @('-v')
  $npmVersion = Get-ToolVersion -CommandName 'npm.cmd' -Arguments @('-v')

  if ($null -eq $nodeVersion -or $null -eq $npmVersion) {
    Require-Winget
    Install-WingetPackage -Id $NodeWingetId -DisplayName 'Node.js LTS (includes npm)'
    Refresh-CommonToolPaths
    return
  }

  $npmCommand = Get-CommandLocation -Name 'npm.cmd'
  $codexMeta = Get-CodexMetadata -NpmCommand $npmCommand
  $codexMinNodeVersion = Get-MinNodeVersionFromRange -Range $codexMeta.engines.node

  Write-Info "Detected node version: $nodeVersion"
  Write-Info "Detected npm version:  $npmVersion"
  Write-Info "Codex latest version: $($codexMeta.version)"
  Write-Info "Codex node range:     $($codexMeta.engines.node)"

  $needNodeUpgrade =
    (-not (Test-VersionAtLeast -Current $nodeVersion -Minimum $codexMinNodeVersion)) -or
    (-not (Test-VersionAtLeast -Current $nodeVersion -Minimum $PreferredNodeVersion)) -or
    (-not (Test-VersionAtLeast -Current $npmVersion -Minimum $MinNpmVersion))

  if ($needNodeUpgrade) {
    Require-Winget
    Upgrade-WingetPackage -Id $NodeWingetId -DisplayName 'Node.js LTS (includes npm)'
    Refresh-CommonToolPaths
  }
}

function Ensure-Git {
  $gitVersion = Get-ToolVersion -CommandName 'git.exe' -Arguments @('--version')

  if ($null -eq $gitVersion) {
    Require-Winget
    Install-WingetPackage -Id $GitWingetId -DisplayName 'Git'
    Refresh-CommonToolPaths
    return
  }

  Write-Info "Detected git version: $gitVersion"

  if (-not (Test-VersionAtLeast -Current $gitVersion -Minimum $MinGitVersion)) {
    Require-Winget
    Upgrade-WingetPackage -Id $GitWingetId -DisplayName 'Git'
    Refresh-CommonToolPaths
  }
}

function Ensure-UserNpmBinOnPath {
  $npmBin = Join-Path $env:APPDATA 'npm'

  if (-not (Test-Path -LiteralPath $npmBin)) {
    if ($DryRun) {
      Write-Host "[dry-run] Would create $npmBin" -ForegroundColor Yellow
    }
    else {
      Ensure-Directory -Path $npmBin
    }
  }

  Ensure-PathEntry -Entry $npmBin
}

function Install-CodexCli {
  Ensure-UserNpmBinOnPath

  $npmCommand = Get-CommandLocation -Name 'npm.cmd'
  if (-not $npmCommand) {
    throw 'npm.cmd was not found after the Node.js installation step.'
  }

  Ensure-NpmCache

  Invoke-Checked -Description 'Installing the latest @openai/codex globally' -Action {
    & $npmCommand --cache $script:NpmCacheDir install -g @openai/codex@latest --prefix (Join-Path $env:APPDATA 'npm')
  }

  if ($DryRun) {
    return
  }

  $codexCommand = Get-CommandLocation -Name 'codex.cmd'
  if (-not $codexCommand) {
    $codexCommand = Get-CommandLocation -Name 'codex'
  }

  if (-not $codexCommand) {
    throw 'Codex CLI installed, but codex was not found on PATH. Open a new terminal and run codex --version.'
  }

  $codexVersion = & $codexCommand --version 2>&1 | Out-String
  Write-Step "Codex CLI is ready: $($codexVersion.Trim())"
}

Write-Step 'Checking Git, Node.js, npm, and Codex CLI requirements'
Refresh-CommonToolPaths
Ensure-Git
Ensure-NodeToolchain
Refresh-CommonToolPaths
Install-CodexCli
