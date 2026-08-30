<#
.SYNOPSIS
  Windroid uninstaller. A clean machine afterwards is an exit criterion
  (plan Phase 2.6): unregister the distro, revert ONLY our .wslconfig
  lines (other distros and Docker Desktop share that file), remove
  shortcuts/CLI/tray, return to the stock WSL kernel.
#>
[CmdletBinding()]
param(
    [string]$DistroName = "windroid",
    [string]$InstallRoot = "$env:LOCALAPPDATA\Windroid",
    [switch]$KeepUserData   # export Android /data before unregistering
)
$ErrorActionPreference = "Stop"
$WslConfig = Join-Path $env:USERPROFILE ".wslconfig"
$StateFile = Join-Path $InstallRoot "state.json"

Write-Host "==> Stopping Windroid" -ForegroundColor Cyan
$registered = (wsl --list --quiet 2>$null) -replace "`0", "" | Where-Object { $_ -eq $DistroName }
if ($registered) {
    wsl -d $DistroName -u windroid -e bash -lc "windroid-session stop" 2>$null | Out-Null
    if ($KeepUserData) {
        $backup = Join-Path $env:USERPROFILE "windroid-data-backup-$(Get-Date -Format yyyyMMddHHmmss).tar.gz"
        Write-Host "==> Exporting Android user data to $backup"
        wsl -d $DistroName -u root -e bash -c "tar -czf - -C /var/lib/waydroid data" > $backup
    }
    Write-Host "==> Unregistering distro '$DistroName'"
    wsl --unregister $DistroName
}

Write-Host "==> Reverting our .wslconfig keys (and only ours)" -ForegroundColor Cyan
if ((Test-Path $StateFile) -and (Test-Path $WslConfig)) {
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    $lines = @(Get-Content $WslConfig)
    foreach ($chg in $state.wslconfigChanges) {
        $inSection = $false
        $lines = @($lines | ForEach-Object {
            if ($_ -match '^\s*\[(.+)\]\s*$') { $inSection = ($Matches[1] -eq $chg.section); $_ }
            elseif ($inSection -and $_ -match "^\s*$([regex]::Escape($chg.key))\s*=") {
                # Restore the pre-install value; drop the line if we added the key.
                if ($null -ne $chg.previous -and "$($chg.previous)" -ne "") { "$($chg.key)=$($chg.previous)" }
                # else: emit nothing (line removed)
            }
            else { $_ }
        })
    }
    # Drop sections left empty by our removals (e.g. [experimental] we created).
    $cleaned = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[.+\]\s*$') {
            $j = $i + 1
            while ($j -lt $lines.Count -and $lines[$j] -notmatch '^\s*\[.+\]\s*$') { $j++ }
            # ($i+1)..($j-1) runs BACKWARDS when the body is empty ($j -eq $i+1) — guard it.
            $body = if ($j -gt $i + 1) { $lines[($i + 1)..($j - 1)] | Where-Object { $_ -and $_.Trim() } } else { @() }
            if ($body) { $cleaned.AddRange([string[]]$lines[$i..($j - 1)]) }
            $i = $j - 1
        } else { $cleaned.Add($lines[$i]) }
    }
    if (($cleaned | Where-Object { $_.Trim() }).Count -eq 0) {
        Remove-Item $WslConfig                       # nothing left but our config: remove the file
    } else {
        Set-Content -Path $WslConfig -Value $cleaned
    }
} elseif (Test-Path $WslConfig) {
    Write-Warning "No install state found — .wslconfig left untouched. Remove Windroid's kernel/kernelModules/memory/autoMemoryReclaim/sparseVhd lines manually if present (backups: $WslConfig.windroid-backup-*)."
}

Write-Host "==> Removing Windows integration" -ForegroundColor Cyan
Remove-Item -Recurse -Force (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Windroid") -ErrorAction SilentlyContinue
$binDir = Join-Path $InstallRoot "bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -like "*$binDir*") {
    [Environment]::SetEnvironmentVariable("Path", (($userPath -split ';' | Where-Object { $_ -and $_ -ne $binDir }) -join ';'), "User")
}
Get-Process | Where-Object { $_.ProcessName -eq 'powershell' -and $_.MainWindowTitle -eq 'Windroid Tray' } | Stop-Process -ErrorAction SilentlyContinue

Write-Host "==> Removing $InstallRoot (kernel, distro vhdx, logs, state)" -ForegroundColor Cyan
Remove-Item -Recurse -Force $InstallRoot -ErrorAction SilentlyContinue

Write-Host "==> Restarting WSL on the stock kernel" -ForegroundColor Cyan
wsl --shutdown
Write-Host "Done. Other WSL distros and Docker Desktop are untouched; the next 'wsl' start uses the stock Microsoft kernel." -ForegroundColor Green
Write-Host "If you kept a data backup it is in your user profile folder."
