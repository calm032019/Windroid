<#
.SYNOPSIS
  Compile the professional Windroid-Setup.exe wizard (Inno Setup 6).

.DESCRIPTION
  Wraps installer/windroid-setup.iss. Finds ISCC.exe (installs Inno Setup
  per-user from jrsoftware.org if missing), then compiles with the given
  artifact directory. Output: Windroid-Setup-<ver>.exe in -OutDir.

.PARAMETER ArtifactDir
  Directory containing versions.json + kernel/rootfs artifacts.
.PARAMETER OutDir
  Where to write the setup exe.
.PARAMETER InstallRootOverride
  Dev/test only: pass a fixed -InstallRoot through to install.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactDir,
    [Parameter(Mandatory)][string]$OutDir,
    [string]$InstallRootOverride
)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent

function Find-Iscc {
    foreach ($p in @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$iscc = Find-Iscc
if (-not $iscc) {
    Write-Host "Inno Setup not found - installing per-user from jrsoftware.org (~7 MB)..."
    $isExe = Join-Path $env:TEMP "innosetup-installer.exe"
    Invoke-WebRequest -Uri "https://jrsoftware.org/download.php/is.exe" -OutFile $isExe
    Start-Process $isExe -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/CURRENTUSER", "/NORESTART" -Wait
    $iscc = Find-Iscc
    if (-not $iscc) { throw "Inno Setup install failed - ISCC.exe not found afterwards." }
}

$defines = @("/DArtifactDir=$ArtifactDir", "/DOutputDir=$OutDir")
if ($InstallRootOverride) { $defines += "/DInstallRootOverride=$InstallRootOverride" }
& $iscc @defines (Join-Path $repo "installer\windroid-setup.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }
Get-ChildItem $OutDir -Filter "Windroid-Setup-*.exe" | ForEach-Object {
    Write-Host "Wrote $($_.FullName) ($([math]::Round($_.Length/1GB,2)) GB)"
}
