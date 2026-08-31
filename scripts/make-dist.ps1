<#
.SYNOPSIS
  Assemble the shareable Windroid zip: one folder, one INSTALL.cmd.

.DESCRIPTION
  Takes a directory of built artifacts (kernel bzImage-*, modules-*.vhdx,
  rootfs tar.gz, versions.json) and stages it with the installer, CLI and
  tray into a zip a user can unpack anywhere and double-click INSTALL.cmd.
  Layout inside the zip mirrors what install.ps1 expects ($PSScriptRoot\..
  for scripts/ and windows/tray/; -ArtifactSource for the artifacts dir).

.PARAMETER ArtifactDir
  Directory containing versions.json + the three artifacts it names.
.PARAMETER OutZip
  Path of the zip to write.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactDir,
    [Parameter(Mandatory)][string]$OutZip
)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent

$manifest = Get-Content (Join-Path $ArtifactDir "versions.json") -Raw | ConvertFrom-Json
$kernelName  = $manifest.kernel.artifact
$modulesName = $kernelName -replace '^bzImage-', 'modules-' -replace '$', '.vhdx'
$rootfsName  = $manifest.rootfs.flavours.vanilla.artifact
foreach ($a in @("versions.json", $kernelName, $modulesName, $rootfsName)) {
    if (-not (Test-Path (Join-Path $ArtifactDir $a))) { throw "artifact missing: $a" }
}

$stage = Join-Path ([IO.Path]::GetTempPath()) "windroid-dist-$(Get-Random)"
$root  = Join-Path $stage "Windroid"
New-Item -ItemType Directory -Force -Path "$root\installer", "$root\scripts", "$root\windows\tray", "$root\assets", "$root\artifacts" | Out-Null

Copy-Item (Join-Path $repo "installer\install.ps1"),(Join-Path $repo "installer\uninstall.ps1") "$root\installer"
Copy-Item (Join-Path $repo "scripts\windroid.ps1"),(Join-Path $repo "scripts\bench.ps1") "$root\scripts"
Copy-Item (Join-Path $repo "windows\tray\windroid-tray.ps1") "$root\windows\tray"
Copy-Item (Join-Path $repo "assets\windroid.ico") "$root\assets"
foreach ($a in @("versions.json", $kernelName, $modulesName, $rootfsName)) {
    Copy-Item (Join-Path $ArtifactDir $a) "$root\artifacts"
}

Set-Content -Path "$root\INSTALL.cmd" -Encoding Ascii -Value @'
@echo off
rem Windroid installer. No admin needed (WSL installs per-user).
rem If a reboot is requested on first run, rerun this file afterwards -
rem it resumes where it left off.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\install.ps1" -ArtifactSource "%~dp0artifacts"
echo.
pause
'@

Set-Content -Path "$root\UNINSTALL.cmd" -Encoding Ascii -Value @'
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\uninstall.ps1"
echo.
pause
'@

Set-Content -Path "$root\README.txt" -Encoding Ascii -Value @'
Windroid - Android apps in windows on your Windows 11 desktop
==============================================================

Requirements
  - Windows 11 (x86-64), virtualization enabled in firmware
  - ~15 GB free disk space, 8 GB RAM minimum (16 GB recommended)

Install
  1. Double-click INSTALL.cmd
  2. If Windows asks to reboot (first-time WSL setup), reboot and run
     INSTALL.cmd again - it continues automatically.
  3. Done when you see "Windroid installed."

Use
  - Everything lives in Start Menu > Windroid. Out of the box you get:
      Aurora Store   - app store (Google Play catalogue, anonymous login)
      Fennec         - Firefox for Android
      Material Files - file manager (your Windows Downloads folder is
                       shared into Android automatically)
      Settings       - Android settings
      Windroid Tray  - status, start/stop, "Install APK..."
  - Or from a terminal:  windroid install <app.apk>
  - Apps you install land in the same Start Menu folder automatically
    (new entries appear at the next session start); each app opens in
    its own window.

Notes
  - Android apps needing Google Play require the GApps flavour: run
    installer\install.ps1 -Gapps instead of INSTALL.cmd (downloads the
    Google image on your machine; not redistributable).
  - Banking apps enforcing Play Integrity will not work. Streaming DRM
    tops out at Widevine L3.
  - Uninstall completely with UNINSTALL.cmd.
'@

if (Test-Path $OutZip) { Remove-Item $OutZip }
# bsdtar (ships with Windows 10+) writes zip entries with forward slashes;
# Compress-Archive uses backslashes, which unix unzip tools mishandle.
& "$env:SystemRoot\System32\tar.exe" -a -c -f $OutZip -C $stage "Windroid"
if ($LASTEXITCODE -ne 0) { throw "tar.exe zip packing failed ($LASTEXITCODE)" }
Remove-Item -Recurse -Force $stage
Write-Host "Wrote $OutZip ($([math]::Round((Get-Item $OutZip).Length/1GB,2)) GB)"
