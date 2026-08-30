<#
.SYNOPSIS
  windroid CLI (plan Phase 2.4).
    windroid install <apk>   sideload an APK
    windroid start|stop|status
    windroid adb             print/run the adb connect line (docs: adb connect <IP>:5555)
    windroid shell           root shell into Android (waydroid shell)
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet("install", "start", "stop", "status", "adb", "shell", "help")]
    [string]$Command = "help",
    [Parameter(Position = 1)][string]$Arg,
    [string]$DistroName = "windroid"
)
$ErrorActionPreference = "Stop"

function Invoke-Guest([string]$cmd, [string]$user = "windroid") {
    # The `bash -c` form is deliberate — prior art found direct-exec less
    # reliable for detached processes (docs/UPSTREAM-FACTS.md §6).
    wsl -d $DistroName -u $user -e bash -lc $cmd
}

switch ($Command) {
    "start"  { Invoke-Guest "windroid-session start" }
    "stop"   { Invoke-Guest "windroid-session stop" }
    "status" { Invoke-Guest "waydroid status" }
    "shell"  { wsl -d $DistroName -u root -e waydroid shell }
    "install" {
        if (-not $Arg) { Write-Error "usage: windroid install <path-to.apk>"; exit 2 }
        if (-not (Test-Path $Arg)) { Write-Error "not found: $Arg"; exit 2 }
        $winPath = (Resolve-Path $Arg).Path
        $wslPath = (wsl -d $DistroName -e wslpath -a "$winPath").Trim()
        Invoke-Guest "windroid-session ensure && waydroid app install '$wslPath'"
        Write-Host "Installed. The app appears in Start Menu > Windroid shortly (desktop sync)."
    }
    "adb" {
        # Official mechanism: adb connect <container IP>:5555
        # (docs.waydro.id/faq/using-adb-with-waydroid). waydroid status
        # prints "IP address:" when the session is RUNNING.
        Invoke-Guest "windroid-session ensure" | Out-Null
        $status = (Invoke-Guest "waydroid status") -join "`n"
        if ($status -match "IP address:\s*([\d.]+)") {
            $target = "$($Matches[1]):5555"
            Write-Host "adb connect $target"
            if (Get-Command adb -ErrorAction SilentlyContinue) { adb connect $target }
            else { Write-Host "(adb not found on PATH — install Android platform-tools and run the line above)" }
        } else {
            Write-Error "Could not read the container IP from 'waydroid status' — is the session RUNNING?"
        }
    }
    default {
        @"
windroid — Android subsystem for Windows

  windroid start | stop | status
  windroid install <apk>
  windroid adb        connect adb to the container (IP:5555)
  windroid shell      root shell into Android
"@ | Write-Host
    }
}
