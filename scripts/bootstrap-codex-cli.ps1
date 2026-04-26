[CmdletBinding()]
param(
  [switch]$DryRun,
  [version]$TargetGitVersion = [version]'2.53.0',
  [version]$MinNpmVersion = [version]'8.0.0',
  [version]$TargetNodeVersion = [version]'22.22.2',
  [string]$TargetNodePackageVersion = '22.22.2',
  [string]$TargetGitPackageVersion = '2.53.0',
  [string]$NodeWingetId = 'OpenJS.NodeJS.LTS',
  [string]$GitWingetId = 'Git.Git'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:WorkspaceRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:NpmCacheDir = Join-Path $script:WorkspaceRoot '.npm-cache'
$script:InstallerCacheDir = Join-Path $script:WorkspaceRoot '.installer-cache'

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

function Upgrade-WingetPackage {
  param(
    [string]$Id,
    [string]$DisplayName,
    [string]$PackageVersion
  )

  $versionSuffix = ''
  if (-not [string]::IsNullOrWhiteSpace($PackageVersion)) {
    $versionSuffix = " to version $PackageVersion"
  }

  Invoke-Checked -Description "Installing or upgrading $DisplayName$versionSuffix via winget" -Action {
    $arguments = @(
      'install'
      '--id', $Id
      '--exact'
      '--silent'
      '--accept-package-agreements'
      '--accept-source-agreements'
      '--source', 'winget'
      '--disable-interactivity'
      '--force'
    )

    if (-not [string]::IsNullOrWhiteSpace($PackageVersion)) {
      $arguments += @('--version', $PackageVersion)
    }

    winget.exe @arguments
    if ($LASTEXITCODE -ne 0) {
      throw "winget install/upgrade failed for $DisplayName."
    }
  }
}

function Ensure-NpmCache {
  Ensure-Directory -Path $script:NpmCacheDir
}

function Ensure-InstallerCache {
  Ensure-Directory -Path $script:InstallerCacheDir
}

function Get-WindowsArchitecture {
  return [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
}

function Get-NodeInstallerSpec {
  $architecture = Get-WindowsArchitecture
  switch ($architecture) {
    'x64' {
      return [pscustomobject]@{
        FileName = "node-v$TargetNodePackageVersion-x64.msi"
        Url = "https://nodejs.org/dist/v$TargetNodePackageVersion/node-v$TargetNodePackageVersion-x64.msi"
      }
    }
    'arm64' {
      return [pscustomobject]@{
        FileName = "node-v$TargetNodePackageVersion-arm64.msi"
        Url = "https://nodejs.org/dist/v$TargetNodePackageVersion/node-v$TargetNodePackageVersion-arm64.msi"
      }
    }
    default {
      throw "Unsupported Windows architecture for Node.js installer download: $architecture"
    }
  }
}

function Get-GitInstallerSpec {
  $architecture = Get-WindowsArchitecture
  switch ($architecture) {
    'x64' {
      return [pscustomobject]@{
        FileName = "Git-$TargetGitPackageVersion-64-bit.exe"
        Url = "https://github.com/git-for-windows/git/releases/download/v$TargetGitPackageVersion.windows.1/Git-$TargetGitPackageVersion-64-bit.exe"
      }
    }
    'arm64' {
      return [pscustomobject]@{
        FileName = "Git-$TargetGitPackageVersion-arm64.exe"
        Url = "https://github.com/git-for-windows/git/releases/download/v$TargetGitPackageVersion.windows.1/Git-$TargetGitPackageVersion-arm64.exe"
      }
    }
    default {
      throw "Unsupported Windows architecture for Git installer download: $architecture"
    }
  }
}

function Download-File {
  param(
    [string]$Url,
    [string]$DestinationPath
  )

  Ensure-InstallerCache

  if (Test-Path -LiteralPath $DestinationPath) {
    return
  }

  Write-Step "Downloading $Url"
  Invoke-WebRequest -Uri $Url -OutFile $DestinationPath
}

function Install-NodeFromOfficialPackage {
  $spec = Get-NodeInstallerSpec
  $installerPath = Join-Path $script:InstallerCacheDir $spec.FileName

  if ($DryRun) {
    Write-Host "[dry-run] Downloading Node.js installer from $($spec.Url)" -ForegroundColor Yellow
    Write-Host "[dry-run] Installing Node.js $TargetNodePackageVersion via msiexec" -ForegroundColor Yellow
    return
  }

  Download-File -Url $spec.Url -DestinationPath $installerPath
  Write-Step "Installing Node.js $TargetNodePackageVersion from official installer"
  $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $installerPath, '/qn', '/norestart') -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "Node.js installer exited with code $($process.ExitCode)."
  }
}

