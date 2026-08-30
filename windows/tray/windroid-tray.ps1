<#
.SYNOPSIS
  Windroid tray app, stage 1 (plan Phase 2.2): PowerShell + NotifyIcon +
  balloon notifications. Deliberately not a GUI-framework app — ADR-005
  says the PowerShell version must run for two weeks before any Tauri/
  WinUI 3 rewrite is considered.

  Menu: Status / Start / Stop / Restart / Install APK… / Android Settings /
  Open logs / Check for updates / Exit.
#>
[CmdletBinding()]
param(
    [string]$DistroName = "windroid",
    [string]$InstallRoot = "$env:LOCALAPPDATA\Windroid",
    [string]$ReleasesApi = "https://api.github.com/repos/calm032019/Windroid/releases/latest"
)
$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$host.UI.RawUI.WindowTitle = "Windroid Tray"

function Invoke-Guest([string]$cmd, [string]$user = "windroid") {
    wsl -d $DistroName -u $user -e bash -lc $cmd 2>&1
}
function Show-Tip($icon, $title, $text, $kind = "Info") {
    $icon.BalloonTipTitle = $title
    $icon.BalloonTipText  = $text
    $icon.BalloonTipIcon  = $kind
    $icon.ShowBalloonTip(4000)
}

$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.SystemIcons]::Application
$icon.Text = "Windroid"
$icon.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$null = $menu.Items.Add("Status", $null, {
    $s = (Invoke-Guest "waydroid status") -join "`n"
    if (-not $s) { $s = "Not running (or distro '$DistroName' not registered)" }
    Show-Tip $icon "Windroid status" $s
})
$null = $menu.Items.Add("Start session", $null, {
    Show-Tip $icon "Windroid" "Starting session…"
    $out = Invoke-Guest "windroid-session start"
    if ($out -match "session ready|already RUNNING") { Show-Tip $icon "Windroid" "Session running." }
    else { Show-Tip $icon "Windroid" "Start failed — see logs.`n$($out | Select-Object -Last 3)" "Error" }
})
$null = $menu.Items.Add("Stop session", $null, {
    Invoke-Guest "windroid-session stop" | Out-Null
    Show-Tip $icon "Windroid" "Session stopped."
})
$null = $menu.Items.Add("Restart session", $null, {
    Invoke-Guest "windroid-session stop" | Out-Null
    $out = Invoke-Guest "windroid-session start"
    Show-Tip $icon "Windroid" $(if ($out -match "session ready") { "Session restarted." } else { "Restart failed — see logs." })
})
$null = $menu.Items.Add("-")
$null = $menu.Items.Add("Install APK…", $null, {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Android packages (*.apk)|*.apk"
    if ($dlg.ShowDialog() -eq "OK") {
        $wslPath = (wsl -d $DistroName -e wslpath -a "$($dlg.FileName)").Trim()
        Show-Tip $icon "Windroid" "Installing $([IO.Path]::GetFileName($dlg.FileName))…"
        Invoke-Guest "windroid-session ensure && waydroid app install '$wslPath'" | Out-Null
        Show-Tip $icon "Windroid" "Installed. It appears in the Start Menu shortly."
    }
})
$null = $menu.Items.Add("Android Settings", $null, {
    # Android's stock settings package (AOSP/LineageOS): com.android.settings
    Invoke-Guest "windroid-session ensure && waydroid app launch com.android.settings" | Out-Null
})
$null = $menu.Items.Add("-")
$null = $menu.Items.Add("Open logs", $null, {
    Start-Process explorer.exe $InstallRoot
    Invoke-Guest "windroid-session status" | Out-Null
})
$null = $menu.Items.Add("Check for updates", $null, {
    try {
        $local = Get-Content (Join-Path $InstallRoot "manifest.json") -Raw | ConvertFrom-Json
        $latest = Invoke-RestMethod -Uri $ReleasesApi -Headers @{ "User-Agent" = "windroid-tray" }
        if ($latest.tag_name -and $latest.tag_name -ne "v$($local.manifest_version)") {
            Show-Tip $icon "Windroid update available" "Installed: $($local.manifest_version) — latest: $($latest.tag_name). Rerun install.ps1 to update (kernel + rootfs offered separately)."
        } else {
            Show-Tip $icon "Windroid" "Up to date ($($local.manifest_version))."
        }
    } catch { Show-Tip $icon "Windroid" "Update check failed: $($_.Exception.Message)" "Warning" }
})
$null = $menu.Items.Add("-")
$null = $menu.Items.Add("Exit", $null, {
    $icon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

$icon.ContextMenuStrip = $menu
$icon.add_DoubleClick({ Invoke-Guest "windroid-session ensure" | Out-Null })

Show-Tip $icon "Windroid" "Tray running — right-click for options."
[System.Windows.Forms.Application]::Run()
