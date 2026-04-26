[CmdletBinding()]
param(
  [switch]$DryRun,
  [version]$MinGitVersion = [version]'2.53.0',
  [version]$MinNpmVersion = [version]'8.0.0',
  [version]$MinNodeVersion = [version]'22.22.2',
  [string]$BootstrapNodePackageVersion = '',
  [string]$BootstrapGitPackageVersion = '',
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

function ConvertTo-VersionString {
  param([version]$Value)

  return "$($Value.Major).$($Value.Minor).$($Value.Build)"
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

function Get-DefaultCodexMetadata {
  return [pscustomobject]@{
    version = 'latest'
    engines = [pscustomobject]@{
      node = '>=16'
    }
  }
}

function Ensure-InstallerCache {
  Ensure-Directory -Path $script:InstallerCacheDir
}

function Get-WindowsArchitecture {
  return [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
}

function Get-NodeInstallerSpec {
  $architecture = Get-WindowsArchitecture
  $resolvedVersion = $null
  $artifactName = $null

  switch ($architecture) {
    'x64' {
      $artifactName = 'win-x64-msi'
    }
    'arm64' {
      $artifactName = 'win-arm64-msi'
    }
    default {
      throw "Unsupported Windows architecture for Node.js installer download: $architecture"
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($BootstrapNodePackageVersion)) {
    $resolvedVersion = ConvertTo-Version -Value $BootstrapNodePackageVersion
  }
  else {
    try {
      $catalog = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
      $release = $catalog |
        Where-Object {
          $_.lts -and
          $_.files -contains $artifactName -and
          (Parse-VersionText -Text $_.version) -ge $MinNodeVersion
        } |
        Sort-Object { Parse-VersionText -Text $_.version } -Descending |
        Select-Object -First 1

      if ($release) {
        $resolvedVersion = Parse-VersionText -Text $release.version
      }
      else {
        Write-Info "No Node.js LTS installer release met the minimum version requirement. Falling back to $MinNodeVersion."
      }
    }
    catch {
      Write-Info 'Node.js release metadata could not be fetched. Falling back to the minimum bootstrap version.'
    }
  }

  if ($null -eq $resolvedVersion) {
    $resolvedVersion = $MinNodeVersion
  }

  $versionText = ConvertTo-VersionString -Value $resolvedVersion

  switch ($architecture) {
    'x64' {
      return [pscustomobject]@{
        Version = $versionText
        FileName = "node-v$versionText-x64.msi"
        Url = "https://nodejs.org/dist/v$versionText/node-v$versionText-x64.msi"
      }
    }
    'arm64' {
      return [pscustomobject]@{
        Version = $versionText
        FileName = "node-v$versionText-arm64.msi"
        Url = "https://nodejs.org/dist/v$versionText/node-v$versionText-arm64.msi"
      }
    }
  }
}

function Get-GitInstallerSpec {
  $architecture = Get-WindowsArchitecture
  $assetSuffix = $null

  switch ($architecture) {
    'x64' {
      $assetSuffix = '64-bit'
    }
    'arm64' {
      $assetSuffix = 'arm64'
    }
    default {
      throw "Unsupported Windows architecture for Git installer download: $architecture"
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($BootstrapGitPackageVersion)) {
    $versionText = ConvertTo-VersionString -Value (ConvertTo-Version -Value $BootstrapGitPackageVersion)
    return [pscustomobject]@{
      Version = $versionText
      FileName = "Git-$versionText-$assetSuffix.exe"
      Url = "https://github.com/git-for-windows/git/releases/download/v$versionText.windows.1/Git-$versionText-$assetSuffix.exe"
    }
  }

  try {
    $release = Invoke-RestMethod -Headers @{ 'User-Agent' = 'codex-cli-bootstrap' } -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest'
    $asset = $release.assets | Where-Object {
      $_.name -match "^Git-(\d+\.\d+\.\d+)-$assetSuffix\.exe$"
    } | Select-Object -First 1

    if ($asset) {
      $resolvedVersion = Parse-VersionText -Text $asset.name
      if ($resolvedVersion -ge $MinGitVersion) {
        return [pscustomobject]@{
          Version = ConvertTo-VersionString -Value $resolvedVersion
          FileName = $asset.name
          Url = $asset.browser_download_url
        }
      }

      Write-Info "The latest Git for Windows release found by GitHub was below the minimum version requirement. Falling back to $MinGitVersion."
    }
    else {
      Write-Info 'GitHub release metadata did not include a matching installer asset. Falling back to the minimum bootstrap version.'
    }
  }
  catch {
    Write-Info 'GitHub release metadata for Git could not be fetched. Falling back to the minimum bootstrap version.'
  }

  $fallbackVersion = ConvertTo-VersionString -Value $MinGitVersion
  return [pscustomobject]@{
    Version = $fallbackVersion
    FileName = "Git-$fallbackVersion-$assetSuffix.exe"
    Url = "https://github.com/git-for-windows/git/releases/download/v$fallbackVersion.windows.1/Git-$fallbackVersion-$assetSuffix.exe"
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
    Write-Host "[dry-run] Installing Node.js bootstrap package $($spec.Version) via msiexec" -ForegroundColor Yellow
    return
  }

  Download-File -Url $spec.Url -DestinationPath $installerPath
  Write-Step "Installing Node.js bootstrap package $($spec.Version) from official installer"
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
    Write-Host "[dry-run] Installing Git bootstrap package $($spec.Version) via unattended installer" -ForegroundColor Yellow
    return
  }

  Download-File -Url $spec.Url -DestinationPath $installerPath
  Write-Step "Installing Git bootstrap package $($spec.Version) from official installer"
  $arguments = @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS')
  $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "Git installer exited with code $($process.ExitCode)."
  }
}

function Ensure-MinimumNodeInstalled {
  if (Get-CommandLocation -Name 'winget.exe') {
    try {
      Upgrade-WingetPackage `
        -Id $NodeWingetId `
        -DisplayName 'Node.js (includes npm)' `
        -PackageVersion $BootstrapNodePackageVersion
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

function Ensure-MinimumGitInstalled {
  if (Get-CommandLocation -Name 'winget.exe') {
    try {
      Upgrade-WingetPackage `
        -Id $GitWingetId `
        -DisplayName 'Git' `
        -PackageVersion $BootstrapGitPackageVersion
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

  if ([string]::IsNullOrWhiteSpace($NpmCommand)) {
    Write-Info 'npm.cmd is not available, falling back to a safe default Codex requirement.'
    return Get-DefaultCodexMetadata
  }

  Ensure-NpmCache

  try {
    $raw = & $NpmCommand --cache $script:NpmCacheDir view @openai/codex version engines --json 2>&1
    $json = $raw | Out-String | ConvertFrom-Json
    return $json
  }
  catch {
    Write-Info 'Falling back to a safe default Codex requirement because npm registry metadata could not be fetched.'
    return Get-DefaultCodexMetadata
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

function Ensure-MinimumNpmInstalled {
  param([string]$NpmCommand)

  if ([string]::IsNullOrWhiteSpace($NpmCommand)) {
    throw 'npm.cmd was not found while trying to upgrade npm.'
  }

  Ensure-NpmCache

  Invoke-Checked -Description 'Upgrading npm to meet the minimum version requirement' -Action {
    & $NpmCommand --cache $script:NpmCacheDir install -g npm@latest
    if ($LASTEXITCODE -ne 0) {
      throw 'npm upgrade failed.'
    }
  }
}

function Ensure-NodeToolchain {
  $nodeVersion = Get-ToolVersion -CommandName 'node.exe' -Arguments @('-v')
  $npmVersion = Get-ToolVersion -CommandName 'npm.cmd' -Arguments @('-v')
  $npmCommand = Get-CommandLocation -Name 'npm.cmd'
  $codexMeta = Get-CodexMetadata -NpmCommand $npmCommand
  $codexMinNodeVersion = Get-MinNodeVersionFromRange -Range $codexMeta.engines.node
  $effectiveMinNodeVersion = $MinNodeVersion

  if ($codexMinNodeVersion -gt $effectiveMinNodeVersion) {
    $effectiveMinNodeVersion = $codexMinNodeVersion
  }

  if ($null -eq $nodeVersion -or -not (Test-VersionAtLeast -Current $nodeVersion -Minimum $effectiveMinNodeVersion)) {
    Ensure-MinimumNodeInstalled
    Refresh-CommonToolPaths
    return
  }

  Write-Info "Detected node version: $nodeVersion"
  Write-Info "Detected npm version:  $npmVersion"
  Write-Info "Minimum node version:  $effectiveMinNodeVersion"
  Write-Info "Codex latest version: $($codexMeta.version)"
  Write-Info "Codex node range:     $($codexMeta.engines.node)"

  if ($null -eq $npmVersion) {
    Ensure-MinimumNodeInstalled
    Refresh-CommonToolPaths
    return
  }

  if (-not (Test-VersionAtLeast -Current $npmVersion -Minimum $MinNpmVersion)) {
    Ensure-MinimumNpmInstalled -NpmCommand $npmCommand
    Refresh-CommonToolPaths
  }
}

function Ensure-Git {
  $gitVersion = Get-ToolVersion -CommandName 'git.exe' -Arguments @('--version')

  if ($null -eq $gitVersion) {
    Ensure-MinimumGitInstalled
    Refresh-CommonToolPaths
    return
  }

  Write-Info "Detected git version: $gitVersion"
  Write-Info "Minimum git version:  $MinGitVersion"

  if (-not (Test-VersionAtLeast -Current $gitVersion -Minimum $MinGitVersion)) {
    Ensure-MinimumGitInstalled
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