function Install-GitFromOfficialPackage {
  $spec = Get-GitInstallerSpec
  $installerPath = Join-Path $script:InstallerCacheDir $spec.FileName

  if ($DryRun) {
    Write-Host "[dry-run] Downloading Git installer from $($spec.Url)" -ForegroundColor Yellow
    Write-Host "[dry-run] Installing Git $TargetGitPackageVersion via unattended installer" -ForegroundColor Yellow
    return
  }

  Download-File -Url $spec.Url -DestinationPath $installerPath
  Write-Step "Installing Git $TargetGitPackageVersion from official installer"
  $arguments = @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS')
  $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "Git installer exited with code $($process.ExitCode)."
  }
}

function Ensure-TargetNodeInstalled {
  if (Get-CommandLocation -Name 'winget.exe') {
    try {
      Upgrade-WingetPackage `
        -Id $NodeWingetId `
        -DisplayName "Node.js $TargetNodePackageVersion (includes npm)" `
        -PackageVersion $TargetNodePackageVersion
      return
    }
    catch {
      Write-Info "winget install for Node.js failed, falling back to the official Node.js installer."
    }
  }
  else {
    Write-Info 'winget.exe was not found. Falling back to the official Node.js installer.'
  }

  Install-NodeFromOfficialPackage
}

function Ensure-TargetGitInstalled {
  if (Get-CommandLocation -Name 'winget.exe') {
    try {
      Upgrade-WingetPackage `
        -Id $GitWingetId `
        -DisplayName "Git $TargetGitPackageVersion" `
        -PackageVersion $TargetGitPackageVersion
      return
    }
    catch {
      Write-Info "winget install for Git failed, falling back to the official Git installer."
    }
  }
  else {
    Write-Info 'winget.exe was not found. Falling back to the official Git installer.'
  }

  Install-GitFromOfficialPackage
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
    Ensure-TargetNodeInstalled
    Refresh-CommonToolPaths
    return
  }

  $npmCommand = Get-CommandLocation -Name 'npm.cmd'
  $codexMeta = Get-CodexMetadata -NpmCommand $npmCommand
  $codexMinNodeVersion = Get-MinNodeVersionFromRange -Range $codexMeta.engines.node

  Write-Info "Detected node version: $nodeVersion"
  Write-Info "Detected npm version:  $npmVersion"
  Write-Info "Target node version:   $TargetNodeVersion"
  Write-Info "Codex latest version: $($codexMeta.version)"
  Write-Info "Codex node range:     $($codexMeta.engines.node)"

  $needNodeUpgrade =
    (-not (Test-VersionAtLeast -Current $nodeVersion -Minimum $codexMinNodeVersion)) -or
    (-not (Test-VersionAtLeast -Current $nodeVersion -Minimum $TargetNodeVersion)) -or
    (-not (Test-VersionAtLeast -Current $npmVersion -Minimum $MinNpmVersion))

  if ($needNodeUpgrade) {
    Ensure-TargetNodeInstalled
    Refresh-CommonToolPaths
  }
}

function Ensure-Git {
  $gitVersion = Get-ToolVersion -CommandName 'git.exe' -Arguments @('--version')

  if ($null -eq $gitVersion) {
    Ensure-TargetGitInstalled
    Refresh-CommonToolPaths
    return
  }

  Write-Info "Detected git version: $gitVersion"
  Write-Info "Target git version:   $TargetGitVersion"

  if (-not (Test-VersionAtLeast -Current $gitVersion -Minimum $TargetGitVersion)) {
    Ensure-TargetGitInstalled
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
    if ($DryRun) {
      Write-Host '[dry-run] npm.cmd is not available yet because the Node.js installation step was only simulated.' -ForegroundColor Yellow
      Write-Host '[dry-run] Installing the latest @openai/codex globally' -ForegroundColor Yellow
      return
    }

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
