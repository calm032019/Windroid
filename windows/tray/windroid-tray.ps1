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
    [string]$DistroName = "Windroid",
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
# Windroid logo, staged by install.ps1; system icon as fallback.
$icoPath = Join-Path $InstallRoot "windroid.ico"
$icon.Icon = if (Test-Path $icoPath) { New-Object System.Drawing.Icon($icoPath) } else { [System.Drawing.SystemIcons]::Application }
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
    # Guest-side logs are what actually matter for session failures
    # (~/.local/state/windroid, /var/log/windroid-firstboot.log).
    $guestLogs = "\\wsl.localhost\$DistroName\home\windroid\.local\state\windroid"
    if (Test-Path $guestLogs) { Start-Process explorer.exe $guestLogs }
})
$null = $menu.Items.Add("Check for updates", $null, {
    try {
        $local = Get-Content (Join-Path $InstallRoot "manifest.json") -Raw | ConvertFrom-Json
        $latest = Invoke-RestMethod -Uri $ReleasesApi -Headers @{ "User-Agent" = "windroid-tray" }
        if ($latest.tag_name -and (($latest.tag_name -replace '^v', '') -ne $local.manifest_version)) {
            Show-Tip $icon "Windroid update available" "Installed: $($local.manifest_version) — latest: $($latest.tag_name). Rerun install.ps1 to update (kernel + rootfs offered separately)."
        } else {
            Show-Tip $icon "Windroid" "Up to date ($($local.manifest_version))."
        }
    } catch { Show-Tip $icon "Windroid" "Update check failed: $($_.Exception.Message)" "Warning" }
})
$null = $menu.Items.Add("Known limits", $null, {
    # Risk R4 surfaced in the tray per plan Phase 4 / known-limits.md.
    Show-Tip $icon "Windroid — known limits" "Play Integrity-enforced apps (most banking) will not work; DRM tops out at Widevine L3 (SD streams). Graphics are software-rendered in v1. See docs/known-limits.md." "Warning"
})
$null = $menu.Items.Add("-")
$null = $menu.Items.Add("Exit", $null, {
    $icon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

$icon.ContextMenuStrip = $menu
$icon.add_DoubleClick({ Invoke-Guest "windroid-session ensure" | Out-Null })

# ---- Taskbar icon watcher -------------------------------------------------
# WSLg cannot associate Waydroid windows with their .desktop entries: its
# app list keys entries by the LAST dot-component of the filename while the
# lookup uses the raw dotted app_id (waydroid.<pkg>) — exact match only, no
# fallbacks (weston-mirror rdprail-shell/app-list.c, verified 2026-08-30).
# So Android windows would all show the generic fallback icon. This watcher
# finds Waydroid RAIL windows by title, composites the app's icon (from
# WSLg's own converted-icon cache) with a small Windroid badge bottom-right,
# and applies it via WM_SETICON.
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WindroidIconFix {
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
  [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
  delegate bool EnumWindowsProc(IntPtr h, IntPtr lp);
  public static List<string> Windows() {
    var r = new List<string>();
    EnumWindows((h, lp) => { if (IsWindowVisible(h)) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); if (sb.Length > 0) r.Add(h.ToInt64() + "|" + sb.ToString()); } return true; }, IntPtr.Zero);
    return r;
  }
}
"@
$script:doneWindows = @{}    # hwnd -> $true (icon applied)
$script:keptIcons  = New-Object System.Collections.ArrayList   # keep HICONs alive
$script:nameToKey  = @{}     # app display Name -> WSLDVCPlugin ico basename

function Update-NameMap {
    $appsDir = "\\wsl.localhost\$script:DistroName\usr\local\share\applications"
    if (-not (Test-Path $appsDir)) { return }
    Get-ChildItem $appsDir -Filter "waydroid.*.desktop" -ErrorAction SilentlyContinue | ForEach-Object {
        $m = Select-String -Path $_.FullName -Pattern '^Name=(.+)$' | Select-Object -First 1
        if ($m) {
            # WSLg's key: filename minus .desktop, then last dot-component.
            $script:nameToKey[$m.Matches.Groups[1].Value] = ($_.BaseName -replace '.*\.', '')
        }
    }
}

$iconTimer = New-Object System.Windows.Forms.Timer
$iconTimer.Interval = 3000
$iconTimer.add_Tick({
  try {
    $suffix = " ($script:DistroName)"
    $wins = [WindroidIconFix]::Windows() | Where-Object { $_ -like "*$suffix" -and $_ -notlike "*sub-surface*" }
    if (-not $wins) { return }
    foreach ($w in $wins) {
        $hwnd, $title = $w -split '\|', 2
        if ($script:doneWindows.ContainsKey($hwnd)) { continue }
        $appName = $title.Substring(0, $title.Length - $suffix.Length)
        # Titles may also carry the COPY MODE warning prefix.
        $appName = $appName -replace '^\[WARN:COPY MODE\] ', ''
        if (-not $script:nameToKey.ContainsKey($appName)) { Update-NameMap }
        if (-not $script:nameToKey.ContainsKey($appName)) { continue }
        $baseIco = Join-Path "$env:LOCALAPPDATA\Temp\WSLDVCPlugin\$script:DistroName" "$($script:nameToKey[$appName]).ico"
        # Badge: install root, next to this script (installer stages both),
        # or the repo checkout during development.
        $badgeIco = @(
            (Join-Path $script:InstallRoot "windroid.ico"),
            (Join-Path $PSScriptRoot "windroid.ico"),
            (Join-Path $PSScriptRoot "..\..\assets\windroid.ico")
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not ((Test-Path $baseIco) -and $badgeIco)) { continue }
        try {
            $base  = New-Object System.Drawing.Icon($baseIco, 64, 64)
            $badge = New-Object System.Drawing.Icon($badgeIco, 48, 48)
            $bmp = New-Object System.Drawing.Bitmap(64, 64)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.DrawIcon($base, (New-Object System.Drawing.Rectangle(0, 0, 64, 64)))
            $g.DrawIcon($badge, (New-Object System.Drawing.Rectangle(32, 32, 32, 32)))
            $g.Dispose()
            $hicon = $bmp.GetHicon()
            [void]$script:keptIcons.Add($hicon)
            $hPtr = [IntPtr][long]$hwnd
            [WindroidIconFix]::SendMessage($hPtr, 0x80, [IntPtr]1, $hicon) | Out-Null   # ICON_BIG
            [WindroidIconFix]::SendMessage($hPtr, 0x80, [IntPtr]0, $hicon) | Out-Null   # ICON_SMALL
            $script:doneWindows[$hwnd] = $true
        } catch { }
    }
    # Forget hwnds that no longer exist so handles can be reused safely.
    $live = @{}; foreach ($w in $wins) { $live[($w -split '\|')[0]] = $true }
    foreach ($k in @($script:doneWindows.Keys)) { if (-not $live.ContainsKey($k)) { $script:doneWindows.Remove($k) } }
  } catch {
    Add-Content (Join-Path $script:InstallRoot "tray.log") "$(Get-Date -Format o) icon-watcher: $($_.Exception.Message)"
  }
})
$iconTimer.Start()

Show-Tip $icon "Windroid" "Tray running — right-click for options."
[System.Windows.Forms.Application]::Run()
