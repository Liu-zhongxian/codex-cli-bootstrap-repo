[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$SkipGit,
  [switch]$SkipNode,
  [switch]$SkipNpm,
  [ValidatePattern('^(latest|\d+(\.\d+){0,2})$')]
  [string]$CodexVersion = 'latest',
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

function Write-WarningText {
  param([string]$Message)
  Write-Host "[warning] $Message" -ForegroundColor Yellow
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

function Normalize-Sha256 {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }

  return $Value.Replace('sha256:', '').Trim().ToLowerInvariant()
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

function Get-ToolState {
  param(
    [string]$CommandName,
    [string[]]$Arguments
  )

  $commandPath = Get-CommandLocation -Name $CommandName
  if (-not $commandPath) {
    return $null
  }

  return [pscustomobject]@{
    Path = $commandPath
    Version = Get-ToolVersion -CommandName $CommandName -Arguments $Arguments
  }
}

function Assert-ToolState {
  param(
    [string]$DisplayName,
    [pscustomobject]$State,
    [version]$MinimumVersion
  )

  if ($null -eq $State -or [string]::IsNullOrWhiteSpace($State.Path)) {
    throw "$DisplayName was not found on PATH after the installation step."
  }

  if ($null -eq $State.Version) {
    throw "$DisplayName was found at $($State.Path), but its version could not be determined."
  }

  if ($State.Version -lt $MinimumVersion) {
    throw "$DisplayName version $($State.Version) at $($State.Path) does not meet the minimum requirement $MinimumVersion."
  }

  Write-Info "Resolved $DisplayName path:    $($State.Path)"
  Write-Info "Resolved $DisplayName version: $($State.Version)"
  return $State
}

function Get-CodexPackageSpec {
  if ($CodexVersion -eq 'latest') {
    return '@openai/codex@latest'
  }

  return "@openai/codex@$CodexVersion"
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

function Ensure-NpmCache {
  Ensure-Directory -Path $script:NpmCacheDir
}

function Ensure-InstallerCache {
  Ensure-Directory -Path $script:InstallerCacheDir
}

function Get-DefaultCodexMetadata {
  return [pscustomobject]@{
    version = 'latest'
    engines = [pscustomobject]@{
      node = '>=16'
    }
  }
}

function Get-CodexMetadata {
  param([string]$NpmCommand)

  if ([string]::IsNullOrWhiteSpace($NpmCommand)) {
    Write-Info 'npm.cmd is not available, falling back to a safe default Codex requirement.'
    return Get-DefaultCodexMetadata
  }

  Ensure-NpmCache
  $packageSpec = Get-CodexPackageSpec

  try {
    $raw = & $NpmCommand --cache $script:NpmCacheDir view $packageSpec version engines --json 2>&1
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

function Get-WindowsArchitecture {
  try {
    $runtimeInfoType = [System.Runtime.InteropServices.RuntimeInformation]
    $architectureProperty = $runtimeInfoType.GetProperty('OSArchitecture')
    if ($null -ne $architectureProperty) {
      return $architectureProperty.GetValue($null, @()).ToString().ToLowerInvariant()
    }
  }
  catch {
  }

  $candidates = @(
    $env:PROCESSOR_ARCHITEW6432
    $env:PROCESSOR_ARCHITECTURE
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    switch ($candidate.ToUpperInvariant()) {
      'ARM64' { return 'arm64' }
      'AMD64' { return 'x64' }
      'X86' { return 'x86' }
    }
  }

  throw 'Windows architecture could not be determined.'
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
        Sha256ManifestUrl = "https://nodejs.org/dist/v$versionText/SHASUMS256.txt"
      }
    }
    'arm64' {
      return [pscustomobject]@{
        Version = $versionText
        FileName = "node-v$versionText-arm64.msi"
        Url = "https://nodejs.org/dist/v$versionText/node-v$versionText-arm64.msi"
        Sha256ManifestUrl = "https://nodejs.org/dist/v$versionText/SHASUMS256.txt"
      }
    }
  }
}

function Get-GitDigestFromReleaseBody {
  param(
    [string]$Body,
    [string]$FileName
  )

  if ([string]::IsNullOrWhiteSpace($Body)) {
    return $null
  }

  $pattern = "(?im)^" + [regex]::Escape($FileName) + "\s*\|\s*([a-f0-9]{64})\s*$"
  $match = [regex]::Match($Body, $pattern)
  if (-not $match.Success) {
    return $null
  }

  return Normalize-Sha256 -Value $match.Groups[1].Value
}

function Get-GitReleaseMetadata {
  param([string]$PackageVersion)

  $uri = 'https://api.github.com/repos/git-for-windows/git/releases/latest'
  if (-not [string]::IsNullOrWhiteSpace($PackageVersion)) {
    $uri = "https://api.github.com/repos/git-for-windows/git/releases/tags/v$PackageVersion.windows.1"
  }

  try {
    return Invoke-RestMethod -Headers @{ 'User-Agent' = 'codex-cli-bootstrap' } -Uri $uri
  }
  catch {
    throw "Git release metadata could not be fetched from GitHub. Refusing to download an unverified installer. $($_.Exception.Message)"
  }
}

function Get-GitInstallerSpec {
  $architecture = Get-WindowsArchitecture
  $assetSuffix = $null
  $fallbackVersionText = ConvertTo-VersionString -Value $MinGitVersion
  $releaseVersionRequest = $BootstrapGitPackageVersion

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

  $release = Get-GitReleaseMetadata -PackageVersion $releaseVersionRequest
  $asset = $release.assets | Where-Object {
    $_.name -match "^Git-(\d+\.\d+\.\d+)-$assetSuffix\.exe$"
  } | Select-Object -First 1

  if ($null -eq $asset -and [string]::IsNullOrWhiteSpace($releaseVersionRequest)) {
    Write-Info "The latest Git release metadata did not include a matching installer asset. Falling back to the minimum bootstrap version $fallbackVersionText."
    $release = Get-GitReleaseMetadata -PackageVersion $fallbackVersionText
    $asset = $release.assets | Where-Object {
      $_.name -eq "Git-$fallbackVersionText-$assetSuffix.exe"
    } | Select-Object -First 1
  }

  if ($null -eq $asset) {
    throw 'Git release metadata did not include a matching installer asset for this architecture.'
  }

  $resolvedVersion = Parse-VersionText -Text $asset.name
  if ($resolvedVersion -lt $MinGitVersion) {
    throw "Git installer release $resolvedVersion is below the minimum required version $MinGitVersion."
  }

  $digest = $null
  if ($asset.PSObject.Properties.Name -contains 'digest') {
    $digest = Normalize-Sha256 -Value $asset.digest
  }

  if (-not $digest) {
    $digest = Get-GitDigestFromReleaseBody -Body $release.body -FileName $asset.name
  }

  if (-not $digest) {
    throw "Git checksum metadata was not found for $($asset.name). Refusing to download an unverified installer."
  }

  return [pscustomobject]@{
    Version = ConvertTo-VersionString -Value $resolvedVersion
    FileName = $asset.name
    Url = $asset.browser_download_url
    Sha256 = $digest
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

function Get-NodeInstallerSha256 {
  param([pscustomobject]$Spec)

  $manifest = Invoke-WebRequest -Uri $Spec.Sha256ManifestUrl -UseBasicParsing
  $pattern = "(?im)^([a-f0-9]{64})\s+" + [regex]::Escape($Spec.FileName) + "$"
  $match = [regex]::Match($manifest.Content, $pattern)
  if (-not $match.Success) {
    throw "The Node.js checksum manifest did not contain an entry for $($Spec.FileName)."
  }

  return Normalize-Sha256 -Value $match.Groups[1].Value
}

function Assert-FileSha256 {
  param(
    [string]$FilePath,
    [string]$ExpectedSha256,
    [string]$DisplayName
  )

  $actualHash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $expectedHash = Normalize-Sha256 -Value $ExpectedSha256

  if ([string]::IsNullOrWhiteSpace($expectedHash)) {
    throw "An expected SHA256 checksum was not provided for $DisplayName."
  }

  if ($actualHash -ne $expectedHash) {
    throw "$DisplayName failed SHA256 verification. Expected $expectedHash but got $actualHash."
  }

  Write-Info "Validated SHA256 for ${DisplayName}: $actualHash"
}

function Write-AuthenticodeSignatureInfo {
  param(
    [string]$FilePath,
    [string]$DisplayName
  )

  try {
    $signature = Get-AuthenticodeSignature -FilePath $FilePath
    if ($null -ne $signature -and $null -ne $signature.SignerCertificate) {
      Write-Info "Authenticode signer for ${DisplayName}: $($signature.SignerCertificate.Subject)"
      Write-Info "Authenticode status for ${DisplayName}: $($signature.Status)"
    }
  }
  catch {
    Write-WarningText "Could not read the Authenticode signature for $DisplayName. SHA256 verification already succeeded."
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

function Install-NodeFromOfficialPackage {
  $spec = Get-NodeInstallerSpec
  $installerPath = Join-Path $script:InstallerCacheDir $spec.FileName

  if ($DryRun) {
    Write-Host "[dry-run] Downloading Node.js installer from $($spec.Url)" -ForegroundColor Yellow
    Write-Host "[dry-run] Validating the downloaded Node.js installer with SHA256 from $($spec.Sha256ManifestUrl)" -ForegroundColor Yellow
    Write-Host "[dry-run] Installing Node.js bootstrap package $($spec.Version) via msiexec" -ForegroundColor Yellow
    return
  }

  Download-File -Url $spec.Url -DestinationPath $installerPath
  $expectedHash = Get-NodeInstallerSha256 -Spec $spec
  Assert-FileSha256 -FilePath $installerPath -ExpectedSha256 $expectedHash -DisplayName "Node.js installer $($spec.FileName)"
  Write-AuthenticodeSignatureInfo -FilePath $installerPath -DisplayName "Node.js installer $($spec.FileName)"
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
    Write-Host "[dry-run] Validating the downloaded Git installer with SHA256 $($spec.Sha256)" -ForegroundColor Yellow
    Write-Host "[dry-run] Installing Git bootstrap package $($spec.Version) via unattended installer" -ForegroundColor Yellow
    return
  }

  Download-File -Url $spec.Url -DestinationPath $installerPath
  Assert-FileSha256 -FilePath $installerPath -ExpectedSha256 $spec.Sha256 -DisplayName "Git installer $($spec.FileName)"
  Write-AuthenticodeSignatureInfo -FilePath $installerPath -DisplayName "Git installer $($spec.FileName)"
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

function Ensure-Git {
  $gitState = Get-ToolState -CommandName 'git.exe' -Arguments @('--version')

  if ($null -eq $gitState) {
    if ($SkipGit) {
      throw "Git is required but --skip-git was specified and git.exe was not found."
    }

    Write-Info 'Git is not installed.'
    Ensure-MinimumGitInstalled
    if ($DryRun) {
      Write-Host '[dry-run] Verifying Git command path and version after installation' -ForegroundColor Yellow
      return $null
    }
    Refresh-CommonToolPaths
    $gitState = Get-ToolState -CommandName 'git.exe' -Arguments @('--version')
  }
  elseif (-not (Test-VersionAtLeast -Current $gitState.Version -Minimum $MinGitVersion)) {
    if ($SkipGit) {
      throw "Git version $($gitState.Version) is below the minimum requirement $MinGitVersion and --skip-git was specified."
    }

    Write-Info "Detected git version: $($gitState.Version)"
    Write-Info "Minimum git version:  $MinGitVersion"
    Ensure-MinimumGitInstalled
    if ($DryRun) {
      Write-Host '[dry-run] Verifying Git command path and version after upgrade' -ForegroundColor Yellow
      return $null
    }
    Refresh-CommonToolPaths
    $gitState = Get-ToolState -CommandName 'git.exe' -Arguments @('--version')
  }

  return Assert-ToolState -DisplayName 'Git' -State $gitState -MinimumVersion $MinGitVersion
}

function Ensure-NodeToolchain {
  $npmCommand = Get-CommandLocation -Name 'npm.cmd'
  $codexMeta = Get-CodexMetadata -NpmCommand $npmCommand
  $codexMinNodeVersion = Get-MinNodeVersionFromRange -Range $codexMeta.engines.node
  $effectiveMinNodeVersion = $MinNodeVersion

  if ($codexMinNodeVersion -gt $effectiveMinNodeVersion) {
    $effectiveMinNodeVersion = $codexMinNodeVersion
  }

  $nodeState = Get-ToolState -CommandName 'node.exe' -Arguments @('-v')
  if ($null -eq $nodeState) {
    if ($SkipNode) {
      throw "Node.js is required but --skip-node was specified and node.exe was not found."
    }

    Write-Info 'Node.js is not installed.'
    Ensure-MinimumNodeInstalled
    if ($DryRun) {
      Write-Host '[dry-run] Verifying Node.js and npm command paths and versions after installation' -ForegroundColor Yellow
      return $null
    }
    Refresh-CommonToolPaths
    $nodeState = Get-ToolState -CommandName 'node.exe' -Arguments @('-v')
  }
  elseif (-not (Test-VersionAtLeast -Current $nodeState.Version -Minimum $effectiveMinNodeVersion)) {
    if ($SkipNode) {
      throw "Node.js version $($nodeState.Version) is below the minimum requirement $effectiveMinNodeVersion and --skip-node was specified."
    }

    Write-Info "Detected node version: $($nodeState.Version)"
    Write-Info "Minimum node version:  $effectiveMinNodeVersion"
    Ensure-MinimumNodeInstalled
    if ($DryRun) {
      Write-Host '[dry-run] Verifying Node.js and npm command paths and versions after upgrade' -ForegroundColor Yellow
      return $null
    }
    Refresh-CommonToolPaths
    $nodeState = Get-ToolState -CommandName 'node.exe' -Arguments @('-v')
  }

  $nodeState = Assert-ToolState -DisplayName 'Node.js' -State $nodeState -MinimumVersion $effectiveMinNodeVersion

  $npmState = Get-ToolState -CommandName 'npm.cmd' -Arguments @('-v')
  if ($null -eq $npmState) {
    if ($SkipNode -or $SkipNpm) {
      throw 'npm.cmd was not found after resolving Node.js, and automatic npm repair was disabled by --skip-node or --skip-npm.'
    }

    Write-Info 'npm.cmd was not found. Reinstalling Node.js to restore npm.'
    Ensure-MinimumNodeInstalled
    if ($DryRun) {
      Write-Host '[dry-run] Verifying npm command path and version after the Node.js repair step' -ForegroundColor Yellow
      return $null
    }
    Refresh-CommonToolPaths
    $nodeState = Assert-ToolState -DisplayName 'Node.js' -State (Get-ToolState -CommandName 'node.exe' -Arguments @('-v')) -MinimumVersion $effectiveMinNodeVersion
    $npmState = Get-ToolState -CommandName 'npm.cmd' -Arguments @('-v')
  }

  if ($null -eq $npmState) {
    throw 'npm.cmd was still not found after the Node.js installation step.'
  }

  if (-not (Test-VersionAtLeast -Current $npmState.Version -Minimum $MinNpmVersion)) {
    if ($SkipNpm) {
      throw "npm version $($npmState.Version) is below the minimum requirement $MinNpmVersion and --skip-npm was specified."
    }

    Ensure-MinimumNpmInstalled -NpmCommand $npmState.Path
    if ($DryRun) {
      Write-Host '[dry-run] Verifying npm command path and version after upgrade' -ForegroundColor Yellow
      return $null
    }
    Refresh-CommonToolPaths
    $npmState = Get-ToolState -CommandName 'npm.cmd' -Arguments @('-v')
  }

  $npmState = Assert-ToolState -DisplayName 'npm' -State $npmState -MinimumVersion $MinNpmVersion

  Write-Info "Requested Codex package: $(Get-CodexPackageSpec)"
  Write-Info "Codex latest version:   $($codexMeta.version)"
  Write-Info "Codex node range:       $($codexMeta.engines.node)"

  return [pscustomobject]@{
    Node = $nodeState
    Npm = $npmState
    Codex = $codexMeta
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

function Confirm-CodexCli {
  $codexCommand = Get-CommandLocation -Name 'codex.cmd'
  if (-not $codexCommand) {
    $codexCommand = Get-CommandLocation -Name 'codex'
  }

  if (-not $codexCommand) {
    throw 'Codex CLI installed, but codex was not found on PATH. Open a new terminal and run codex --version.'
  }

  $codexVersionOutput = & $codexCommand --version 2>&1 | Out-String
  $resolvedVersion = Parse-VersionText -Text $codexVersionOutput
  if ($null -eq $resolvedVersion) {
    throw "codex was found at $codexCommand, but its version output could not be parsed."
  }

  if ($CodexVersion -ne 'latest') {
    $expectedVersion = ConvertTo-Version -Value $CodexVersion
    if ($resolvedVersion -ne $expectedVersion) {
      throw "Codex CLI version $resolvedVersion was installed, but version $expectedVersion was requested."
    }
  }

  Write-Info "Resolved Codex path:    $codexCommand"
  Write-Info "Resolved Codex version: $resolvedVersion"
  Write-Step "Codex CLI is ready: $($codexVersionOutput.Trim())"
}

function Install-CodexCli {
  Ensure-UserNpmBinOnPath

  $npmCommand = Get-CommandLocation -Name 'npm.cmd'
  if (-not $npmCommand) {
    if ($DryRun) {
      Write-Host '[dry-run] npm.cmd is not available yet because the Node.js installation step was only simulated.' -ForegroundColor Yellow
      Write-Host "[dry-run] Installing $(Get-CodexPackageSpec) globally" -ForegroundColor Yellow
      Write-Host '[dry-run] Verifying codex on PATH after installation' -ForegroundColor Yellow
      return
    }

    throw 'npm.cmd was not found after the Node.js installation step.'
  }

  Ensure-NpmCache
  $packageSpec = Get-CodexPackageSpec

  Invoke-Checked -Description "Installing $packageSpec globally" -Action {
    & $npmCommand --cache $script:NpmCacheDir install -g $packageSpec --prefix (Join-Path $env:APPDATA 'npm')
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to install $packageSpec."
    }
  }

  if ($DryRun) {
    Write-Host '[dry-run] Verifying codex on PATH after installation' -ForegroundColor Yellow
    return
  }

  Refresh-CommonToolPaths
  Confirm-CodexCli
}

Write-Step 'Checking Git, Node.js, npm, and Codex CLI requirements'
Write-WarningText 'This bootstrap may install or upgrade system Git, Node.js, and npm.'
Write-WarningText 'Windows launchers use PowerShell with ExecutionPolicy Bypass.'
Refresh-CommonToolPaths
Ensure-Git | Out-Null
Ensure-NodeToolchain | Out-Null
Refresh-CommonToolPaths
Install-CodexCli
