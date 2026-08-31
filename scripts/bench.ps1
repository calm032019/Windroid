<#
.SYNOPSIS
  Windroid measurement harness (plan Phase 3 — built before any tuning).
  All PERF.md numbers come from here, never hand-timing.

    bench.ps1 cold-start   [-AppPackage org.fdroid.fdroid] [-AppWindowTitle "F-Droid"]
    bench.ps1 warm-launch  [-AppPackage ...] [-AppWindowTitle ...]
    bench.ps1 idle-ram     [-SettleMinutes 5]
    bench.ps1 all

.NOTES
  "App window visible" is detected by polling every top-level window title
  for -AppWindowTitle (WSLg RAIL windows surface as normal Windows windows
  hosted by msrdc). That is the honest user-visible moment; if a window
  never gets a matching title, pass the actual title text the app shows.
  Results are appended as one machine-readable line each to bench-results.csv
  next to this script — copy rows into docs/PERF.md with machine + manifest.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet("cold-start", "warm-launch", "idle-ram", "all")]
    [string]$Stage = "all",
    [string]$DistroName = "Windroid",
    [string]$AppPackage = "org.fdroid.fdroid",
    [string]$AppWindowTitle = "F-Droid",
    [int]$SettleMinutes = 5,
    [int]$TimeoutSec = 120
)
$ErrorActionPreference = "Stop"
$ResultsFile = Join-Path $PSScriptRoot "bench-results.csv"
if (-not (Test-Path $ResultsFile)) {
    Set-Content $ResultsFile "timestamp,stage,seconds,detail"
}

function Invoke-Guest([string]$cmd) { wsl -d $DistroName -u windroid -e bash -lc $cmd }
function Record($stage, $seconds, $detail) {
    Add-Content $ResultsFile "$(Get-Date -Format o),$stage,$seconds,$detail"
    Write-Host ("{0}: {1}s  ({2})" -f $stage, $seconds, $detail) -ForegroundColor Green
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public static class WinEnum {
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    delegate bool EnumProc(IntPtr h, IntPtr lp);
    public static List<string> VisibleTitles() {
        var list = new List<string>();
        EnumWindows((h, lp) => {
            if (IsWindowVisible(h)) {
                var sb = new StringBuilder(512);
                GetWindowText(h, sb, sb.Capacity);
                if (sb.Length > 0) list.Add(sb.ToString());
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@

function Wait-AppWindow([string]$titlePattern, [int]$timeoutSec) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        if ([WinEnum]::VisibleTitles() | Where-Object { $_ -match [regex]::Escape($titlePattern) }) {
            return [math]::Round($sw.Elapsed.TotalSeconds, 1)
        }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

function Measure-ColdStart {
    # Budget: nothing running -> app window visible <= 20 s.
    wsl --shutdown
    Start-Sleep -Seconds 2
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Invoke-Guest "windroid-session ensure && waydroid app launch $AppPackage" | Out-Null
    $t = Wait-AppWindow $AppWindowTitle $TimeoutSec
    if ($null -eq $t) { Record "cold-start" "TIMEOUT" "no window titled ~$AppWindowTitle in ${TimeoutSec}s" }
    else { Record "cold-start" ([math]::Round($sw.Elapsed.TotalSeconds, 1)) "window=$AppWindowTitle pkg=$AppPackage" }
}

function Measure-WarmLaunch {
    # Budget: session already up, app cold -> window <= 3 s.
    Invoke-Guest "windroid-session ensure" | Out-Null
    Start-Sleep -Seconds 5
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Invoke-Guest "waydroid app launch $AppPackage" | Out-Null
    $t = Wait-AppWindow $AppWindowTitle $TimeoutSec
    if ($null -eq $t) { Record "warm-launch" "TIMEOUT" "no window titled ~$AppWindowTitle" }
    else { Record "warm-launch" ([math]::Round($sw.Elapsed.TotalSeconds, 1)) "window=$AppWindowTitle pkg=$AppPackage" }
}

function Measure-IdleRam {
    # Budget: session up, no apps, after reclaim settle: <= 1.5 GB.
    # The WSL2 VM's host-side footprint is the vmmem/vmmemWSL process.
    Invoke-Guest "windroid-session ensure" | Out-Null
    Write-Host "Settling $SettleMinutes min for autoMemoryReclaim…"
    Start-Sleep -Seconds ($SettleMinutes * 60)
    $vm = Get-Process | Where-Object { $_.ProcessName -match '^vmmem' } | Sort-Object WS -Descending | Select-Object -First 1
    if (-not $vm) { Record "idle-ram" "N/A" "no vmmem process found" ; return }
    $gb = [math]::Round($vm.WS / 1GB, 2)
    Record "idle-ram" $gb "GB working set of $($vm.ProcessName) after ${SettleMinutes}min settle"
}

switch ($Stage) {
    "cold-start"  { Measure-ColdStart }
    "warm-launch" { Measure-WarmLaunch }
    "idle-ram"    { Measure-IdleRam }
    "all"         { Measure-ColdStart; Measure-WarmLaunch; Measure-IdleRam }
}
Write-Host "Results appended to $ResultsFile — copy into docs/PERF.md with machine + manifest version."
